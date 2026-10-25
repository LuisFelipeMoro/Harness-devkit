# claude-devkit — Agent Instructions

This repo is the claude-devkit — a multi-plugin skill/agent library originally built for
Claude Code. If you are Codex CLI, or another harness reading this file, working in this
repo: the canonical engineering standards live in a single place to avoid drift —

**Read `plugins/coding-pipeline/CLAUDE.md` before making any change.** It covers coding discipline,
quality gates, security defaults, and per-language rules that apply regardless of which
harness you are.

Two conventions there are easy to get wrong and worth calling out up front:

- **Tests are written after the implementation, against a spec frozen before it** — then
  *falsified* (break the code path, confirm the test fails on its own assertion, restore).
  Not TDD. A tautological or unfalsified test blocks handoff regardless of coverage. The one
  exception is a bug fix, which keeps its RED reproduction test.
- **Branching**: work on the current branch; on `main`/`master` cut `feat/{slug}` first, never
  commit to `main`, and never push or open a PR unless asked. See
  `plugins/coding-pipeline/references/branching.md`.
- **Skills are manual**: every skill is started by the user and does one job; none runs another.

## Harness-specific notes

- **Skills** (`plugins/*/skills/*/SKILL.md`) use only `name:`/`description:` (plus `disable-model-invocation: true`, which Codex ignores) frontmatter —
  this is the same shape Codex's own Skills convention expects, so they are directly usable
  once placed under a `.agents/skills/` directory Codex scans (repo, user, or system level).
  See `plugins/coding-pipeline/scripts/install-codex.sh` to install them for Codex.
- **Agents** (`plugins/coding-pipeline/agents/*.md`) are Claude Code Task-tool subagent definitions
  (`tools:`/`model:` frontmatter, dispatched by name from skills). Codex has its
  own declarative subagent format (`~/.codex/agents/<name>.toml`) — run
  `plugins/coding-pipeline/scripts/generate-codex-agents.sh` to generate one per agent, with
  reasoning effort mapped from the Claude `model:` tier. See
  `plugins/coding-pipeline/codex/harness-adapter.md` for the current mapping and known gaps
  (pipeline *sequencing* is not yet validated in a live Codex session).
- **Git hooks** (`plugins/coding-pipeline/git-hooks/`) are plain POSIX shell and work under any
  harness or none at all — install via `bash plugins/coding-pipeline/scripts/install-git-hooks.sh`.
