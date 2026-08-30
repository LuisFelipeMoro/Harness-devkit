# Diff Collection, Reviewer Payload, Verdict, Anti-patterns

## Collect changed files (Phase 2)

```bash
rtk git diff --name-only HEAD    # unstaged + staged
# or for staged only:
rtk git diff --name-only --cached
```

## Reviewer payload

Dispatch the Reviewer subagent — `coding-pipeline:reviewer` (or `reviewer` in a flat `~/.claude/agents` install). The subagent already carries its Reviewer persona; do not read the agent file into the main context. Pass:

1. Full content of each changed file (not a diff — the Reviewer needs complete context for context-sensitive checks).
2. One-line gate summary: `"Gates: all green — {X}% coverage, {N} tests"`

The Reviewer runs the full Security Deep-Dive checklist, language-specific checks, and the **test-falsifiability check**: every behaviour shipped in the diff has a test that asserts an observable outcome (not a tautology, not mock-call-only), each test has been falsified — the code path broken, the assertion observed to fail, the break reverted — corner/error cases are covered, and no existing test was weakened to pass. Because tests here are written after the code, read them adversarially: a test whose expected value is re-derived with the implementation's own logic, or whose name describes the code rather than the requirement, proves nothing. Absent, unfalsified, or tautological tests for shipped behaviour = MAJOR finding, regardless of coverage percentage.

## Phase 3 — Verdict table

| Score | Security | Action |
|-------|----------|--------|
| ≥ 8.0 | No CRITICAL | ✅ `CODE REVIEW GATE PASSED — Score: X/10 · Coverage: Y% · N tests` |
| ≥ 8.0 | CRITICAL finding | ❌ BLOCK — fix security issue first, then re-run from Phase 1 |
| < 8.0 | No CRITICAL | Show findings; ask: *"Fix and re-run, or push with known issues?"* |
| < 8.0 | CRITICAL | ❌ BLOCK — fix required; do not push |

On re-run after fixes: restart from Phase 1 (gates must re-pass after any code change).

## Anti-patterns

- Don't run this inside a pipeline — pipelines embed their own gates + reviewer loop.
- Don't skip Phase 2 after Phase 1 passes — gates catch format/coverage/lint, not logic or security bugs.
- Don't pass a git diff to the Reviewer — pass complete file content so context-sensitive checks work.
