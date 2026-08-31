#!/usr/bin/env bash
# Behaviour tests for the duplication attribution Sensor.
#
# The gate's whole value is the split it makes: a clone this delivery wrote
# blocks, a clone that was already there does not. Get that split wrong in either
# direction and the gate is worthless — over-blame and it fails every push on a
# repo with history (so it gets disabled, taking the real finding with it);
# under-blame and the reimplemented helper it exists to catch sails through.
#
# Attribution is line-level, so the case that matters most is the third one: a
# file the delivery touched, carrying a clone in a region the diff never went
# near. File-level attribution calls that introduced. It is not.
#
# Known limitation, stated rather than papered over: these cases feed the script a
# report this file writes, and the hook cases stub jscpd entirely. That proves the
# attribution logic and the hook's wiring — it cannot prove jscpd was *invoked*
# correctly. An ignore-list defect (the .git/ directory being scanned, say) is
# invisible here and only shows on a real run. Verify that by hand when the
# invocation changes.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ATTR="$ROOT/plugins/coding-pipeline/git-hooks/dup-attribution.py"
WORK="${TMPDIR:-/tmp}/devkit-dup-tests"
fail=0
pass=0

rm -rf "$WORK"; mkdir -p "$WORK"

# repo <name> — a git repo with one commit on main, then a second commit whose
# diff touches known lines. Attribution is measured against that first commit.
repo() {
    local dir="$WORK/$1"
    mkdir -p "$dir"
    (
        cd "$dir" || exit 1
        git init -q .
        git config user.email t@t; git config user.name t
        git config commit.gpgsign false
        # 40 lines of legacy; the clone fixtures point into it
        seq 1 40 | sed 's/^/legacy line /' > legacy.txt
        git add -A && git commit -qm "base"
        git branch -M main
    )
    printf '%s' "$dir"
}

# change <dir> <file> <line-count> — a second commit adding lines to a NEW file,
# so the added ranges are unambiguous.
change() {
    local dir="$1" file="$2" n="$3"
    ( cd "$dir" || exit 1
      seq 1 "$n" | sed 's/^/new line /' > "$file"
      git add -A && git commit -qm "delivery" )
}

# report <dir> <total-lines> <fileA> <startA> <endA> <fileB> <startB> <endB>
report() {
    local dir="$1" total="$2"
    python3 - "$dir/report.json" "$total" "$3" "$4" "$5" "$6" "$7" "$8" <<'PY'
import json, sys
out, total, fa, sa, ea, fb, sb, eb = sys.argv[1:]
json.dump({
    "statistics": {"total": {"lines": int(total)}},
    "duplicates": [{
        "lines": int(ea) - int(sa) + 1,
        "firstFile": {"name": fa, "start": int(sa), "end": int(ea)},
        "secondFile": {"name": fb, "start": int(sb), "end": int(eb)},
    }],
}, open(out, "w"))
PY
}

run() {             # run <dir> [extra args...] — echoes output, returns exit code
    local dir="$1"; shift
    ( cd "$dir" && python3 "$ATTR" --report "$dir/report.json" "$@" 2>&1 )
}

expect_exit() {     # expect_exit <name> <dir> <want-exit> [args...]
    local name="$1" dir="$2" want="$3"; shift 3
    run "$dir" "$@" >/dev/null 2>&1; local got=$?
    if [ "$got" = "$want" ]; then pass=$((pass + 1)); else
        echo "FAIL: $name — exited $got, expected $want"; fail=1
    fi
}

expect_says() {     # expect_says <name> <dir> <yes|no> <substring> [args...]
    local name="$1" dir="$2" want="$3" needle="$4"; shift 4
    local out saw
    out="$(run "$dir" "$@")"
    case "$out" in *"$needle"*) saw=yes ;; *) saw=no ;; esac
    if [ "$saw" = "$want" ]; then pass=$((pass + 1)); else
        echo "FAIL: $name — expected '$needle' present=$want, got present=$saw"
        echo "       output: $out"
        fail=1
    fi
}

base_of() { ( cd "$1" && git rev-parse HEAD~1 ); }

# ── 1. A clone the delivery wrote blocks ────────────────────────────────────
d="$(repo introduced)"; change "$d" "new.txt" 30
report "$d" 200 "new.txt" 1 30 "legacy.txt" 1 30
expect_exit "introduced clone blocks"      "$d" 1 --base "$(base_of "$d")" --threshold 3
expect_says "introduced clone is labelled" "$d" yes "Introduced by this delivery" --base "$(base_of "$d")" --threshold 3

# ── 2. A clone that was already there does not ──────────────────────────────
# Same repo shape, same size clone — only the location differs. This is the case
# that decides whether the gate is usable on a real codebase.
d="$(repo preexisting)"; change "$d" "new.txt" 30
report "$d" 200 "legacy.txt" 1 20 "legacy.txt" 21 40
expect_exit "pre-existing clone does not block" "$d" 0 --base "$(base_of "$d")" --threshold 3
expect_says "pre-existing clone is reported"    "$d" yes "Pre-existing debt" --base "$(base_of "$d")" --threshold 3

# ── 3. Line-level, not file-level ───────────────────────────────────────────
# legacy.txt IS in the diff (2 lines appended), but the clone sits at lines the
# change never touched. File-level attribution blames the delivery for it.
d="$(repo untouched-region)"
( cd "$d" && printf 'appended a\nappended b\n' >> legacy.txt && git add -A && git commit -qm "delivery" )
report "$d" 200 "legacy.txt" 1 20 "legacy.txt" 21 40
expect_exit "clone in an untouched region of a changed file does not block" "$d" 0 --base "$(base_of "$d")" --threshold 3
expect_says "…and is reported as debt" "$d" yes "Pre-existing debt" --base "$(base_of "$d")" --threshold 3

# ── 4. It is a threshold, not zero tolerance ────────────────────────────────
d="$(repo under-threshold)"; change "$d" "new.txt" 30
report "$d" 100000 "new.txt" 1 30 "legacy.txt" 1 30
expect_exit "introduced clone below the threshold passes" "$d" 0 --base "$(base_of "$d")" --threshold 3

# ── 5. No baseline: gate everything, and say so ─────────────────────────────
# Silently skipping would be the 2.2.1 failure again — a gate that cannot measure
# must be loud, not absent.
d="$(repo no-base)"; change "$d" "new.txt" 30
report "$d" 200 "new.txt" 1 30 "legacy.txt" 1 30
expect_exit "no baseline still gates"        "$d" 1 --threshold 3
expect_says "no baseline is announced"       "$d" yes "ATTRIBUTION UNAVAILABLE" --threshold 3

# ── 6. An unreadable report is a failure, never a pass ──────────────────────
d="$(repo malformed)"; change "$d" "new.txt" 30
printf 'not json at all' > "$d/report.json"
expect_exit "malformed report blocks" "$d" 1 --base "$(base_of "$d")" --threshold 3

d="$(repo empty-total)"; change "$d" "new.txt" 30
printf '{"statistics":{"total":{"lines":0}},"duplicates":[]}' > "$d/report.json"
expect_exit "zero measured lines blocks" "$d" 1 --base "$(base_of "$d")" --threshold 3

rm -rf "$WORK"
echo "dup-attribution tests: $pass passed, exit=$fail"
exit $fail
