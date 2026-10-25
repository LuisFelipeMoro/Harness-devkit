# Worktrees and Parallel Coders

The default is simple: work on the current branch, sequentially (`references/branching.md`). A
**git worktree** is an *execution mode*, used when `/code` runs Tasks rows in parallel and the user
chose that mode. It is never mandatory, and nothing here applies to a sequential run.

## 1. When a worktree is warranted

Parallel mode is offered only when all of these hold; otherwise `/code` offers the sequential modes:

- two or more Tasks rows have **no `Depends on`** between them, and their `Files` sets are **disjoint**;
- at most **3 writers** run at once (the CLAUDE.md writer cap; the `Writer subagents per turn` row in `references/thresholds.md`);
- the user picked the mode after seeing the token estimate from `scripts/estimate-run.py`. Parallel costs more
  than sequential: each coder carries its own prompt and transcript, and merging adds a step.

Two coders editing one working tree overwrite each other, so **never dispatch parallel coders into the same tree**. Read-only
subagents (Explore, mapping) may run in parallel anywhere — they mutate nothing. Their width is the
`Read-only subagents per turn` row in `references/thresholds.md`; they may run in the background, but a step that consumes
their result waits for every completion notification, never a polling loop.

## 2. Identity

- **Slug** — the plan's slug, kebab-cased, max 40 chars (`Checkout Flow Rework` → `checkout-flow-rework`), the same slug as `docs/plans/{slug}/`.
- **Row id** — the Tasks table ID (`T3`), lowercased.

```sh
SLUG=checkout-flow-rework; ROW=t3
WORK=$(git branch --show-current)          # the branch /code is working on (never main/master)
```

The names are pure functions of the plan, so a re-run resolves to the same worktree and branch — resumption is idempotent.

## 3. Setup (once per parallel batch)

```sh
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }
git worktree add -b "feat/${SLUG}-${ROW}" ".worktrees/${SLUG}-${ROW}" "$WORK"
```

If the worktree already exists, the batch is being **resumed** — do not recreate it:

```sh
git worktree list | grep -q "${SLUG}-${ROW}" && echo "resuming existing worktree"
```

Add `.worktrees/` to `.gitignore` if absent. Never commit the worktree directory itself. The coder
receives the worktree path as its working directory plus the plan path and Task ID; it runs its gates
inside that tree.

`api-spec.yaml` stays at the project root. It is the application's shared, cumulative API contract that tooling
(Spectral config, CI, codegen) expects at a fixed path; each worktree has its own checkout of it, and rows that touch
the same endpoints surface as a merge conflict at merge time, exactly as they would for the code implementing them.
Rows that both change it do not belong in the same parallel batch.

## 4. Merge, one row at a time

Rows of a batch finish in any order; they merge **serially** into the work branch, each only after its own gates are green:

```sh
git checkout "$WORK"
git merge --no-ff "feat/${SLUG}-${ROW}"      # keeps the row visible as a unit in history
```

After each merge, re-run the format, lint and existing-test gates on the work branch before the next merge — a clean textual
merge can still break behaviour. A merge conflict is not resolved by the agent: stop, report the files, and ask.

## 5. Teardown

```sh
git worktree remove ".worktrees/${SLUG}-${ROW}"     # add --force only if the user agrees to discard changes
git worktree prune
```

Keep the row branch until the work branch is merged to the base. Never delete a branch with unmerged commits without asking.

## 6. Branch rules still apply

- Never commit or merge to `main`/`master`; the work branch is `feat/{slug}` (or `fix/{slug}`), cut as in `references/branching.md`.
- Nothing is pushed and no PR is opened unless the user asks. Ask before the first `git push` — it is the first outward-facing action.
- Row branches are local scaffolding. When a PR is requested it is opened from the work branch, reviewed with `/review-code`.
- Uncommitted changes you did not make are not yours: never stash, reset or revert them.

## 7. Resuming and PROGRESS.md

`PROGRESS.md` stays at the **repo root** (not in a worktree), and entries are prefixed with the plan slug and row id so parallel rows interleave readably:

```markdown
### Done
- `[checkout-flow-rework]` T3 cart totals — 7/7 Test Case rows, all falsified; gates green
```

A resumed session finds its batch with `git worktree list`, reads the plan's Tasks table and the matching `PROGRESS.md` entries, and continues from the first unfinished row.
