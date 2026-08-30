# claude-devkit — Agent Instructions

This repo is the claude-devkit — a multi-plugin skill/agent library originally built for
Claude Code. If you are Codex CLI, or another harness reading this file, working in this
repo: the canonical engineering standards live in a single place to avoid drift —

**Read `plugins/bmad_v6/CLAUDE.md` before making any change.** It covers coding discipline,
quality gates, security defaults, and per-language rules that apply regardless of which
harness you are.

Two conventions there are easy to get wrong and worth calling out up front:

- **Tests are written after the implementation, against a spec frozen before it** — then
  *falsified* (break the code path, confirm the test fails on its own assertion, restore).
  Not TDD. A tautological or unfalsified test blocks handoff regardless of coverage. The one
  exception is a bug fix, which keeps its RED reproduction test.
- **Pipeline runs are *deliveries***: a keyed plan file under `docs/deliveries/`, one
  `git worktree` per delivery on a `release/{slug}-{key}` branch, and **never a commit or
  merge to `main`** — the terminal step is a PR. See
  `plugins/bmad_v6/references/delivery-and-worktree.md`.

## Harness-specific notes

- **Skills** (`plugins/*/skills/*/SKILL.md`) use only `name:`/`description:` frontmatter —
  this is the same shape Codex's own Skills convention expects, so they are directly usable
  once placed under a `.agents/skills/` directory Codex scans (repo, user, or system level).
  See `plugins/bmad_v6/scripts/install-codex.sh` to install them for Codex.
- **Agents** (`plugins/bmad_v6/agents/*.md`) are Claude Code Task-tool subagent definitions
  (`tools:`/`model:` frontmatter, dispatched by name from pipeline skills). Codex has its
  own declarative subagent format (`~/.codex/agents/<name>.toml`) — run
  `plugins/bmad_v6/scripts/generate-codex-agents.sh` to generate one per persona, with
  reasoning effort mapped from the Claude `model:` tier. See
  `plugins/bmad_v6/codex/harness-adapter.md` for the current mapping and known gaps
  (pipeline *sequencing* is not yet validated in a live Codex session).
- **Git hooks** (`plugins/bmad_v6/git-hooks/`) are plain POSIX shell and work under any
  harness or none at all — install via `bash plugins/bmad_v6/scripts/install-git-hooks.sh`.
