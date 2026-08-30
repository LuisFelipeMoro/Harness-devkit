#!/usr/bin/env bash
# PreToolUse(Bash) — block irreversible commands the pipeline never needs.
#
# The devkit's own rule is that a delivery ends in a PR from a release branch,
# never a force-push or a reset on the mainline. That rule lived only in prose;
# this is the sensor for it. Exit 2 blocks the call.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "pre:bash:destructive-guard" || exit 0

input=$(cat)
cmd="$(devkit_field "$input" command)"
[ -n "$cmd" ] || exit 0

block() {
    echo "BLOCKED by devkit destructive-guard: $1"
    echo "If this is genuinely intended, run it yourself outside the agent, or set DEVKIT_DISABLED_HOOKS=pre:bash:destructive-guard for this session."
    exit 2
}

# Force-push or delete a remote branch. The pipeline opens PRs; it never rewrites
# published history.
case "$cmd" in
    *"git push"*"--force"*|*"git push"*" -f "*|*"git push"*" +"*)
        block "force-push. A delivery ends in a PR, never a rewritten remote branch." ;;
    *"git push"*"--delete"*|*"git push origin :"*)
        block "remote branch deletion." ;;
esac

# History destruction on a checked-out mainline.
case "$cmd" in
    *"git reset --hard"*|*"git checkout -- ."*|*"git clean -fd"*|*"git clean -df"*)
        branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
        case "$branch" in
            main|master|develop)
                block "$branch is checked out and this discards uncommitted work irreversibly." ;;
        esac ;;
esac

# Recursive deletes aimed at a root, a home directory, or a bare glob.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+)+'; then
    if printf '%s' "$cmd" | grep -qE 'rm[[:space:]]+-[a-zA-Z]*[[:space:]]*(/|~|\$HOME|\*)([[:space:]]|$)'; then
        block "recursive delete targeting a filesystem root, home directory, or bare glob."
    fi
fi

# Remote script execution — the classic supply-chain foothold.
if printf '%s' "$cmd" | grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'; then
    block "piping a downloaded script straight into a shell. Download it, read it, then run it."
fi

# World-writable permissions.
if printf '%s' "$cmd" | grep -qE 'chmod[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*777'; then
    block "chmod 777 makes the target world-writable."
fi

# Destructive SQL executed straight from the shell.
if printf '%s' "$cmd" | grep -qiE '(drop[[:space:]]+(database|table)|truncate[[:space:]]+table)'; then
    block "destructive DDL from the shell. Route schema changes through /engineering:database-migration, which requires a reversible down migration."
fi

exit 0
