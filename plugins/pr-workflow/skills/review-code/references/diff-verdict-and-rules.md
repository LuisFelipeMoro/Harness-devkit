# Diff Collection, Reviewer Payload, Verdict, Anti-patterns

## Collect changed files (`/review-code` step 1)

```bash
rtk git diff --name-only $(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master)   # everything on the branch + uncommitted
rtk git diff --name-only HEAD    # unstaged + staged only
# or for staged only:
rtk git diff --name-only --cached
```

## Reviewer payload

Dispatch the Reviewer subagent — `coding-pipeline:reviewer` (or `reviewer` in a flat `~/.claude/agents` install). The subagent already carries its Reviewer role; do not read the agent file into the main context. Pass paths, never pasted contents:

1. The diff range plus the changed-file paths — the Reviewer opens each changed file in full (not just the hunks), because context-sensitive checks need complete context. Paths, never pasted content.
2. One-line gate summary: `"Gates: all green — {X}% coverage, {N} tests"`
3. **The original request, verbatim** — the user's ask, or the Test Case table the change was built against. Without it the Reviewer cannot judge change discipline (CD1, CD3, CD7) and must say so instead of guessing; the diff cannot be its own specification.

The Reviewer runs the full Security Deep-Dive checklist, language-specific checks, and the **test-falsifiability check**: every behaviour shipped in the diff has a test that asserts an observable outcome (not a tautology, not mock-call-only), each test has been falsified — the code path broken, the assertion observed to fail, the break reverted — corner/error cases are covered, and no existing test was weakened to pass. Because tests here are written after the code, read them adversarially: a test whose expected value is re-derived with the implementation's own logic, or whose name describes the code rather than the requirement, proves nothing. Absent, unfalsified, or tautological tests for shipped behaviour = MAJOR finding, regardless of coverage percentage.

It also runs the **change-discipline check** (CD1–CD8, defined in `coding-pipeline/references/change-discipline.md`): every changed line must trace to a sentence of the request. Without an approved plan there is nothing filtering scope up front, so this is where an inline session's drive-by refactors, single-use abstractions, and silently-resolved ambiguities get caught. Unrequested surface (CD3), pre-existing dead code deleted unasked (CD5), an ambiguity resolved in code without being raised (CD7), and a new file an existing file could hold (CD8) are MAJOR.

## Verdict table (`/review-code` step 5)

| Score | Security | Action |
|-------|----------|--------|
| ≥ 8.0 | No CRITICAL | ✅ `CODE REVIEW GATE PASSED — Score: X/10 · Coverage: Y% · N tests` |
| ≥ 8.0 | CRITICAL finding | ❌ BLOCK — Score Loop removes the finding, then `/validate-code` and `/review-code` again; no pass until it is gone |
| < 8.0 | No CRITICAL | Score Loop on the checked-out branch: a fix round by `coder`, then a narrow re-check; on exhaustion the human chooses *Fix the gaps yourself* · *Accept with known issues* · *Stop* (`coding-pipeline/references/quality-gate-reference.md` § Score Loop) |
| < 8.0 | CRITICAL | ❌ BLOCK — Score Loop; fix required, do not push |

Both loop rows apply only to the checked-out branch (step 5 of `SKILL.md`); any other target keeps show-findings-and-ask.

On re-run after fixes: run `/validate-code` first (gates must re-pass after any code change), then `/review-code`.

## Language proof check (`/review-code` step 5)

Runs once, on the first pass, and only the Standards return is checked (with `--split`, the `Axis: standards` dispatch; the `Axis: spec` dispatch emits no Language lines). Score Loop confirmation rounds emit no Language lines and are not checked.

For each name in the dispatch's `Languages:` field, the return must contain `Language {name}: references/languages/{name}.md · {K} findings`.

- **Missing line** → print `Language review missing: {name}` and re-dispatch once, narrowly: `Axis: standards · Languages: {missing} · Scope: language rules only`. That retry is at most one extra `reviewer` dispatch per review, inside the AC8 dispatch slack.
- **Still missing after the retry** → the printed review says `Language {name}: UNMEASURED`, never a clean line for that language.
- **`Languages: none`** → no Language lines are expected. **`Languages: unknown`** → nothing to check the names against; the reviewer names the languages it inferred in its Language lines, and the printed review says they were inferred.
- Language findings sit on the Standards axis and count in the Score Loop like any other finding.

## Anti-patterns

- Don't duplicate `/validate-code`: it owns the gates, qa and stress; `/review-code` owns the review.
- Don't skip the review after `/validate-code` passes — gates catch format/coverage/lint, not logic or security bugs.
- Don't let the Reviewer judge from hunks alone — it opens the complete changed files so context-sensitive checks work.
