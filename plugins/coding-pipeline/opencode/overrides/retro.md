---
name: retro
description: 'Run a retrospective on a coding session and propose severity-ordered improvements to the agent environment — pointers, checks, reviewer rules, AGENTS.md, tool economy, information access — applying only the ones you approve. Usage: /retro [session-id | "last" | path] [--metrics], e.g. "/retro last" or "/retro --metrics".'
disable-model-invocation: true
---

**Input**: a session — default the current one; `last`, a session id, or a session id from the OpenCode server names another; `--metrics` for the Harness health signals instead.
**Output**: a severity-ordered table of environment improvements, each with a concrete proposed edit; the approved ones applied. With `--metrics`: the five-signal table and what each reading suggests.
**Boundary**: improves the agent's *environment* (docs, pointers, checks, hooks, reviewer rules, tooling) — never the session's product code. Applies nothing without the user's OK. No dispatch.

**Rules**: every candidate cites evidence from the session (the turn, the tool call, the mistake) — no evidence, no candidate · a **mechanical** violation (a fixed pattern, a banned API, an import shape, a file location) gets a deterministic check — a linter rule, a git hook or a CI job — never a prose rule · a **judgement call** (cross-file consistency, "matches the surrounding style") gets a reviewer rule or a pointer.

## Steps

0. **`--metrics` only** — then stop; the session steps below do not run. Run `python3 <devkit>/scripts/harness-metrics.py` from the install target (the `devkit/` directory `install-opencode.sh` wrote). If that file is absent, run `python3 plugins/coding-pipeline/scripts/harness-metrics.py` in the repo. Neither found → say which paths were tried and stop.
1. **Read the session.** Current session: work from this context. Another one: read it through the OpenCode server's session API with `opencode api` (run `opencode api --help` first and confirm the session operation names for the installed version — do not guess them). List sessions to resolve `last` or to check a session id, then fetch that session's messages and tool calls. Extract the user's messages, tool names with counts, subagent dispatches with their prompt sizes, failed commands, and edits that were later reverted. Never dump the whole session into context — pull only the fields above.
2. **Read the environment.** The repo's `AGENTS.md` (or `CLAUDE.md`) and the user's global instructions, its check commands (`package.json` / `Makefile` / build-tool `lint`·`check`·`test` scripts, `.pre-commit-config.yaml`, `.githooks/` or `git-hooks/`, `.github/workflows/`), and the devkit's own sensors that are installed under OpenCode (the `devkit/git-hooks/` and `devkit/scripts/verify/` files). Done when you know which checks exist, which are wired into a hook or CI job, and which are not.
3. **Find candidates**, in these categories:

   | Category | Look for | Proposed edit |
   |---|---|---|
   | **Navigation pointers** | A piece of information that took many calls to find; a hidden dependency between files | One pointer line where the agent was looking — front-loaded with its trigger |
   | **Automated checks** | A mistake a deterministic check would have caught. Read the existing checks first: a check that exists but is unwired or silently broken *is* the finding, not a reinvention. A repo with no guardrail at all (no hook, no CI job running lint/typecheck/test) is itself a finding | A linter rule, a pre-commit / pre-push hook, or a CI job — whichever the repo's stack makes natural |
   | **Reviewer rules** | A judgement-call mistake the review let through; a rule that misfired or is unclear | A row in the reviewer agent definition (`<devkit>/agents/reviewer.md`), the review checklist, or `<devkit>/references/change-discipline.md`; or a rule removed or clarified |
   | **AGENTS.md bloat and no-ops** | `AGENTS.md` is always loaded — every line costs context on every turn of every session. Steering that belongs in a check or a reviewer rule; a sentence the model obeys by default (a no-op); a section consulted rarely that should be a pointer to a reference | Move it, point at it, or delete the whole sentence |
   | **Tool economy** | Expensive calls (whole files or logs read to find one line, repeated searches), dispatch count, token spend — read against the `context-budget` (60% warn / 80% ceiling) and `dispatch-budget` (session budget) signals, and `<devkit>/references/harness-metrics.md` | A cheaper command, a script or sensor that answers it, fewer or smaller dispatches |
   | **Information access** | A fact the agent needed and could not get — server logs, a third-party service, a schema | Tee the logs to a file, a read-only credential or MCP, a fixture |

   Note: the Claude Code session hooks (`hooks.json`) are not installed under OpenCode. A candidate that depends on one of them is a finding about the OpenCode install, not a missing check in the repo.

   Done when every mistake, retry and slow lookup from step 1 is either a candidate or explained as a one-off.
4. **Present.** One table ordered by severity — `# · Severity · Category · Evidence (turn / call) · Proposed edit (file + the change)` — then each proposed edit as an exact diff or file sketch.
5. **Apply only what is approved.** Ask the user with the `question` tool (`multiSelect: true`) over the candidates, ≤ 4 per call (more → several calls, severity first). Apply the chosen edits surgically; run the repo's checks on any check or hook you added and show it failing on the session's mistake and passing on clean code.

Next: `/review-code` on the environment changes, then `/pr`.

Credit: adapted from ideas in mattpocock/skills.
