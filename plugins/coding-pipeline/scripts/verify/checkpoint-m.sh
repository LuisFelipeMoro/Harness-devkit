#!/usr/bin/env bash
# checkpoint-m.sh — the mechanical half of a mid-story checkpoint.
#
# A Coder round that only ever hears about the first thing wrong fixes that
# one thing and re-runs blind to the rest — so every check here runs to
# completion and every failure is collected before anything is reported,
# never a bail-out on the first miss. What it checks, composed from sensors
# that already exist rather than re-typed: every Test Case row is actually
# implemented (spec-coverage.sh), the changed-file set is exactly what was
# declared — no silent extra edit, no silent revert, a rename or a deletion
# counted as touching every path it touches — no stray commit sits ahead of
# the base, no `*.devkit-break` marker was left behind by an interrupted
# break-run.sh, duplication stays under the delivery's own gate
# (git-hooks/dup-gate.sh), the declared agent roster still matches the real
# diff (classify-diff.sh, opt-in via --declared), and an arbitrary gates
# command exits clean (opt-in via --gates).
#
# Usage: checkpoint-m.sh --base <ref> --spec <file.md> --tests <path>...
#            --expect <file>... [--declared cosmetic|light|standard|full]
#            [--allow-commits] [--gates "<cmd>"]
# Exit 0 — every check passed: `M: PASS`.
# Exit 1 — one or more checks failed: one `M: FAIL <check> — <detail>` line
#          per failure, then `M: FAIL (n)`.
# Exit 2 — bad usage, not a git repository, or a sub-sensor itself came back
#          unmeasured (spec-coverage.sh / classify-diff.sh exiting 2) — never
#          folded into an ordinary FAIL, because "could not measure" is not
#          the same claim as "measured and it passed".
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "usage: checkpoint-m.sh --base <ref> --spec <file.md> --tests <path>..." >&2
    echo "           --expect <file>... [--declared cosmetic|light|standard|full]" >&2
    echo "           [--allow-commits] [--gates \"<cmd>\"]" >&2
    exit 2
}

TMPFILES=()
cleanup_tmp() {
    [ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}"
}
trap cleanup_tmp EXIT

unmeasured() {
    echo "M: UNMEASURED — $1" >&2
    exit 2
}

new_tmp() {  # new_tmp <prefix> — prints the path, registers it for cleanup
    local t
    t=$(mktemp "${TMPDIR:-/tmp}/checkpoint-m.$1.XXXXXX") || unmeasured "could not create a temp file"
    TMPFILES+=("$t")
    printf '%s' "$t"
}

fail_count=0
fail() {  # fail <check> <detail>
    echo "M: FAIL $1 — $2"
    fail_count=$((fail_count + 1))
}

