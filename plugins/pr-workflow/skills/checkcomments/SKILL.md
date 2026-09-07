---
name: checkcomments
description: List every open comment on the current branch's PR with file name and line number. Use when the user runs /checkcomments or asks to see PR review comments. Read-only — finds the open PR, fetches inline and general comments, and prints them grouped by file. Trigger phrases — "check comments", "PR comments", "what comments are open", "show review comments", "any feedback on my PR".
allowed-tools: [Bash]
---

# checkcomments

List all open comments on the current branch's PR, grouped by file. No actions taken, no files modified.

## Contract

**Inputs**: the current git branch (used to resolve the open PR); a repo with `gh` authenticated.
**Outputs**: a printed report — the PR URL, inline comments grouped by file and sorted by line, then general PR comments. No files written, no API mutations.
**Boundary**: does NOT reply to, resolve, or create comments; does NOT modify code, branches, or the PR.

**Dependencies** (verify before starting):
- `gh` — GitHub CLI, authenticated; used to resolve the PR and read comments via `gh api`.
- `git` — to read the current branch name.

## Steps

1. Verify prerequisites — `gh auth status`; stop if not authenticated.
2. Get the current branch (`git branch --show-current`); stop if detached HEAD.
3. Find the open PR for that branch; stop if none — report "No open PR found".
4. Resolve `OWNER` and `REPO`.
5. Fetch inline review comments (`pulls/.../comments`).
6. Fetch general PR comments (`issues/.../comments`).
7. Display: PR URL, inline comments grouped by file and sorted by line, then general comments.

Exact commands, API field handling, alignment rules, and the output example: `references/procedure.md`.

**Done when**: the PR URL and both comment sections are printed (each section shows its "No … comments." line when empty). If no open PR resolves for the branch, stop and report that instead of printing an empty report.
