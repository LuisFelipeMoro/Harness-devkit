#!/usr/bin/env bash
# PostToolUse — the sensor behind the 80% context ceiling.
#
# CLAUDE.md states the ceiling in three places and enforced it in none: the model
# was asked to report its own context fill, which is the one thing it cannot
# measure. This reads the number from the session transcript, where the harness
# already records it, and injects the instruction the ceiling asks for.
#
# Current fill = input + cache_read + cache_creation + output of the last assistant
# turn: the prompt it was sent plus what it wrote, both of which are now in the
# window. It still lags by the tool results appended since that turn, so it reads
# low by at most one turn's tool output — which is why the warn line sits at 60%.
#
# Window: DEVKIT_CONTEXT_WINDOW when set. Otherwise 1M when the model id carries a
# 1m marker or any turn in the transcript already exceeded 200k — a window that
# held 300k is not a 200k window — else 200k. The transcript records the model id
# but not the window, so observed usage is the only evidence that cannot lie.
#
# Thresholds (fractions of the window):
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

read -r used pct ceiling warn <<<"$(tail -n 400 "$transcript" 2>/dev/null | python3 -c '
import sys, json, os
last = peak = 0
model = ""
for line in sys.stdin:
    try:
        d = json.loads(line)
    except Exception:
        continue
    # Subagent turns measure their own window, not this one: one landing in the
    # tail would mask the main thread fill or flip the window inference.
    if d.get("isSidechain"):
        continue
    m = d.get("message") or {}
    model = m.get("model") or model
    u = m.get("usage")
    if not isinstance(u, dict):
        continue
    total = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) \
        + (u.get("cache_creation_input_tokens") or 0) + (u.get("output_tokens") or 0)
    if total:
        last = total
        peak = max(peak, total)
def frac(name, default):
    try:
        return int(float(os.environ.get(name) or default) * 100)
    except ValueError:
        return int(default * 100)
try:
    window = int(os.environ.get("DEVKIT_CONTEXT_WINDOW") or 0)
except ValueError:
    window = 0
if window <= 0:
    window = 1000000 if ("1m" in model.lower() or peak > 200000) else 200000
print(last, last * 100 // window, frac("DEVKIT_CONTEXT_CEILING", 0.80), frac("DEVKIT_CONTEXT_WARN", 0.60))
' 2>/dev/null)"

# One interpreter per tool call, not three: this hook fires on every one.
case "$used$pct$ceiling$warn" in ''|*[!0-9]*) exit 0 ;; esac
[ "$used" -gt 0 ] || exit 0

if [ "$pct" -ge "$ceiling" ]; then
    # Past the ceiling the warn branch must not fire: downgrading "stop" to
    # "compact" on the next tool call is worse than saying nothing.
    [ -f "$state/ctx-ceiling" ] && exit 0
    : > "$state/ctx-ceiling"
    : > "$state/ctx-warn"
    echo "devkit context-budget: ${pct}% of the window used (${used} tok) — CEILING. \
Checkpoint now, then continue without waiting for the human: (1) update PROGRESS.md — \
Done / Current State / Next, precise enough to resume from cold; (2) commit and push the \
current branch (never main). Then carry on with the next step. When the harness compacts, \
precompact-snapshot.sh records branch, dirty files and commits, and session-bootstrap.sh \
re-injects them with PROGRESS.md. Past this line recall of mid-context detail drops, so \
re-read files instead of trusting memory of them."
    exit 0
fi

if [ "$pct" -ge "$warn" ] && [ ! -f "$state/ctx-warn" ]; then
    : > "$state/ctx-warn"
    echo "devkit context-budget: ${pct}% of the window used (${used} tok). Compact now — \
drop implementation code, test files and completed stories; keep the delivery file, the \
manifest and every score as one-line refs. Ceiling is ${ceiling}%."
fi
exit 0
