# PR comments — triage additions, replies and push

Fetching and listing follow `procedure.md` (this folder) exactly. Additions for `/pr-fix`:

```bash
gh api --paginate "repos/$OWNER/$REPO/pulls/<PR_NUMBER>/reviews?per_page=100"   # review bodies: id, state, body (skip empty)
```
- A comment with `in_reply_to_id` is part of a thread: triage the thread once, by its first comment.
- Skip comments by the PR author and bot status messages (CI, coverage bots) unless they name a defect.
- `line` and `original_line` both null (outdated) → class it not-actionable unless the code still has the problem.

## Reply and push (only after the user's explicit yes)

```bash
# reply in an inline thread (id = the thread's first comment)
gh api "repos/$OWNER/$REPO/pulls/<PR_NUMBER>/comments/<id>/replies" --method POST -f body="$(cat "$TMPDIR/reply-<id>.md")"
# reply to a general comment or review body
gh pr comment "<PR_NUMBER>" --body-file "$TMPDIR/reply-general.md"
# commit + push (current branch only; never main)
git add <fixed files> && git commit -m "fix: address review comments on #<PR_NUMBER>" && git push
```

Reply shapes (keep them short, in the commenter's language):
- **Fixed**: `Fixed in <sha> — <what changed> (<file:line>).`
- **Not actionable**: `<reason> — <evidence: file:line or the existing behaviour>. Happy to revisit if I misread.`
- **Question**: the direct answer, then a pointer to the code (`file:line`).

Post the commit sha into "Fixed" replies after the commit exists; if the user chose "Post replies only" with
uncommitted fixes, say `Fixed locally, pushing shortly` instead of inventing a sha.
