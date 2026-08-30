---
name: code-review-gate
description: Gate and review any code generated outside a full pipeline (inline spec-first sessions, direct edits, ad-hoc fixes) by clearing all quality gates and then routing to the Reviewer agent. Gates must pass before the Reviewer runs. Trigger phrases — "gate and review", "pre-push check", "ready to push", "sign off my code", "check before PR", "review my changes", "done coding".
---

Every code change outside a pipeline must clear this gate before it counts as done. Gates must be green before the Reviewer runs, and a CRITICAL security finding always blocks.

## Contract
- Input: a working directory with changed files.
- Output: a gate report (PASS/FAIL per gate), then a Reviewer score (1–10) with structured findings, then a verdict line.
- Tool boundary: this skill reports and routes; it never auto-fixes failing gates or findings. The Reviewer sees only the changed files, never the full codebase.
- Done when: Phase 3 prints a PASS verdict line, or a BLOCK with the specific finding to fix.

## Steps
1. **Phase 1 — Quality Gates.** Invoke the `/quality-gate` skill. If any gate fails, show the failing gate and its error output, stop, surface the fix, and wait for a re-run. Phase 2 begins after every gate is green.
2. **Phase 2 — Reviewer.** Collect the changed files with the commands in `references/diff-verdict-and-rules.md`, then dispatch the Reviewer subagent — `coding-pipeline:reviewer` (or `reviewer` in a flat `~/.claude/agents` install) — handing it the full content of each changed file, the one-line gate summary, and the original request verbatim (the Reviewer needs it to judge change discipline). The dispatched subagent already carries its Reviewer persona; do not read the agent file into the main context. It covers the Security Deep-Dive checklist, language-specific checks, the test-falsifiability check, and the change-discipline check (CD1–CD7) defined in that reference.
3. **Phase 3 — Verdict.** Apply the verdict table in `references/diff-verdict-and-rules.md`: score ≥ 8.0 with no CRITICAL passes; any CRITICAL blocks; below 8.0 surfaces findings for a decision. After any fix, restart from Phase 1.

## References
- `references/diff-verdict-and-rules.md` — diff collection commands, Reviewer payload, falsifiability check, verdict table, and anti-patterns.
- `coding-pipeline/references/change-discipline.md` — CD1–CD7 rows, severities, and worked ❌/✅ examples (single source of truth).
