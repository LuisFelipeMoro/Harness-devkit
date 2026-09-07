# Prose Standards — editorial pass for agent-authored text

Agents write prose that never runs through a compiler: handoff documents, `PROGRESS.md` entries,
PR bodies, CHANGELOG lines. This file catalogues the tells that make that prose read as generated
rather than written, and what to write instead. It runs as an editorial pass at the point the text
is authored — wired into `skills/handoff` and `skills/release-management` — never as a gate. There
is no exit code for prose quality, and wiring a subjective check into a blocking gate is the
"unverifiable claim" the Harness ranks below no claim at all.

**Scope**: agent-authored prose only — handoff docs, `PROGRESS.md`, PR bodies, CHANGELOG entries.
Code comments are governed by the *why-not-what* rule in `CLAUDE.md`, which is stricter and
already enforced; this file does not touch them.

## Tells

| Tell | Instead |
|---|---|
| Magic adverbs — *quietly, deeply, fundamentally* | Cut it, or give the number |
| Pompous vocabulary — *delve, tapestry, landscape, leverage, harness* | *explore, look at, use* |
| The "serves as" dodge — *serves as a reminder, stands as a testament* | *is, shows* |
| Negative parallelism — *"It's not X — it's Y"* | State it directly |
| Dramatic countdown — *"Not a bug. Not a feature. A design flaw."* | One sentence |
| Self-answering rhetoric — *"The result? Devastating."* | Say what happened |
| Filler transitions — *"It's worth noting that…"* | Delete the preamble |
| Pedagogical signposting — *"Let's break this down"* | Present the facts |
| Fractal summaries — a conclusion at the end of every section | Let the content stand |

## Applying it

Read the drafted text once, checking only for these nine patterns — not for tone or style more
broadly. Rewrite the lines that match and leave the rest alone. A pass that changes nothing means
the text was already clean, not that the pass was skipped.

**Reviewer wiring**: one NIT-severity finding, for docs and PR prose only. It never fires on code
comments and never blocks a gate or a PR.
