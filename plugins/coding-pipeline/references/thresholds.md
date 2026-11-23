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
| `/validate-code` weighting (`verdict.sh --no-review`) | Stress 35% · QA 30%, renormalised over 65% — the review is `/review-code`'s own gate (≥ 8.0, no CRITICAL) |
| `/validate-code` light depth (`verdict.sh --no-review --no-stress`) | QA 30%, renormalised over 30% — stress not dispatched (classify-diff `light`); no stress score accepted, so no Stress floor |
| PRODUCTION READY | all hard gates PASS · overall ≥ 8.0 · 0 CRITICAL |
| READY WITH CONDITIONS | all hard gates PASS · 6.5–7.9, or ≥ 8.0 with ≤ 1 non-security CRITICAL |
| NOT READY | any hard gate FAIL · overall < 6.5 · any unmitigated CRITICAL security issue |
| Per-lens floor | Reviewer ≥ 7/10 · Stress ≥ 7/10 |
| Reviewer BLOCK | caps overall at 5.0 |
| Tautological test | MAJOR — caps QA score at 4 |
| Review/Stress score gap | > 3 → WARNING note, verdict unchanged |
| Score loop | overall < 8.0 → fix round · 3 fix rounds after the first score · then the human (procedure: `quality-gate-reference.md` § Score Loop) |

## Roster

Optional `--roster` mode of `scripts/verify/verdict.sh` (`--roster R --classify-exit N`). It applies these lenses and floors on top of
the Scores table above, which still governs `standard`/`full`/the roster-absent default path.

**What v3 skills actually call.** `/validate-code` is the only skill that runs `verdict.sh`, in exactly
three modes: `--roster cosmetic --classify-exit N` (cosmetic depth), `--no-review --no-stress --qa Q` (light),
and `--no-review --stress S --qa Q` (standard/full) — the last two are in the Scores table. The roster-absent
default and the `light`/`standard`/`full` rosters below are **legacy modes of `verdict.sh --roster`, kept for
compatibility** with 2.x callers and still covered by tests; no v3 skill invokes them. Their "Review" lens and
the `[folded]` label are 2.x concepts (the Reviewer agent once scored Stress as a folded lens) — in v3 the
review is `/review-code`'s own gate.

| Roster | Lenses required | Score | Floors | Extra hard gates |
|---|---|---|---|---|
| (absent, legacy) | Review · Stress · QA | 35/35/30 (legacy) | Review ≥ 7 · Stress ≥ 7 | — |
| `cosmetic` | none — any score flag given = exit 2 | n/a — gates only | — | `--hard-gate-fail`, `--critical-security > 0`, or `--classify-exit ≠ 0` → NOT READY |
| `light` (legacy) | Review · Stress; `--qa` given = exit 2 | (R·0.35 + S·0.35) / 0.70 | Review ≥ 7 · Stress ≥ 7 | the caller passes any non-zero spec-coverage/falsification/tautology-scan result as `--hard-gate-fail` |
| `standard` (legacy) | Review · Stress · QA — legacy: Stress was the 2.x Reviewer's folded lens | 35/35/30 | Review ≥ 7 · Stress ≥ 7 | — |
| `full` (legacy) | Review · Stress · QA — Stress is a dispatched agent | 35/35/30 | Review ≥ 7 · Stress ≥ 7 | — |

`--classify-exit` is mandatory whenever `--roster` is given; a non-zero value is always NOT READY
(`roster not verified (classify-diff exit N)`) regardless of score — an escalation the caller
has not resolved must never ship. `standard` never changes the outcome a legacy run would give for
the same three scores; only the Stress label differs (`[folded]` vs `[dispatched]`).

## Limits

| Thing | Limit |
|---|---|
| Context ceiling | 80% of window (warn at 60%) — sensor: `hooks/context-budget.sh` |
| SessionStart output | ≤ 9,500 characters (Claude Code cuts at 10,000); PROGRESS.md gives way first, oldest `## [` entries first — sensor: `hooks/session-bootstrap.sh` |
| Subagent dispatches | 20 per session, advisory — derived: plan (1 map + 2 reviews) 3 + `/code` (1 `coder` per Tasks row, 5-row run) 5 + `/validate-code` 2 + one score round 3 + `/review-code` 1 + one score round 2 = 16, + slack = 20. Shape: `/planning` (1 map + 1 `plan-reviewer` per round, max 3 fix rounds) + `/code` (1 `coder` per Tasks row) + `/validate-code` (0–2, by depth) + `/review-code` (1). Sensor: `hooks/dispatch-budget.sh` |
| Writer subagents per turn | 3 (never 4+); read-only subagents are counted separately in the next row |
| Read-only subagents per turn | 6 — each returns ≤ 150 words or one table; every one counts toward the session dispatch budget |
| Fix Loop iterations | 3, then `QA ESCALATION` |
| Plan-review rounds | 3 fix rounds after the first score, then the human |
| Task size (one Tasks row) | ~200 lines of production code |
| Graceful shutdown drain | ≤ 30s |
| Gate timeout | 900 s (`DEVKIT_GATE_TIMEOUT`, positive integer; unset or invalid → 900) — `checkpoint-m.sh --gates` and `break-run.sh` kill the command and exit 2 |
| Push stdin bound | 10 s per line (`DEVKIT_PUSH_STDIN_TIMEOUT`, positive integer) — `git-hooks/pre-push` reading git's ref lines; no line → base-resolution fallback |
| Background run stall | 10 minutes with no change to its output file — kill, say so, re-run with stdin closed (`</dev/null`) |
| Auto-compact window (flat install) | 300000 — Claude Code `autoCompactWindow`, code.claude.com/docs/en/model-config#set-the-auto-compact-window · written by `scripts/wire-claude-settings.py` only when absent |
