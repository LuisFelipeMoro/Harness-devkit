---
name: code
description: Implement a plan (or a small inline task) row by row — spec, implement, test, falsify — in the run mode you pick from token estimates, with gates and falsification evidence on in every mode. Usage: /code [plan-path | "task text"], e.g. "/code docs/plans/checkout-retry/plan.md".
disable-model-invocation: true
---

**Input**: a plan path, inline task text, or nothing (the skill looks for a plan).
**Output**: the implemented diff on the work branch, `docs/plans/{slug}/evidence.md` (falsification lines), a green checkpoint, a `PROGRESS.md` entry per row.
**Boundary**: no qa/review/stress/verdict (that is `/validate-code` and `/review-code`), no commit unless asked, no push, no PR. Dispatches depend on the mode: 0 (inline), 1 (single coder), 1 per row (sequential / parallel, ≤ 3 writers at once). `coder` runs on `haiku`.

**Rules**: the coder owns tests + implementation, written against the plan's frozen Test Case table and falsified before handoff; the ACs + Test Case table are the acceptance contract — never redefined at code time; a `Gap found` is a plan defect for the user, never absorbed; mechanical gates and falsification evidence run in every mode and at every size; never two writers in one working tree. Load each reference only at the step that names it.

## Steps

1. **Resolve the plan.**
   - Path given → use it. `Status` not `approved` → say so; ask proceed anyway / stop.
   - Nothing given → look for `docs/plans/*/plan.md`, `Status: approved` first. One match → confirm it. Several → AskUserQuestion to pick. None → treat the request as inline text.
   - Inline text → derive `{slug}`, write a mini-plan at `docs/plans/{slug}/plan.md` from `references/plan-template.md` (header, Goal, Requirements & ACs, Test Case table, Tasks; the rest `n/a — small change`). Show it; edit until the user gives a one-line OK.
2. **Branch + base.** Apply `references/branching.md`. `BASE=$(git merge-base HEAD main)` (fall back to `master`); `START=$(git rev-parse HEAD)`. Uncommitted changes outside `docs/` at start → list them and ask (commit them first / continue, adding them to `--expect`); never stash or revert them.
3. **Estimate.** Run `python3 scripts/estimate-run.py --plan docs/plans/{slug}/plan.md` (plugin-relative script, `scripts/estimate-run.py`). Exit 2 → the Tasks table is malformed: show the message, fix the plan with the user, re-run. Never estimate by hand.
4. **Choose the mode.** AskUserQuestion with the four modes in the script's order (recommended first), each option's description carrying its dispatch count and token range: **Inline** · **Single coder** · **Sequential coders** · **Parallel coders** (only offered when the script lists ≥ 2 parallel-safe rows). Add the script's fix-rounds line to the question text, and each range's basis label (`measured` / `partly measured` / `assumed`) to its option. The user may also override per row (e.g. "T4 inline, rest sequential") — honour it, but never run a row the script marked not parallel-safe in parallel.
5. **Execute.** At this step, read `references/loop.md` (this skill's) — the section for the chosen mode plus the shared sections. Per row: the coder (or the main session, inline) runs Phase 0 → implement → write exactly the row's Test Case rows → falsify each with `scripts/verify/break-run.sh`; its evidence lines go to `docs/plans/{slug}/evidence.md`; then **verify the claim yourself** (row tests green, one re-break per row, two with a SEC test) and run checkpoint M. Dispatch prompts pass only: plan path, Task ID, base, Language, the row's Files.
6. **Fix rounds.** Any FAIL or exit 2 → a fresh, narrow coder dispatch with that output, then checkpoint M again. 3 rounds on one row → ask: fix differently / relax scope / stop. Loop Integrity (`references/quality-gate-reference.md`, read at this step if a round is needed) forbids moving the goalpost.
7. **Final checkpoint.** After the last row, `scripts/verify/checkpoint-m.sh --base $START --spec docs/plans/{slug}/plan.md --tests <paths> --expect <union of Files> --gates "<format + lint + existing tests>"` must print `M: PASS`.
8. **Report.** One table: Task · mode · files · rows implemented/falsified · checkpoint line; then every `Gap found` and anything the coder flagged (pinned versions, blast-radius callers the plan missed).

Next: `/validate-code docs/plans/{slug}/plan.md`, then `/review-code`.
