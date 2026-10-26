#!/bin/bash
# PostToolUse hook: after git push, tell the user how many comments are open and suggest /pr-fix.
# Exits silently (0) if command is not a push or no open PR exists for this branch.

input=$(cat)
command=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('command', '') or d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" <<< "$input" 2>/dev/null)

if ! echo "$command" | grep -qE '(git push|rtk git push)'; then
    exit 0
fi

branch=$(git branch --show-current 2>/dev/null)
[ -z "$branch" ] && exit 0

pr_number=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null)
[ -z "$pr_number" ] && exit 0

n=$(gh api "repos/{owner}/{repo}/pulls/$pr_number/comments" --jq 'length' 2>/dev/null)
echo "PR #$pr_number has ${n:-0} open inline comments. Run /pr-fix to triage them (or /pr-fix --list to only read)."
