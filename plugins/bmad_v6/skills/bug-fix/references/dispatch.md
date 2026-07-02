# Bug-fix sub-agent dispatch templates

## Phase 1 — Sam (Bug Investigator) dispatch

```text
Agent(
  description: "Sam — bug investigation",
  subagent_type: "claude",
  model: "sonnet",
  prompt: """
Read agents/bug-investigator.md — that is your persona and instructions.

Bug: [paste user's bug description]
Working directory: [cwd]

Run your full Phase 0 → Phase 1 → Phase 2.
Write the failing test to disk. Run it and confirm RED (show failure output).

Return ONLY:
1. BUG REPORT — root cause in ≤3 sentences
2. Failing test: file path + full failure output (quoted)
3. SAM HANDOFF — everything Amelia needs to fix it, ≤200 words
"""
)
```

## Phase 2 — Amelia (Coder) dispatch

```text
Agent(
  description: "Amelia — bug fix",
  subagent_type: "claude",
  model: "opus",
  prompt: """
Read agents/coder.md (core) PLUS the tier overlay for the bug's stack —
agents/coder-backend.md if the fix is server/API/domain, agents/coder-frontend.md if it is UI/SSR/client.
Load only the language-rules-reference.md section for the affected language.

SAM HANDOFF:
[paste full SAM HANDOFF]

Minimum change to fix the root cause. Run Sam's failing test after your fix to confirm GREEN.
You may ADD regression tests for edge cases the fix exposes; never weaken, delete, or rewrite an existing test to make it pass.

Return ONLY: CODER DONE — BUGFIX COMPLETE — [file:line — what changed, one sentence]
"""
)
```

## Phase 3 — Verify: full gate set per detected stack

Run every gate for the detected stack from `references/quality-gate-reference.md` (format, type/vet, lint, build, tests + coverage, race for Go, vuln scan) — not the test command alone. A bug fix that passes its new regression test but fails lint/typecheck/build is still a gate FAIL and routes back to Amelia.

Gate report:

```text
| Gate       | Status | Details                   |
|------------|--------|---------------------------|
| new test   | ✅     | [name] RED → GREEN        |
| full suite | ✅     | N tests, 0 failed         |
| lint       | ✅     | —                         |
| types/vet  | ✅     | —                         |
| build      | ✅     | —                         |
```

## Phase 5 — Summary template

```text
Bug Fix Summary
Root cause: [one sentence]
Fix:        [file:line — what changed]
Test:       [test name — file]
Suite:      [N passed, 0 failed]
Review:     [X/10 — key finding if any]
```
