# Delivery Files, Worktrees, and Branching

Every pipeline run is a **delivery**: one named unit of work with its own plan file, its own
git worktree, and its own release branch. Nothing a delivery produces collides with the host
repo's own documentation, and two deliveries can run against the same repo without sharing a
single byte of state.

## 1. Delivery identity

A delivery has a **slug** and a **key**.

- **Slug** — the feature name, kebab-cased, max 40 chars: `Checkout Flow Rework` → `checkout-flow-rework`.
- **Key** — first 6 hex chars of the SHA-256 of the feature name, lowercased and trimmed:

```sh
DELIVERY_NAME="Checkout Flow Rework"
DELIVERY_SLUG=$(printf '%s' "$DELIVERY_NAME" | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-40)
DELIVERY_KEY=$(printf '%s' "$DELIVERY_NAME" | tr '[:upper:]' '[:lower:]' \
  | shasum -a 256 | cut -c1-6)
```

The key is a pure function of the feature name, so re-running a pipeline for the same feature
resolves to the same delivery — that is the point. It makes resumption idempotent: the
orchestrator finds the existing delivery file and continues instead of forking a duplicate.

**Consequence to state out loud**: two *different* deliveries for the same feature name are
not representable. If the human genuinely wants a second, independent pass at the same
feature, ask them to name it differently (`Checkout Flow Rework v2`) rather than silently
overwriting the first.

## 2. The delivery file (replaces `architecture.md`)

```
docs/deliveries/delivery-{slug}-{key}.md
```

e.g. `docs/deliveries/delivery-checkout-flow-rework-a8f3c1.md`

The devkit **never writes `architecture.md`**. Many repositories already keep an
`architecture.md` describing the system as a whole; overwriting it would destroy the host
project's own documentation, and a single fixed filename also means two concurrent deliveries
would fight over one file. The delivery file solves both: it is namespaced by key, it lives
under `docs/deliveries/`, and it is additive to whatever the repo already documents.

If the repo has its own `architecture.md`, the Architect **reads it as context** and never
modifies it.

### Required header

Every delivery file opens with this block, verbatim:

```markdown
# Delivery: {Feature Name}

| Field | Value |
|-------|-------|
| Delivery-Key | `{key}` |
| Slug | `{slug}` |
| Status | Planning \| In Progress \| Blocked \| Delivered |
| Base commit | `{git rev-parse --short HEAD at kickoff}` |
| Release branch | `release/{slug}-{key}` |
| Worktree | `.worktrees/dlv-{key}/` |
| Stories | `{STORY-1 … STORY-N, or "pending decomposition"}` |
| Created | `{YYYY-MM-DD}` |
```

The `Delivery-Key` line is the signature: it is how the orchestrator, the Scrum Master, and a
resumed session all confirm they are looking at the same delivery. Every artifact the delivery
produces (manifest, stories, `PROGRESS.md` entries, branch names) carries the same key.

### Body

The body is the architecture document as specified in `bmad-artifacts.md` and
`agents/architect.md` — Overview, Tech Stack, Security Architecture, Component Design, Data
Structures, Data Flow, API Contracts, ADRs, Edge Cases, **Test Case Specification**, NFR Notes,
Implementation Checklist. Only the filename and the header block changed; the required
sections did not.

### Companion artifacts

Manifests and stories are keyed the same way, and live beside the delivery file:

```
docs/deliveries/delivery-{slug}-{key}.md
docs/deliveries/{key}/product-brief.md
docs/deliveries/{key}/PRD.md
docs/deliveries/{key}/epic-manifest.md        (or task-manifest.md)
docs/deliveries/{key}/story-{slug}.md
```

**`api-spec.yaml` is the exception — it stays at the project root.** It is the application's
shared, cumulative API contract, not a per-delivery document: tooling (Spectral config, CI,
codegen) expects it at a fixed path, and a delivery *extends* it rather than owning a private
copy. Isolation still holds, because each delivery's worktree has its own checkout of the root
file; if two deliveries touch the same endpoints, that surfaces as a merge conflict at PR time
— exactly as it would for the code implementing them.

## 3. Worktree — one per delivery

```
.worktrees/dlv-{key}/
```

The whole delivery — every story, every QA run, every gate — executes inside this worktree, on
the delivery's release branch. The main working tree is never touched by the pipeline, so the
human can keep working in it while a delivery runs.

