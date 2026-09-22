#!/usr/bin/env bash
# PreCompact — what the session was doing, written down before the summary replaces it.
#
# Auto-compaction is what lets a long session continue without a human opening a
# new one. Its summary is a model's paraphrase, though, and the facts a resumed
# agent needs most — which branch, which files are dirty, what was last committed,
# whether PROGRESS.md was updated — are exactly the ones a paraphrase drops. This
# records them deterministically; session-bootstrap.sh re-injects them when the
# session restarts with source=compact.
#
# Never blocks. Exit 2 here cancels compaction, and when compaction was triggered
# by a full window that fails the request outright. Every path exits 0.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "pre:compact:snapshot" || exit 0

input=$(cat)
state="$(devkit_state_dir "$input")" || exit 0
cwd="$(devkit_field "$input" cwd)"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
cd "$cwd" 2>/dev/null || exit 0

snap="$state/precompact.md"
{
    echo "=== pre-compaction snapshot ($(date -u +%Y-%m-%dT%H:%M:%SZ), trigger: $(devkit_field "$input" trigger)) ==="
    echo "cwd: $cwd"
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
        echo "uncommitted (first 40):"
        git status --short 2>/dev/null | head -40 | sed 's/^/  /'
        echo "last commits:"
        git log --oneline -5 2>/dev/null | sed 's/^/  /'
        progress="$root/PROGRESS.md"
        # The checkpoint the 80% line asks for is the step most likely to be skipped
        # under pressure; say so plainly rather than let the summary imply it happened.
        if [ ! -f "$progress" ]; then
            echo "PROGRESS.md: MISSING — write it before continuing"
        elif [ -f "$state/ctx-ceiling" ] && [ "$state/ctx-ceiling" -nt "$progress" ]; then
            echo "PROGRESS.md: NOT updated since the 80% ceiling — update it before continuing"
        else
            echo "PROGRESS.md: up to date with the last ceiling checkpoint"
        fi
    else
        echo "not a git repository"
    fi
    echo "=== end snapshot ==="
} > "$snap.tmp" 2>/dev/null && mv "$snap.tmp" "$snap" 2>/dev/null
exit 0
