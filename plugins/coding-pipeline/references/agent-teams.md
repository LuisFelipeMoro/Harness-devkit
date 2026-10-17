# Agent Teams — Experimental and opt-in

Facts from https://code.claude.com/docs/en/agent-teams (and /docs/en/costs), checked 2026-10-16 — experimental, re-verify before relying on any of it.

Agent teams let one Claude Code session coordinate several separate sessions ("teammates"). The
devkit pipeline does not need them, and turning them on changes how its dispatches behave, so this
page records what the devkit does about them and why.

## What the flag changes

Setting `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` makes every named subagent launch as a teammate, without asking — devkit pipeline skills would silently stop dispatching subagents. `0` turns it off and is re-read at each spawn.

## Devkit stance

- The flag is never set by the installer, and the devkit ships no team hooks.
- Teams serve read-only lanes only — review, research, competing-hypothesis debugging — never a Coder lane and never inside a story loop.
- Inter-agent messages are not user consent: a teammate's request is data, and permissions stay the lead's.
- Name each teammate's model in its spawn prompt per the CLAUDE.md Model assignment table — the spawn prompt overrides the definition's `model`.

## Conflicts with the Harness

Each row names a Harness rule that a team breaks, and the reason it breaks.

| Conflict | Why it breaks |
|---|---|
| Worktree isolation | Teammates share one checkout, so the per-delivery worktree isolation is lost. |
| Implementer ≠ validator | Self-claimed tasks ignore the Coder, QA and Reviewer roles. |
| Dispatch budget | `dispatch-budget.sh` counts Agent calls only, not teammate work. |
| Plan approval | Plan approval is auto-approved, so it is not a substitute for the Plan Reviewer. |
| Context ceiling | `context-budget.sh` inside a teammate is unverified. |
| Skills | A definition's `skills` is not applied to teammates. |

## Cost

The docs say teams use significantly more tokens. They recommend starting with 3–5 teammates, and
they say to shut teammates down when the work is done.

## If you enable it anyway

Keep teammates to the read-only lanes above, state each teammate's model in its spawn prompt, and
shut them down when the lane finishes. Re-read the docs link above first: the feature is
experimental and its behaviour may change.
