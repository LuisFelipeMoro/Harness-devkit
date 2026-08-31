# PROGRESS.md schema

> **Canonical elsewhere.** The full schema is defined in
> `coding-pipeline/references/progress-file.md` and **only** there. This file mirrors it so the
> `devtools` plugin stands alone (no `coding-pipeline` dependency) — on conflict, `coding-pipeline`'s
> copy wins; change it there first, then propagate here.

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

## Lessons
- [Rule learned] — evidence: [the failure or gate output that taught it] ([date])
```

Rules:
- Append at each checkpoint; never silently rewrite history.
- Keep entries factual and terse — one line each.
- Redact secrets, tokens, and PII.
- **Prefix every entry with the delivery key** — `` `[a8f3c1]` STORY-3 cart totals — … `` — so concurrent deliveries interleave readably in one root-level file and a resumed session can filter to its own. Bug fixes use their hotfix slug: `` `[hotfix/null-cart]` ``.
- **Tie each `Done` item to the sensor that proves it** — the test that was falsified (and the break that made it fail), the gate that passed.

## Lessons — the section that outlives the delivery

`Done` / `Failed` / `Current State` / `Next` describe *this* delivery and go stale with it.
`Lessons` is the only section meant to survive it: a rule that would have prevented a failure,
written so a future session can apply it without re-deriving it. It is the cheapest cross-session
memory the harness has — one line, read back automatically by the SessionStart hook — which is
exactly why a handoff that omits it silently throws the session's most durable output away.

- **A lesson is a rule, not a diary entry.** "The Stripe client needs an explicit timeout — the
  default is infinite and the worker hung" is a lesson. "Debugged the payment worker" is not.
- **Every lesson carries its evidence** — the error, the failing gate, the review finding that
  produced it. A lesson with no evidence is an opinion, and opinions do not accumulate.
- **Project-scoped by default.** A lesson that would hold in any repo belongs in the global
  standards; promote it deliberately rather than letting it drift in here.
- **Delete a lesson that turns out to be wrong.** A stale rule is worse than no rule — it gets
  applied confidently.
- **Cap it.** Past ~15 entries, fold the settled ones into the repo's conventions doc and drop them.
