# Reference: PROGRESS.md — Harness Memory & Progress

`PROGRESS.md` lives at the repo root. It is the devkit's cross-session memory: `/code`, `/bugfix`, `/handoff` and `/validate-code` append entries to it; the SessionStart bootstrap hook (`hooks/session-bootstrap.sh`) reads it so the next session starts with context instead of blind. It is **git-ignored, local session state** — read straight off disk, never committed, and never part of the release content the guard checks.

## Entry format

Each entry is one `## [{slug}]` heading with up to five bullets. Entries are appended, never rewritten: a later entry corrects an earlier one, it does not edit it.

```markdown
# PROGRESS

## [{slug}] YYYY-MM-DD — {title}
- Done: {atomic, verifiable accomplishment} ({commit sha or test/gate that proves it})
- Failed: {what was attempted and why it failed — exact error, not a paraphrase}
- Current State: {where the work stands right now: branch, what is green, what is in flight}
- Next: {the single next action a fresh session should take}
- Lessons: {rule learned} — evidence: {the failure or gate output that taught it} ({date})
```

Row state is not prose. `docs/plans/{slug}/tasks.json`, written only by `scripts/tasks_state.py`, is authoritative for which Tasks row is `todo`, `in_progress`, `done` or `failed`. PROGRESS.md carries the narrative. Where the two disagree on status, trust `tasks.json`.

The bootstrap hook prints the computed row status of unfinished plans. When it drops old entries to fit its budget, it keeps their `- Lessons:` lines (deduplicated, newest first, at most 15), so the durable output survives the cut.

## Rules

- **Append, never rewrite.** Keep prior entries; add new ones.
- **One fact per bullet.** Each `Done` / `Failed` line is independently verifiable.
- **Convert relative dates to absolute** (`2026-06-26`, not "today").
- **Never log secrets, tokens, or PII** — same rule as application logs.
- **Tie to the Sensors.** A `Done` item should reference the test or gate that proves it — the test that was falsified (and the break that made it fail), the gate that passed.
- **Prefix every entry with the plan slug** — `## [cart-totals] 2026-06-26 — T3 totals rounding` — so entries from concurrent pieces of work interleave readably in one root-level file, and a resumed session can filter to its own. `/bugfix` uses its fix slug instead: `## [fix/null-cart] …`.
- **Atomic-commit discipline.** Each `Done` entry maps to one atomic commit where possible, so the progress log and git history agree.

## Lessons — what carries to the next session

`Done` and `Failed` describe this piece of work. `Lessons` is the only bullet meant to outlive it:
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
- **Cap it.** Keep the most recent and most load-bearing; when the lessons pass ~15 entries,
  fold the settled ones into the repo's own conventions doc and drop them here.

## Who writes it

Each writer appends one entry; nothing is rewritten.

- `/code`: append one entry per completed Tasks row.
- `/bugfix`: append one entry with the root cause, fix and regression test on completion.
- `/handoff`: append one entry with the `Current State` and `Next` snapshot at end of session, and its `Lessons`.
- `/validate-code`: append one entry carrying the verdict.
- Any agent that hits a failure worth not repeating: add the `Lessons` line in the same entry it
  reports the failure in, while the evidence is still in hand.
