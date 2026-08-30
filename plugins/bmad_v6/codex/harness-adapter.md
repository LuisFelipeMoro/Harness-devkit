# Harness Adapter — Claude Code ↔ Codex CLI (and others)

This devkit's skills and agents were built for Claude Code. This doc maps the
Claude-specific primitives skills/agents reference onto Codex CLI's equivalents, so
someone reading a skill under Codex knows what to do when it says "spawn a subagent" or
"use TaskCreate." It documents current state — it does not change any skill or agent file.

## What already works identically

- **SKILL.md format**: `name:`/`description:` frontmatter + markdown body, optional
  `references/*.md` — this is exactly Codex's own Skills convention. Every skill in this
  devkit is directly usable once placed under `.agents/skills/<name>/` (see
  `scripts/install-codex.sh`).
- **Single-agent skills** — no subagent dispatch, just a playbook the calling agent
  follows directly: `security-review`, `quality-gate`, `code-review-gate`,
  `database-migration`, `observability`, `performance-profiling`, `release-management`,
  `business-analysis`, `grill-me`, `handoff`, `improve-codebase-architecture`,
  `technical-analysis`, `write-a-skill`, `rote`, `pr-review`, `checkcomments`. These work
  under Codex exactly as they do under Claude Code.
- **Git hooks** (`git-hooks/pre-commit`, `pre-push`, `commit-msg`) — plain POSIX shell,
  harness-agnostic.

## Vocabulary mapping (Claude Code → Codex CLI)

| Claude Code primitive | Codex CLI equivalent | Notes |
|---|---|---|
| `Agent` tool, `subagent_type: bmad_v6:<name>` | Codex custom subagent (`~/.codex/agents/<name>.toml` or `<repo>/.codex/agents/<name>.toml`) | Codex has a real per-file declarative subagent schema (`name`/`description`/`developer_instructions`/`model`/`model_reasoning_effort`, GA'd 2026-03) — see `scripts/generate-codex-agents.sh`, which generates one `<name>.toml` per BMAD persona from `agents/*.md`, with `developer_instructions` set to that persona's full body. No longer an approximation. |
| Agent frontmatter `tools: Bash, Read, Grep, Glob` | No direct equivalent | Codex subagent files don't currently support per-agent tool allowlists the same way. Treat as informational (the persona's intended scope), not an enforced restriction. |
| Agent frontmatter `model: haiku/sonnet/opus` | Per-agent `model_reasoning_effort` in the generated `.toml` (`opus`→`high`, `sonnet`→`medium`, `haiku`→`low`); `model` itself is left commented out to inherit the session's `agents.default_subagent_model` | Map by role, not by literal model name: architecture design → highest reasoning effort; planning/review/validation → mid-tier; read-only/exploration and code-writing → lowest. `generate-codex-agents.sh` does this mapping automatically from each agent's frontmatter — no manual translation needed. |
| `TaskCreate` / `TaskUpdate` (task tracking) | No built-in equivalent | Use a plain markdown checklist in the working file/PR description instead. |
| `SendMessage` (resume a paused subagent) | Not applicable | Codex subagent threads don't expose this cross-thread resume primitive; keep orchestration within a single thread instead. |

## Codex subagent generation (`scripts/generate-codex-agents.sh`)

```bash
bash plugins/bmad_v6/scripts/generate-codex-agents.sh              # -> ~/.codex/agents/*.toml
CODEX_HOME=/tmp/.codex-test bash .../generate-codex-agents.sh      # custom target, for testing
```

Writes one `<name>.toml` per BMAD persona (17 files — `coder.md` is core-only and never
dispatched bare, so its body is merged into both `coder-backend.toml` and
`coder-frontend.toml`, matching how the Claude pipelines pair it with exactly one tier
overlay). Each file's `model_reasoning_effort` is derived from that persona's `model:`
frontmatter via the mapping above. Additive only — does not touch `~/.codex/config.toml`;
prints a recommended `[agents]` block (`enabled`, `max_concurrent_threads_per_session`,
`default_subagent_model`, `default_subagent_reasoning_effort`) for you to review and merge
into your own config by hand, since that's a shared file this script shouldn't overwrite.

Schema verified against `developers.openai.com/codex/subagents` (2026-08). Codex's
multi-agent feature GA'd 2026-03 and is still evolving — if `codex` rejects a generated
`.toml`, re-check the current docs for schema drift before filing a devkit bug.

## Known gaps — pipeline orchestration not yet validated in a live Codex session

Every BMAD persona now has a real Codex subagent definition at the correct reasoning
effort (above), which closes the model-tiering half of running the multi-agent pipelines
under Codex. What's still unverified is **sequencing**: the pipeline skills'
phase-by-phase orchestration (`multi-agent-coding-pipeline`, `task-coding-pipeline`,
`bug-fix`'s Investigator → Coder handoff, `rote-adapter`'s dispatch) is plain prose written
for a human or a Claude orchestrator to follow — under Codex, the session driving the
pipeline is expected to read the same `SKILL.md` phases and delegate to each named persona
in turn (natural-language delegation request, or `/agent` to manage the resulting thread),
watching for the same handoff signals (`CODER DONE`, `QA→CODER BUG REPORT`, etc.) in each
subagent's output exactly as a Claude orchestrator would. This has **not been exercised
end-to-end in a live Codex session** — treat it as ready to try, not yet validated. If you
run a full pipeline under Codex, record what broke (or didn't) here.

- `multi-agent-coding-pipeline` (9-agent BMAD pipeline: Analyst → PM → Architect →
  ScrumMaster → Coder → QA → Reviewer → Stress → Verdict)
- `task-coding-pipeline`
- `bug-fix` (Bug Investigator → Coder handoff)
- `analysis`, `planning`, `architecture` (single-agent dispatch, likely portable, but
  untested)
- `rote-adapter` (dispatches `rote-adapter` agent)

**Delivery isolation is harness-neutral and should port cleanly.** The delivery model
(`references/delivery-and-worktree.md`) — keyed delivery file under `docs/deliveries/`, one
`git worktree` per delivery on a `release/{slug}-{key}` branch, sequential stories inside it,
never committing or merging to `main` — is plain `git` and plain paths, with no Claude-specific
mechanism behind it. A Codex session following the same `SKILL.md` phases gets the same
isolation. The unvalidated part is the same as above: whether the orchestrating session
actually *performs* the Phase 0 setup and the terminal PR step in order, not whether the
commands work.
