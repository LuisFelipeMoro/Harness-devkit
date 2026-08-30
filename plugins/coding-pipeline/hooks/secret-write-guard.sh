#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit) — block writing a live credential into a file.
#
# env-guard.sh stops the agent *reading* secrets. This is the other direction:
# a key pasted into context by the user, or invented by the model, must not be
# committed to the tree. Only provider-specific high-entropy prefixes are
# matched — a generic /password\s*=/ rule would fire on documentation and test
# fixtures, and a guard that cries wolf gets disabled. Exit 2 blocks the call.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "pre:write:secret-guard" || exit 0

input=$(cat)
payload="$(devkit_field "$input" content new_string edits)"
[ -n "$payload" ] || exit 0

hit=""
match() { printf '%s' "$payload" | grep -qE -e "$1" && hit="$2"; }

match 'AKIA[0-9A-Z]{16}'                                  "AWS access key id"
match 'ASIA[0-9A-Z]{16}'                                  "AWS temporary access key id"
match '-----BEGIN [A-Z ]*PRIVATE KEY-----'                "private key block"
match 'sk-ant-[A-Za-z0-9_-]{24,}'                         "Anthropic API key"
match 'sk-[A-Za-z0-9]{32,}'                               "OpenAI-style API key"
match 'gh[pousr]_[A-Za-z0-9]{36,}'                        "GitHub token"
match 'github_pat_[A-Za-z0-9_]{40,}'                      "GitHub fine-grained token"
match 'xox[baprs]-[A-Za-z0-9-]{10,}'                      "Slack token"
match 'AIza[0-9A-Za-z_-]{35}'                             "Google API key"
match 'glpat-[A-Za-z0-9_-]{20,}'                          "GitLab token"

if [ -n "$hit" ]; then
    file="$(devkit_field "$input" file_path path)"
    echo "BLOCKED by devkit secret-write-guard: this write contains what looks like a $hit${file:+ (target: $file)}."
    echo "Secrets belong in the environment, not the tree. Read it from an env var and document the variable name instead."
    echo "False positive (a redacted example, a test fixture)? Set DEVKIT_DISABLED_HOOKS=pre:write:secret-guard for this session."
    exit 2
fi
exit 0
