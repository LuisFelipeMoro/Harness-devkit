# Planning — phase detail

Read each section at the `/planning` step that names it. Artifacts live under `docs/plans/{slug}/`;
`{slug}` is the kebab-case feature name, ≤ 5 words, derived first.

## Phase 0 — Requirements Input

**If the user passed a base plan / notes file**: load it as context. Normalize it into
`references/plan-template.md` (plugin root): keep every decision the user already made, verbatim,
tagged `(user decision)`, and never overrule one silently — a conflict with the codebase map becomes
an Open question. Every template section the base lacks is drafted and listed as a gap when the plan
is presented.

**If `docs/plans/{slug}/plan.md` already exists**: ask whether to continue it or start over. Continuing
keeps its Review log and resumes at the first phase whose output is missing.

**If neither exists**: build the Goal, Requirements & ACs and Out of scope from the request. Include
language context and security constraints. **Security ACs are mandatory for any change touching I/O,
auth or data handling** — write `SEC-n` rows, or `none — {reason}` only when there is genuinely no
such surface. Ask the user (AskUserQuestion, ≤ 4 per call) only for what the request and the code
cannot answer.

Show: `✓ docs/plans/{slug}/plan.md (draft — requirements)`

## Phase 0.5 — Codebase Discovery (MANDATORY — before any design)

The plan's Design is drawn from the requirements. Without this phase it is drawn as if the repository
were empty, which is where duplicated components originate: a plan that never saw the existing rate
limiter specifies a new one, and no gate downstream compares the two.

Run the procedure in `skills/map/references/map-procedure.md`: a **read-only** Explore subagent on
`haiku` (no edits, no plan opinions) writes **`docs/plans/{slug}/codebase-map.md`** with the seven
sections — Blast radius · Reusable symbols · Prior art · Conventions · Extension points · Contracts in
force · Test conventions — every entry cited `file:line`. Reuse an existing map only if its base sha
is an ancestor of HEAD.

When the request touches two or more independent areas (separate plugins, packages or services), fan
the mapping out by vector — one read-only mapper per area, within the `Read-only subagents per turn`
row in `references/thresholds.md`, each returning its sections as tables — and merge the returns into
the one `codebase-map.md` yourself: mappers never write it.

The blast-radius rules (enumerate, do not estimate · every caller gets a line · one hop past direct
callers · count non-code callers · name the tests that will change · state the total · an empty radius
is a finding) are in the map procedure and apply unchanged. The total line is what the plan uses to
size and split the Tasks table, and what `plan-reviewer` checks against the code.

For a greenfield repo, run it anyway and record the empty result — "nothing exists yet" is a fact the
plan and the plan reviewer both need stated, not inferred from a missing file.

Show: `✓ docs/plans/{slug}/codebase-map.md`

## Phase 1 — Design (main session)

Drafting runs in the main session (`sonnet`), not a dispatched agent. Read the codebase map before
designing anything, and open the files it cites; the map is a summary, not a substitute.

Fill every section of `references/plan-template.md`, following its rules. The Design section carries
the architecture content listed in this skill's `references/sections.md` (Tech Stack · Security
Architecture with the OWASP threat table · Component Design with testable seams · Data Model · API
Contracts · Data Flow (Mermaid, `references/data-flow-example.md` in this skill) · Error Handling ·
Observability · Performance · ADRs with rejected alternatives).

> **Backend-Driven Architecture check (mandatory):** verify tier placement for every component:
> **Frontend** = render only; **BFF** = orchestrate + shape for UI; **Core** = domain logic. Flag and
> push back on any AC asking the wrong tier to own logic.

- Every component carries a decided Reuse Map row (`reuse:` / `extend:` / `new:` with the closest
  existing thing cited). Reuse and extend beat new.
- Use context7 to verify current library capabilities, API stability and version compatibility before
  specifying any library or framework. A new datastore, or an existing one taking on a materially
  different use case, loads `references/db-selection-reference.md` at that moment.
- HTTP endpoints → write `api-spec.yaml` (OpenAPI 3.1) per `references/spec-driven-reference.md` and
  run `rtk npx @stoplight/spectral-cli lint api-spec.yaml` before review.
- Resolve ambiguity at plan time: decide every question the requirements support and write the decision
  in; anything you cannot decide becomes an Open question. Never "depends on requirements".

Show: `✓ docs/plans/{slug}/plan.md (draft — design)`

## Phase 2 — Stress the Plan (grill — offered every time)

Ask (AskUserQuestion): "Grill the draft before review?" Recommend **Yes** for anything beyond a small,
single-row change. On Yes, read `references/grilling.md` and grill the design + Tasks table inline in
its rounds — the design tree's whole frontier per round, numbered, each question with your
recommended answer worded so "yes" accepts it, the frontier recomputed after every round: missing
error cases, auth gaps, schema problems, undecided edge cases, unowned failure modes. Facts come from
the codebase map, or a grep / read when the map does not carry them — never from the user. The goal
is to surface and **close gaps now**, while changes are cheap — not at code time.

For each gap:
- If the requirements or the map support a decision → **decide it and write it into the plan**. A
  question the plan should have answered but didn't is a planning error — fix the plan, do not defer
  it to the coder.
- If it cannot be decided from the available context → carry it to Phase 3 as an Open question.

Repeat until the frontier is empty — no new gap the plan can resolve on its own appears — and the user
confirms the understanding is shared (or stops early with "done" / "enough").