base=""
spec=""
declared=""
gates_cmd=""
allow_commits=0
TESTS=()
EXPECT=()
while [ $# -gt 0 ]; do
    case "$1" in
        --base)
            [ $# -ge 2 ] || usage
            base="$2"
            shift 2
            ;;
        --spec)
            [ $# -ge 2 ] || usage
            spec="$2"
            shift 2
            ;;
        --tests)
            shift
            while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
                TESTS+=("$1")
                shift
            done
            ;;
        --expect)
            shift
            while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
                EXPECT+=("$1")
                shift
            done
            ;;
        --declared)
            [ $# -ge 2 ] || usage
            declared="$2"
            shift 2
            ;;
        --allow-commits)
            allow_commits=1
            shift
            ;;
        --gates)
            [ $# -ge 2 ] || usage
            gates_cmd="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

[ -n "$base" ] || usage
[ -n "$spec" ] || usage
[ -f "$spec" ] || { echo "checkpoint-m: usage — no such spec file '$spec'" >&2; exit 2; }
[ ${#TESTS[@]} -gt 0 ] || usage
[ ${#EXPECT[@]} -gt 0 ] || usage

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    unmeasured "not a git repository"
fi
top="$(git rev-parse --show-toplevel)"
cd "$top" || unmeasured "could not enter repository root $top"

# Same charset/range guard diff-lib.sh applies before ever handing a ref to
# git: a leading dash reads as an option, ".." turns a single ref into a
# range, and a metacharacter reaches a shell somewhere downstream.
if ! [[ "$base" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || [[ "$base" == *".."* ]]; then
    unmeasured "invalid base ref '$base'"
fi
if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
    unmeasured "unknown base ref '$base'"
fi

# ── file-set: git diff <base>...HEAD ∪ git diff HEAD (working tree) ∪ ───────
# ── untracked files, docs/ excluded ─────────────────────────────────────────
touched=()
add_touched() {
    case "$1" in
        docs/*) return 0 ;;
    esac
    touched+=("$1")
}

# A rename/copy status carries two paths (old, new) and both count as
# touched; every other status carries one. Read as an indexed array rather
# than a streaming state machine so a NUL-delimited git diff -z output can be
# walked with a plain index instead of hand-rolled state transitions.
collect_namestatus() {  # collect_namestatus <NUL-delimited name-status file>
    local tmp="$1" t
    local toks=()
    while IFS= read -r -d '' t; do
        toks+=("$t")
    done < "$tmp"
    local i=0 n=${#toks[@]} st
    while [ "$i" -lt "$n" ]; do
        st="${toks[$i]}"
        i=$((i + 1))
        case "$st" in
            R*|C*)
                add_touched "${toks[$i]}"
                add_touched "${toks[$((i + 1))]}"
                i=$((i + 2))
                ;;
            *)
                add_touched "${toks[$i]}"
                i=$((i + 1))
                ;;
        esac
    done
}

ns_committed="$(new_tmp ns-committed)"
if ! git diff -z -M --name-status "$base...HEAD" -- >"$ns_committed" 2>/dev/null; then
    unmeasured "git diff $base...HEAD failed"
fi
collect_namestatus "$ns_committed"

ns_worktree="$(new_tmp ns-worktree)"
if ! git diff -z -M --name-status HEAD -- >"$ns_worktree" 2>/dev/null; then
    unmeasured "git diff HEAD (working tree) failed"
fi
collect_namestatus "$ns_worktree"

ns_untracked="$(new_tmp untracked)"
if ! git ls-files --others --exclude-standard -z >"$ns_untracked" 2>/dev/null; then
    unmeasured "git ls-files --others failed"
fi
untracked_f=""
while IFS= read -r -d '' untracked_f; do
    add_touched "$untracked_f"
done < "$ns_untracked"

in_touched() {  # in_touched <path>
    local needle="$1" x
    [ ${#touched[@]} -gt 0 ] || return 1
    for x in "${touched[@]}"; do
        [ "$x" = "$needle" ] && return 0
    done
    return 1
}

in_expect() {  # in_expect <path>
    local needle="$1" x
    [ ${#EXPECT[@]} -gt 0 ] || return 1
    for x in "${EXPECT[@]}"; do
        [ "$x" = "$needle" ] && return 0
    done
    return 1
}

in_seen() {  # in_seen <path> — dedup guard so a file touched by both the
             # committed and working-tree diff is not reported as "extra" twice
    local needle="$1" x
    [ ${#seen[@]} -gt 0 ] || return 1
    for x in "${seen[@]}"; do
        [ "$x" = "$needle" ] && return 0
    done
    return 1
}

for e in "${EXPECT[@]}"; do
    in_touched "$e" || fail "file-set" "missing $e"
done
seen=()
if [ ${#touched[@]} -gt 0 ]; then
    for p in "${touched[@]}"; do
        in_seen "$p" && continue
        seen+=("$p")
        in_expect "$p" || fail "file-set" "extra $p"
    done
fi

# ── spec rows: every Test Case row actually implemented ─────────────────────
sc_out=$(bash "$SCRIPT_DIR/spec-coverage.sh" "$spec" "${TESTS[@]}" 2>&1)
sc_rc=$?
case "$sc_rc" in
    0) : ;;
    1)
        while IFS= read -r line; do
            case "$line" in
                "MISSING ROW: "*) fail "spec-rows" "missing row: ${line#MISSING ROW: }" ;;
            esac
        done <<EOF
$sc_out
EOF
        ;;
    *) unmeasured "spec-coverage: $sc_out" ;;
esac

# ── commits: nothing lands on HEAD beyond --base unless --allow-commits ─────
if [ "$allow_commits" -eq 0 ]; then
    ahead=$(git rev-list --count "$base..HEAD" 2>/dev/null)
    [ -n "$ahead" ] || unmeasured "could not count commits ahead of $base"
    if [ "$ahead" -gt 0 ]; then
        fail "commits" "$ahead commit(s) ahead of $base (pass --allow-commits if that is expected)"
    fi
fi

# ── break-marker: no interrupted break-run.sh left a mutation in place ──────
mk_tmp="$(new_tmp markers)"
find . -name .git -prune -o -name '*.devkit-break' -print0 >"$mk_tmp" 2>/dev/null
marker_f=""
while IFS= read -r -d '' marker_f; do
    fail "break-marker" "leftover marker ${marker_f#./}"
done < "$mk_tmp"

# ── dup: git-hooks/dup-gate.sh, resolved the same way pre-push resolves it ──
# (0 pass, 1 fail, 2 UNENFORCED — already warned by the gate itself — is
# never rendered as a fail here, exactly as pre-push treats it. Any other
# exit — the sub-sensor crashed rather than measured — is unmeasured, never
# folded into a silent pass, same rule the spec-coverage/classify-diff calls
# already apply.)
# DEVKIT_DUP_GATE overrides the resolved path — test-only hook so a fixture
# can stub the sub-sensor's exit code without touching the real dup-gate.sh.
dup_gate="${DEVKIT_DUP_GATE:-}"
if [ -z "$dup_gate" ]; then
    dup_gate="$SCRIPT_DIR/../../git-hooks/dup-gate.sh"
    [ -f "$dup_gate" ] || dup_gate="$HOME/.claude/git-hooks/dup-gate.sh"
fi
if [ -f "$dup_gate" ]; then
    dup_out=$(bash "$dup_gate" 2>&1)
    dup_rc=$?
    case "$dup_rc" in
        0|2) : ;;
        1)
            dup_detail=$(printf '%s\n' "$dup_out" | grep '^FAIL:' | tail -1)
            fail "dup" "${dup_detail:-duplication gate failed}"
            ;;
        *) unmeasured "dup-gate: $dup_out" ;;
    esac
fi

# ── roster: the declared agent roster still matches the real diff (opt-in) ──
if [ -n "$declared" ]; then
    cd_out=$(bash "$SCRIPT_DIR/classify-diff.sh" --diff "$base" --declared "$declared" 2>&1)
    cd_rc=$?
    case "$cd_rc" in
        0) : ;;
        1)
            cd_detail=$(printf '%s\n' "$cd_out" | grep '^ROSTER:' | tail -1)
            fail "roster" "${cd_detail:-roster escalation required}"
            ;;
        *) unmeasured "classify-diff: $cd_out" ;;
    esac
fi

# ── gates: an arbitrary command this checkpoint requires to exit clean ──────
if [ -n "$gates_cmd" ]; then
    gates_out=$(bash -c "$gates_cmd" 2>&1)
    gates_rc=$?
    if [ "$gates_rc" -ne 0 ]; then
        gates_detail=$(printf '%s\n' "$gates_out" | tail -1)
        fail "gates" "\`$gates_cmd\` exited $gates_rc${gates_detail:+ — $gates_detail}"
    fi
fi

if [ "$fail_count" -gt 0 ]; then
    echo "M: FAIL ($fail_count)"
    exit 1
fi
echo "M: PASS"
exit 0
