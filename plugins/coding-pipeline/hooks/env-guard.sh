#!/usr/bin/env bash
# PreToolUse(Read|Bash|Grep|Glob) — block any access to .env / .envrc files.
#
# These may hold production secrets, so the agent must never read, echo, or log
# them. Payload shape is read through hook-lib's devkit_field, which accepts both
# the nested tool_input form and the flat form; an earlier version of this hook
# only understood the flat form and silently stopped blocking anything.
# Exit 2 blocks the call.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "pre:read:env-guard" || exit 0

input=$(cat)
target="$(devkit_field "$input" file_path path command pattern)"
[ -n "$target" ] || exit 0

if printf '%s' "$target" | grep -qE '(^|[/[:space:]"'\''])\.(env)(rc|(\.[^/[:space:]"'\'']+)?)?([/[:space:]"'\''`]|$)'; then
    echo "BLOCKED: .env / .envrc files may contain production secrets — Claude must never read them."
    echo "Need a value from one? Ask the operator for the variable name, and read it from the environment at runtime."
    exit 2
fi
exit 0
