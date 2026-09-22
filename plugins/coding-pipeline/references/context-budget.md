# Context budget

One copy of the rule that `multi-agent` and `task` both enforce. It lived verbatim in both loops,
which is a duplication finding in the devkit's own terms and meant a change had to land twice.

**80% is a hard ceiling, not a warning.** Model reliability degrades before the window is full:
recall of mid-context detail drops and confident invention rises. A pipeline is where that is most
expensive — a hallucinated interface signature or a mis-remembered AC propagates through every
stage after it.

`hooks/context-budget.sh` measures the real fill from the session transcript and injects the
instruction at 60% and 80%, so the ceiling no longer depends on the model estimating itself.

- **Between stories/epics**: drop implementation code, test files, and completed stories. Retain
  the delivery file, the Manifest, and every score.
- **At 4+ units, or 60%**: compact completed work to one-line refs —
  `"{unit}: {title} — DONE (Review: X/10, Stress: Y/10, QA: Z/10)"` — never dropping a score.
- **At 80%: stop and hand off.** Run `/handoff`, write the `[{key}]` `PROGRESS.md` entries, push
  the current story branch, and start a fresh session that resumes from the delivery file's Status
  plus those entries. Do not "push a bit further" — the next thing produced past this line is the
  thing least likely to be right, and hardest to spot as wrong.
- **Handoff state lives in `PROGRESS.md` and the handoff doc — never in the code.** No `TODO`, no
  `FIXME`, no commented-out stub, no placeholder marking where the session stopped. A source file
  must not record that an agent ran out of context; that is what the Memory leg is for, and a
  marker left behind is a finding (CD6) in the next review.
