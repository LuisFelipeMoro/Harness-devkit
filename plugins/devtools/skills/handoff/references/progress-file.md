# PROGRESS.md schema

`PROGRESS.md` lives at the repo root and is the durable, committed state the
SessionStart bootstrap hook reads at the start of the next session. It must stay
in agreement with the rich `/tmp` handoff narrative.

```markdown
# PROGRESS

## Done
- [Completed work, newest last]

## Failed
- [What was attempted and did not work, with the reason]

## Current State
- [Where the codebase / task stands right now]

## Next
- [Ordered next actions for the following session]
```

Rules:
- Append at each checkpoint; never silently rewrite history.
- Keep entries factual and terse — one line each.
- Redact secrets, tokens, and PII.
- **Prefix every entry with the delivery key** — `` `[a8f3c1]` STORY-3 cart totals — … `` — so concurrent deliveries interleave readably in one root-level file and a resumed session can filter to its own. Bug fixes use their hotfix slug: `` `[hotfix/null-cart]` ``.
- **Tie each `Done` item to the sensor that proves it** — the test that was falsified (and the break that made it fail), the gate that passed.
