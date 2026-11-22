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
- **Window size** — the hook takes the first of these that is set (first match wins):
  1. `DEVKIT_CONTEXT_WINDOW` — the devkit's own override, always wins.
  2. `CLAUDE_CODE_AUTO_COMPACT_WINDOW` — integer, `k`/`M` suffix accepted (`300k`, `1M`).
  3. `autoCompactWindow` in the first of `<repo>/.claude/settings.local.json`,
     `<repo>/.claude/settings.json`, `~/.claude/settings.json` that holds a valid value.
  4. Inferred: 1M if the model id says so or usage has already passed 200k, else 200k.

  A value below `100000` (Claude Code's floor) or not a positive integer is ignored and the lookup
  falls through. A malformed settings file is skipped.

- **Plugin installs write no settings.** The flat install (`install-global.sh`) sets
  `"autoCompactWindow": 300000` in `~/.claude/settings.json` when the key is absent, so the harness
  compacts at 300k and the 60% and 80% lines land at 180k and 240k, before compaction. Plugin users
  choose their own window. Either run `/autocompact 300k` (or any value), or set `autoCompactWindow`
  in a settings file, or export `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. Claude Code's own setting is
  documented at code.claude.com/docs/en/model-config#set-the-auto-compact-window.

- **Models with a 200k window**: `autoCompactWindow` above the model's real window does not
  change what Claude Code can hold, and the hook cannot read that cap. On such a model the hook
  measures against 300k and its lines land late. Set `DEVKIT_CONTEXT_WINDOW=200000` in the
  environment to make the hook measure against the real window.
- **Handoff state lives in `PROGRESS.md` and the handoff doc — never in the code.** No `TODO`, no
  `FIXME`, no commented-out stub, no placeholder marking where the session stopped. A source file
  must not record that an agent ran out of context; that is what the Memory leg is for, and a
  marker left behind is a finding (CD6) in the next review.
