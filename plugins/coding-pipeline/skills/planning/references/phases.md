# Planning — phase detail

## Phase 0 — Requirements Input

Derive the delivery slug + key from the feature name first (`references/delivery-and-worktree.md`) — every artifact below is keyed under `docs/deliveries/{key}/`. Then check for existing analysis artifacts:

**If `{key}/product-brief.md` and `{key}/PRD.md` already exist** (from a prior `/analysis` run for this key):
- Load them as context
- Skip to Phase 1

**If `{key}/product-brief.md` exists but `{key}/PRD.md` does not**:
- Load the existing Brief
- Run PM only: Load `agents/pm.md` → **`{key}/PRD.md`** *(security ACs mandatory for I/O/auth epics)*
- Skip Analyst step; show `✓ docs/deliveries/{key}/PRD.md`, then continue to Phase 1

**If neither exists** — run full analysis inline:
1. Load `agents/analyst.md` → **`{key}/product-brief.md`** *(include language context + security constraints)*
2. Load `agents/pm.md` → **`{key}/PRD.md`** *(security ACs mandatory for I/O/auth epics)*

Show: `✓ docs/deliveries/{key}/product-brief.md` / `✓ docs/deliveries/{key}/PRD.md` as each is produced.

All planning artifacts are keyed under the delivery — see `references/delivery-and-worktree.md`. Only `api-spec.yaml` stays at the project root.

## Phase 0.5 — Codebase Discovery (MANDATORY — before any architecture)

The Architect designs from the PRD. Without this phase it designs as if the repository were
empty, which is where duplicated components originate: a plan that never saw the existing
rate limiter specifies a new one, and no gate downstream compares the two.

Dispatch a **read-only** Explore/mapping subagent on `haiku` (no edits, no plan opinions) and
write **`docs/deliveries/{key}/codebase-map.md`**:

| Section | Contents |
|---|---|
| Blast radius | **Every existing symbol the feature will change, with every caller of it.** See the rules below — this row decides the size of the work, so getting it wrong misprices everything downstream |
| Reusable symbols | Existing helpers, types, constants, validators, clients, middleware the feature could use — `file:line — signature — what it does` |
| Prior art | Features already solving a **similar** problem, even partially. The near-miss is the duplication risk; name it even when it does not fit |
| Conventions | Naming, error wrapping/propagation, dependency injection, context threading, layering — with a `file:line` exemplar for each |
| Extension points | Interfaces, registries, hooks, config surfaces the feature can plug into instead of adding a parallel path |
| Contracts in force | Existing signatures, error shapes, table/column names, config keys the feature must not contradict |
| Test conventions | Where tests live, framework, fixture/mock style, how existing tests are named |

### Blast radius — the rules

Everything else in the map is context. This row is a measurement, and it is the one most often
done by guess. A feature that "just adds a field" and turns out to change a shared type with 40
call sites is not a small feature — it was mis-scoped at the moment nobody counted.

- **Enumerate, do not estimate.** Use LSP find-references for every symbol the feature will change;
  grep only where LSP cannot reach (templates, config keys, reflection, string-built queries,
  cross-language boundaries). "Several callers" is not a measurement.
- **Every caller gets a line**: `file:line — what it assumes — does the change hold for it?`
- **Go one hop past the direct callers** for anything that changes an error value, a nil-ness, an
  ordering, or a type's width. Second-order breakage is where the regressions actually live.
- **Count the non-code callers too**: serialized payloads, DB columns, migrations, API consumers,
  feature flags, dashboards, alert queries, generated clients. A wire format has callers you cannot
  find with find-references.
- **Name the tests that will need to change** — a change requiring 30 test edits is a design signal,
  not a chore.
- **State the total**: `Blast radius: N symbols · M callers · K test files · {wire/schema surfaces}`.
  The Architect uses that number to decide whether the change is a story or an epic, and the Plan
  Reviewer checks it against the code.
- **An empty blast radius is a finding, not a formality** — if a feature touches nothing existing,
  say so explicitly, because it usually means the search was too narrow.

Rules: cite `file:line` for every entry — an uncited claim about existing code is not a finding
· report absence explicitly (`Reusable symbols: none — greenfield package`) rather than omitting
a section · never propose the design, only report what is there.

For a greenfield repo, run it anyway and record the empty result — "nothing exists yet" is a
fact the Architect and the Plan Reviewer both need stated, not inferred from a missing file.

Show: `✓ docs/deliveries/{key}/codebase-map.md`

## Phase 1 — Architecture

Load `agents/architect.md` with Brief + PRD + **`codebase-map.md`** as input.

Required output sections: Security Architecture + OWASP threat table + Mermaid data-flow diagram(s) + the **Reuse Map** (every planned component marked `reuse: file:sym` or `new: why nothing existing fits`).

Output: **the delivery file** — write to `docs/deliveries/delivery-{slug}-{key}.md` with the header block from `references/delivery-and-worktree.md` (show in full). Show: `✓ docs/deliveries/delivery-{slug}-{key}.md`

## Phase 2 — Stress the Plan (grill-me — MANDATORY before any code)

Every plan is stress-tested before coding. Load `/grill-me` and grill the architecture + manifest: missing error cases, auth gaps, schema problems, undecided edge cases, unowned failure modes. The goal is to surface and **close gaps now**, while changes are cheap — not at code time.

For each gap grill-me raises:
- If the requirements (Brief/PRD/delivery file) support a decision → **decide it and write it into the delivery file**. A question the plan should have answered but didn't is a planning error — fix the plan, do not defer it to the coder.
- If it cannot be decided from the available context → carry it to Phase 3 as an explicit open question for the human.

Re-run grill-me until it raises no new gaps the plan can resolve on its own.

