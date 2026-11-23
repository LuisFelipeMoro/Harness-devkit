---
name: code
description: Implement a plan (or a small inline task) row by row — spec, implement, test — then falsify and gate the whole run once in a Final proof stage, in the run mode you pick from token estimates. Usage: /code [plan-path | "task text"], e.g. "/code docs/plans/checkout-retry/plan.md".
disable-model-invocation: true
---

**Input**: a plan path, inline task text, or nothing (the skill looks for a plan).
**Output**: the implemented diff on the work branch, `docs/plans/{slug}/evidence.md` (falsification lines), a green checkpoint, a `PROGRESS.md` entry per row.
**Boundary**: no qa/review/stress/verdict (that is `/validate-code` and `/review-code`), no commit unless asked, no push, no PR. Dispatches depend on the mode: 0 (inline), 1 (single coder), 1 per row (sequential / parallel, ≤ 3 writers at once). `coder` runs on `haiku`.

**Rules**: the coder owns tests + implementation, written against the plan's frozen Test Case table and falsified before handoff; the ACs + Test Case table are the acceptance contract — never redefined at code time; a `Gap found` is a plan defect for the user, never absorbed; mechanical gates run in every mode and at every size, and falsification plus the full gates run once, in Final proof (`references/loop.md` § Final proof); never two writers in one working tree. Load each reference only at the step that names it.

## Steps

1. **Resolve the plan.**
   - Path given → use it. `Status` not `approved` → say so; ask proceed anyway / stop.
   - Nothing given → look for `docs/plans/*/plan.md`, `Status: approved` first. One match → confirm it. Several → AskUserQuestion to pick. None → treat the request as inline text.
   - Inline text → derive `{slug}`, write a mini-plan at `docs/plans/{slug}/plan.md` from `references/plan-template.md` (header incl. the `Gates:` line, Goal, Requirements & ACs, Test Case table, Tasks; the rest `n/a — small change`). Show it; edit until the user gives a one-line OK.
   - When AskUserQuestion is unavailable (headless run), take the answer from the prompt's `Answers:` line per `references/headless-runs.md`; no key → print `NEEDS_USER: <question>` and stop. This applies to every question in steps 1, 2, 4 and 6.
2. **Branch + base.** Apply `references/branching.md`. `BASE=$(git merge-base HEAD main)` (fall back to `master`); `START=$(git rev-parse HEAD)`. Uncommitted changes outside `docs/` at start → list them and ask (commit them first / continue, adding them to `--expect`); never stash or revert them.
3. **Estimate.** Run `python3 scripts/estimate-run.py --plan docs/plans/{slug}/plan.md` (plugin-relative script, `scripts/estimate-run.py`). Exit 2 → the Tasks table is malformed: show the message, fix the plan with the user, re-run. Never estimate by hand.
4. **Choose the mode.** AskUserQuestion with the four modes in the script's order (recommended first), each option's description carrying its dispatch count, token range and the `Measured $` median from run-state (`$X.XX (n=N)` or `— (n=0)`): **Inline** · **Single coder** · **Sequential coders** · **Parallel coders** (only offered when the script lists ≥ 2 parallel-safe rows). Add the script's fix-rounds line to the question text, and each range's basis label (`measured` / `partly measured` / `assumed`) to its option. The user may also override per row (e.g. "T4 inline, rest sequential") — honour it, but never run a row the script marked not parallel-safe in parallel.
4a. **Row state.** Run `python3 scripts/tasks_state.py init docs/plans/{slug}/plan.md` before the first dispatch. Then route on `python3 scripts/tasks_state.py status docs/plans/{slug}/plan.md`:
   - every row `done` → Final proof (`references/loop.md` § Final proof; idempotent, so a finished run can be re-entered safely).
   - any row `in_progress` or `failed`, or some rows `done` and some `todo` → `references/loop.md` § Resume first.
   - all `todo` → fresh run: go on to step 5.

   Per row, through `python3 scripts/tasks_state.py set docs/plans/{slug}/plan.md {ID} <status>`: `set {ID} in_progress` before its dispatch; `set {ID} done --evidence "M: PASS …"` once that row's checkpoint M prints `M: PASS`, the `…` being the rest of that line, pasted verbatim (the tool checks only the prefix). If the user stops a row after the fix-round limit (step 6): `set {ID} failed --evidence "<last M: FAIL line>"`. A `failed` row goes to the user as the decision question in `loop.md` § Resume, step 3b.
5. **Execute.** At this step, read `references/loop.md` (this skill's) — the section for the chosen mode plus the shared sections. Per row: `set {ID} in_progress` (step 4a), then the coder (or the main session, inline) runs Phase 0 → implement → write exactly the row's Test Case rows → run the suite once green; no falsification per row. Run checkpoint M in its fast form (no `--gates`). When it prints `M: PASS`, `set {ID} done` (step 4a). Falsification runs once, in step 7. Dispatch prompts pass only: plan path, Task ID, base, Language, the row's Files.
6. **Fix rounds.** Any FAIL or exit 2 → a fresh, narrow coder dispatch with that output, then checkpoint M again. 3 rounds on one row → ask: fix differently / relax scope / stop. Loop Integrity (`references/quality-gate-reference.md`, read at this step if a round is needed) forbids moving the goalpost.
7. **Final proof.** After the last row (or at start when every row is `done`), run `references/loop.md` § Final proof: the plan's Gates once, FINAL-PROOF coder dispatches (one per Language or test suite) that falsify every code row, their evidence lines appended to `evidence.md` by the main session, a main-session re-break sample, then `checkpoint-m.sh --spec docs/plans/{slug}/plan.md --gates "<plan Gates>"` must print `M: PASS`.
8. **Report.** One table: Task · mode · files · rows implemented · checkpoint line · Final proof line (gates, falsified rows, re-break sample); then every `Gap found` and anything the coder flagged (pinned versions, blast-radius callers the plan missed). Last line: `python3 scripts/tasks_state.py status docs/plans/{slug}/plan.md`. The run is complete only when it reads `{n}/{n} done`.

Next: `/validate-code docs/plans/{slug}/plan.md`, then `/review-code`.
