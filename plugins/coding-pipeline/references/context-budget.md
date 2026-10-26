# Context budget

One copy of the context rule that `/planning`, `/code` and `/bugfix` all follow. It lives here once so a change lands once.

**80% is a hard ceiling, not a warning.** Model reliability degrades before the window is full:
recall of mid-context detail drops and confident invention rises. A multi-step run is where that is most
expensive — a hallucinated interface signature or a mis-remembered AC propagates through every
stage after it.

`hooks/context-budget.sh` measures the real fill from the session transcript and injects the
instruction at 60% and 80%, so the ceiling no longer depends on the model estimating itself.

- **Between tasks**: drop implementation code, test files, and completed tasks. Retain
  the plan, `evidence.md`, and every score.
- **At 4+ tasks, or 60%**: compact completed work to one-line refs —
  `"{task}: {title} — DONE (Review: X/10, Stress: Y/10, QA: Z/10)"` — never dropping a score.
- **At 80%: checkpoint, then continue — no human in the loop.** Write the `[{slug}]` `PROGRESS.md`
  entries precisely enough to resume from cold, commit the current branch (push only if the user has asked for pushes), and carry
  on. The harness auto-compacts when the window fills; `hooks/precompact-snapshot.sh` records branch,
  dirty files, last commits and whether `PROGRESS.md` is stale, and `hooks/session-bootstrap.sh`
  re-injects that plus `PROGRESS.md` and re-arms the 60/80% latches. Past this line, re-read files
  rather than trusting memory of them — the next thing produced from memory is the least likely to
  be right. `/handoff` remains for ending a session on purpose.
- **Window size**: `DEVKIT_CONTEXT_WINDOW` when set; otherwise inferred (1M if the model id says so
  or usage has already passed 200k, else 200k).
- **Handoff state lives in `PROGRESS.md` and the handoff doc — never in the code.** No `TODO`, no
  `FIXME`, no commented-out stub, no placeholder marking where the session stopped. A source file
  must not record that an agent ran out of context; that is what the Memory leg is for, and a
  marker left behind is a finding (CD6) in the next review.