## Phase 2.5 — Plan Review (MANDATORY — before the human sees it)

grill-me interrogates the plan from inside the context that wrote it and never opens the
repository. Phase 2.5 adds the reader that does both: fresh eyes, codebase open.

Load `agents/plan-reviewer.md` (Priya, `sonnet`) with the delivery file, the manifest (if Phase 4
already ran for a re-review), `codebase-map.md`, the PRD, and the repository. She reads the real
code and reports PR1–PR10 findings — already exists · reuse not declared · contradicts existing
code · convention breach · ambiguous AC · unfalsifiable Test Case row · untraced requirement ·
undecided question deferred into code · blast radius unstated · not independently testable.

Routing on her `Gate:` line:
- **`PLAN APPROVED`** → Phase 3.
- **`PLAN CHANGES REQUIRED`** → return the findings to the Architect, update the delivery file,
  re-review **only the changed sections**. Maximum 2 rounds; a third means the requirements
  themselves are unclear — carry the remaining findings to Phase 3 as open questions for the
  human rather than looping.

An `[OPEN QUESTION]` finding is never resolved by the Architect guessing — it goes to Phase 3.

Show: `✓ plan review — {score}/10, {n} findings resolved`

## Phase 3 — Human Validation

Present to user:
- Mermaid diagram(s)
- Tech stack decisions
- Top ADRs and tradeoffs
- **Open questions grill-me could not resolve from context** — ask the human to decide each before coding
- **Plan Review result** — Priya's score, her reuse verdict (`{N}/{M} planned components justified`), and any `[OPEN QUESTION]` finding she could not settle from the PRD

Ask: *"Does the architecture make sense? Any changes to libraries, strategies, or design? Please resolve the open questions above. Approve / request changes?"*

On changes → update the delivery file → re-confirm before continuing.

**If `api-spec.yaml` was produced** (feature has HTTP endpoints):

Present the API contract summary:
- Endpoint list: `METHOD /path — operationId` for each endpoint
- Auth scheme and which endpoints are protected
- Key request/response schema names

Ask: *"Does the API contract look right? Any changes to endpoints, schemas, auth, or error shapes before implementation starts? Once approved, Coder implements to this spec exactly — changes after that require updating the spec first."*

The API contract was already stressed in Phase 2 (grill-me) — confirm those findings are reflected in the spec.

On spec changes → update `api-spec.yaml` → run `rtk npx @stoplight/spectral-cli lint api-spec.yaml --ruleset .spectral.yaml` → re-confirm before continuing.

**Do not proceed to Phase 4 (Manifest) until both the delivery file and `api-spec.yaml` (if present) are approved and all open questions resolved.**

## Phase 4 — Manifest

Determine scope from the PRD epic count:

**Multiple epics (≥ 2)** → produce **Epic Manifest**:

| Epic | Task | Stories/ACs | Security ACs | Key Constraints | Projected diff | Language |
|------|------|-------------|--------------|-----------------|----------------|----------|
| Epic 1: {title} | T1.1: {imperative} | AC1, AC2 | SEC-1 | NFR-1 | ~140 lines | Go 1.26.2 |

**Single task / small scope (1 epic)** → produce **Task Manifest**:

| Sub-Task | Stories/ACs | Security ACs | Key Constraints | Projected diff | Language |
|----------|-------------|--------------|-----------------|----------------|----------|
| ST1: {imperative verb phrase} | AC1, AC2 | SEC-1 | NFR-1 | ~180 lines | TypeScript 5 |

`Language` must be populated from the Architect's Tech Stack decision — carries runtime, version, and framework (e.g. `Go 1.26.2`, `TypeScript 5 / Next.js 14`, `Java 21 / Spring Boot 3`). Every downstream agent reads Language from the Manifest — never inferred.

Each task/sub-task must be **independently testable** — expressible as one or more Test Case rows, each with an observable result and a named break that would falsify it. If a row cannot be stated that way, split it until it can.

It must also be **independently reviewable**. Review is where defects are actually caught, and reviewer effectiveness collapses with diff size — for a human and for an agent alike, a large diff gets skimmed rather than read, and the approval it produces means nothing. Size every row against a projected diff: **≤ 200 changed lines is the target, 400 the soft ceiling, 800 the hard one.** Past 800 the row is split, not justified. Isolate mechanical bulk (generated code, compiler-verified renames, formatting passes) into its own row — 40 lines of logic hidden inside 600 mechanical ones is the worst diff there is to review, and worse than either half alone.

Add the `Projected diff` estimate and the split decision to the manifest. The Plan Reviewer verifies it (PR11).

Write to: `docs/deliveries/{key}/epic-manifest.md` or `docs/deliveries/{key}/task-manifest.md` — beside the delivery file, keyed the same. Show: `✓ epic-manifest` or `✓ task-manifest`

## Phase 5 — Plan Summary

> *(When invoked from `/multi-agent` or `/task`, this phase is informational only — print the summary, do NOT halt, let the pipeline orchestrator continue.)*

Print the manifest and halt (standalone invocation only):

```text
Plan ready.

Artifacts produced:
  ✓ docs/deliveries/{key}/product-brief.md
  ✓ docs/deliveries/{key}/PRD.md
  ✓ docs/deliveries/{key}/codebase-map.md
  ✓ docs/deliveries/delivery-{slug}-{key}.md   (plan review: {score}/10)
  ✓ docs/deliveries/{key}/[epic-manifest | task-manifest].md

To implement:
  → /multi-agent   — multiple epics (full multi-agent pipeline)
  → /task          — single task (fast pipeline, no re-planning)

⚠ This skill does not start implementation.
  Invoke a pipeline skill to proceed.
```

Use `references/output-format.md` section headers for all agent output. Load agent files on demand — never pre-load all at once.
