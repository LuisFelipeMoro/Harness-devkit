# Grilling — rounds over a design tree

Shared by `/grill-me` and the optional grill step of `/planning` (Phase 2). The goal is a shared
understanding with nothing left silently assumed, reached in as few rounds as the decisions allow.

## The design tree and its frontier

Map the plan or idea as a **design tree**: every decision branches into the decisions that hang off
it. The **frontier** is every open decision whose prerequisites are already settled — the questions
that can be asked *now* without guessing at an answer not yet heard.

- **Ask the whole frontier in one round**, numbered. A question whose answer depends on another
  question still open in this round belongs to a later round, not this one.
- **Recompute the frontier after every round.** Settled decisions push it outward and unblock what
  hung off them; a changed answer can re-open a settled branch — re-ask what it invalidates.
- **Facts are looked up, never asked.** A frontier question that needs a fact about the environment
  (what the code does, which version is pinned, whether a symbol exists) is answered by you: the
  codebase map when there is one, then grep / read, then — for a wide question — one read-only
  Explore subagent (`model: "haiku"`, prompt forbids mutation, returns ≤ 150 words). Do not block
  on it: only the questions downstream of a pending lookup wait; ask the rest of the frontier now.
  The **decisions** are the user's: put each to them.

## Round format

```text
❓ **Q1 — <question title>**: <the assumption being challenged, and the consequence if it is wrong>
- A. <option> — trade-off: <cost; risk; what it gives up>
- B. <option> — trade-off: <cost; risk; what it gives up> · Recommended
- C. <option> — trade-off: <cost; risk; what it gives up>

---

❓ **Q2 — <confirmation of an already-decided action>**: <the action>. Approve / change?
```

- **Decision questions offer options, never a bare recommendation** — see § Decision questions.
  The user answers a round by letter, e.g. `1 B, 2 A, 3: C`.
- One recommendation per question, concrete — never "it depends".
- No softening ("just wondering"), no praise before critique, no question the user already
  answered or the plan already decides.

## Decision questions

Every question that asks the user to choose a design or solution offers **at least 3 concrete
options**, labelled A/B/C…. Each option states its **trade-off**: the cost, the risk, and what it
gives up. Exactly one option is marked `Recommended`. The user answers by letter.

Exempt: a question that confirms one already-decided action — approve the plan, commit or push,
proceed, run the grill — is a confirmation, not a decision, and needs no options.

## Done

The grill is done when **the frontier is empty** — every branch of the tree visited — **and the
user confirms the understanding is shared**. Restate the settled decisions in one block and ask
for that confirmation; act on none of it before it is given.

The user can stop it early with "done", "enough", "ship it" or "next": then list the 3 unresolved
risks in order of severity, one line each.

Credit: the frontier-round format is adapted from ideas in mattpocock/skills.
