#!/usr/bin/env bash
# PostToolUse — the sensor behind the 80% context ceiling.
#
# CLAUDE.md states the ceiling in three places and enforced it in none: the model
# was asked to report its own context fill, which is the one thing it cannot
# measure. This reads the number from the session transcript, where the harness
# already records it, and injects the instruction the ceiling asks for.
#
# Current fill = input + cache_read + cache_creation of the last assistant turn.
# cache_read dominates and is exactly the re-sent prefix, so the sum is the real
# window occupancy, not an estimate.
#
# Thresholds (fractions of DEVKIT_CONTEXT_WINDOW):
#   DEVKIT_CONTEXT_WARN     0.60  — compact completed epics to one-line refs
#   DEVKIT_CONTEXT_CEILING  0.80  — stop and /handoff
# Each fires once per session; a hook that repeats every tool call trains the
# operator to ignore it, and the whole point is that the 80% line gets obeyed.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "post:context-budget" || exit 0

input=$(cat)
state="$(devkit_state_dir "$input")" || exit 0

transcript="$(devkit_field "$input" transcript_path)"

# Fall back to reconstructing the path from session_id + cwd when the payload
# does not carry it — same file, derived the way Claude Code names it.
if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
    sid="$(devkit_field "$input" session_id)"
    cwd="$(devkit_field "$input" cwd)"
    [ -n "$cwd" ] || cwd="$PWD"
    slug="$(printf '%s' "$cwd" | tr -c 'A-Za-z0-9' '-')"
    transcript="$HOME/.claude/projects/$slug/$sid.jsonl"
fi
[ -f "$transcript" ] || exit 0

used="$(tail -n 400 "$transcript" 2>/dev/null | python3 -c '
import sys, json
last = 0
for line in sys.stdin:
    try:
        d = json.loads(line)
    except Exception:
        continue
    u = (d.get("message") or {}).get("usage")
    if not isinstance(u, dict):
        continue
    total = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) \
        + (u.get("cache_creation_input_tokens") or 0)
    if total:
        last = total
print(last)
' 2>/dev/null)"

case "$used" in ''|*[!0-9]*) exit 0 ;; esac
[ "$used" -gt 0 ] || exit 0

window="${DEVKIT_CONTEXT_WINDOW:-200000}"
pct=$(( used * 100 / window ))
ceiling=$(python3 -c "print(int(float('${DEVKIT_CONTEXT_CEILING:-0.80}')*100))" 2>/dev/null || echo 80)
warn=$(python3 -c "print(int(float('${DEVKIT_CONTEXT_WARN:-0.60}')*100))" 2>/dev/null || echo 60)

if [ "$pct" -ge "$ceiling" ]; then
    # Past the ceiling the warn branch must not fire: downgrading "stop" to
    # "compact" on the next tool call is worse than saying nothing.
    [ -f "$state/ctx-ceiling" ] && exit 0
    : > "$state/ctx-ceiling"
    : > "$state/ctx-warn"
    echo "devkit context-budget: ${pct}% of the window used (${used} tok) — CEILING. \
Stop adding work. Run /handoff now: write PROGRESS.md, push the current branch, and \
resume in a fresh session from the delivery file's Status. Do not push further; past this \
line recall of mid-context detail drops and confident invention rises."
    exit 0
fi

if [ "$pct" -ge "$warn" ] && [ ! -f "$state/ctx-warn" ]; then
    : > "$state/ctx-warn"
    echo "devkit context-budget: ${pct}% of the window used (${used} tok). Compact now — \
drop implementation code, test files and completed stories; keep the delivery file, the \
manifest and every score as one-line refs. Ceiling is ${ceiling}%."
fi
exit 0
