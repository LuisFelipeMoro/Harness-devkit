#!/usr/bin/env bash
# Shared helpers for devkit hooks. Sourced, never executed.
#
# Profiles let an operator dial the sensors without editing hooks.json:
#   DEVKIT_HOOK_PROFILE=off       — every optional hook is inert
#   DEVKIT_HOOK_PROFILE=standard  — default; guards block, advisory hooks warn
#   DEVKIT_HOOK_PROFILE=strict    — advisory hooks block too
#   DEVKIT_DISABLED_HOOKS=id,id   — disable individual hooks by id
#
# A hook that cannot parse its input must exit 0. Failing open on a parse error
# is deliberate: a guard that blocks every tool call because of a payload shape
# change is worse than the risk it guards against.

devkit_profile() {
    printf '%s' "${DEVKIT_HOOK_PROFILE:-standard}"
}

# devkit_hook_enabled <hook-id> — exit 1 when this hook should not run.
devkit_hook_enabled() {
    [ "$(devkit_profile)" = "off" ] && return 1
    case ",${DEVKIT_DISABLED_HOOKS:-}," in
        *",$1,"*) return 1 ;;
    esac
    return 0
}

# devkit_field <json> <dotted.path> [more paths...] — first non-empty wins.
# Reads both the current payload shape (tool_input.*) and the flat shape, so a
# hook keeps working across harness payload revisions.
devkit_field() {
    local json="$1"; shift
    printf '%s' "$json" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
for path in sys.argv[1:]:
    cur = d
    for part in path.split("."):
        cur = cur.get(part) if isinstance(cur, dict) else None
        if cur is None:
            break
    if cur in (None, ""):
        cur = ti.get(path) if isinstance(ti, dict) else None
    if isinstance(cur, (dict, list)):
        cur = json.dumps(cur)
    if cur not in (None, ""):
        print(cur)
        break
' "$@" 2>/dev/null
}

# devkit_state_dir <json> — per-session scratch dir, created on demand.
devkit_state_dir() {
    local sid
    sid="$(devkit_field "$1" session_id)"
    [ -n "$sid" ] || sid="nosession"
    # Session ids come from the harness; keep only path-safe characters.
    sid="$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_-')"
    local dir="${TMPDIR:-/tmp}/claude-devkit/${sid:-nosession}"
    mkdir -p "$dir" 2>/dev/null || return 1
    printf '%s' "$dir"
}
