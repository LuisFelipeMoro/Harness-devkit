#!/usr/bin/env bash
# Full global install — copies every plugin's agents/skills/hooks flat into
# ~/.claude/, wires the hook graph into settings.json, and installs git hooks.
#
# This is the file-copy stage. `install.sh` at the repo root is the machine
# bootstrap that also handles OS detection, dependencies, and repo sync, and it
# calls this script. Run this one directly when the machine is already set up and
# only the devkit files need refreshing.
#
# The devkit is a multi-plugin marketplace (coding-pipeline, engineering, devtools,
# pr-workflow). This script walks ALL of them: skills are directory-format
# (skills/<name>/SKILL.md with an optional references/ subfolder), agents live
# under each plugin's agents/, and the shared hooks / git-hooks / references /
# CLAUDE.md live under coding-pipeline.
#
# Platform support:
#   Linux / macOS  — run directly: bash plugins/coding-pipeline/scripts/install-global.sh
#
# ┌─ USE THIS SCRIPT when ────────────────────────────────────────────────────┐
# │  • Private/internal fork not published to public GitHub                   │
# │  • No internet at install time                                            │
# │  • You are the repo owner iterating on the devkit itself — edit locally,  │
# │    run this, changes land in ~/.claude/ immediately without a             │
# │    git push + `claude plugin update` cycle                                │
# │  • You want files flat in ~/.claude/ rather than namespaced under         │
# │    ~/.claude/plugins/cache/                                               │
# └───────────────────────────────────────────────────────────────────────────┘
#
# ┌─ SKIP THIS SCRIPT and use the plugin when ────────────────────────────────┐
# │  • Distributing to teammates from a public GitHub repo                    │
# │    → `claude plugin install github:LuisFelipeMoro/Harness-devkit`          │
# │  • You want `claude plugin update` for version management                 │
# └───────────────────────────────────────────────────────────────────────────┘
#
# Safe on existing ~/.claude/:
#   - Same-named agents/skills/references are updated to the new version
#   - Your custom files with different names are untouched
#   - ~/.claude/CLAUDE.md is NEVER overwritten — an @include line is injected
#     once; re-running is idempotent
#
# Only the files Claude actually reads are copied per skill (SKILL.md +
# references/*.md). SkillSpec tool artifacts (skill.spec.yml, deps.toml,
# source/, imports/, resources/, .skillspec/) are skipped by design.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$SCRIPT_DIR/.." && pwd)"                 # plugins/coding-pipeline (canonical hooks/CLAUDE.md)
PLUGINS="$(cd "$SCRIPT_DIR/../.." && pwd)"           # plugins/
GLOBAL="$HOME/.claude"

# Detect fresh vs existing install for clearer output
if [ -d "$GLOBAL/agents" ] || [ -f "$GLOBAL/CLAUDE.md" ]; then
    echo "Updating existing ~/.claude/ ..."
    MODE="update"
else
    echo "Creating fresh ~/.claude/ ..."
    MODE="fresh"
fi

mkdir -p "$GLOBAL/agents" "$GLOBAL/skills" "$GLOBAL/references" \
         "$GLOBAL/hooks"  "$GLOBAL/git-hooks" "$GLOBAL/devkit"

# ── Agents (every plugin that ships them) ────────────────────────────────────
agent_count=0
for agent_dir in "$PLUGINS"/*/agents; do
    [ -d "$agent_dir" ] || continue
    if ls "$agent_dir"/*.md >/dev/null 2>&1; then
        cp "$agent_dir"/*.md "$GLOBAL/agents/"
        agent_count=$((agent_count + $(ls "$agent_dir"/*.md | wc -l)))
    fi
done
echo "✓ agents — $agent_count installed (your custom agents left untouched)"

# ── Skills (directory-format, all plugins) ───────────────────────────────────
# Copy ONLY SKILL.md + references/*.md so the flat install stays clean and does
# not carry SkillSpec tool scaffolding that Claude never reads.
skill_count=0
for skill_dir in "$PLUGINS"/*/skills/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    dest="$GLOBAL/skills/$skill_name"
    mkdir -p "$dest"
    cp "$skill_dir/SKILL.md" "$dest/SKILL.md"
    if ls "$skill_dir"references/*.md >/dev/null 2>&1; then
        mkdir -p "$dest/references"
        cp "$skill_dir"references/*.md "$dest/references/"
    fi
    rm -f "$GLOBAL/skills/${skill_name}.md"   # drop any stale flat file
    skill_count=$((skill_count + 1))
done
echo "✓ skills — $skill_count installed (directory format, stale flat files removed)"

# ── Shared references (non-skill; currently coding-pipeline only) ─────────────────────
for ref_dir in "$PLUGINS"/*/references; do
    [ -d "$ref_dir" ] || continue
    ls "$ref_dir"/*.md >/dev/null 2>&1 && cp "$ref_dir"/*.md "$GLOBAL/references/"
    # Nested reference sets (e.g. references/languages/*.md) are one file per
    # language on purpose — the index is useless without them.
    for sub_dir in "$ref_dir"/*/; do
        [ -d "$sub_dir" ] || continue
        sub_name="$(basename "$sub_dir")"
        mkdir -p "$GLOBAL/references/$sub_name"
        ls "$sub_dir"*.md >/dev/null 2>&1 && cp "$sub_dir"*.md "$GLOBAL/references/$sub_name/"
    done
