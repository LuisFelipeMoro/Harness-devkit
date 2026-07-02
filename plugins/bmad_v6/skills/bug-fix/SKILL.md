---
name: bug-fix
description: Use when investigating and fixing a behavioral bug — dispatches Sam (Bug Investigator) and Amelia (Coder) as sub-agents to keep exploration out of main context. Trigger phrases — "bug", "fix", "broken", "not working", "wrong behavior", "unexpected", "crash", "regression", "debug", "fails with".
---

> **Discipline**: Failing test written RED before any fix. Never modify existing tests to fit the fix.

Behavior contract: [skill.spec.yml](skill.spec.yml) · dependency ledger: [deps.toml](deps.toml). Sub-agent dispatch prompts and report templates: [references/dispatch.md](references/dispatch.md).

## Contract

- **Input**: bug description + reproduction steps (ask if not provided).
- **Output**: a minimal fix that turns a RED test GREEN, a green full suite, a Reviewer score, and a Bug Fix Summary.
- **Boundary**: never weaken/delete/rewrite an existing test to make the fix pass; Reviewer sees changed files only.
- **Steps**: 1) Investigate (Sam) → 2) Fix (Amelia) → 3) Verify (Quinn) → 4) Review → 5) Summary.

## Phase 1 — Investigate (Sam sub-agent)

Input: Bug description from user. Ask if not provided: "What's the wrong behavior? How do I reproduce it?"
Output: BUG REPORT + SAM HANDOFF packet.
Boundary: does NOT fix anything.

Dispatch Sam (model `sonnet`) using the Phase 1 template in [references/dispatch.md](references/dispatch.md).
Show BUG REPORT and SAM HANDOFF to user before continuing.

## Phase 2 — Fix (Amelia sub-agent)

Input: SAM HANDOFF from Phase 1 (includes Sam's failing RED test).
Output: `CODER DONE — BUGFIX COMPLETE` signal (see Agent Handoff Signals in `references/quality-gate-reference.md`).
Boundary: make Sam's RED test GREEN with the minimum fix. Amelia may ADD regression tests for edge cases the fix exposes; she must NOT weaken, delete, or rewrite an existing test to fit the fix.

Dispatch Amelia (model `opus`) using the Phase 2 template in [references/dispatch.md](references/dispatch.md).

## Phase 3 — Verify (Quinn)

Input: `CODER DONE` signal from Phase 2.
Output: Gate report or `QA→CODER BUG REPORT` if any gate fails.

Run every quality gate for the detected stack — not just the test suite: format, type/vet, lint, **build**, tests + coverage, race (Go), vuln scan — per `references/quality-gate-reference.md` (same gate set the full pipelines use). A fix that passes its new test but fails lint/typecheck/build must not reach Reviewer. Emit the gate report per `references/dispatch.md`.

Any gate FAIL (regression, lint, typecheck, build, or otherwise): emit `QA→CODER BUG REPORT` → route back to Amelia (Bug-Fix Loop Protocol, max 3 iterations — see `references/quality-gate-reference.md`).
After 3 failures: escalate to `/task-coding-pipeline` with original BUG REPORT as input.

## Phase 4 — Review (Reviewer)

Input: `QA→REVIEWER APPROVAL` from Phase 3 (all gates green) + changed files (scope per the Contract above).
Output: Review score + findings.

Load `agents/reviewer.md`. Pass:
- Full content of files changed by the fix
- Gate summary: `"Gates: all green — {N} tests, 0 failed"`

| Score | Security | Action |
|-------|----------|--------|
| ≥ 8.0 | No CRITICAL | Proceed to Phase 5 |
| Any | CRITICAL | BLOCK — security issue introduced by fix; route back to Amelia |
| < 8.0 | No CRITICAL | Show findings; ask user to confirm before closing |

## Phase 5 — Summary

Print the Bug Fix Summary using the template in [references/dispatch.md](references/dispatch.md).
