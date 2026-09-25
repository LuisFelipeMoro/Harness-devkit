#!/usr/bin/env bash
# PreToolUse(Agent|Task) — count subagent dispatches against a session budget.
#
# CLAUDE.md's Sub-agent Discipline caps three per *turn* and nothing per session,
# so a pipeline can spend sixty dispatches without ever breaking the rule. Each
# dispatch is its own request with its own prompt, which is why subagent-heavy
# sessions read as a separate cost line from long ones.
#
# This counts, warns once at the budget, and never blocks: a pipeline legitimately
# needs many dispatches, and a guard that stops one mid-delivery strands the work.
# DEVKIT_DISPATCH_BUDGET tunes it (default 14). That is derived, not guessed: 3 per story
# (Coder, QA, Reviewer) + 3 planning + 2 delivery, which is a 3-story delivery. A larger
# delivery legitimately exceeds it, which is why this warns once and never blocks.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "pre:agent:dispatch-budget" || exit 0

input=$(cat)

# ── prompt-size warning — oversized single prompts stalled dispatches ───────
# Advisory only, per dispatch (no session latch): a prompt is either too big
# this time or it is not. DEVKIT_PROMPT_MAX_CHARS/DEVKIT_PROMPT_MAX_FILES tune
# the thresholds; devkit_field is the one JSON reader every hook shares.
prompt="$(devkit_field "$input" tool_input.prompt)"
if [ -n "$prompt" ]; then
    prompt_max_chars="${DEVKIT_PROMPT_MAX_CHARS:-6000}"
    prompt_max_files="${DEVKIT_PROMPT_MAX_FILES:-8}"
    prompt_chars=${#prompt}
    # File-path-shaped tokens: at least one path separator, ending in a
    # dotted extension. A heuristic, not a parser — good enough to flag "this
    # prompt names a pile of files", not to enumerate them precisely.
    prompt_files=$(printf '%s' "$prompt" \
        | grep -oE '[A-Za-z0-9_.~/-]*/[A-Za-z0-9_.-]+\.[A-Za-z0-9]+' \
        | sort -u | wc -l | tr -d ' ')
    if [ "$prompt_chars" -gt "$prompt_max_chars" ] || [ "$prompt_files" -gt "$prompt_max_files" ]; then
        echo "devkit dispatch-budget: prompt is ${prompt_chars} chars and names ${prompt_files} distinct \
file paths (limits: ${prompt_max_chars} chars / ${prompt_max_files} files) — split the task."
    fi
fi

state="$(devkit_state_dir "$input")" || exit 0

printf 'x' >> "$state/dispatches"
count=$(wc -c < "$state/dispatches" | tr -d ' ')
budget="${DEVKIT_DISPATCH_BUDGET:-14}"

[ "$count" -le "$budget" ] && exit 0
[ -f "$state/dispatch-warned" ] && exit 0
: > "$state/dispatch-warned"

echo "devkit dispatch-budget: $count subagent dispatches this session (budget $budget). \
Each one is a separate request with its own prompt. Before the next: can a mechanical \
check answer it — scripts/verify/*.sh, grep, or the gate output you already have? \
Expected shape is 3 per story — Coder, QA, Reviewer — plus 3 planning and 2 delivery."
exit 0
