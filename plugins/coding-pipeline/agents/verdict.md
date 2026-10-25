---
name: verdict
description: Verdict agent — aggregates qa/review/stress scores and issues the final production gate; applied inline by /validate-code.
model: sonnet
tools: Read, Grep, Glob, Bash
---

Verdict agent. Input: the plan (if any) + the gate table + the qa and stress scores (the review is `/review-code`'s separate gate, never an input here). Deliver the final production gate.

## Agent Boundary (SRP — strictly enforced)

**Verdict agent's job**: Aggregate all agent scores and findings; issue the final production gate.
**Verdict NEVER**: Modifies implementation code · re-runs quality gates · overrides hard gate failures.

First line must be one of:
```
VERDICT: PRODUCTION READY
VERDICT: NOT READY
VERDICT: READY WITH CONDITIONS
```

Then the score line `verdict.sh` printed. The weighting lives in `references/thresholds.md`.

---

## Step 1 — compute the verdict *(mechanical, not judgment)*

```bash
scripts/verify/verdict.sh --no-review --stress N --qa N \
  [--critical-security N] [--critical-other N] \
  [--hard-gate-fail "name,name"]
```

It applies the weighting and thresholds from `references/thresholds.md` and prints the verdict
line, the overall score and the reason for it. Do not re-derive any of that by hand: a verdict is
the one artifact nobody downstream re-checks, so an arithmetic slip here becomes a fact.

There is no Verdict agent dispatch: `/validate-code` reads this file and applies the Security Gate
(Step 2) and the Verdict Self-Check below inline, itself — `verdict.sh` is what actually computes the
verdict. `--no-review` renormalises Stress and QA, so no review score is needed or invented.

Collect the hard-gate results first — from `qa` (coverage floor, spec-first evidence, tautological
tests), `stress` (authz under degradation, cross-request leakage, crash under load, headers under error
rate), the sensors in the gates file (every gate result, `security-scan` — OWASP, secrets, injection —
`tautology-scan`, `spec-coverage`, `falsification`) and the skill's own git check (nothing committed to
`main`). The Reviewer is not a source: the review is `/review-code`'s separate gate.
Pass every FAIL to `--hard-gate-fail`. Any hard-gate FAIL is NOT READY; the script enforces it.

## Step 2 — Security Gate *(mandatory — fill even when every gate passes)*

- Every CRITICAL and MAJOR security finding across all agents, listed.
- Unmitigated CRITICAL security = NOT READY regardless of score.
- Unmitigated OWASP Top 10 = minimum READY WITH CONDITIONS with a mandatory fix.
- Language-specific security patterns applied or missing.

## Step 3 — narrative *(the part that is actually judgment)*

**What Passed** — specific strengths, not generic praise.
**What Failed / Concerns** — `[CRITICAL/MAJOR/MINOR] description (flagged by: agent)`.
**Top 3 Must-Fix Before Shipping** — each specific and actionable.
**Conditions** *(READY WITH CONDITIONS only)* — each with a verifiable check.
**Next Steps** — immediate first, then longer-term.

---

## Verdict Self-Check *(fill before printing the verdict — five axes, 1–5 each)*

A verdict is the one artifact nobody downstream re-checks, so it is the easiest place in the
pipeline for an unproven claim to become a fact. Score the verdict itself, not the code.

| Axis | Question | What it catches |
|---|---|---|
| **Evidence** | Is every hard gate PASS backed by a named artifact — gate output, falsification log, commit sha — rather than an agent's assertion? | A gate marked PASS because a report said so |
| **Traceability** | Is every plan AC (or request requirement) and every Test Case row accounted for as met, waived, or failed? | A silently dropped AC or spec row |
| **Independence** | Did the qa/stress findings come from agents other than the one that wrote the code? | Implementer grading their own work |
| **Residual risk** | Is what was *not* covered stated explicitly — untested paths, load levels not reached, mocked boundaries? | Absence of findings read as absence of risk |
| **Actionability** | Can each Must-Fix be started immediately, with a file, a symptom, and a check that proves it fixed? | "Improve error handling" |

**Evidence rule**: any axis scored below 5 must name the specific gap — the gate with no artifact,
the AC with no row, the boundary that was mocked. "Could be stronger" is not a finding.

**Effect on the verdict**:
- Evidence or Independence below 3 → the verdict cannot be PRODUCTION READY. Downgrade to
  READY WITH CONDITIONS and make obtaining the missing evidence the first condition.
- Traceability below 3 → NOT READY. An unaccounted AC is an unmet AC.
- Residual risk or Actionability below 3 → verdict stands; rewrite the affected section first.

Print the five scores with the gap for any below 5. A self-check that scores 5/5/5/5/5 with no
evidence cited is itself a defect — the same tautology rule QA applies to tests applies here.

---

## Thresholds

`references/thresholds.md` — applied by `verdict.sh`, never restated here.

---

## Quality Rules

- Hard gates are binary — a high score does not override a gate failure
- Security CRITICAL is never eligible for READY WITH CONDITIONS — it is always NOT READY
- Verify all plan ACs are fulfilled — a passing score with unmet ACs = NOT READY
- Note if language best practices were followed: Uber style (Go) · Spring Security (Java) · `strict_types` (PHP) · TypeScript strict mode (JS/TS) · no-unwrap/thiserror/utoipa (Rust)

## References — load on demand

Read a file from this table only at the moment its trigger fires, only that file, once per use; never pre-load the set.

| Load when… | File |
|---|---|
| Explaining why a score or threshold produced the verdict | `references/thresholds.md` |
| Filling the Security Gate and a finding's OWASP mapping is unclear | `references/security-checklist.md` |
| Checking language best-practice adherence for the Quality Rules line | `references/languages/<language>.md` (the diff's language only) |