done
echo "✓ shared references"

# ── CLAUDE.md — never overwrite ─────────────────────────────────────────────
# Devkit standards land in ~/.claude/devkit/CLAUDE.md. An @include line is
# injected once into ~/.claude/CLAUDE.md so your personal rules are preserved.
INCLUDE_LINE="@~/.claude/devkit/CLAUDE.md"
cp "$PLUGIN/CLAUDE.md" "$GLOBAL/devkit/CLAUDE.md"

if [ ! -f "$GLOBAL/CLAUDE.md" ]; then
    printf '%s\n' "$INCLUDE_LINE" > "$GLOBAL/CLAUDE.md"
    echo "✓ CLAUDE.md created with @include → devkit/CLAUDE.md"
elif ! grep -qF "$INCLUDE_LINE" "$GLOBAL/CLAUDE.md"; then
    printf '\n%s\n' "$INCLUDE_LINE" >> "$GLOBAL/CLAUDE.md"
    echo "✓ CLAUDE.md — @include injected (your existing content preserved)"
else
    echo "✓ CLAUDE.md — @include already present, skipped"
fi

# ── Claude Code hooks (every plugin that ships *.sh) ─────────────────────────
for hook_dir in "$PLUGINS"/*/hooks; do
    [ -d "$hook_dir" ] || continue
    if ls "$hook_dir"/*.sh >/dev/null 2>&1; then
        cp "$hook_dir"/*.sh "$GLOBAL/hooks/"
    fi
done
chmod +x "$GLOBAL/hooks/"*.sh 2>/dev/null || true
hook_count=$(ls "$GLOBAL/hooks/"*.sh 2>/dev/null | grep -vc 'hook-lib\.sh$' || true)
echo "✓ Claude Code hooks — $hook_count scripts staged to ~/.claude/hooks/"

# ── Git hook templates (canonical set under coding-pipeline) ─────────────────────────
if ls "$PLUGIN/git-hooks/"* >/dev/null 2>&1; then
    cp "$PLUGIN/git-hooks/"* "$GLOBAL/git-hooks/"
    chmod +x "$GLOBAL/git-hooks/pre-commit" \
             "$GLOBAL/git-hooks/pre-push" \
             "$GLOBAL/git-hooks/commit-msg" \
             "$GLOBAL/git-hooks/install.sh" 2>/dev/null || true
    echo "✓ git-hook templates staged to ~/.claude/git-hooks/"
fi

# ── Wire git hooks into current repo ────────────────────────────────────────
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo ""
    echo "Wiring git hooks into current repo..."
    bash "$PLUGIN/git-hooks/install.sh"
else
    echo "Not in a git repo — git hooks not wired."
    echo "To install later in any repo: bash ~/.claude/git-hooks/install.sh"
fi

echo ""
if [ "$MODE" = "fresh" ]; then
    echo "✅ Fresh install complete — $skill_count skills, $agent_count agents."
else
    echo "✅ Update complete — $skill_count skills, $agent_count agents; existing customizations preserved."
fi
echo ""
# Staging the scripts is not enough — Claude Code only runs them if settings.json
# points at them, so wire it here instead of printing JSON to paste by hand. The
# graph is derived from hooks.json, so it cannot drift from what was just copied.
if python3 "$SCRIPT_DIR/wire-claude-settings.py" "$PLUGIN" --home "$HOME"; then
    :
else
    echo "! settings.json was not wired — the hooks are staged but inactive."
    echo "  Fix the reported problem, then re-run:"
    echo "  python3 $SCRIPT_DIR/wire-claude-settings.py $PLUGIN"
fi
echo ""
echo "Restart Claude Code so it re-reads ~/.claude/settings.json."
