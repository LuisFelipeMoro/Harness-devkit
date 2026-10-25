# Bug-fix sub-agent dispatch templates

## Investigate — `bug-investigator` dispatch

```text
Agent(
  description: "bug-investigator — root cause",
  subagent_type: "bug-investigator",
  model: "sonnet",
  prompt: """
Symptom vs expected: [the user's answer, verbatim]
Reproduction: [the user's answer, verbatim]
Fix depth: [Minimal patch | Root-cause fix | Not sure — investigate first]
Base: [git merge-base HEAD main — fall back to master]
Working directory: [cwd]

Run Phase 0 → Phase 3 (load references on demand only): build and run the feedback loop,
reproduce and minimise, rank 3–5 falsifiable hypotheses. Redact every secret you quote.

Return ONLY the CHECKPOINT block (or NO LOOP with what you tried and what you need).
"""
)
```

## Continue — same investigator, after the checkpoint

Continue the agent with SendMessage (its context is intact; this is not a new dispatch). Where
continuation is unavailable, dispatch `bug-investigator` afresh with the template above plus the
whole CHECKPOINT block pasted under `Checkpoint: done` — it counts toward the dispatch budget.

```text
Checkpoint: done
User input: [re-rank / ruled-out hypotheses, verbatim — or "none, proceed in your ranking"]

Run Phase 4 → Phase 5: instrument one variable at a time in rank order, confirm the root cause,
write the failing test at a correct seam (or report Seam: none). Run it and confirm RED (show
failure output). Remove every [DEBUG-xxxx] line and show the grep empty.

Return ONLY:
1. BUG REPORT — root cause in ≤3 sentences, plus each hypothesis's verdict
2. Failing test: file path + full failure output (quoted) — or the loop's RED output on Seam: none
3. HANDOFF — everything the coder needs to fix it, ≤200 words
```

## Fix — `coder` dispatch

```text
Agent(
  description: "coder — bug fix",
  subagent_type: "coder-backend" | "coder-frontend" | "coder",   # the bug's tier; the overlay loads agents/coder.md
  model: "haiku",
  prompt: """
Language: [affected language — load only references/languages/<language>.md]
RED test: [test file] :: [test name]   — or, on Seam: none, RED loop: [loop command]
Root cause: [one sentence from the BUG REPORT]
Depth: [the depth the user confirmed]
Fix files: [the HANDOFF's Fix scope]
Constraints: [the HANDOFF's Constraints]

Minimum change to fix the root cause. Run the investigator's failing test (or loop) after your fix to confirm GREEN.
You may ADD regression tests for edge cases the fix exposes; never weaken, delete, or rewrite an existing test to make it pass.

Return ONLY: BUGFIX COMPLETE — [file:line — what changed, one sentence] + the RED → GREEN output.
"""
)
```

## Verify: full gate set per detected stack

Run every gate for the detected stack from `references/quality-gate-reference.md` (format, type/vet, lint, build, tests + coverage, race for Go, vuln scan) — not the test command alone. A bug fix that passes its new regression test but fails lint/typecheck/build is still a gate FAIL and routes back to the coder.

Gate report:

```text
| Gate       | Status | Details                   |
|------------|--------|---------------------------|
| new test   | ✅     | [name] RED → GREEN        |
| full suite | ✅     | N tests, 0 failed         |
| lint       | ✅     | —                         |
| types/vet  | ✅     | —                         |
| build      | ✅     | —                         |
| dup-gate   | ✅     | introduced N% (≤ 3%)      |
| original loop | ✅  | un-minimised command green |
| re-break   | ✅     | fix reverted → [name] FAIL |
```

## Summary template

```text
Bug Fix Summary
Root cause: [one sentence]
Fix:        [file:line — what changed]
Test:       [test name — file | none: no correct seam — <why>, loop: <command>]
Confirmed:  [the hypothesis that held — put this sentence in the commit / PR text]
Falsified:  [#n — by what probe], one per line
Suite:      [N passed, 0 failed]
Depth:      [Minimal patch | Root-cause fix]
Gates:      [all green | failing list]
Review:     [run /review-code — not part of /bugfix]
```

## Cleanup checklist — every box before the summary

- [ ] The original (un-minimised) feedback loop no longer reproduces
- [ ] Regression test GREEN — or the absence of a correct seam is documented in the summary
- [ ] No debug instrumentation left: `grep -rn "\[DEBUG-" .` returns nothing
- [ ] Throwaway prototypes and harnesses deleted (only a loop script the summary names survives, under `$TMPDIR`)
- [ ] The confirmed hypothesis is stated in the summary's `Confirmed` line, ready for the commit / PR text
- [ ] Every command and output shown has its secrets as `<REDACTED>`
