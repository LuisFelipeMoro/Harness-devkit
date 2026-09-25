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

## Roster

`scripts/verify/verdict.sh --roster R --classify-exit N` applies these lenses and floors on top of
the Scores table above, which still governs `standard`/`full`/the roster-absent legacy path.

| Roster | Lenses required | Score | Floors | Extra hard gates |
|---|---|---|---|---|
| (absent) | Review · Stress · QA | 35/35/30 (legacy) | Review ≥ 7 · Stress ≥ 7 | — |
| `cosmetic` | none — any score flag given = exit 2 | n/a — gates only | — | `--hard-gate-fail`, `--critical-security > 0`, or `--classify-exit ≠ 0` → NOT READY |
| `light` | Review · Stress; `--qa` given = exit 2 | (R·0.35 + S·0.35) / 0.70 | Review ≥ 7 · Stress ≥ 7 | orchestrator passes any non-zero spec-coverage/falsification/tautology-scan result as `--hard-gate-fail` |
| `standard` | Review · Stress · QA — Stress is the Reviewer's folded lens | 35/35/30 | Review ≥ 7 · Stress ≥ 7 | — |
| `full` | Review · Stress · QA — Stress is a dispatched agent | 35/35/30 | Review ≥ 7 · Stress ≥ 7 | — |

`--classify-exit` is mandatory whenever `--roster` is given; a non-zero value is always NOT READY
(`roster not verified (classify-diff exit N)`) regardless of score — an escalation the orchestrator
has not resolved must never ship. `standard` never changes the outcome a legacy run would give for
the same three scores; only the Stress label differs (`[folded]` vs `[dispatched]`).

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
