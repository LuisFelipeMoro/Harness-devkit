---
name: bugfix
description: Build a feedback loop that goes red on a bug, rank and test hypotheses to its root cause, then apply the fix depth you choose and prove it RED to GREEN with the full suite and every gate. Usage: /bugfix [description], e.g. "/bugfix cart total goes negative after removing a coupon".
disable-model-invocation: true
---

**Input**: a bug description; the questions in step 1 fill in the rest.
**Output**: a feedback-loop command, ranked hypotheses with the confirmed one, a root-cause report, a regression test observed RED then GREEN (or a documented no-seam finding with the loop as the RED evidence), the minimal fix at the chosen depth, a green full suite and gates, a Bug Fix Summary, a `PROGRESS.md` entry.
**Boundary**: never weaken, delete or rewrite an existing test to make the fix pass. Dispatches: `bug-investigator` (`sonnet`) + `coder` (`haiku`) per fix round — exploration stays out of the main context; the post-checkpoint continuation resumes the same investigator, not a new dispatch. No push, no PR.

> **Discipline**: the failing reproduction test is written RED before any fix. This is the **one
> deliberate exception** to the devkit's spec-first rule (feature work implements first, then writes and
> falsifies the specified tests). A bug fix keeps test-first because the RED run is the evidence that the
> root cause was actually found rather than guessed: a fix applied without a test that failed beforehand
> can just as easily be masking the symptom. The RED here *is* the falsification step, obtained for free.

## Steps

1. **Ask first** — one AskUserQuestion call, up to four questions (skip one the description already answers):
   - Symptom vs expected — what happens now, and what should happen?
   - Reproduction — exact command, input or steps (or "not reproducible yet").
   - Fix depth — Minimal patch / Root-cause fix / Not sure — investigate first.
   - Branch — current branch / new `fix/{slug}` (per `references/branching.md`; on `main`/`master` always `fix/{slug}`).
2. **Loop and hypothesise.** At this step, read `references/dispatch.md` (this skill's) and dispatch `bug-investigator` with its template: the answers verbatim, `Base: $(git merge-base HEAD main)` (fall back to `master`). Before any theory it builds a tight feedback loop (one command, already run, red on the user's exact symptom, deterministic, fast, agent-runnable), reproduces and minimises, then returns a CHECKPOINT: the loop, the minimised repro and 3–5 ranked falsifiable hypotheses. `NO LOOP` → show what it tried and its ask (environment access, a redacted artifact, or permission for temporary instrumentation) and stop for the user.
3. **Show the hypotheses, then continue.** Print the ranked list — the user's domain knowledge often re-ranks it instantly — and continue the same investigator in this turn with the continuation template in `references/dispatch.md`; do not block on an answer (the user may be away). A re-rank or a ruled-out item the user gives is passed on verbatim. It instruments one variable at a time, confirms one hypothesis, writes the RED test at a correct seam, and returns BUG REPORT (root cause, code path `file:line`, why existing tests miss it, each hypothesis's verdict), the failing test (path + quoted RED output) and HANDOFF. Root cause `unknown` → show exactly what it asks to instrument and stop for the user. It does not fix anything.
4. **Confirm.** Show the BUG REPORT, RED output and the HANDOFF's `Seam` line (a `none` is a finding the user sees before the fix). AskUserQuestion: Fix as proposed / Change depth / Stop. "Not sure" from step 1 becomes a concrete depth here, chosen by the user from the HANDOFF's minimal-patch and root-cause options.
5. **Fix.** Dispatch the coder matching the bug's tier (`coder-backend`, `coder-frontend`, or `coder`) with the template in `references/dispatch.md` — paths and one-line facts only. Make the RED test GREEN with the minimum change at the chosen depth; the coder may ADD regression tests for edge cases the fix exposes, never weaken an existing one.
6. **Verify yourself** — every gate for the detected stack, not just the test suite (`references/quality-gate-reference.md`, read at this step): the regression test GREEN · the HANDOFF's original, un-minimised loop command green · full suite · format · type/vet · lint · **build** · coverage · race (Go) · vuln · `bash ~/.claude/git-hooks/dup-gate.sh --worktree`. A fix that passes its new test but fails lint/typecheck/build must not be called done. Re-break the fix once with `scripts/verify/break-run.sh` (revert the fix line → the regression test, or the loop on a no-seam finding, must fail by name). Any FAIL → a fresh coder dispatch with the output (Loop Integrity applies); after 3 failed rounds stop and suggest `/planning` with the BUG REPORT as input — the bug is bigger than a fix.
7. **Clean up, report and record.** Tick the cleanup checklist in `references/dispatch.md` (original loop green · regression test green or no-seam documented · no `[DEBUG-` tag left (`grep -rn "\[DEBUG-" .` empty) · throwaway prototypes deleted · confirmed hypothesis written into the summary's commit/PR line); an unticked item is not done. Print the gate report and the Bug Fix Summary from `references/dispatch.md`. Append to `PROGRESS.md`: `` `[{slug}]` root cause — fix (file:line) — regression test (RED → GREEN) ``.

Next: `/validate-code`, then `/review-code` (score ≥ 8.0 with no CRITICAL), then `/pr` — the confirmed hypothesis goes in its text. A no-seam finding is a lead for `/improve-codebase-architecture`.
