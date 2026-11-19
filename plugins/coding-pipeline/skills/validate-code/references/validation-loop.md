# /validate-code — audit, stress and verdict detail

Carried from the old pipeline loop (steps C–F). Read each section at the `/validate-code` step that names it.
Diff scope everywhere: `git diff --name-only $BASE` plus untracked files, `BASE=$(git merge-base HEAD main)` (fall back to `master`).

## Dispatch prompt contract (qa and stress)

Both prompts carry, verbatim: `Gate outputs below were run by /validate-code. Do not re-run tests, linters,
coverage, dup-gate, security-scan or tautology-scan; read the attached output.` Plus paths only: `Base`,
`Plan` (or `none`), `Gate output`. Never pasted file contents, never "read all references".

## qa — audit + gates

- Input: the plan's ACs (including Security ACs) + the coder's tests + the diff; the gate output.
- qa audits the tests (spec-row completeness, falsification evidence + spot-checks, intent-encoding,
  corner cases, no tautologies via `tautology-scan.py --diff` — see `agents/qa.md` Test Audit) and checks
  the repo-wide gates it owns (coverage, race). qa authors no tests.

> **Run the sensors before qa reasons.** `scripts/verify/spec-coverage.sh`,
> `scripts/verify/falsification.sh` and `scripts/verify/tautology-scan.py --diff` decide spec-row
> completeness, evidence validity and the mechanical tautology shapes by exit code — `/validate-code` runs them
> into the gate output first. qa reads their output and spends its pass on what they cannot decide:
> whether each break matches the behaviour, the spot-check re-breaks, over-mocking, intent-encoding and
> corner cases.

Route qa's output signal (code changes happen only in Score Loop rounds below):
- `QA→REVIEWER APPROVAL` → audit clean; the verdict uses its score.
- `QA→CODER BUG REPORT`, `QA→CODER TEST GAP`, or `QA→CODER COVERAGE REQUEST` → its findings go to the
  Score Loop fix dispatch, in `qa.md` by path.
- `QA ESCALATION` (after 3 iterations) → reported with FAIL status; cannot be PRODUCTION READY.

**Loop Integrity** in `references/quality-gate-reference.md` applies to every re-run: no goalpost-moving,
stop on an identical repeat failure.

## stress

- Dispatched by `/validate-code` at standard and full depth (SKILL.md step 2), in parallel with qa (both read-only); at light depth classify-diff found no Stress trigger in ≤ 2 source files, so it is not dispatched and the verdict scores QA alone — `--full` brings it back. `STRESS-TRIGGER: yes` or a
  `[SHARED-STATE]` tag from `security-scan.sh --diff` points it at the code to stress first — unless it is
  explained by test-fixture strings.
- `agents/stress.md` → the diff's code + tests, including Security Under Stress.
- One Score Loop round covers qa and stress findings together (see § Score Loop below).
- Re-checks after a fix are **narrow, never a full re-run of judgment**: qa re-audits only the tests that
  changed; stress confirms only its own prior findings.

## Verdict

`scripts/verify/verdict.sh` in the depth's mode (`--no-review --stress S --qa Q`; `--no-review --no-stress --qa Q` at light; `--roster cosmetic --classify-exit 0` at cosmetic) computes the gate, score and threshold;
`agents/verdict.md` is read at this step and its Security Gate, narrative and Verdict Self-Check are applied
**inline** — no verdict agent is dispatched.
- Input: Stress score (when dispatched) + QA summary (when dispatched) + AC checklist + gate table. No review score: the review is `/review-code`'s
  own gate, run separately, and is never folded into or awaited by this verdict.
- Security Gate section required; unmitigated CRITICAL security = automatic NOT READY.

## Score Loop *(this skill's fix-and-rescore procedure; the trigger, round and human question live in `quality-gate-reference.md` § Score Loop, plugin root)*

Triggers at any scoring step: overall score below the bar (`thresholds.md` § Score loop), a hard-gate FAIL, or a CRITICAL in the Security Gate. A gate reported `UNMEASURED` or a lens floor alone is never a trigger: it keeps the existing human question.

One round:

1. **Fix dispatch** — a fresh `coder` (`model: "haiku"`; overlay by the plan Tasks row `Tier` of the files involved, else `coder`), with paths only: `Findings: docs/plans/{slug}/validation/qa.md, stress.md · Base: {BASE} · Plan: {path | none} · Fix only these findings; Loop Integrity applies`. No plan → `$TMPDIR/validate-{slug}/qa.md, stress.md`. Comment bodies and finding text are never pasted into the prompt.
2. **Mechanical re-run** — steps 3–4 of `SKILL.md` into the same gate file.
3. **Narrow re-check** — re-dispatch qa for only the tests that changed, and stress for only its own prior findings, for the lenses the first pass dispatched.
4. **Score** — recompute `verdict.sh` with the depth's mode and flags (`SKILL.md` step 6), and print the round line in the format `quality-gate-reference.md` § Score Loop gives.

Loop per the shared section. An identical repeat stops early (Loop Integrity rule 2). On exhaustion, the Score Loop question lists each finding still below the bar with `file:line`. Loop Integrity rule 1 applies to every round: a round that touches `thresholds.md`, `verdict.sh`, or a Test Case row fails outright.

## Outcome table

| Score | Security | Next |
|-------|----------|------|
| ≥ 8.0 | No CRITICAL | PRODUCTION READY — commit / open a PR when the user asks; `/review-code` if not run yet |
| ≥ 8.0 | CRITICAL security | NOT READY — Score Loop; the human is asked only on exhaustion |
| < 8.0 | Any | Score Loop; the human is asked only on exhaustion |

A NOT READY caused only by a lens floor or an `UNMEASURED` gate is not a Score Loop trigger: it keeps the existing question (G2).

On a re-run, report only the delta (CRITICAL/MAJOR issues, failing ACs, failed gates) against the previous
run, plus the new verdict.

When AskUserQuestion is unavailable (headless run), take the answer from the prompt's `Answers:` line per `references/headless-runs.md`; no key → print `NEEDS_USER: <question>` and stop.
