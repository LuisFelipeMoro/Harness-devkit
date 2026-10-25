---
name: grill-me
description: 'Stress-test a plan or design in rounds: every question whose prerequisites are settled, numbered, each with a recommended answer. Usage: /grill-me [args], e.g. "/grill-me docs/plans/cart/plan.md".'
disable-model-invocation: true
---

**Input**: a plan path, a design, or an idea in the conversation.
**Output**: a shared understanding confirmed by the user — the settled decisions in one block — or, on an early stop, the 3 unresolved risks.
**Boundary**: asks and records; changes no code. Facts are looked up, never asked; decisions are the user's.

At the start, read `coding-pipeline/references/grilling.md` — it holds the design tree, the frontier rule, the round format and the done criterion.

## Steps

1. **Build the tree.** Read the plan or idea; list its decisions as a design tree, marking each settled (the plan or the user already decided it) or open. Done when every decision the plan makes or leaves open is on the tree.
2. **Look up the facts.** For each open node that hinges on a fact, find it — codebase map, grep / read, or one read-only Explore subagent (`haiku`) for a wide question — and settle what the fact settles. Do not wait on a pending lookup: only its downstream questions wait.
3. **Ask the frontier.** One round: every open decision whose prerequisites are settled, numbered, in the round format, each with a recommended answer worded so "yes" accepts it. Wait for the answers.
4. **Recompute and repeat.** Write the answers into the tree, re-open anything an answer invalidates, recompute the frontier, ask the next round. Done when the frontier is empty.
5. **Confirm.** Restate the settled decisions in one block and ask the user to confirm the understanding is shared; with a plan path, offer to write the decisions into it.

## Ending

When the user says "done", "enough", "ship it", or "next": list the 3 unresolved risks in order of severity, one line each.

Next: `/planning` to turn the settled decisions into a plan, or `/code` when the plan is already approved.
