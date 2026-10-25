# checkcomments — Commands & Output Format

All commands are read-only. Replace `<BRANCH>`, `<OWNER>`, `<REPO>`, `<PR_NUMBER>` with the values resolved in earlier steps.

## Step 1 — Verify prerequisites

```bash
gh auth status
```

If this fails, report the error and stop. Do not proceed without a working `gh` session.

## Step 2 — Get current branch

```bash
git branch --show-current
```

If the output is empty (detached HEAD), report "Not on a named branch — cannot look up a PR" and stop. Store the result as `BRANCH`.

## Step 3 — Find open PR

```bash
PR_NUMBER=$(gh pr list --head <BRANCH> --state open --json number --jq '.[0].number')
PR_URL=$(gh pr list --head <BRANCH> --state open --json url --jq '.[0].url')
```

If either result is empty or null, report "No open PR found for branch `<BRANCH>`" and stop. Store `PR_NUMBER` and `PR_URL`.

## Step 4 — Get owner and repo

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
```

Store `OWNER` and `REPO`.

## Step 5 — Fetch inline review comments

```bash
gh api "repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/comments?per_page=100"
```

Returned chronologically (oldest first, the API default). Each item has:
- `path` — file path relative to repo root
- `line` — current line number. If `line` is null, fall back to `original_line`. If both are null (outdated/deleted context), display the line as `?` (e.g. `filename.kt:?`)
- `body` — comment text
- `id` — comment ID (used internally; not displayed in output)

## Step 6 — Fetch general PR comments

```bash
gh api "repos/<OWNER>/<REPO>/issues/<PR_NUMBER>/comments?per_page=100"
```

Returned chronologically (oldest first). Each item has:
- `body` — comment text
- `id` — comment ID
- No `path` or `line` — these are top-level PR comments, not tied to a file

## Step 7 — Display results

Print the PR URL first, then the comment list.

Group inline comments by file, sorted by line number. Truncate comment bodies to 80 characters with `...` if longer.

For alignment, left-align the `filename:line` part padded to the width of the longest `filename:line` entry in the list, then ` — `, then the truncated comment body in quotes.

Output format (example where `SuperNiceController.kt:183` is the longest entry at 26 chars):

```text
PR: <PR_URL>

### Inline comments

SuperNiceController.kt:183  — "You're calling the same function twice..."
SuperNiceController.kt:210  — "This method is too long, consider extracting..."
AuthService.kt:44           — "Missing null check here"

### General comments

[General] — "Overall this PR looks good but the error handling needs work"
```

- If there are no inline comments, print "No inline comments." under that section.
- If there are no general comments, print "No general comments." under that section.
- If there are no comments at all, print "No comments found on PR #<PR_NUMBER>."
