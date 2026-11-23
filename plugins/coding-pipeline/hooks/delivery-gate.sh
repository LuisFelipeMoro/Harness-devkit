#!/usr/bin/env bash
# Stop — refuse to call a coding session finished with no gate evidence, and say
# what a session leaves behind that the next one must not inherit.
#
# Clean-state checks run first, whether or not source changed: a *.devkit-break
# marker means a break-run.sh mutation may still be in place, and an in_progress
# row in docs/plans/*/tasks.json means a coder was interrupted. A finding set is
# printed once per session; it repeats only after it changes (ADR-5).
#
# Then the original check: source files were written, and no test/lint/typecheck
# command was ever observed in the session.
#
# Default profile warns. strict blocks — but only once per session, because a
# Stop hook that blocks forever traps the operator rather than the mistake.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "stop:delivery-gate" || exit 0

input=$(cat)
state="$(devkit_state_dir "$input")" || state=""

# Root: the git toplevel of the payload cwd, the same root the bootstrap uses.
# Not a repo (or no cwd) → that directory.
cwd="$(devkit_field "$input" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || root=""
[ -n "$root" ] || root="$cwd"
case "$root" in -*) root="./$root" ;; esac

# Break markers. The prune list matches checkpoint-m.sh plus node_modules (NFR-2).
marker_total=0
marker_names=""
while IFS= read -r -d '' marker; do
    marker_total=$((marker_total + 1))
    [ "$marker_total" -le 5 ] || continue
    rel="${marker#"$root"/}"
    rel="$(printf '%s' "$rel" | tr -d '[:cntrl:]')"
    marker_names="${marker_names}${marker_names:+, }$rel"
done < <(find "$root" \( -name .git -o -name node_modules \) -prune -o -name '*.devkit-break' -print0 2>/dev/null)

marker_msg=""
if [ "$marker_total" -gt 0 ]; then
    more=""
    [ "$marker_total" -gt 5 ] && more=" (+$((marker_total - 5)) more)"
    marker_msg="devkit delivery-gate: leftover break marker(s) — a break-run.sh mutation may still be in place; restore the file and delete the marker: $marker_names$more"
fi

# in_progress rows. Paths go to python as argv; python validates each file and
# prints only `[slug] ID` for validated in_progress rows. A bad file prints nothing.
in_progress_rows() {
    python3 -I - "$@" <<'PY' 2>/dev/null
import json, os, re, sys

TASKS_CAP = 64 * 1024  # SEC-5
# Literals copied byte-identical from plugins/coding-pipeline/scripts/tasks_state.py.
ID_RE = re.compile(r"[A-Za-z][A-Za-z0-9._-]{0,15}")
STATUSES = ("todo", "in_progress", "done", "failed")
ROW_KEYS = {"id", "status", "evidence", "head", "updated"}
# The slug is the plan dir name; SEC-1 slug regex.
SLUG_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")


def row_ok(row):
    if not isinstance(row, dict) or set(row) != ROW_KEYS:
        return False
    if not isinstance(row["id"], str) or not ID_RE.fullmatch(row["id"]):
        return False
    if row["status"] not in STATUSES:
        return False
    return all(isinstance(row[k], str) for k in ("evidence", "head", "updated"))


for path in sys.argv[1:]:
    slug = os.path.basename(os.path.dirname(path))
    if not SLUG_RE.fullmatch(slug):
        continue
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(fd, "rb") as fh:
            raw = fh.read(TASKS_CAP + 1)
    except OSError:
        continue
    if len(raw) > TASKS_CAP:
        continue
    try:
        doc = json.loads(raw.decode("utf-8"))
    except (ValueError, RecursionError):
        continue
    rows = doc.get("rows") if isinstance(doc, dict) else None
    if not isinstance(rows, list) or not all(row_ok(r) for r in rows):
        continue
    ids = [r["id"] for r in rows]
    if len(set(ids)) != len(ids):
        continue
    for r in rows:
        if r["status"] == "in_progress":
            print(f"[{slug}] {r['id']}")
PY
}

plan_files=()
for f in "$root"/docs/plans/*/tasks.json; do
    [ -f "$f" ] && [ ! -L "$f" ] && [ ! -L "$(dirname "$f")" ] && plan_files+=("$f")
done
ip_out=""
if [ ${#plan_files[@]} -gt 0 ]; then
    ip_out="$(in_progress_rows ${plan_files[@]+"${plan_files[@]}"})"
fi

ip_names=""
ip_total=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    ip_total=$((ip_total + 1))
    [ "$ip_total" -le 5 ] || continue
    ip_names="${ip_names}${ip_names:+, }$row"
done <<<"$ip_out"

ip_msg=""
if [ "$ip_total" -gt 0 ]; then
    more=""
    [ "$ip_total" -gt 5 ] && more=" (+$((ip_total - 5)) more)"
    ip_msg="devkit delivery-gate: in_progress row(s) left at session end — the next session resumes them, it does not trust them: $ip_names$more"
fi

# One finding text for the whole clean state; empty when clean.
clean=""
[ -n "$marker_msg" ] && clean="$marker_msg"
if [ -n "$ip_msg" ]; then
    if [ -n "$clean" ]; then clean="$clean
$ip_msg"; else clean="$ip_msg"; fi
fi

# Dedupe against the last finding set this session. Without a state dir nothing
# is remembered, so the finding prints on every Stop and strict never blocks.
last=""
[ -n "$state" ] && last="$(cat "$state/clean-last" 2>/dev/null)"
fresh=0
if [ -n "$clean" ] && [ "$clean" != "$last" ]; then
    printf '%s\n' "$clean"
    fresh=1
fi
[ -n "$state" ] && printf '%s' "$clean" > "$state/clean-last" 2>/dev/null

if [ "$fresh" = 1 ] && [ -n "$state" ] && [ "$(devkit_profile)" = "strict" ] && [ ! -f "$state/clean-blocked" ]; then
    : > "$state/clean-blocked"
    echo "BLOCKED — devkit delivery-gate: resolve the clean-state finding above before ending the session. This block happens once per session."
    exit 2
fi

[ -n "$state" ] || exit 0

[ -s "$state/edits" ] || exit 0     # nothing was coded — nothing to gate
[ -s "$state/gates" ] && exit 0     # a gate command ran — evidence exists

count=$(sort -u "$state/edits" | wc -l | tr -d ' ')
msg="devkit delivery-gate: $count source file(s) changed this session, but no test, lint, or type-check command was observed. Run /validate-code before treating this as done."

if [ "$(devkit_profile)" = "strict" ] && [ ! -f "$state/gate-blocked" ]; then
    : > "$state/gate-blocked"
    echo "BLOCKED — $msg"
    exit 2
fi

echo "$msg"
exit 0
