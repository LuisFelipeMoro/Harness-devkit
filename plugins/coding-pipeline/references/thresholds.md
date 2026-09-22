# Thresholds — single source

Every numeric gate in the devkit. Restating a number anywhere else is how they drift:
before this file, the coverage floor appeared in 18 files and `verdict.md` had already lost
React, Flutter and Kotlin from its list. Cite this file; do not copy the numbers out of it.

`scripts/verify/verdict.sh` reads these values, so a change here changes the gate.

## Coverage floor

| Stack | Floor |
|---|---|
| Go · Java · Kotlin · JS/TS · React · Next.js · Rust | 85% |
| PHP · Flutter | 80% |

## Repo-wide

| Gate | Limit | Sensor |
|---|---|---|
| Duplication | ≤ 3% | `git-hooks/dup-gate.sh` (jscpd + line-level attribution) — limit applies to duplication this change *introduced*; pre-existing debt is reported, never blocks |
| Lint | 0 errors | ERROR mode per stack (`--max-warnings 0`, `-D warnings`, `golangci-lint`) |

## Scores

| Gate | Value |
|---|---|
| Verdict weighting | Review 35% · Stress 35% · QA 30% |
| PRODUCTION READY | all hard gates PASS · overall ≥ 8.0 · 0 CRITICAL |
| READY WITH CONDITIONS | all hard gates PASS · 6.5–7.9, or ≥ 8.0 with ≤ 1 non-security CRITICAL |
| NOT READY | any hard gate FAIL · overall < 6.5 · any unmitigated CRITICAL security issue |
| Story floor | Reviewer ≥ 7/10 · Stress ≥ 7/10 |
| Reviewer BLOCK | caps overall at 5.0 |
| Tautological test | MAJOR — caps QA score at 4 |
| Review/Stress score gap | > 3 → WARNING note, verdict unchanged |

## Limits

| Thing | Limit |
|---|---|
| Context ceiling | 80% of window (warn at 60%) — sensor: `hooks/context-budget.sh` |
| Subagent dispatches | 14 per session, advisory — 3 per story (Coder · QA · Reviewer) × 3 stories + 3 planning + 2 delivery. Sensor: `hooks/dispatch-budget.sh` |
| Subagents per turn | 3 (never 4+) |
| Tuner iterations | 2 per pipeline run |
| Bug-Fix Loop iterations | 3, then `QA ESCALATION` |
| Plan-review rounds | 2 |
| Sub-task size | ~200 lines of production code |
| Graceful shutdown drain | ≤ 30s |
