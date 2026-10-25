---
name: pr-fix
description: Fetch every open comment on the current branch's PR, triage each as valid, not actionable or a question, fix the ones you pick with the coder agent, and draft a reply per comment — posting and pushing only after you confirm. Usage: /pr-fix [--list], e.g. "/pr-fix --list".
disable-model-invocation: true
---

**Input**: the current branch's open PR (`gh` authenticated, `git` on a named branch); `--list` for a read-only listing.
**Output**: the PR URL and every comment grouped by file and line; a triage table; with fixes, the changed code, green gates, and one drafted reply per comment.
**Boundary**: one `coder` dispatch (`haiku`) per fix group. `--list` is read-only — no files written, no API mutations. Never pushes, posts, or resolves a thread without an explicit yes. Never leaves a comment unanswered: a valid one gets what changed, a non-actionable one gets why.

## Steps

1. **Prerequisites and PR.** At this step, read `references/procedure.md` (this skill's) and run its Steps 1–4: `gh auth status` (fail → report and stop) · current branch (detached HEAD → stop) · the open PR for the branch (none → "No open PR found for branch `<BRANCH>`" and stop) · `OWNER` / `REPO`.
2. **Fetch** inline review comments and general comments (procedure Steps 5–6), plus review bodies and thread grouping from `references/comments.md` (read at this step).
3. **List** per procedure Step 7: the PR URL, inline comments grouped by file and sorted by line (`line`, else `original_line`, else `?`), bodies truncated to 80 chars, aligned; then general comments; the "No … comments." lines when a section is empty. `--list` → stop here.
4. **Triage** every comment, reading the code at the cited line before judging, into one table:
   `| # | file:line | Comment (≤ 80 chars) | Class | Why | Proposed action |`
   Class: **valid** (a bug, missing test, security hole, or a fair request) · **not-actionable** (style preference, opinion, already done, outdated or wrong — say why with `file:line`) · **question** (needs an answer, not code). Group valid comments touching the same code into one fix group.
5. **Pick.** AskUserQuestion with `multiSelect: true` over the fix groups (≤ 4 options per question; more → several questions in one call). Nothing picked → skip to step 7.
6. **Fix each picked group**, sequentially: dispatch the coder matching the code's tier (`coder-backend`, `coder-frontend`, or `coder`), `model: "haiku"`, with paths and ids only — `Comments: {ids + file:line} · Files: {list} · Base: $(git merge-base HEAD main) · Change only what the comments ask; a behaviour change gets a test falsified with scripts/verify/break-run.sh.` Then run the stack's gates (`coding-pipeline/references/quality-gate-reference.md`, read at this step) and `bash ~/.claude/git-hooks/dup-gate.sh --worktree`. A failure → one fresh coder dispatch with the output; still failing → report and stop that group.
7. **Draft replies** — one per comment, in the commenter's language, shapes in `references/comments.md`: fixed (what changed, `file:line`, commit to follow) · not-actionable (the reason, politely, with evidence) · question (the answer). Show them all in one block.
8. **Confirm before anything leaves the machine.** AskUserQuestion: Commit + push + post replies / Commit only / Post replies only / Nothing. Act on exactly that answer with the commands in `references/comments.md`; never resolve threads unless asked.

Next: `/review-code` on the updated diff, or `/validate-code` before pushing.
