---
name: validate-code
description: Validate the current diff against its base branch — every quality gate for the detected stack, the verify sensors, a qa audit and a stress pass at the depth the diff needs, then the scripted verdict — and report without fixing anything. Usage: /validate-code [plan-path] [--full], e.g. "/validate-code docs/plans/checkout-retry/plan.md".
disable-model-invocation: true
---

**Input**: the working diff vs `BASE=$(git merge-base HEAD main)` (fall back to `master`); optionally the plan path; `--full` forces full depth.
**Output**: the depth line, a gate report (one PASS/FAIL row per gate + overall line + coverage figure), the qa and stress reports the depth dispatched, and a verdict with its self-check — printed only.
**Boundary**: read-only verification — never edits, auto-fixes, commits or pushes; source files stay unmodified. Dispatches by depth (`sonnet`), nothing else: cosmetic none · light `qa` · standard/full `qa` + `stress`; the verdict is `verdict.sh` + an inline self-check.

**Rules**: every gate must pass before a change counts as done — a single failing gate blocks; duplication (≤ 3% introduced) runs once for the whole repo regardless of stack, because a duplicate passes every other gate; tests + coverage is the mandatory sensor and coverage is a floor, never the goal; exit 2 from any sensor is UNENFORCED, never a pass; an unmitigated CRITICAL security finding is always NOT READY; depth only ever escalates — `classify-diff.sh` sets the floor, `--full` raises it, nothing lowers it, and an unmeasured classification is full depth. Load each reference only at the step that names it.

## Steps

1. **Scope.** `git diff --name-only $BASE` plus untracked files. Empty → say so and stop. Plan given → its `Language` / `Tier` drive the gates. No plan → at this step, read `references/stack-detection.md` (this skill's) and detect the stack; a monorepo matches every stack present.
2. **Depth.** `scripts/verify/classify-diff.sh --diff $BASE --declared cosmetic` — declaring the lowest roster makes the script report what the diff requires, since it never de-escalates. Exit 0 → `cosmetic`; exit 1 → the `X` of its `ROSTER: ESCALATE cosmetic → X` line; exit 2 (dirty tree, empty diff, security-scan unmeasured) → `full`, quoting its `UNMEASURED` line — commit first to let it measure. `--full` → `full`, whatever it said. Print one line before any gate: `Depth: {depth} — {its REASON: line | UNMEASURED reason | --full}`, then what runs:

   | Depth | classify-diff found | qa | stress | Verdict (step 6) |
   |---|---|---|---|---|
   | cosmetic | every changed file doc/style, content clean | — | — | `--roster cosmetic --classify-exit 0` |
   | light | tests/docs only, or ≤ 2 non-test source files, no dependency change, no Stress trigger | ✓ | — | `--no-review --no-stress --qa Q` |
   | standard | > 2 non-test source files or a dependency manifest changed | ✓ | ✓ | `--no-review --stress S --qa Q` |
   | full | a Stress trigger, a doc file holding code, unmeasured, or `--full` | ✓ | ✓ | `--no-review --stress S --qa Q` |

   Gates and sensors run at every depth; depth only decides which agents are dispatched.
3. **Gates — run all, collect every result** into `$TMPDIR/validate-{slug}/gates.txt`. At this step, read `references/execution-and-report.md` (this skill's) for the order and the shared `references/quality-gate-reference.md` (plugin root) for the per-stack commands: format → type/vet/static analysis → lint → **build** (type-check alone misses bundler/compiler-only failures) → tests + coverage → race (Go) → vulnerability scan (network, last). `api-spec.yaml` present → its spec gates first. Go modernize is advisory and never counts toward Overall. Report mode: keep going past a failure so every result is reported.
4. **Sensors** into the same file: `bash ~/.claude/git-hooks/dup-gate.sh --worktree` · `scripts/verify/security-scan.sh --diff $BASE` · `scripts/verify/tautology-scan.py --diff $BASE` · with a plan, `scripts/verify/spec-coverage.sh <plan> <test paths>` and `scripts/verify/falsification.sh docs/plans/{slug}/evidence.md <plan>` (no evidence file → `falsification: no evidence file`, a FAIL).
5. **qa + stress, in parallel** (both read-only), as the depth table says — cosmetic skips this step, light dispatches `qa` alone. At this step, read `references/validation-loop.md` (this skill's) for the prompt contract and routing. Prompts carry paths only — `Base: {BASE} · Plan: {path | none} · Gate output: $TMPDIR/validate-{slug}/gates.txt` plus the contract line. `subagent_type: "qa"` and `subagent_type: "stress"`, both `model: "sonnet"`.
6. **Verdict.** `scripts/verify/verdict.sh` with the depth's mode from the table, plus `[--critical-security N] [--critical-other N] [--hard-gate-fail "a,b"]` — every FAIL from the gates, sensors, qa and stress goes into `--hard-gate-fail`. This is the verdict on the code itself (Stress 35% + QA 30% renormalised; QA alone at light; gates only at cosmetic); the review lens belongs to `/review-code`, a separate skill with its own pass/block, so this verdict never waits for or invents a review or stress score.
7. **Self-check inline.** At this step, read `agents/verdict.md` and apply its Security Gate, narrative and five-axis Verdict Self-Check (Evidence · Traceability · Independence · Residual risk · Actionability), with its downgrade rules.
8. **Report.** The depth line, then the gate table and overall line in the template of `references/execution-and-report.md` (`Overall: ✅ PASS — all gates green · {X}% coverage · {N} tests`, or the failing gates); then the summary of `references/output-format.md`: the qa and stress scores the depth produced with top findings, the verdict line, self-check scores, Security Gate, top 3 action items each with `file:line`, and the outcome row from `references/validation-loop.md`.

Next: `/code` with the findings to fix them, or `/review-code` for the standards and spec review.
