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
# DEVKIT_DISPATCH_BUDGET tunes it (default 12). That is derived, not guessed: 3 per story
# (Coder, QA, Reviewer) + 3 planning + 2 delivery, which is a 3-story delivery. A larger
# delivery legitimately exceeds it, which is why this warns once and never blocks.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "pre:agent:dispatch-budget" || exit 0

input=$(cat)
state="$(devkit_state_dir "$input")" || exit 0

printf 'x' >> "$state/dispatches"
count=$(wc -c < "$state/dispatches" | tr -d ' ')
budget="${DEVKIT_DISPATCH_BUDGET:-12}"

[ "$count" -le "$budget" ] && exit 0
[ -f "$state/dispatch-warned" ] && exit 0
: > "$state/dispatch-warned"

echo "devkit dispatch-budget: $count subagent dispatches this session (budget $budget). \
Each one is a separate request with its own prompt. Before the next: can a mechanical \
check answer it — scripts/verify/*.sh, grep, or the gate output you already have? \
Expected shape is 3 per story — Coder, QA, Reviewer — plus 3 planning and 2 delivery."
exit 0
