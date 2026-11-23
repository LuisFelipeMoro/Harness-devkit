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
  the row's Files. Phase 0 → implement → write the row's Test Case rows by exact name → run the suite once
  green → return CODER DONE without falsification lines (≤ 40 lines).`
  Single-coder mode lists every Task ID in order: `Tasks: T1, T2, T3 — one CODER DONE block per task`.
- The plan's ACs + Test Case table are the frozen acceptance contract — the coder satisfies it, never
  redefines it. A `Gap found` it reports is a plan defect for the user to decide.
- Falsification is not part of a row dispatch. The FINAL-PROOF dispatch writes each row's `Falsification
  evidence` lines to `docs/plans/{slug}/evidence.md` under `## {ID}` (§ Final proof) — the file `/validate-code`
  feeds to `scripts/verify/falsification.sh`.
- Keep a compact reference per row, not the transcript: `"T1: {file}.{ext} + tests, {N} lines, implements {Interface}"`.

## Mode — Inline

The main session implements every row itself, in order, following `agents/coder.md` Phases 0–2 as if it
were the coder (read that file at this step): spec → implement → write exactly the row's tests → run the suite. Falsification runs in § Final proof, as in every mode. No subagent. Best for
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
so a row not built yet is never reported missing; after the last row, § Final proof runs it with
`--spec docs/plans/{slug}/plan.md` — the full table must pass with no exception.

It returns all failures at once, never a bail-out on the first red one: every Test Case row implemented
by exact name (spec-coverage.sh), the changed-file set exactly matching `--expect` (a rename counts as
touching both paths, a deletion as touching the deleted path — missing or extra is a FAIL), no commit on
HEAD beyond `--base`, no leftover `*.devkit-break` marker anywhere in the tree, and the duplication gate
(`git-hooks/dup-gate.sh`) — into one `M: PASS` / `M: FAIL (n)` line. Exit 2 is unmeasured, not a pass —
route it exactly like a FAIL.
- The per-row form runs without `--gates` and the main session re-breaks nothing per row. The re-break
  sample runs once, in § Final proof, against the final tree. `checkpoint-m.sh` proves the marker is gone,
  not that a break was real.
- `--gates` carries format + lint + the existing test suite for the stack
  (`references/quality-gate-reference.md`). The per-row form omits it (the coder runs the suite once green);
  § Final proof passes it once. Mechanical gates still run in every mode, at every size.

## Fix rounds

Any FAIL or exit 2 → back to a fresh coder dispatch with the output. Every coder fix — whether it came
from M, a gate, `/validate-code`'s qa/stress or `/review-code` — goes back to M before anything sees the code
again. 3 round trips at one checkpoint → ask the user: fix differently / relax scope / stop. Follow
**Loop Integrity** in `references/quality-gate-reference.md`: no goalpost-moving (no lowered threshold,
skipped test, weakened assertion, edited Test Case row), and stop on an identical repeat failure.

## After each row

Once the row's checkpoint M prints `M: PASS`, set the row done with that line verbatim:
`python3 scripts/tasks_state.py set docs/plans/{slug}/plan.md {ID} done --evidence "M: PASS …"` (the whole line
the checkpoint printed). The tool checks only the `M: PASS` prefix, so the evidence stays the main session's claim;
the per-row re-break sample still applies. Per-row checkpoint and smoke use the fast form (no `--gates`); the
end-of-run gates and falsification are defined in § Final proof of this file.

Append a `PROGRESS.md` entry at the repo root (`[{slug}]` prefix; Done / Failed / Current State / Next —
`references/progress-file.md`) so the next session boots with state. Commit only if the user asked for
commits (one atomic commit per row). Never push.

## Final proof

Runs once after the last row is `done`, and at `/code` start when every row is already `done` (SKILL.md
step 4a). It is idempotent: a re-entry on a finished run repeats the same steps on the same tree. Against the
final tree, in order:

1. **Gates** — the plan's `Gates:` line (`references/plan-template.md`), run once: format, lint and the full
   suite for the stack. Red → step 5.
