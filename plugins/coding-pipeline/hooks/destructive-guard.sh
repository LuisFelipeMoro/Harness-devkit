#!/usr/bin/env bash
# PreToolUse(Bash) — block irreversible commands the pipeline never needs.
#
# The devkit's own rule is that a delivery ends in a PR from a release branch,
# never a force-push or a reset on the mainline. That rule lived only in prose;
# this is the sensor for it. Exit 2 blocks the call.
#
# Precision matters as much as coverage here. A guard that fires on a command
# that merely *mentions* something dangerous trains the operator to disable it,
# and a disabled guard blocks nothing at all. So the checks below look at the
# command's structure, not at whether a scary substring appears somewhere in it.
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

# ── Force-push and remote branch deletion ────────────────────────────────────
# Only the `git push` invocation itself is inspected, cut at the first command
# separator. Scanning the whole line meant `git push origin main && echo 1 + 2`
# tripped the force-refspec check on an unrelated plus sign.
push_seg="$(printf '%s' "$cmd" | grep -oE 'git[[:space:]]+push[^;&|]*' | head -1)"
if [ -n "$push_seg" ]; then
    # --force, --force-with-lease, or a bundled short flag such as -f / -fu.
    if printf '%s' "$push_seg" | grep -qE '(^|[[:space:]])(--force([a-z-]*)?|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|=|$)'; then
        block "force-push. A delivery ends in a PR, never a rewritten remote branch."
    fi
    # A leading + on a refspec is a force push in disguise: git push origin +main
    if printf '%s' "$push_seg" | grep -qE '[[:space:]]\+[A-Za-z0-9_./-]+'; then
        block "force-push via a + refspec. A delivery ends in a PR, never a rewritten remote branch."
    fi
    if printf '%s' "$push_seg" | grep -qE '(^|[[:space:]])(--delete|-d)([[:space:]]|$)|[[:space:]]:[A-Za-z0-9_./-]+'; then
        block "remote branch deletion."
    fi
fi

# ── History destruction on a checked-out mainline ────────────────────────────
case "$cmd" in
    *"git reset --hard"*|*"git checkout -- ."*|*"git clean -fd"*|*"git clean -df"*)
        branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
        case "$branch" in
            main|master|develop)
                block "$branch is checked out and this discards uncommitted work irreversibly." ;;
        esac ;;
esac

# ── Recursive deletes aimed at a root, a home directory, or a bare glob ──────
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+)+'; then
    if printf '%s' "$cmd" | grep -qE 'rm[[:space:]]+-[a-zA-Z]*[[:space:]]*(/|~|\$HOME|\*)([[:space:]]|$)'; then
        block "recursive delete targeting a filesystem root, home directory, or bare glob."
    fi
fi

# ── Remote script execution — the classic supply-chain foothold ─────────────
if printf '%s' "$cmd" | grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'; then
    block "piping a downloaded script straight into a shell. Download it, read it, then run it."
fi

# ── World-writable permissions ──────────────────────────────────────────────
if printf '%s' "$cmd" | grep -qE 'chmod[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*777'; then
    block "chmod 777 makes the target world-writable."
fi

# ── Destructive DDL actually being executed ─────────────────────────────────
# The statement alone is not enough: `grep -rn "DROP TABLE" migrations/` reads
# about DDL, it does not run any. A database client has to be in the command
# for this to be an execution rather than a mention.
if printf '%s' "$cmd" | grep -qiE '(drop[[:space:]]+(database|table)|truncate[[:space:]]+table)'; then
    if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(psql|mysql|mariadb|sqlite3|mongosh|mongo|clickhouse-client|cockroach|duckdb|surreal|redis-cli)([[:space:]]|$)'; then
        block "destructive DDL executed through a database client. Route schema changes through /engineering:database-migration, which requires a reversible down migration."
    fi
fi

exit 0
