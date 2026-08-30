#!/usr/bin/env bash
# Install git hook templates globally and wire them into the current repo.
# Companion step when the devkit was installed as a Claude Code plugin: a plugin
# cannot write to .git/hooks/, so the git-side gates need this one command.
#
# Platform support:
#   Linux / macOS  — bash .claude/scripts/install-git-hooks.sh
#
# ┌─ USE THIS SCRIPT when ────────────────────────────────────────────────────┐
# │  • You installed via the Claude Code plugin manager and also want         │
# │    pre-commit format checks, pre-push quality gates, and commit-msg       │
# │    Conventional Commits enforcement wired at the OS level                 │
# │  • Adding this devkit to a new repo after already having the plugin       │
# │    → just run: bash ~/.claude/git-hooks/install.sh                        │
# └───────────────────────────────────────────────────────────────────────────┘
#
# ┌─ SKIP THIS SCRIPT when ───────────────────────────────────────────────────┐
# │  • You only want Claude Code skills/agents with no git-level enforcement  │
# │    → `claude plugin install` alone is sufficient                          │
# │  • Your team already has its own pre-commit / pre-push hooks in place     │
# │  • You ran install.sh or install-global.sh — they already do this        │
# └───────────────────────────────────────────────────────────────────────────┘
#
# Usage: bash .claude/scripts/install-git-hooks.sh
set -e

DOTCLAUDE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOBAL="$HOME/.claude"

mkdir -p "$GLOBAL/git-hooks"

# Stage hook templates globally so they're available for future repos without
# needing the original .claude/ folder present.
if ls "$DOTCLAUDE/git-hooks/"* >/dev/null 2>&1; then
    cp "$DOTCLAUDE/git-hooks/"* "$GLOBAL/git-hooks/"
    chmod +x "$GLOBAL/git-hooks/pre-commit" \
             "$GLOBAL/git-hooks/pre-push" \
             "$GLOBAL/git-hooks/commit-msg" \
             "$GLOBAL/git-hooks/install.sh" 2>/dev/null || true
    echo "✓ git-hook templates staged to ~/.claude/git-hooks/"
fi

# Wire into current repo
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    bash "$DOTCLAUDE/git-hooks/install.sh"
else
    echo "Not in a git repo — skipped per-repo wiring."
    echo "To install later, run: bash ~/.claude/git-hooks/install.sh"
fi

echo ""
echo "To wire Claude Code hooks, add to ~/.claude/settings.json:"
echo '  "hooks": {'
echo '    "SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/session-bootstrap.sh"}]}],'
echo '    "PreToolUse":  [{"matcher": "Read",  "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/env-guard.sh", "timeout": 3}]}],'
echo '    "PostToolUse": [{"matcher": "Bash",  "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/pr-review-responder.sh"}]}]'
echo '  }'
