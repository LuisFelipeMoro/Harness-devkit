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
3. **The original request, verbatim** — the user's ask, or the Test Case table the change was built against. Without it the Reviewer cannot judge change discipline (CD1, CD3, CD7) and must say so instead of guessing; the diff cannot be its own specification.

The Reviewer runs the full Security Deep-Dive checklist, language-specific checks, and the **test-falsifiability check**: every behaviour shipped in the diff has a test that asserts an observable outcome (not a tautology, not mock-call-only), each test has been falsified — the code path broken, the assertion observed to fail, the break reverted — corner/error cases are covered, and no existing test was weakened to pass. Because tests here are written after the code, read them adversarially: a test whose expected value is re-derived with the implementation's own logic, or whose name describes the code rather than the requirement, proves nothing. Absent, unfalsified, or tautological tests for shipped behaviour = MAJOR finding, regardless of coverage percentage.

It also runs the **change-discipline check** (CD1–CD7, defined in `coding-pipeline/references/change-discipline.md`): every changed line must trace to a sentence of the request. Outside a pipeline there is no Scrum Master filtering scope, so this is where an inline session's drive-by refactors, single-use abstractions, and silently-resolved ambiguities get caught. Unrequested surface (CD3), pre-existing dead code deleted unasked (CD5), and an ambiguity resolved in code without being raised (CD7) are MAJOR.

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
