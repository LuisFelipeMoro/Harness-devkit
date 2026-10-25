---
name: retro
description: 'Run a retrospective on a coding session and propose severity-ordered improvements to the agent environment — pointers, checks, reviewer rules, CLAUDE.md, tool economy, information access — applying only the ones you approve. Usage: /retro [session-id | "last" | path] [--metrics], e.g. "/retro last" or "/retro --metrics".'
disable-model-invocation: true
---

**Input**: a session — default the current one; `last`, a session id, or a `.jsonl` path names another; `--metrics` for the Harness health signals instead.
**Output**: a severity-ordered table of environment improvements, each with a concrete proposed edit; the approved ones applied. With `--metrics`: the five-signal table and what each reading suggests.
**Boundary**: improves the agent's *environment* (docs, pointers, checks, hooks, reviewer rules, tooling) — never the session's product code. Applies nothing without the user's OK. No dispatch.

**Rules**: every candidate cites evidence from the session (the turn, the tool call, the mistake) — no evidence, no candidate · a **mechanical** violation (a fixed pattern, a banned API, an import shape, a file location) gets a deterministic check — a linter rule, a git hook or a CI job — never a prose rule · a **judgement call** (cross-file consistency, "matches the surrounding style") goes to the reviewer, not to `CLAUDE.md` · standards are enforced at review: the implementing agent carries the most context pressure (exploring, writing, debugging), the reviewer the least (it receives a diff), so a rule the implementer keeps missing belongs on the reviewer's checklist.

## Steps

0. **`--metrics` only** — then stop; the session steps below do not run. Run `python3 coding-pipeline/scripts/harness-metrics.py` in the repo — resolved by the standards' Path resolution rule for cross-plugin paths, first existing wins: the `coding-pipeline` plugin root beside `${CLAUDE_PLUGIN_ROOT}` → flat `~/.claude/devkit/scripts/harness-metrics.py` → `plugins/coding-pipeline/scripts/harness-metrics.py` in a devkit checkout; found nowhere → print `harness-metrics: UNMEASURED — script not found` and stop, never estimate the table — `--base <ref>` / `--since <when>` if the user names them. Exit 2 → show its `UNMEASURED` line and stop. At this step, read `coding-pipeline/references/harness-metrics.md`; print the script's table, then per signal one line from that reference's "What to do with a reading" and its Healthy column — say which readings point at the Guides, the spec or the ceremony. Every `n/a — needs judgement` row stays n/a: name the source a human would read for it, never estimate a number. Close with the reference's warning that these are diagnostics, never targets or gates; propose no edit from a single reading.
1. **Read the session.** Current session: work from this context. Another one: find it under `~/.claude/projects/<cwd-with-slashes-as-dashes>/` (`ls -t … | head` for `last`), and extract with `jq` or a short script — the user's messages, tool names with counts, `Agent` dispatches with their prompts' size, failed commands, and edits that were later reverted — never read the whole `.jsonl` into context. Done when you can list the session's mistakes, retries and slow lookups, each with its turn.
2. **Read the environment.** The repo's `CLAUDE.md` / `AGENTS.md` (and the user's global one), its check commands (`package.json` / `Makefile` / build-tool `lint`·`check`·`test` scripts, `.pre-commit-config.yaml`, `.githooks/` or `git-hooks/`, `.github/workflows/`), and the devkit's own sensors (`coding-pipeline/hooks/hooks.json`). Done when you know which checks exist, which are wired into a hook or CI, and which run green today.
3. **Find candidates**, in these categories:

   | Category | Look for | Proposed edit |
   |---|---|---|
   | **Navigation pointers** | A piece of information that took many calls to find; a hidden dependency between files | One pointer line where the agent was looking — front-loaded with its trigger |
   | **Automated checks** | A mistake a deterministic check would have caught. Read the existing checks first: a check that exists but is unwired or silently broken *is* the finding, not a reinvention. A repo with no guardrail at all (no hook, no CI job running lint/typecheck/test) is itself a finding | A linter rule, a pre-commit / pre-push hook, or a CI job — whichever the repo's stack makes cheapest |
   | **Reviewer rules** | A judgement-call mistake the review let through; a rule that misfired or is unclear | A row in `coding-pipeline/agents/reviewer.md`, the review checklist, or `coding-pipeline/references/change-discipline.md`; or a rule removed or clarified |
   | **CLAUDE.md bloat and no-ops** | `CLAUDE.md` is always loaded — every line costs context on every turn of every session. Steering that belongs in a check or a reviewer rule; a sentence the model obeys by default (a no-op); a section consulted rarely that should be a pointer to a reference | Move it, point at it, or delete the whole sentence |
   | **Tool economy** | Expensive calls (whole files or logs read to find one line, repeated searches), dispatch count, token spend — read against the `context-budget` (60% warn / 80% ceiling) and `dispatch-budget` (session budget) hook warnings and `coding-pipeline/references/harness-metrics.md` | A cheaper command, a script or sensor that answers it, fewer or smaller dispatches |
   | **Information access** | A fact the agent needed and could not get — server logs, a third-party service, a schema | Tee the logs to a file, a read-only credential or MCP, a fixture |

   Done when every mistake, retry and slow lookup from step 1 is either a candidate or explained as a one-off.
4. **Present.** One table ordered by severity — `# · Severity · Category · Evidence (turn / call) · Proposed edit (file + the change)` — then each proposed edit as an exact diff or file sketch.
5. **Apply only what is approved.** One AskUserQuestion (`multiSelect: true`) over the candidates, ≤ 4 per call (more → several calls, severity first). Apply the chosen edits surgically; run the repo's checks on any check or hook you added and show it failing on the session's mistake and passing on clean code.

Next: `/review-code` on the environment changes, then `/pr`.

Credit: adapted from ideas in mattpocock/skills.
