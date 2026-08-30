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

## Phase 1 — Architecture

Load `agents/architect.md` with Brief + PRD as input.

Required output sections: Security Architecture + OWASP threat table + Mermaid data-flow diagram(s).

Output: **the delivery file** — write to `docs/deliveries/delivery-{slug}-{key}.md` with the header block from `references/delivery-and-worktree.md` (show in full). Show: `✓ docs/deliveries/delivery-{slug}-{key}.md`

## Phase 2 — Stress the Plan (grill-me — MANDATORY before any code)

Every plan is stress-tested before coding. Load `/grill-me` and grill the architecture + manifest: missing error cases, auth gaps, schema problems, undecided edge cases, unowned failure modes. The goal is to surface and **close gaps now**, while changes are cheap — not at code time.

For each gap grill-me raises:
- If the requirements (Brief/PRD/delivery file) support a decision → **decide it and write it into the delivery file**. A question the plan should have answered but didn't is a planning error — fix the plan, do not defer it to the coder.
- If it cannot be decided from the available context → carry it to Phase 3 as an explicit open question for the human.

Re-run grill-me until it raises no new gaps the plan can resolve on its own.

## Phase 3 — Human Validation

Present to user:
- Mermaid diagram(s)
- Tech stack decisions
- Top ADRs and tradeoffs
- **Open questions grill-me could not resolve from context** — ask the human to decide each before coding

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

| Epic | Task | Stories/ACs | Security ACs | Key Constraints | Language |
|------|------|-------------|--------------|-----------------|----------|
| Epic 1: {title} | T1.1: {imperative} | AC1, AC2 | SEC-1 | NFR-1 | Go 1.26.2 |

**Single task / small scope (1 epic)** → produce **Task Manifest**:

| Sub-Task | Stories/ACs | Security ACs | Key Constraints | Language |
|----------|-------------|--------------|-----------------|----------|
| ST1: {imperative verb phrase} | AC1, AC2 | SEC-1 | NFR-1 | TypeScript 5 |

`Language` must be populated from the Architect's Tech Stack decision — carries runtime, version, and framework (e.g. `Go 1.26.2`, `TypeScript 5 / Next.js 14`, `Java 21 / Spring Boot 3`). Every downstream agent reads Language from the Manifest — never inferred.

Each task/sub-task must be **independently testable** — expressible as one or more Test Case rows, each with an observable result and a named break that would falsify it. If a row cannot be stated that way, split it until it can.

Write to: `docs/deliveries/{key}/epic-manifest.md` or `docs/deliveries/{key}/task-manifest.md` — beside the delivery file, keyed the same. Show: `✓ epic-manifest` or `✓ task-manifest`

## Phase 5 — Plan Summary

> *(When invoked from `/multi-agent-coding-pipeline` or `/task-coding-pipeline`, this phase is informational only — print the summary, do NOT halt, let the pipeline orchestrator continue.)*

Print the manifest and halt (standalone invocation only):

```text
Plan ready.

Artifacts produced:
  ✓ docs/deliveries/{key}/product-brief.md
  ✓ docs/deliveries/{key}/PRD.md
  ✓ docs/deliveries/delivery-{slug}-{key}.md
  ✓ docs/deliveries/{key}/[epic-manifest | task-manifest].md

To implement:
  → /multi-agent-coding-pipeline   — multiple epics (full BMAD v6 pipeline)
  → /task-coding-pipeline          — single task (fast pipeline, no re-planning)

⚠ This skill does not start implementation.
  Invoke a pipeline skill to proceed.
```

Use `references/output-format.md` section headers for all agent output. Load agent files on demand — never pre-load all at once.
