---
name: rote
description: 'rote wraps installed adapters (MCP servers and CLI-based tools) and adds flow reuse, response caching, and crystallized workflows — used in place of calling an MCP server or CLI tool directly. Trigger examples: "list my open tickets", "what should I work on next", "fetch issues from the project", "show calendar events", "get data from the API", "what tasks are open", "run my flow", "search flows", "list adapters", "use existing integration", "what flows do I have", "automate [any workflow]".'
---

Claude and the rote CLI are a pair: Claude discovers + executes via the skill; the CLI crystallizes + replays. Every successful Claude operation becomes a reusable CLI flow. Every CLI-crystallized flow is available to Claude on next invocation.

Command syntax and templates live in `references/rote-reference.md`; this body is the router. Never `cat`, `ls`, or hand-edit files under `~/.rote/` — always use the `rote` commands listed under "State inspection" below.

## Phase 0 — State Snapshot (always runs at skill invocation)

Before any other step, establish what rote knows right now: run `rote adapter list` and `rote flow search ""`, then emit a compact ≤5-line inventory of adapters and flows (format in `references/rote-reference.md`). If rote is not installed (`command not found`), tell the user to install it and stop.

## Rule 1 — Search flows FIRST, always

Before calling any MCP server or CLI tool directly, run `rote flow search "<your intent>"`. Flow found → run it from `/tmp` (keeps you outside `~/.rote/workspaces/`) using the shell or `rote deno` run commands in `references/rote-reference.md`. No flow → proceed to Rule 2.

## Rule 2 — Check catalog before falling back out-of-band

If `rote flow search` and `rote explore "<intent>"` both come up empty, check the installable catalog before any WebFetch/curl/direct MCP, using the `rote adapter catalog search` / `catalog info` / `adapter new` / `<id>_probe` / `<id>_call` sequence in `references/rote-reference.md`. If catalog has nothing → tell the user explicitly and wait for confirmation before falling back out-of-band.

**Do not retry discovery after a hit.** A result from `catalog search` means advance to `catalog info` or `adapter new` — not another search.

## Rule 3 — Crystallize every successful operation

After any successful adapter call that was NOT already run from a flow, crystallize it with `rote flow crystallize` then `rote flow release` (full syntax and the `<adapter>-<verb>-<noun>` name format in `references/rote-reference.md`) so the CLI can replay it. This is what makes the CLI and skill a pair. Skip crystallization only when the operation is destructive, one-off, or parameterized in a way that makes reuse meaningless.

## Rule 4 — Keep MEMORY.md in sync

Write or update a `rote` memory entry (template in `references/rote-reference.md`) after:
- First successful rote use in a project
- Any adapter installed, removed, or updated
- Any new flow crystallized

## State inspection — use rote, not cat/ls

Use these `rote` commands (never `cat`/`ls` under `~/.rote/`):

| Goal | Command |
|------|---------|
| Adapter config + health | `rote adapter info <id>` |
| List installed adapters | `rote adapter list` |
| List tools in adapter | `rote <id>_probe` |
| List cached responses | `rote ls` |
| Inspect workspace | `rote workspace inspect` |
| Extract from cached response | `rote @<N> '<jq>' -r` |
| Update adapter field | `rote adapter set <id> <key> <value>` |

For the full 5-step task execution flow, model-tracked runs, and troubleshooting, see `references/rote-reference.md`.
