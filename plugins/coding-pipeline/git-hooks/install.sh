#!/bin/bash
# Install git hooks into the current repo's .git/hooks/
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repository"; exit 1; }

for hook in pre-commit pre-push commit-msg; do
    if [ -f "$SCRIPT_DIR/$hook" ]; then
        cp "$SCRIPT_DIR/$hook" "$REPO_ROOT/.git/hooks/$hook"
        chmod +x "$REPO_ROOT/.git/hooks/$hook"
        echo "✓ Installed: .git/hooks/$hook"
    fi
done

# pre-push shells out to this for duplication attribution; it has to land beside
# the hook, or the gate degrades to whole-repo mode on every push.
# pre-push delegates the duplication gate to these; without them beside it the
# gate degrades to UNENFORCED on any machine with no global ~/.claude/git-hooks.
# release-content-guard.sh (G7) is called by both pre-commit and pre-push the
# same way — missing it here leaves the guard inert on both. base-lib.sh's
# resolve_base() is sourced by both dup-gate.sh and pre-push's fallback path —
# missing it degrades dup-gate.sh's attribution and pre-push's manual-run guard
# to whole-repo/skipped mode.
for helper in dup-gate.sh dup-attribution.py release-content-guard.sh base-lib.sh; do
    if [ -f "$SCRIPT_DIR/$helper" ]; then
        cp "$SCRIPT_DIR/$helper" "$REPO_ROOT/.git/hooks/$helper"
        chmod +x "$REPO_ROOT/.git/hooks/$helper"
        echo "✓ Installed: .git/hooks/$helper"
    fi
done

echo ""
echo "Git hooks installed. Run 'git commit --allow-empty -m \"test: verify hooks\"' to verify."
