# Reference: PROGRESS.md — Harness Memory & Progress

`PROGRESS.md` lives at the repo root. It is the devkit's cross-session memory: pipelines and `/handoff` append to it; the SessionStart bootstrap hook (`hooks/session-bootstrap.sh`) reads it so the next session starts with context instead of blind.

## Schema

```markdown
# PROGRESS

_Last updated: <YYYY-MM-DD HH:MM> — <branch>_

## Done
- <atomic, verifiable accomplishment> (<commit sha or test/gate that proves it>)

## Failed
- <what was attempted and why it failed — exact error, not a paraphrase>

## Current State
- <where the work stands right now: branch, what is green, what is in flight>

## Next
- <the single next action a fresh session should take>
- <ordered follow-ups>
```

## Rules

- **Append, don't rewrite history.** Keep prior `Done` entries; add new ones.
- **One fact per bullet.** Each `Done`/`Failed` line is independently verifiable.
- **Convert relative dates to absolute** (`2026-06-26`, not "today").
- **Never log secrets, tokens, or PII** — same rule as application logs.
- **Tie to the Sensors.** A `Done` item should reference the test or gate that proves it — the test that was falsified (and the break that made it fail), the gate that passed.
- **Prefix every entry with the delivery key** — `` `[a8f3c1]` STORY-3 cart totals — … `` — so concurrent deliveries interleave readably in one root-level file, and a resumed session can filter to its own. Bug fixes use their hotfix slug instead: `` `[hotfix/null-cart]` ``. See `references/delivery-and-worktree.md`.
- **Atomic-commit discipline.** Each `Done` entry maps to one atomic commit where possible, so the progress log and git history agree.

## Who writes it

- `task-coding-pipeline` / `multi-agent-coding-pipeline`: append an entry at each sub-task/epic Verdict.
- `bug-fix`: append the root cause + fix + regression test on completion.
- `/handoff`: write the full `Current State` + `Next` snapshot at end of session.
