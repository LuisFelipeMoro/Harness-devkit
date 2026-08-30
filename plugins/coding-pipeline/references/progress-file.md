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

## Lessons
- <rule learned> — evidence: <the failure or gate output that taught it> (<date>)
```

## Rules

- **Append, don't rewrite history.** Keep prior `Done` entries; add new ones.
- **One fact per bullet.** Each `Done`/`Failed` line is independently verifiable.
- **Convert relative dates to absolute** (`2026-06-26`, not "today").
- **Never log secrets, tokens, or PII** — same rule as application logs.
- **Tie to the Sensors.** A `Done` item should reference the test or gate that proves it — the test that was falsified (and the break that made it fail), the gate that passed.
- **Prefix every entry with the delivery key** — `` `[a8f3c1]` STORY-3 cart totals — … `` — so concurrent deliveries interleave readably in one root-level file, and a resumed session can filter to its own. Bug fixes use their hotfix slug instead: `` `[hotfix/null-cart]` ``. See `references/delivery-and-worktree.md`.
- **Atomic-commit discipline.** Each `Done` entry maps to one atomic commit where possible, so the progress log and git history agree.

## Lessons — what carries to the next session

`Done` and `Failed` describe this delivery. `Lessons` is the only section meant to outlive it:
a rule that would have prevented a failure, written so a future session can apply it without
re-deriving it. This is the cheapest form of cross-session memory the harness has — it costs
one line and is read back automatically by the SessionStart hook.

- **A lesson is a rule, not a diary entry.** "The Stripe client needs an explicit timeout —
  the default is infinite and the worker hung" is a lesson. "Debugged the payment worker" is not.
- **Every lesson carries its evidence** — the error, the failing gate, the review finding that
  produced it. A lesson with no evidence is an opinion, and opinions do not accumulate.
- **Project-scoped by default.** These are facts about *this* repo — its conventions, its
  infrastructure, its sharp edges. A lesson that would hold in any repo belongs in the global
  standards, not here; promote it deliberately rather than letting it drift in.
- **Delete a lesson that turns out to be wrong.** A stale rule is worse than no rule: it gets
  applied confidently. Correct it in place, or remove it.
- **Cap it.** Keep the most recent and most load-bearing; when the section passes ~15 entries,
  fold the settled ones into the repo's own conventions doc and drop them here.

## Who writes it

- `task` / `multi-agent`: append an entry at each sub-task/epic Verdict.
- `bug-fix`: append the root cause + fix + regression test on completion.
- `/handoff`: write the full `Current State` + `Next` snapshot at end of session, and record any
  `Lessons` the session produced.
- Any agent that hits a failure worth not repeating: add the `Lessons` line at the same time it
  reports the failure, while the evidence is still in hand.
