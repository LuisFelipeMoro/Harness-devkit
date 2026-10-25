---
name: handoff
description: Compact the session into a standalone handoff document and refresh PROGRESS.md so the next session resumes exactly where this one stopped. Usage: /handoff [next-session objective], e.g. "/handoff finish T3 of the checkout-retry plan".
disable-model-invocation: true
---

**Input**: this conversation; optionally the next session's objective.
**Output**: `/tmp/handoff-<YYYY-MM-DD-HHMMSS>.md` and a refreshed `PROGRESS.md` at the repo root; the path plus a 3-line summary printed.
**Boundary**: writes those two files only — no code, no commit. `PROGRESS.md` is **git-ignored**, local session memory the SessionStart hook reads next session; it is never committed.

## Steps

1. **Collect state.** `git branch --show-current`, `git status --short`, `git log --oneline -5`, the active plan (`docs/plans/{slug}/plan.md` — its `Status` and which Tasks rows are done), and the last gate results seen this session.
2. **Write the handoff** — at this step, read `references/handoff-template.md` and follow its structure. Point to existing artifacts (plan, codebase map, ADRs) instead of restating them; record the branch and plan slug first — without them the next session cannot resume the work. With an objective argument, tailor Next steps and Suggested skills to it.
3. **Refresh `PROGRESS.md`** — at this step, read `references/progress-file.md`: append `Done` / `Failed`, rewrite `Current State` and `Next`, add `Lessons`. The handoff and `PROGRESS.md` must agree.
4. **Lessons are mandatory** — every rule this session learned the hard way, each with the failure or gate output that taught it. Omit the section only when nothing was learned, and say so.
5. **Redact** API keys, tokens, passwords and PII from both files.
6. **Editorial pass** (not a gate): run both texts past `coding-pipeline/references/prose-standards.md`.
7. Print the handoff path and a 3-line summary: where it stands, the next action, the blocker if any.

Next: in the new session, the skill named first under Suggested skills.