### Setup (orchestrator, once, at kickoff)

```sh
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }
BASE=$(git rev-parse --short HEAD)
git worktree add -b "release/${DELIVERY_SLUG}-${DELIVERY_KEY}" \
  ".worktrees/dlv-${DELIVERY_KEY}" HEAD
```

If the worktree already exists, the delivery is being **resumed** — do not recreate it. Read
the delivery file's Status and `PROGRESS.md`, and continue from the first unfinished story:

```sh
git worktree list | grep -q "dlv-${DELIVERY_KEY}" && echo "resuming existing delivery"
```

Add `.worktrees/` to `.gitignore` if absent. Never commit the worktree directory itself.

### Stories run sequentially inside it

One worktree per delivery means stories **share a working tree**, so they run **one at a
time** — story N is merged and its gates are green before story N+1 is dispatched. This is a
deliberate trade: it gives up parallel story execution in exchange for no cross-story
interference and no merge choreography. Two coders editing one tree concurrently would
overwrite each other, so never dispatch parallel Coder subagents into the same worktree.

Read-only subagents (Explore, code mapping) may still run in parallel — they mutate nothing.

### Teardown

After the delivery's final Verdict and its PR to `main`:

```sh
git worktree remove ".worktrees/dlv-${DELIVERY_KEY}"     # add --force only if the human agrees to discard changes
git worktree prune
```

Keep the release branch until the PR merges. Never delete a branch with unmerged commits
without asking.

## 4. Branching — never merge to main

The pipeline **never commits to `main` and never merges into `main`.** The furthest it goes on
its own is opening a pull request. A human merges.

| Branch | Created from | Purpose | Terminal step |
|--------|--------------|---------|---------------|
| `release/{slug}-{key}` | `main` | The delivery's integration branch. All pipeline work lands here. | PR → `main` |
| `feature/{key}-{story-slug}` | `release/{slug}-{key}` | **Optional.** Use when a story is large enough that its own history is worth keeping separate. | Merge → its release branch |
| `hotfix/{slug}` | `main` | Bug fixes (`/bug-fix`). No release branch, no feature branches — the fix commits straight onto the hotfix branch. | PR → `main` |

Rules:

1. **Every delivery gets a release branch**, even a one-story delivery. It is the unit the PR
   is opened from.
2. **Feature branches are optional and per-story.** Create one when the story is substantial
   and you want its work isolated in history; skip it for small stories and commit directly to
   the release branch. Merge it back into the release branch once the story's Verdict passes —
   use `--no-ff` so the story stays visible as a unit.
3. **Bug fixes bypass the release/feature structure entirely.** `/bug-fix` cuts
   `hotfix/{slug}` from `main`, commits the fix and its RED-proven regression test, and opens a
   PR to `main`. Do not create a release branch for a hotfix, and do not add feature branches
   on top of one.
4. **A PR to `main` may only be opened from a `release/*` or `hotfix/*` branch.** Never from a
   feature branch, never from a story branch, never from a detached worktree HEAD.
5. **Opening the PR is the last automated step.** Report the PR URL and stop. Do not merge it,
   do not enable auto-merge, and do not push to `main` under any circumstance.

### Commands

```sh
# story done, optional feature branch in use
git checkout "release/${DELIVERY_SLUG}-${DELIVERY_KEY}"
git merge --no-ff "feature/${DELIVERY_KEY}-${STORY_SLUG}"

# delivery done — the terminal step
git push -u origin "release/${DELIVERY_SLUG}-${DELIVERY_KEY}"
gh pr create --base main --head "release/${DELIVERY_SLUG}-${DELIVERY_KEY}" \
  --title "{Feature Name}" --body "Delivery-Key: ${DELIVERY_KEY} …"
```

Ask before the first `git push` of a delivery — it is the first outward-facing action, and the
human may want the branch named differently or the work kept local.

## 5. Resuming and PROGRESS.md

`PROGRESS.md` stays at the **repo root** (not in the worktree) and its entries are prefixed
with the key so multiple deliveries interleave readably:

```markdown
### Done
- `[a8f3c1]` STORY-3 cart totals — 7/7 Test Case rows, all falsified; gates green
```

A resumed session identifies its delivery by key, reads the delivery file's Status and the
matching `PROGRESS.md` entries, and continues from the first unfinished story.
