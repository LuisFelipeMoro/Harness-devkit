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
if [ -f "$SCRIPT_DIR/dup-attribution.py" ]; then
    cp "$SCRIPT_DIR/dup-attribution.py" "$REPO_ROOT/.git/hooks/dup-attribution.py"
    chmod +x "$REPO_ROOT/.git/hooks/dup-attribution.py"
    echo "✓ Installed: .git/hooks/dup-attribution.py"
fi

echo ""
echo "Git hooks installed. Run 'git commit --allow-empty -m \"test: verify hooks\"' to verify."
