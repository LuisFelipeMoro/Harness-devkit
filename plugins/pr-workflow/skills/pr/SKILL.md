---
name: pr
description: 'Commit the branch as atomic conventional commits, then push and open a pull request with a Summary / Evidence / Merge Danger body — only after you approve the commit list and the body. Usage: /pr [base-branch] [--draft], e.g. "/pr main --draft".'
disable-model-invocation: true
---

**Input**: the current branch's changes (committed and uncommitted); optionally a base branch (default `main`, else `master`) and `--draft`. A plan for the branch (`docs/plans/{slug}/plan.md`) and a `/validate-code` run in this session feed the body when present.
**Output**: atomic conventional commits, the branch pushed, and the PR URL.
**Boundary**: one job — commit, push, open. Never commits to or pushes `main` / `master`, never force-pushes, never bypasses a hook (`--no-verify`), never stages a path `.devkit/release-exclude` names, never merges. Nothing is committed, pushed or opened before the user approves step 5. No dispatch.

## Steps

1. **Branch and auth.** `gh auth status` (fail → report and stop). Per `coding-pipeline/references/branching.md`: on `main` / `master`, cut `feat/{slug}` (`fix/{slug}` for a bug fix) before any commit; detached HEAD → stop. An open PR already exists for the branch (`gh pr view --json url`) → say so, offer to push new commits to it, and skip step 6's `gh pr create`.
2. **Collect.** `BASE=$(git merge-base HEAD <base>)` (`<base>`: the PR's base branch — `main`, falling back to `master`); `git status --porcelain`, `git diff $BASE --stat`, `git log $BASE..HEAD --oneline`. Drop from the candidate set every path matching `.devkit/release-exclude` (PROGRESS.md, handoff snapshots, generated test output — coverage, junit, `__pycache__`, `*.devkit-break`) and anything else that is session state rather than product; uncommitted changes you did not make are named to the user, never staged silently. Done when every changed path is either assigned or excluded with a reason.
3. **Plan the commits.** Group the remaining changes into atomic commits — one logical change each, the tree building and its tests passing at every commit — with Conventional Commits subjects (`type(scope): imperative summary`, ≤ 72 chars; `feat` · `fix` · `refactor` · `test` · `docs` · `chore` · `perf` · `build` · `ci`; `!` + a `BREAKING CHANGE:` footer for a breaking change). Follow the repo's own convention where `git log` shows one, and end each message with the attribution lines the session requires. A `/bugfix` result puts its confirmed hypothesis in the fix commit's body.
4. **Draft the PR.** At this step, read `references/pr-body.md` and fill its template: **Summary** (the smallest clear view of the change), **Evidence** (before → after; the `/validate-code` gate line when one ran), **Merge Danger** (Door: one-way / two-way · Blast Radius: one word + ramifications), and the plan link when a plan exists. Title = the main commit's subject. Done when every claim in the body points at a command output, a test name, a `file:line` or the plan.
5. **Show, then ask.** Print the commit list (subject + files per commit), the excluded paths, the PR title and the full body. One AskUserQuestion call:
   - Go? — Commit, push and open the PR / Commit only / Change something / Stop.
   - PR language — English / Português (BR).
   Português (BR): translate the prose of the body and title, never code, identifiers, paths, commands or the `type(scope):` prefix; commit messages stay in the repo's language.
6. **Commit, push, open — exactly what was approved.** `git add <paths>` per commit (never `git add -A`), `git commit` letting the repo's hooks run — a hook failure (lint, tests, release-content guard) is fixed at the cause and the commit re-run, never skipped; a fix that changes code goes back to step 5. Then `git push -u origin <branch>` and `gh pr create --base <base> --title … --body-file $TMPDIR/pr-body.md` (+ `--draft`). Print the PR URL.

Next: `/pr-fix` when review comments arrive.
