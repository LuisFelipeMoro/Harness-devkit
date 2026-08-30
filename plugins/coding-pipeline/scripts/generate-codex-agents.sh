#!/usr/bin/env bash
# Generate Codex CLI subagent definitions from this devkit's pipeline agent personas,
# so a Codex CLI session can delegate to them by name with the correct
# model_reasoning_effort per plugins/coding-pipeline/CLAUDE.md's Model assignment table
# (opus persona -> "high", sonnet -> "medium", haiku -> "low").
#
# Schema source: https://developers.openai.com/codex/subagents — subagent definition
# files live at ~/.codex/agents/<name>.toml (or <repo>/.codex/agents/<name>.toml for a
# project-scoped override); required fields name/description/developer_instructions,
# optional fields (model, model_reasoning_effort, sandbox_mode, mcp_servers,
# skills.config) fall back to config.toml if omitted. Verified against the docs as of
# 2026-08 — Codex's multi-agent feature GA'd 2026-03 and is still evolving, so if
# `codex` rejects a generated file, re-check the current docs for schema drift before
# filing a devkit bug.
#
# This does NOT touch the user's ~/.codex/config.toml (a shared, hand-edited file) —
# it writes per-persona files only and prints a companion [agents] snippet for the
# user to review and merge themselves. Additive only, like install-codex.sh.
#
# Coder is core (agents/coder.md) + exactly one tier overlay in every Claude pipeline
# dispatch — it is never spawned bare. This script mirrors that: coder.md's body is
# merged into coder-backend.toml and coder-frontend.toml; no standalone coder.toml
# is written.
#
# Usage:
#   bash plugins/coding-pipeline/scripts/generate-codex-agents.sh              # -> ~/.codex/agents
#   CODEX_HOME=/tmp/.codex-test bash .../generate-codex-agents.sh      # custom target (testing)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$(cd "$SCRIPT_DIR/../agents" && pwd)"
TARGET="${CODEX_HOME:-$HOME/.codex}/agents"

mkdir -p "$TARGET"

tier_to_effort() {
  case "$1" in
    opus) echo "high" ;;
    sonnet) echo "medium" ;;
    haiku) echo "low" ;;
    *) echo "medium" ;;  # personas with no model: field (rote-*) are sonnet-tier in practice
  esac
}

# Extract a frontmatter field's value (first match only). Frontmatter is everything
# between the first '---' line and the next '---' line.
frontmatter_field() {
  local file="$1" field="$2"
  awk -v f="$field" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm && $0 ~ "^"f":" { sub("^"f":[ \t]*", ""); print; exit }
  ' "$file"
}

# Everything after the second '---' line (the markdown body, frontmatter stripped).
body_of() {
  awk 'NR==1 && $0=="---" {c=1; next} c==1 && $0=="---" {c=2; next} c==2 {print}' "$1"
}

# Wrap content as a TOML literal multi-line string ('''...'''). Literal strings do no
# escaping, so backslashes/quotes/backticks in markdown pass through untouched — the
# one input that breaks this is a literal ''' sequence, which markdown bodies don't
# contain; guard for it anyway rather than emit silently-broken TOML.
toml_literal() {
  local content="$1"
  if printf '%s' "$content" | grep -qF "'''"; then
    return 1
  fi
  printf "'''\n%s\n'''" "$content"
}

# Basic double-quoted TOML string with minimal escaping, for single-line values.
toml_basic_string() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

write_agent() {
  local out_name="$1" persona_file="$2" extra_file="${3:-}"
  local name description model effort body literal

  name="$(frontmatter_field "$persona_file" name)"
  description="$(frontmatter_field "$persona_file" description)"
  model="$(frontmatter_field "$persona_file" model)"
  effort="$(tier_to_effort "${model:-sonnet}")"
  body="$(body_of "$persona_file")"
  if [ -n "$extra_file" ]; then
    body="$body

$(body_of "$extra_file")"
  fi

  if ! literal="$(toml_literal "$body")"; then
    echo "generate-codex-agents.sh: FAILED $out_name.toml — body contains a literal ''' sequence that would break the TOML string. Fix the source .md file or this script's escaping before retrying." >&2
    exit 1
  fi

  {
    echo "name = $(toml_basic_string "$out_name")"
    echo "description = $(toml_basic_string "$description")"
    echo "model_reasoning_effort = $(toml_basic_string "$effort")"
    echo "# model left unset — inherits agents.default_subagent_model from config.toml."
    echo "# Override here with a specific Codex model id if this persona should always"
    echo "# run on something stronger/cheaper than the session default."
    echo "developer_instructions = $literal"
  } > "$TARGET/$out_name.toml"
  echo "✓ $out_name.toml ($effort effort, from $(basename "$persona_file")$([ -n "$extra_file" ] && echo " + $(basename "$extra_file")"))"
}

echo "Generating Codex subagent definitions to $TARGET ..."

for persona in analyst architect bug-investigator devops pm qa reviewer \
               rote-adapter rote-analytics rote-datadog rote-github \
               scrum-master stress tuner verdict; do
  write_agent "$persona" "$AGENTS_DIR/$persona.md"
done

write_agent "coder-backend" "$AGENTS_DIR/coder.md" "$AGENTS_DIR/coder-backend.md"
write_agent "coder-frontend" "$AGENTS_DIR/coder.md" "$AGENTS_DIR/coder-frontend.md"

echo ""
echo "$(ls "$TARGET"/*.toml | wc -l | tr -d ' ') subagent definitions written to $TARGET/"
echo ""
echo "This does NOT edit your ~/.codex/config.toml. Recommended [agents] block —"
echo "review and merge it into your own config.toml (do not blindly overwrite it):"
echo ""
cat <<'SNIPPET'
[agents]
enabled = true
max_concurrent_threads_per_session = 4
default_subagent_model = "<your default Codex model>"
default_subagent_reasoning_effort = "medium"
SNIPPET
echo ""
echo "Per-persona reasoning effort is already baked into each <name>.toml above — the"
echo "global default only applies to subagents Codex spawns without a matching"
echo "generated file (e.g. ad-hoc proactive delegation)."
echo ""
echo "Orchestration note: this closes the model-tiering half of the multi-agent-"
echo "pipeline gap (see plugins/coding-pipeline/codex/harness-adapter.md) — each pipeline"
echo "persona now has a real Codex subagent definition at the right reasoning"
echo "effort. Sequencing (which persona runs when, reading handoff signals like"
echo "'CODER DONE') still happens the same way it does for a human reading the"
echo "pipeline SKILL.md: the Codex session driving the pipeline reads the skill's"
echo "phases and delegates to each named persona in turn. This has not been"
echo "exercised in a live Codex session by this script's author — validate before"
echo "relying on it in production."
