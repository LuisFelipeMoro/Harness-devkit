# Writing a skill an agent follows the same way every run

What makes a skill predictable is not that it produces the same output each run but that the agent
takes the same *process* each run. These are the levers, fitted to the devkit's manual-skill format
(`disable-model-invocation: true`, a one-sentence human-facing description, steps that say
"At this step, read …", and agents with a "References — load on demand" table).

## Context pointers — wording decides when material is reached

A **context pointer** is a line in context that names material out of context and the condition for
reaching it: "At this step, read `references/<topic>.md`", a row of a load-on-demand table, a line in
`CLAUDE.md` naming a doc. The pointer's *wording*, not its target, decides whether the agent reaches
the material, and when. A must-have reference behind a vague pointer is a variance bug — sharpen the
pointer first, and inline the material only if sharpening fails.

- **Front-load the leading word.** The trigger goes first: "**Choosing a mock pattern** → `test-audit-reference.md`", not "For more detail on several topics including mocks, see …".
- **One trigger per branch.** Synonyms that rename one case are one branch written twice; collapse them. Keep only genuinely distinct branches, one row each.
- **Cut identity the body already carries.** The pointer says when, not what the file is about at length.
- **Name the step, not "as needed".** "At step 4, read …" fires at step 4; "see … when relevant" fires at random.

A manual skill's description is not a trigger — nothing auto-routes it — so it carries no trigger list:
one sentence saying what the skill does, plus `Usage:`.

## The two loads

- **Context load** — what always-loaded material costs the agent's window every turn, fired or not: `CLAUDE.md` lines, a model-invoked description, an agent's full body when dispatched.
- **Cognitive load** — what the human must remember: which skills exist and when to type each. A manual skill moves its cost here; the devkit's Skills table in `CLAUDE.md` and each skill's `Next:` line are how that load is paid down.

Material behind a pointer escapes context load for the price of the pointer's line. That is the whole
economy of the load-on-demand tables.

## Information hierarchy — where each piece sits

Two content types: **steps** (what the agent does, in order) and **reference** (rules, tables, facts
consulted on demand). Each piece sits on one rung, ranked by how immediately the agent needs it:

1. **In-file step** — the numbered Steps of `SKILL.md`.
2. **In-file reference** — a short Rules block or table in `SKILL.md` every run consults (a flat peer-set of rules is fine here).
3. **Disclosed reference** — a file under `references/`, reached only through a pointer at the step that needs it.

Push too little down and the steps drown; push too much and the agent misses what it needed.

- **Progressive disclosure by branch** — the clean test: inline what *every* branch needs; disclose behind a pointer what only *some* branches reach (`--split` mode, the no-PR case, a language-specific table). Reference left inline that only one branch uses buries the steps, and attending to them becomes a coin-flip.
- **Co-location** — once a piece has a rung, keep its definition, rules and caveats under one heading, so reading one part brings its neighbours. A rule scattered across three sections is read as three partial rules.
- **Sprawl** — a file simply too long, even when every line is live, thins attention across all of it. The cure is the ladder: disclose by branch, split by sequence. (This is why `SKILL.md` targets ≤ 60 lines.)

## Completion criteria — every step ends on one

Each step ends on the condition that tells the agent it is done — "**Done when** every remaining element is load-bearing", "an unticked item is not done".

- **Clarity** — can the agent tell done from not-done? A vague bound ("once you understand it") invites *premature completion*: the visible later steps pull attention toward being done. Sharpen the bound first; only if it is irreducibly fuzzy *and* you observe the rush, move the later steps behind a real context boundary (a subagent dispatch or a separate skill) — an inline pointer does not hide them.
- **Demand** — how much the criterion requires. "Every changed exported symbol's callers opened" forces legwork "review the callers" does not. Demand binds flat reference too: "every rule applied" makes a checklist exhaustive.

The strongest criteria are checkable and exhaustive: a command that exits 0, a grep that returns nothing, a count that matches.

## Leading words and negation

- A **leading word** is a compact concept the model already knows (*tight* loop, *red*, *frontier*, *tracer bullet*). Repeated as a token, it anchors a region of behaviour in the fewest tokens. Prefer an existing word to a coined one, which recruits no priors.
- **State the target, not the ban.** A prohibition drags the forbidden behaviour into context. Write "write one-line comments", not "don't write long comments". A guardrail that cannot be phrased positively keeps its "never", paired with the positive target.

## Pruning

- **Single source of truth** — one meaning, one place; other files point at it. In the devkit that place is usually a file under `coding-pipeline/references/`.
- **The environment is a source of truth** — do not restate a `package.json` script, a config value or `--help` output; cache only what looking cannot find (the unwritten convention, the reason behind a choice).
- **No-ops** — a sentence the model already obeys by default changes nothing; delete the whole sentence. A word too weak to beat the default (*be thorough*) is a no-op too; the fix is a stronger word (*relentless*) or a checkable criterion.

Credit: adapted from ideas in mattpocock/skills.
