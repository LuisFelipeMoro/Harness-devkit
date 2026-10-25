# /code — execution loop detail

Read the section for the mode the user picked, then the shared sections (dispatch hygiene, checkpoint M,
fix rounds, after each row). Work happens on the current branch (`references/branching.md`), except the
parallel mode's per-row worktrees.

**Dispatch hygiene (all modes)** — the main session's own context is the largest cost measured on a run, so:
- The main session never Reads the plan whole once the run starts. For an anchor (one Tasks row, its Test
  Case rows) it uses `grep -n` / `sed -n`.
- A resume costs a full transcript: `SendMessage` replays the agent's whole history, and
  `dispatch-budget.sh` does not count it. Every fix round is a **fresh, narrowly-scoped coder dispatch**
  with the finding list, never a resumed context — resuming a large coder transcript for a small fix was
  the single most expensive path measured.
- Dispatch prompt shape: paths, the Task ID, the frozen excerpt the agent must match, and a return cap.
  Never pasted conversation, never pasted file contents, never tool output longer than 40 lines, never
  "read all references" — each agent loads its own references on demand.
- **Split a dispatch that spans many files.** A prompt naming a large file set stalls rather than
  finishing — `dispatch-budget.sh` warns once past its threshold, but the fix is narrowing the dispatch;
  break the row into per-file or per-component dispatches instead.

## Coder dispatch (sequential, single-coder and parallel modes)

- **Stack-aware**: pick the agent by the row's `Tier` — `coder-backend` (server/API/domain/data/worker),
  `coder-frontend` (UI/SSR/client/mobile), or `coder` for neither (scripts, docs, config). The overlay
  loads `agents/coder.md` itself; the coder loads only `references/languages/<language>.md` for the row's
  `Language` — never the index — and the rest of its references on demand.
  - Full-stack work was split in the plan into a backend producer row and a frontend consumer row sharing
    the `api-spec.yaml` contract. Run the backend row first so the spec is real before the frontend
    consumes it.
  - No frontend stack in the plan → `coder-frontend` is never spawned.
  - A frontend row creating or materially redesigning visual surface takes its visual direction from the
    plan's Design; if the Design has none, stop and ask rather than letting the coder invent it.
- **Model**: `haiku`. Escalate a row to `sonnet` only with a stated reason (shared state, concurrency,
  money, auth, or a haiku run that already misreported coverage on this row).
- **Prompt** (paths and ids only):
  `Plan: docs/plans/{slug}/plan.md · Task: {ID} · Base: {merge-base} · Language: {Language} · Edit only
  the row's Files. Phase 0 → implement → write the row's Test Case rows by exact name → falsify each with
  scripts/verify/break-run.sh → return CODER DONE (≤ 40 lines).`
  Single-coder mode lists every Task ID in order: `Tasks: T1, T2, T3 — one CODER DONE block per task`.
- The plan's ACs + Test Case table are the frozen acceptance contract — the coder satisfies it, never
  redefines it. A `Gap found` it reports is a plan defect for the user to decide.
- On return, append the `Falsification evidence` lines to `docs/plans/{slug}/evidence.md` under
  `## {ID}` — that file is what `/validate-code` feeds to `scripts/verify/falsification.sh`.
- Keep a compact reference per row, not the transcript: `"T1: {file}.{ext} + tests, {N} lines, implements {Interface}"`.

## Mode — Inline

The main session implements every row itself, in order, following `agents/coder.md` Phases 0–3 as if it
were the coder (read that file at this step): spec → implement → write exactly the row's tests → falsify
each with `break-run.sh`, writing the same `CODER DONE` block into `evidence.md`. No subagent. Best for
1–2 small rows; the implementer ≠ validator separation is kept by `/validate-code`'s independent `qa`.

## Mode — Single coder

