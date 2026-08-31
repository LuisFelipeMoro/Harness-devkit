---
name: handoff
description: 'Use when ending a long session or switching context. Compacts the conversation into a structured handoff document saved to /tmp. Trigger phrases: "handoff", "wrap up", "end session", "save context", "create handoff", "compact this session", "summarize for next session".'
---

Compact the conversation into a single, standalone handoff document. Save to `/tmp/handoff-<YYYY-MM-DD-HHMMSS>.md`. Print the path and a 3-line summary.

Also update the Harness memory file: write/refresh `PROGRESS.md` at the repo root (`Done` / `Failed` / `Current State` / `Next` / `Lessons` — schema in `references/progress-file.md`). The `/tmp` handoff is the rich narrative; `PROGRESS.md` is the durable, committed state the SessionStart bootstrap hook reads next session. The two must agree.

## Rules

- Point to existing artifacts (PRD, delivery file, ADR) rather than recreating them
- **If a delivery is in flight, record its identity first**: the `Delivery-Key`, the delivery file path, the release branch, the worktree path, and which story is next. Without the key the next session cannot resume the delivery — it will derive a fresh one and fork the work. Same for a bug fix: record the `hotfix/{slug}` branch.
- Redact API keys, passwords, and PII
- **Record the session's `Lessons`** — every rule the session learned the hard way, each with the
  failure or gate output that taught it. `/handoff` is the only writer of that section, and it is
  the one part of `PROGRESS.md` meant to outlive the delivery; a handoff that skips it discards
  the session's most durable output. Nothing learned this session is the only valid reason to omit it.
- The Suggested skills section is mandatory — it helps the next session start with the right tool
- If arguments provided, tailor the document toward that next-session objective

## Document format

Follow the structure in `references/handoff-template.md` (Task, Status, Key decisions, Files changed, Next steps, Suggested skills).
