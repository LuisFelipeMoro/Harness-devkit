# Branching

One rule set for every skill that touches git. No worktrees, no release branches.

- **Work on the current branch.** Check it first: `git branch --show-current`.
- **If it is `main` or `master`, cut a branch before the first edit**: `feat/{slug}` (`fix/{slug}` for `/bugfix`). `{slug}` is the kebab-case feature name, at most 5 words, the same slug as `docs/plans/{slug}/`.
- **Never commit to `main` / `master`.** If you are on it and cannot branch, stop and ask.
- **Never push, merge, or open a PR on your own.** Do it only when the user asks. `/pr-fix` asks before it pushes.
- Commits are atomic and follow the repo's convention; `PROGRESS.md`, handoffs and generated test output are never committed (`.devkit/release-exclude`).
- The base for diffs is the merge-base with `main`: `git merge-base HEAD main` (fall back to `master`).
- Uncommitted changes you did not make are not yours: never stash, reset or revert them.
- Branch already exists for this work? Reuse it. Do not create a second one.