## Phase 2.5 — Plan Review (MANDATORY — before the human sees it)

Grilling interrogates the plan from inside the context that wrote it; it looks facts up but never
audits the plan against the repository.
Phase 2.5 adds the reader that does both: fresh eyes, codebase open.

Dispatch `subagent_type: "plan-reviewer"`, `model: "sonnet"`, with only two paths — the plan and the
codebase map. It reads the real code and reports PR1–PR11 findings — already exists · reuse not
declared · contradicts existing code · convention breach · ambiguous AC · unfalsifiable Test Case row
· untraced requirement · undecided question deferred into code · blast radius wrong or unmeasured ·
not independently testable · not reviewable at the planned size.

Routing on its `Gate:` line:
- **`PLAN APPROVED`** → Phase 3.
- **`PLAN CHANGES REQUIRED`** → fix the plan from the findings, then re-dispatch for a review of
  **only the changed sections**. Maximum 2 rounds; a third means the requirements themselves are
  unclear — carry the remaining findings to Phase 3 as Open questions rather than looping.

An `[OPEN QUESTION]` finding is never resolved by guessing — it goes to Phase 3. Each round is appended
to the plan's Review log; after review, `Status: reviewed`.

Show: `✓ plan review — {score}/10, {n} findings resolved`

## Phase 3 — Human Validation

Present to the user:
- Mermaid diagram(s)
- Tech stack decisions
- Top ADRs and trade-offs, with rejected alternatives
- Blast-radius total and the Reuse Map verdict (`{N}/{M} planned components reused or justified`)
- Gaps found in the base file (if one was given)
- **Open questions** the grill and the review could not resolve — ask the human to decide each
  (AskUserQuestion, ≤ 4 per call, each with a recommended option) and write every answer into the plan
- **Plan review result** — score, reuse verdict, and any `[OPEN QUESTION]` finding

Ask: *"Does the design make sense? Any changes to libraries, strategies, or design? Approve / request
changes?"* On changes → update the plan → re-present the changed sections → re-confirm.

**If `api-spec.yaml` was produced** (the change has HTTP endpoints), present the API contract summary:
- Endpoint list: `METHOD /path — operationId` for each endpoint
- Auth scheme and which endpoints are protected
- Key request/response schema names

Ask: *"Does the API contract look right? Any changes to endpoints, schemas, auth, or error shapes before
implementation starts? Once approved, the coder implements to this spec exactly — changes after that
require updating the spec first."* The contract was already stressed in Phase 2 — confirm those findings
are reflected in it. On spec changes → update `api-spec.yaml` → run
`rtk npx @stoplight/spectral-cli lint api-spec.yaml --ruleset .spectral.yaml` → re-confirm.

**Do not set `Status: approved` until both the plan and `api-spec.yaml` (if present) are approved and
all open questions are resolved.**

## Phase 4 — Tasks table (the execution manifest)

The Tasks table in the plan is what `/code` executes, one row at a time or in the mode the user picks.

| ID | Task | Files | Test rows | Language | Tier | Depends on |
|----|------|-------|-----------|----------|------|------------|
| T1 | {imperative verb phrase} | `internal/cart/store.go`, `internal/cart/store_test.go` | TestX, TestY | Go 1.26 | Backend | — |

`Language` comes from the Design's tech-stack decision — runtime, version and framework (e.g. `Go 1.26`,
`TypeScript 5 / Next.js 15`, `Java 21 / Spring Boot 3`). Every downstream agent reads it from the row —
never inferred. `Tier` (Backend / Frontend, or `—` for scripts/docs/config) picks the coder overlay.
`Files` is complete: it becomes the checkpoint's `--expect` set and decides which rows can run in
parallel (disjoint `Files`, no `Depends on`).

Cut the rows as **vertical tracer-bullet slices**, per the Tasks rules in `references/plan-template.md`:
a narrow but complete path through every layer of the row's tier, verifiable alone, sized for one fresh
coder context window; prefactoring rows first ("make the change easy, then make the easy change");
every blocking edge explicit in `Depends on`; a wide refactor sequenced **expand → migrate in batches
sized by blast radius → contract**, each batch its own row. Explicit edges over complete slices are
what make the parallel run mode safe.

Each row must be **independently testable** — expressible as one or more Test Case rows, each with an
observable result and a named break that would falsify it. If a row cannot be stated that way, split it
until it can.

It must also be **independently reviewable**. Review is where defects are actually caught, and reviewer
effectiveness collapses with diff size — for a human and for an agent alike, a large diff gets skimmed
rather than read, and the approval it produces means nothing. Size every row against a projected diff:
**≤ 200 changed lines is the target, 400 the soft ceiling, 800 the hard one.** Past 800 the row is split,
not justified. Isolate mechanical bulk (generated code, compiler-verified renames, formatting passes)
into its own row — 40 lines of logic hidden inside 600 mechanical ones is the worst diff there is to
review, and worse than either half alone. A full-stack change is split around the `api-spec.yaml`
contract: backend producer row first, frontend consumer row after it.

The plan reviewer verifies the sizing (PR11).

**Bundle small doc rows.** Adjacent rows that are doc/guide-only, in the same plugin or package, with a
combined projected diff ≤ 120 lines, become one row. Each row costs a full coder dispatch and
checkpoint; the bundled row costs one.

## Phase 5 — Plan Summary

Print the block in this skill's `references/output-contract.md` and stop. This skill never starts
implementation.
