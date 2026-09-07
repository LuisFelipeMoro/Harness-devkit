---
name: improve-codebase-architecture
description: 'Use when deepening architectural quality of a codebase. Finds coupling, boundary violations, missed abstractions, and SRP failures. Produces HTML report in /tmp. Offers ADRs and grilling loop. Trigger phrases: "improve architecture", "architectural review", "find coupling", "refactor architecture", "codebase health", "zoom out", "architectural debt", "tech debt audit".'
---

Report findings only — never fix in this skill. Each finding includes severity, location, and a concrete recommendation.

> **Refactor guard**: this skill only reports. Any refactor that follows must be protected by a characterization test first — pin the current observable behaviour with a passing test (it goes RED the moment the refactor changes behaviour), then refactor under green. Never restructure code that has no test covering it; add the test first.

## Phase 1 — Map (1 Explore sub-agent, model: haiku)

Input: Working directory. Optionally: focus area.
Output: Raw observations list.
Boundary: no analysis, no recommendations.

Dispatch one read-only Explore sub-agent using the call template in `references/arch-report-reference.md`.

## Phase 2 — Score

Input: Phase 1 observations.
Output: Findings grouped by severity.

| Severity | Examples |
|----------|---------|
| Critical | Domain logic in HTTP/DB layer; circular imports; unhandled errors on mutation path |
| High | 3+ callers duplicating logic; file >500 lines; cross-feature deep imports |
| Medium | File 300–500 lines; inconsistent patterns; magic values |
| Low | Naming inconsistency; minor duplication; dead code |

## Phase 3 — Report

Write HTML report to `/tmp/arch-report-<YYYY-MM-DD>.html`.
See `references/arch-report-reference.md` for HTML scaffold.
Print: `Architecture report: /tmp/arch-report-<date>.html — N critical, N high, N medium, N low findings.`

## Phase 4 — Grill (optional)

Offer: "Want to stress-test any finding? Type `/grill-me` with the finding."

## Phase 5 — ADR (optional)

For each Critical/High finding the user wants to address: offer `docs/adr/ADR-NNN-title.md`.
See `references/arch-report-reference.md` for the ADR template.
