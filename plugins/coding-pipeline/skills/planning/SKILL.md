---
name: planning
description: Produce a reviewed, approved plan in the devkit plan template, from scratch or from your own notes, mapped and checked against the real codebase. Usage: /planning [path-to-base-plan-or-notes], e.g. "/planning docs/notes/checkout-retry.md".
disable-model-invocation: true
---

**Input**: a feature request, optionally a base plan/notes path (ask for the goal if neither is given).
**Output**: `docs/plans/{slug}/plan.md` (`Status: approved`) and `docs/plans/{slug}/codebase-map.md`; `api-spec.yaml` when the change has HTTP endpoints.
**Boundary**: plan artifacts only — writes no code and starts no implementation. Dispatches: 1 map (Explore, `haiku`) + 1 `plan-reviewer` (`sonnet`) per review round, max 2 rounds. Drafting runs here, in the main session (`sonnet`; `opus` only for a hard design call, stated).

**Rules**: no design without the codebase map · nothing reaches the human that `plan-reviewer` has not read · every AC and SEC row lands in a Test Case row, every Test Case row in exactly one Tasks row · every Tasks row is independently testable and reviewable · `Language` comes from the Technology decisions, never inferred · questions the plan cannot answer go to the human, never into the code. Load each reference only at the step that names it.

## Steps

1. **Frame.** Derive `{slug}` (kebab-case, ≤ 5 words). Check the branch per `references/branching.md` before writing any file. At this step, read `references/phases.md` § Phase 0 and apply it: base file → normalize it, keeping every user decision verbatim; existing plan → ask continue / start over; neither → draft requirements from the request, Security ACs mandatory for any I/O, auth or data-handling change.
2. **Map** (mandatory, also on a greenfield repo). At this step, read § Phase 0.5, then run the procedure in `skills/map/references/map-procedure.md` (one Explore dispatch, `haiku`; one per area if the request spans independent areas). Reuse an existing map only if its base sha is an ancestor of HEAD.
3. **Design** in the main session. At this step, read § Phase 1 and `references/plan-template.md`; fill every section, with the Design built from this skill's `references/sections.md` (Mermaid per `references/data-flow-example.md`). Every component gets a Reuse Map row; the tier check (frontend renders, BFF orchestrates, core owns domain logic) is mandatory; HTTP endpoints → `api-spec.yaml` per `references/spec-driven-reference.md`, lint-clean. `Status: draft`.
4. **Grill (offered every time).** At this step, read § Phase 2. AskUserQuestion: "Grill the draft before review?" (recommend Yes beyond a single small row). On Yes, grill inline in rounds per `references/grilling.md` (read on Yes): each round asks the whole frontier, numbered, each with a recommended answer worded so "yes" accepts it; facts come from the map or a lookup, never from the user; decide what the request and map support, carry the rest to Open questions; repeat until the frontier is empty and the user confirms.
5. **Review.** At this step, read § Phase 2.5. Dispatch `subagent_type: "plan-reviewer"`, `model: "sonnet"`, with only the two paths: `docs/plans/{slug}/plan.md` and `docs/plans/{slug}/codebase-map.md`.
6. **Fix rounds (max 2).** `PLAN CHANGES REQUIRED` → fix the plan, re-dispatch for the changed sections only. `[OPEN QUESTION]` findings are never guessed. After round 2, carry what is left to Open questions verbatim. Append each round to the Review log; `Status: reviewed`.
7. **Human validation.** At this step, read § Phase 3. Present diagrams, stack, ADRs with rejected alternatives, blast-radius total, Reuse Map verdict, review score, base-file gaps, the `api-spec.yaml` contract summary, and every Open question (AskUserQuestion, ≤ 4 per call, recommended option first). Write each answer into the plan; re-confirm on any change.
8. **Tasks table + approve.** At this step, read § Phase 4: rows are vertical tracer-bullet slices (prefactoring first; wide refactors as expand → migrate batches → contract); check every row's `Files`, `Test rows`, `Language`, `Tier`, `Depends on`, sizing (≤ 200 target · 400 soft · 800 hard) and bundling. AskUserQuestion: Approve / Request changes. Approve → `Status: approved`.
9. **Summary.** At this step, read `references/output-contract.md` and print its block.

Next: `/code docs/plans/{slug}/plan.md`.
