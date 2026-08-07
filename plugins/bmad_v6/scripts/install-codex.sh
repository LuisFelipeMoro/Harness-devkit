#!/usr/bin/env bash
# Install claude-devkit skills for Codex CLI (and any harness that reads the
# same convention). Additive only — never touches any file Claude Code reads
# (plugins/*/skills, plugins/*/agents, plugins/*/.claude-plugin/, hooks.json).
#
# Codex scans `.agents/skills/<name>/SKILL.md` at repo, user (~/.agents/skills),
# and system level. Every SKILL.md in this devkit already uses only
# `name:`/`description:` frontmatter — the same shape Codex expects — so
# skills need zero transformation, only placement.
#
# Agents (plugins/bmad_v6/agents/*.md) are Claude Code Task-tool subagent
# definitions with no direct Codex equivalent (Codex subagent orchestration is
# session/config driven, not per-file declarative). They are copied to a
# reference-only directory so their persona/procedure content is readable,
# NOT wired into Codex's own [agents] config. See
# plugins/bmad_v6/codex/harness-adapter.md for the current mapping and known
# gaps (multi-agent pipeline skills are not yet validated under Codex). This
# codex/ directory is a dedicated namespace that install-global.sh's glob
# patterns (*/agents, */skills/*/, */references, */hooks) never match — Codex
# artifacts never land in ~/.claude/, by directory-structure construction.
#
# Platform support:
#   Linux / macOS  — bash plugins/bmad_v6/scripts/install-codex.sh
#
# Usage:
#   bash plugins/bmad_v6/scripts/install-codex.sh              # installs to ~/.agents
#   AGENTS_HOME=/tmp/.agents-test bash .../install-codex.sh     # custom target (testing)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BMAD="$(cd "$SCRIPT_DIR/.." && pwd)"                 # plugins/bmad_v6
PLUGINS="$(cd "$SCRIPT_DIR/../.." && pwd)"           # plugins/
TARGET="${AGENTS_HOME:-$HOME/.agents}"

if [ -d "$TARGET/skills" ]; then
    echo "Updating existing $TARGET ..."
    MODE="update"
else
    echo "Creating fresh $TARGET ..."
    MODE="fresh"
fi

mkdir -p "$TARGET/skills" "$TARGET/agents-reference"

# ── Skills (directory-format, all plugins) ───────────────────────────────────
# Copy ONLY SKILL.md + references/*.md, same exclusion policy as
# install-global.sh, so SkillSpec tool scaffolding never lands here.
skill_count=0
for skill_dir in "$PLUGINS"/*/skills/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    dest="$TARGET/skills/$skill_name"
    mkdir -p "$dest"
    cp "$skill_dir/SKILL.md" "$dest/SKILL.md"
    if ls "$skill_dir"references/*.md >/dev/null 2>&1; then
        mkdir -p "$dest/references"
        cp "$skill_dir"references/*.md "$dest/references/"
    fi
    skill_count=$((skill_count + 1))
done
echo "✓ skills — $skill_count installed to $TARGET/skills/"

# ── Agents (reference-only — not wired into any Codex config) ───────────────
agent_count=0
for agent_dir in "$PLUGINS"/*/agents; do
    [ -d "$agent_dir" ] || continue
    if ls "$agent_dir"/*.md >/dev/null 2>&1; then
        cp "$agent_dir"/*.md "$TARGET/agents-reference/"
        agent_count=$((agent_count + $(ls "$agent_dir"/*.md | wc -l)))
    fi
done
echo "✓ agents — $agent_count persona docs copied to $TARGET/agents-reference/ (reference only, not auto-wired)"

# ── Codex-only docs (harness-adapter.md, isolated namespace) ────────────────
if [ -f "$BMAD/codex/harness-adapter.md" ]; then
    cp "$BMAD/codex/harness-adapter.md" "$TARGET/harness-adapter.md"
    echo "✓ harness-adapter.md copied to $TARGET/"
fi

echo ""
if [ "$MODE" = "fresh" ]; then
    echo "✅ Fresh install complete — $skill_count skills, $agent_count agent references."
else
    echo "✅ Update complete — $skill_count skills, $agent_count agent references."
fi
echo ""
echo "Notes:"
echo "  - Pipeline skills (multi-agent-coding-pipeline, task-coding-pipeline, bug-fix,"
echo "    analysis, planning, architecture, rote-adapter) dispatch agents by name;"
echo "    run scripts/generate-codex-agents.sh to generate a real Codex subagent"
echo "    (~/.codex/agents/<name>.toml) per persona at the right reasoning effort —"
echo "    see plugins/bmad_v6/codex/harness-adapter.md for what's still unvalidated"
echo "    (pipeline sequencing in a live Codex session)."
echo "  - All other skills have no subagent dependency and should work as-is."
echo "  - To also scope skills to one project instead of (or in addition to) user-level,"
echo "    copy $TARGET/skills/<name>/ into <project>/.agents/skills/<name>/ — Codex scans"
echo "    both repo and user level."
