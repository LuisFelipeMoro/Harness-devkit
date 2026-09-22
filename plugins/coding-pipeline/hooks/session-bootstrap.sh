#!/usr/bin/env bash
# SessionStart hook — Harness "Memory & Progress" component.
# Reconstructs cross-session context: prints PROGRESS.md so a new session boots
# with what was done, what failed, and the current state — instead of starting blind.
# This hook only injects context; it never blocks. Exit code is always 0.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

input=""
[ -t 0 ] || input="$(cat 2>/dev/null)"
source_kind="$(devkit_field "$input" source)"

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
progress="$root/PROGRESS.md"

if [ -f "$progress" ]; then
    echo "=== PROGRESS.md (resume context — written by pipelines/handoff last session) ==="
    cat "$progress"
    echo "=== end PROGRESS.md ==="
else
    echo "No PROGRESS.md at repo root — fresh start. Pipelines and /handoff will create it (see references/progress-file.md)."
fi

# After auto-compaction the session continues on its own — no human opens a new
# one — so the deterministic snapshot precompact-snapshot.sh wrote goes back in,
# and the context-budget latches re-arm: the window just emptied, and the next
# climb to 80% must be announced again.
if [ "$source_kind" = "compact" ] && state="$(devkit_state_dir "$input")"; then
    # Same session id only. Guessing by directory would hand one session another
    # concurrent session's branch and dirty files as authoritative resume state.
    snap="$state/precompact.md"
    if [ -f "$snap" ]; then
        cat "$snap"
        rm -f "$snap"
    fi
    rm -f "$state/ctx-warn" "$state/ctx-ceiling"
    echo "Resumed after compaction. Continue the task from PROGRESS.md and the snapshot above;"
    echo "if the snapshot flags PROGRESS.md as stale, update it first. Do not ask the human to restart."
fi

# Prune session-tracker scratch dirs older than a day so /tmp does not accumulate.
find "${TMPDIR:-/tmp}/claude-devkit" -mindepth 1 -maxdepth 1 -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true

exit 0