One coder dispatch implements all rows in order. Use it when rows are tightly coupled or share files.
Past 4 rows the coder's own context ceiling becomes the risk — prefer sequential. Checkpoint M runs once
per returned row block, in row order, before anything else.

## Mode — Sequential coders (default)

One coder per row, in `Depends on` order, **one at a time** — rows share one working tree, so two
concurrent coders would overwrite each other. Row N clears checkpoint M before row N+1 is dispatched.

## Mode — Parallel coders

Only rows with no `Depends on` (or whose dependencies are already merged) and pairwise-disjoint `Files`,
as listed by `scripts/estimate-run.py`. At most **3 writers at once** (CLAUDE.md Sub-agent Discipline).
- Each parallel row runs in its own worktree: dispatch with the Agent tool's `isolation: "worktree"` —
  never two writers in one tree. Worktree mechanics and cleanup: `references/delivery-and-worktree.md`.
- When the batch returns, merge each row's worktree branch back into the work branch **in row-ID order**,
  one at a time, and run checkpoint M plus the stack's gates after **each** merge. A merge conflict or a
  red gate stops the merge sequence: the conflicting row is redone sequentially on the merged tree.
- Rows that are not parallel-safe run sequentially after the batch.

## Checkpoint M (every mode, after every row and every fix round, and after ANY agent exit — done, stalled, rate-limited or killed — before anything else runs)

One command, not a hand-run list:
```
scripts/verify/checkpoint-m.sh --base $START --spec $TMPDIR/code-{slug}/spec-so-far.md \
  --tests <path>... --expect <file>... [--gates "<cmd>"]
```
`$START` is HEAD when `/code` started, so earlier work on the branch is not counted as this run's.
`--expect` is the union of `Files` of the rows done so far. `spec-so-far.md` is the plan's Test Case
table header plus only the rows of the Tasks done so far (spec-coverage reads the `| Test Name |` table),
so a row not built yet is never reported missing; after the last row, run it once more with
`--spec docs/plans/{slug}/plan.md` — the full table must pass with no exception.

It returns all failures at once, never a bail-out on the first red one: every Test Case row implemented
by exact name (spec-coverage.sh), the changed-file set exactly matching `--expect` (a rename counts as
touching both paths, a deletion as touching the deleted path — missing or extra is a FAIL), no commit on
HEAD beyond `--base`, no leftover `*.devkit-break` marker anywhere in the tree, and the duplication gate
(`git-hooks/dup-gate.sh`) — into one `M: PASS` / `M: FAIL (n)` line. Exit 2 is unmeasured, not a pass —
route it exactly like a FAIL.
- The main session still re-breaks a sample of the falsification evidence by hand with `break-run.sh`
  (one line per row, two if the row carries a SEC test) — an agent's claimed break is a claim, not proof;
  `checkpoint-m.sh` proves the marker is gone, not that the break itself was real.
- `--gates` carries format + lint + the existing test suite for the stack
  (`references/quality-gate-reference.md`). Mechanical gates run in every mode, at every size.

## Fix rounds

Any FAIL or exit 2 → back to a fresh coder dispatch with the output. Every coder fix — whether it came
from M, a gate, `/validate-code`'s qa/stress or `/review-code` — goes back to M before anything sees the code
again. 3 round trips at one checkpoint → ask the user: fix differently / relax scope / stop. Follow
**Loop Integrity** in `references/quality-gate-reference.md`: no goalpost-moving (no lowered threshold,
skipped test, weakened assertion, edited Test Case row), and stop on an identical repeat failure.

## After each row

Append a `PROGRESS.md` entry at the repo root (`[{slug}]` prefix; Done / Failed / Current State / Next —
`references/progress-file.md`) so the next session boots with state. Commit only if the user asked for
commits (one atomic commit per row). Never push.

> **Context budget — 80% is a hard ceiling**, measured by `hooks/context-budget.sh`. Compact at 60%,
> `/handoff` at 80%, and never record session state in a source file.
