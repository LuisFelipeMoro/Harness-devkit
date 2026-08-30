#!/usr/bin/env bash
# Stop — refuse to call a coding session finished with no gate evidence.
#
# CLAUDE.md already says every coding task ends in /engineering:code-review-gate.
# That was a Guide with no Sensor behind it, so it held only when the model
# remembered it. This checks the recorded facts: source files were written, and
# no test/lint/typecheck command was ever observed in the session.
#
# Default profile warns. strict blocks — but only once per session, because a
# Stop hook that blocks forever traps the operator rather than the mistake.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "stop:delivery-gate" || exit 0

input=$(cat)
state="$(devkit_state_dir "$input")" || exit 0

[ -s "$state/edits" ] || exit 0     # nothing was coded — nothing to gate
[ -s "$state/gates" ] && exit 0     # a gate command ran — evidence exists

count=$(sort -u "$state/edits" | wc -l | tr -d ' ')
msg="devkit delivery-gate: $count source file(s) changed this session, but no test, lint, or type-check command was observed. Run /engineering:code-review-gate before treating this as done."

if [ "$(devkit_profile)" = "strict" ] && [ ! -f "$state/gate-blocked" ]; then
    : > "$state/gate-blocked"
    echo "BLOCKED — $msg"
    exit 2
fi

echo "$msg"
exit 0
