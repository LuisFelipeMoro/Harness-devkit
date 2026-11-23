#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit) — block a hand edit of a plan's tasks.json.
#
# tasks.json holds the status of every Tasks row and its embedded checksum. Only
# scripts/tasks_state.py may write it: a hand edit can drop or reorder rows, or
# forge a status the next session would trust. The match is on the normalised absolute
# path, one directory level under docs/plans (parent dir resolved, so a symlinked dir cannot bypass it), so ordinary json files are never judged.
# Exit 2 blocks the call and prints the reason on stderr. Every other outcome exits 0:
# a path that does not match, a malformed payload, or an internal fault. A guard fault
# must never block every Write (fail open, SEC-4).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

# block — the agent learns the tool-ownership rule at the moment it tries the edit.
block() {
    echo "BLOCKED tasks.json is written only by scripts/tasks_state.py (init / set) — a hand edit can drop or reorder rows." >&2
    exit 2
}

# fail_open — any internal fault allows the call. Every internal error path routes here.
fail_open() { exit 0; }

devkit_hook_enabled "pre:write:tasks-state" || exit 0

input=$(cat)
target="$(devkit_field "$input" file_path)"
# Cheap pre-filter, case-insensitive: macOS filesystems fold case, so TASKS.JSON is the same file.
case "$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')" in
    *tasks.json) ;;
    *) exit 0 ;;
esac

cwd="$(devkit_field "$input" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
case "$target" in
    /*) abs="$target" ;;
    *) abs="$cwd/$target" ;;
esac
# Resolve the parent directory (symlinks, `..`, doubled slashes) so neither a symlinked
# plan dir nor a lexical trick hides the plan path; the whole resolved path is case-folded
# because a case-insensitive filesystem treats DOCS/Plans as docs/plans.
abs="$(python3 -c 'import os, sys
d, b = os.path.split(sys.argv[1])
print(os.path.join(os.path.realpath(d), b).casefold())' "$abs" 2>/dev/null)" || fail_open
[ -n "$abs" ] || fail_open

case "$abs" in
    */docs/plans/*/tasks.json) ;;
    *) exit 0 ;;
esac

# One directory level under plans: the `*` above also matches slashes, so the segment
# between `docs/plans/` and the file name must hold no further slash.
tail="${abs#*/docs/plans/}"
seg="${tail%/*}"
case "$seg" in
    */*) exit 0 ;;
esac

block
