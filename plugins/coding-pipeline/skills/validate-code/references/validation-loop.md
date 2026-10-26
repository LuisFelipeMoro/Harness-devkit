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

Report on qa's output signal (never fix — `/validate-code` is report-only):
- `QA→REVIEWER APPROVAL` → audit clean; the verdict uses its score.
- `QA→CODER BUG REPORT`, `QA→CODER TEST GAP`, or `QA→CODER COVERAGE REQUEST` → listed as the first action
  items; the user fixes via `/code` (its checkpoint re-runs), then re-runs `/validate-code`.
- `QA ESCALATION` (after 3 iterations) → reported with FAIL status; cannot be PRODUCTION READY.

**Loop Integrity** in `references/quality-gate-reference.md` applies to every re-run: no goalpost-moving,
stop on an identical repeat failure.

## stress

- Dispatched by `/validate-code` at standard and full depth (SKILL.md step 2), in parallel with qa (both read-only); at light depth classify-diff found no Stress trigger in ≤ 2 source files, so it is not dispatched and the verdict scores QA alone — `--full` brings it back. `STRESS-TRIGGER: yes` or a
  `[SHARED-STATE]` tag from `security-scan.sh --diff` points it at the code to stress first — unless it is
  explained by test-fixture strings.
- `agents/stress.md` → the diff's code + tests, including Security Under Stress.
- One fix round (via `/code`) covers qa and stress findings together; then `/validate-code` re-runs.
- Re-checks after a fix are **narrow, never a full re-run of judgment**: qa re-audits only the tests that
  changed; stress confirms only its own prior findings.

## Verdict

`scripts/verify/verdict.sh` in the depth's mode (`--no-review --stress S --qa Q`; `--no-review --no-stress --qa Q` at light; `--roster cosmetic --classify-exit 0` at cosmetic) computes the gate, score and threshold;
`agents/verdict.md` is read at this step and its Security Gate, narrative and Verdict Self-Check are applied
**inline** — no verdict agent is dispatched.
- Input: Stress score (when dispatched) + QA summary (when dispatched) + AC checklist + gate table. No review score: the review is `/review-code`'s
  own gate, run separately, and is never folded into or awaited by this verdict.
- Security Gate section required; unmitigated CRITICAL security = automatic NOT READY.

## Outcome table

| Score | Security | Next |
|-------|----------|------|
| ≥ 8.0 | No CRITICAL | PRODUCTION READY — commit / open a PR when the user asks; `/review-code` if not run yet |
| ≥ 8.0 | CRITICAL security | NOT READY — security fix via `/code`, then `/validate-code` again |
| < 8.0 | Any | Show issues; ask: *"Fix via /code and re-run / accept with known issues / stop?"* |

On a re-run, report only the delta (CRITICAL/MAJOR issues, failing ACs, failed gates) against the previous
run, plus the new verdict.
