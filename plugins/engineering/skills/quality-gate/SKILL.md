---
name: quality-gate
description: Verify code is shippable by detecting the project stack and reporting PASS or FAIL for every gate before handoff. Trigger phrases — "quality gate", "run gates", "CI check", "lint", "coverage", "run tests", "check before PR".
---

Every gate must pass before handoff; a single failing gate blocks the handoff.

## Contract
- Input: a working directory containing source code.
- Output: a report table with one PASS/FAIL row per gate plus an overall verdict line.
- Tool boundary: read-only verification; source files stay unmodified, never auto-fixed.
- Done when: the report table prints with an overall verdict line and a coverage figure.

## Steps
1. Detect the stack from the markers in `references/stack-detection.md`. Monorepos match every stack present.
2. For each detected stack, the gate commands in `references/quality-gate-reference.md` apply in the fail-fast order from `references/execution-and-report.md`: format, type/vet, lint, build, tests + coverage, race (Go), vulnerability scan. **Duplication (≤ 3%) runs once for the whole repo regardless of stack** — it is language-agnostic, and a duplicate passes every other gate in the list.
3. Tests + coverage is the mandatory sensor: every changed source file wants a corresponding test, and coverage below threshold counts as a failing gate.
4. The report table and overall verdict line follow the template in `references/execution-and-report.md`. The verdict line states PASS when every gate is green.

## References
- `references/stack-detection.md` — detection command and file→stack table.
- `references/execution-and-report.md` — gate order and report template.
- `references/quality-gate-reference.md` — per-stack gate commands and common fixes.