2. **Falsify every code row** — the FINAL-PROOF coder dispatch: `Plan: docs/plans/{slug}/plan.md · Task: FINAL-PROOF ·
   Tasks: {rows} · Base: {merge-base} · Language: {Language of each row, from its Tasks row} · Edit only the rows'
   Files.` Rows split into one dispatch per `Language`, or per test suite when a suite is slow; dispatches that run
   in parallel each get their own worktree (`references/delivery-and-worktree.md`). Each coder runs
   `agents/coder.md` Phase 3 for its rows' Test Case rows, with `scripts/verify/break-run.sh`, and returns its
   evidence lines to the main session: a break line per test, and a `wiring:` line for each prose row (the label
   `scripts/verify/falsification.sh` requires). Only the main tree's `docs/plans/{slug}/evidence.md` is written,
   by the main session from the returned lines, one `## {ID}` block per row. A test that does not fail against
   its break is reported `NOT FALSIFIED` with the reason; it is not rewritten inside the FINAL-PROOF dispatch
   and goes to step 5.
3. **Re-break a sample** — the main session, not the coder: one break per code row, two for a row that carries
   a SEC test. Each break is applied with `break-run.sh` and must FAIL by the row's name; the break's marker is
   restored by the script. Prose rows (`n/a — Markdown, wiring check`) are not broken.
4. **Checkpoint M** — `scripts/verify/checkpoint-m.sh --base $START --spec docs/plans/{slug}/plan.md
   --tests <paths> --expect <union of Files> --gates "<plan Gates>"` must print `M: PASS`.
5. **Failure** — a red gate, a FAIL from M, a `NOT FALSIFIED` line from step 2, or a re-break that does not fail → for each affected row
   `python3 scripts/tasks_state.py set docs/plans/{slug}/plan.md {ID} todo --evidence "<that line>"`, then a fresh
   coder fix round (§ Fix rounds), `set {ID} in_progress`, checkpoint M (fast form), `set {ID} done`, and Final
   proof again for the affected rows (steps 2–4).

The run is complete only when Final proof passes and `python3 scripts/tasks_state.py status` reads `{n}/{n} done`.

## Resume

Entered from SKILL.md step 4a when a row is `in_progress` or `failed`, or some rows are `done` and some `todo`.
Every restore below is logged under `- Failed:` in this run's `PROGRESS.md` entry.

1. **Bearings** — one Bash call: `git branch --show-current`, `git status --short`, `git log --oneline -10`,
   `python3 scripts/tasks_state.py status docs/plans/{slug}/plan.md`,
   `python3 scripts/tasks_state.py verify docs/plans/{slug}/plan.md`, and the marker list
   `find . -name '*.devkit-break' -not -path './.git/*'`. `verify` exit 1 or 2 → stop and ask the user: `tasks.json`
   changed outside `tasks_state.py`, or could not be checked.
2. **Restore leftover markers** — a marker `M` (`F.devkit-break`) with no live break run (`pgrep -f break-run.sh`
   prints nothing) is left by a dead run: restore it with `cp -p M F && cmp -s M F && rm M`, then log it under
   `- Failed:`. A live `break-run.sh` means the marker is not leftover: do not touch it, ask the user.
3. **In-progress rows: repair, not trust.** Each `in_progress` row's partial work is untrusted. Run checkpoint M
   (fast form, no `--gates`) with that row included in `--tests` and `--expect`.
   - `M: PASS` → `set {ID} done --evidence "M: PASS …"` (the whole line, verbatim). Its falsification waits for
     § Final proof.
   - `M: FAIL` or exit 2 → one fresh coder dispatch told to repair, not trust, the partial work. It is fix round 1
     of the 3-round limit (§ Fix rounds). The protocol never runs `git restore` itself; restoring the row's Files
     and `set {ID} todo` happen only when the user picks option B in step 3b.
3b. **Failed rows.** Each `failed` row goes to the user as one decision question, with its last `M: FAIL` line as
    evidence:
    - **A** — retry with a fresh coder (`set {ID} in_progress`).
    - **B** — restore its Files and `set {ID} todo`.
    - **C** — leave it `failed` and stop the run; its dependants cannot start.
4. **Smoke** — before the next dispatch, checkpoint M (fast form) over the `done` rows. `M: FAIL` → no new row starts;
   a fix round runs on the output. A row whose Test Case rows spec-coverage reports missing goes back to `todo`:
   `set {ID} todo --evidence "<the MISSING ROW line>"`.

> **Context budget — 80% is a hard ceiling**, measured by `hooks/context-budget.sh`. Compact at 60%,
> `/handoff` at 80%, and never record session state in a source file.
