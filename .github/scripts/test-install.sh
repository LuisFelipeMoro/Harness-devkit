#!/usr/bin/env bash
# Behaviour tests for the machine bootstrap: install.sh and wire-claude-settings.py.
#
# Everything runs against a throwaway HOME, so no assertion depends on — or
# touches — the operator's real ~/.claude. The settings merge is the part worth
# testing hardest: it edits a file that holds the user's permissions and model
# config, and getting it wrong destroys work that is not recoverable from git.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN="$REPO/plugins/coding-pipeline"
WIRE="$PLUGIN/scripts/wire-claude-settings.py"
pass=0
fail=0

check() {   # check <name> <condition-description> <0|1 result>
    if [ "$3" = "0" ]; then pass=$((pass + 1)); else echo "FAIL: $1 — $2"; fail=1; fi
}

newhome() { mktemp -d "${TMPDIR:-/tmp}/devkit-test.XXXXXX"; }

hook_count() {  # how many entries reference a given script name
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
n = 0
for entries in d.get("hooks", {}).values():
    for e in entries:
        for h in e.get("hooks", []):
            if sys.argv[2] in h.get("command", ""):
                n += 1
print(n)' "$1" "$2"
}

# ── wire-claude-settings ─────────────────────────────────────────────────────

# creates_when_absent — a bare machine must end up with live hooks, not staged ones
H="$(newhome)"
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
S="$H/.claude/settings.json"
[ -f "$S" ] && [ "$(hook_count "$S" env-guard.sh)" = "1" ] && [ "$(hook_count "$S" delivery-gate.sh)" = "1" ]
check "creates_when_absent" "settings.json missing or hooks absent" $?
rm -rf "$H"

# preserves_unrelated_keys — this file also holds permissions and model config
H="$(newhome)"; mkdir -p "$H/.claude"
cat > "$H/.claude/settings.json" <<'JSON'
{"model": "opus", "permissions": {"allow": ["Bash(ls:*)"]}, "env": {"FOO": "bar"}}
JSON
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("model") == "opus", "model lost"
assert d["permissions"]["allow"] == ["Bash(ls:*)"], "permissions lost"
assert d["env"]["FOO"] == "bar", "env lost"
assert d["hooks"], "hooks not written"
' "$H/.claude/settings.json" 2>/dev/null
check "preserves_unrelated_keys" "an unrelated top-level key was dropped" $?
rm -rf "$H"

# idempotent — re-running the installer is the normal case, not the exception
H="$(newhome)"
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
[ "$(hook_count "$H/.claude/settings.json" env-guard.sh)" = "1" ]
check "idempotent" "env-guard duplicated after repeated runs" $?
rm -rf "$H"

# preserves_foreign_hooks — operators run RTK, caveman, and their own hooks here
H="$(newhome)"; mkdir -p "$H/.claude"
cat > "$H/.claude/settings.json" <<'JSON'
{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/.claude/rtk/activate.sh"}]}]}}
JSON
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
[ "$(hook_count "$H/.claude/settings.json" rtk/activate.sh)" = "1" ] &&
[ "$(hook_count "$H/.claude/settings.json" session-bootstrap.sh)" = "1" ]
check "preserves_foreign_hooks" "a non-devkit hook was removed" $?
rm -rf "$H"

# heals_stale_devkit_hook — the bmad_v6 -> coding-pipeline rename is exactly this case
H="$(newhome)"; mkdir -p "$H/.claude/hooks"
cat > "$H/.claude/settings.json" <<JSON
{"hooks": {"PreToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "bash $H/.claude/hooks/old-removed-guard.sh"}]}]}}
JSON
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
[ "$(hook_count "$H/.claude/settings.json" old-removed-guard.sh)" = "0" ] &&
[ "$(hook_count "$H/.claude/settings.json" env-guard.sh)" = "1" ]
check "heals_stale_devkit_hook" "stale entry survived or replacement missing" $?
rm -rf "$H"

# aborts_on_invalid_json — never trade a broken file for a destroyed one
H="$(newhome)"; mkdir -p "$H/.claude"
printf '{ this is not json' > "$H/.claude/settings.json"
before="$(cksum < "$H/.claude/settings.json")"
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
rc=$?
after="$(cksum < "$H/.claude/settings.json")"
[ "$rc" != "0" ] && [ "$before" = "$after" ]
check "aborts_on_invalid_json" "exited 0 or rewrote the malformed file" $?
rm -rf "$H"

# ── install.sh helpers ───────────────────────────────────────────────────────
# shellcheck source=../../install.sh
DEVKIT_LIB_ONLY=1 . "$REPO/install.sh"
# install.sh sets -euo pipefail for its own run; sourcing leaks that into this
# shell, where a deliberately-failing assertion would abort the suite instead of
# being reported. Every check below inspects $? itself.
set +e +o pipefail

case "$(uname -s)" in
    Darwin) want_os=macos ;;
    Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then want_os=wsl; else want_os=linux; fi ;;
    *)      want_os=unsupported ;;
esac
got_os="$(detect_os)"
[ "$got_os" = "$want_os" ]; rc=$?
# $? must be captured before building the message: a command substitution inside
# the message argument runs first and overwrites it.
check "detects_os" "detect_os returned $got_os, expected $want_os" "$rc"

pm="$(detect_pkg_manager)"
if [ "$pm" = "none" ]; then
    [ "$(uname -s)" = "Darwin" ] && ! command -v brew >/dev/null 2>&1
    check "detects_pkg_manager" "reported none while a manager is installed" $?
else
    command -v "$pm" >/dev/null 2>&1
    check "detects_pkg_manager" "reported '$pm' which is not on PATH" $?
fi

[ -n "$(detect_arch)" ]
check "detects_arch" "detect_arch returned empty" $?

# claude_mem_preflight — an optional third-party tool must never fail the install
FAKEBIN="$(newhome)"
printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/npx"; chmod +x "$FAKEBIN/npx"

mk_node() { printf '#!/bin/sh\necho %s\n' "$1" > "$FAKEBIN/node"; chmod +x "$FAKEBIN/node"; }

mk_node v20.12.0
( PATH="$FAKEBIN:$PATH"; claude_mem_preflight ) >/dev/null 2>&1
check "claude_mem_passes_on_node_20" "eligible machine was rejected" $?

mk_node v18.20.0
out="$( PATH="$FAKEBIN:$PATH"; claude_mem_preflight 2>&1 )"; rc=$?
[ "$rc" != "0" ] && printf '%s' "$out" | grep -qi 'node'
check "claude_mem_gated_on_node_major" "node 18 accepted, or reason did not mention node" $?

rm -f "$FAKEBIN/node"
# Asserts the specific reason, not merely a refusal: the version-parse branch also
# refuses when node is absent, so a looser assertion would pass with this guard
# deleted and the operator would get "could not read the version" instead of
# "not found" — a message that sends them debugging the wrong thing.
out="$( PATH="$FAKEBIN:/usr/bin:/bin"; claude_mem_preflight 2>&1 )"; rc=$?
[ "$rc" != "0" ] && printf '%s' "$out" | grep -q 'not found'
check "claude_mem_skipped_without_node" "passed, or reason was not 'not found'" $?

mk_node v20.12.0
out="$( PATH="$FAKEBIN:$PATH"; SKIP_CLAUDE_MEM=1; claude_mem_preflight 2>&1 )"; rc=$?
[ "$rc" != "0" ] && printf '%s' "$out" | grep -q 'no-claude-mem'
check "claude_mem_opt_out_flag" "--no-claude-mem did not suppress it" $?
rm -rf "$FAKEBIN"

# verify_wiring — the step that catches "every guard on disk, none referenced"
H="$(newhome)"
verify_wiring "$PLUGIN" "$H" >/dev/null 2>&1
[ "$?" != "0" ]
check "verify_wiring_fails_when_unwired" "reported success with no settings.json" $?
python3 "$WIRE" "$PLUGIN" --home "$H" >/dev/null 2>&1
verify_wiring "$PLUGIN" "$H" >/dev/null 2>&1
check "verify_wiring_passes_when_wired" "reported failure on a correctly wired home" $?
python3 - "$H/.claude/settings.json" <<'PYFIX'
import json, sys
d = json.load(open(sys.argv[1]))
for event in list(d.get("hooks", {})):
    d["hooks"][event] = [e for e in d["hooks"][event]
                         if not any("destructive-guard.sh" in h.get("command", "")
                                    for h in e.get("hooks", []))]
json.dump(d, open(sys.argv[1], "w"), indent=2)
PYFIX
verify_wiring "$PLUGIN" "$H" >/dev/null 2>&1
[ "$?" != "0" ]
check "verify_wiring_catches_missing_hook" "passed with destructive-guard unreferenced" $?
rm -rf "$H"

# test_install_agent_wired_hook_exempt — a guard wired only by an agent's frontmatter
# `hooks:` block is not missing from settings.json; a hook that nothing references is.
# Synthetic plugin, so the assertion does not depend on the real hook set.
P="$(newhome)"; H="$(newhome)"
mkdir -p "$P/hooks" "$P/agents" "$H/.claude"
printf '#!/bin/bash\n' > "$P/hooks/agent-only-guard.sh"
printf '#!/bin/bash\n' > "$P/hooks/orphan-guard.sh"
printf '#!/bin/bash\n' > "$P/hooks/comment-only-guard.sh"
cat > "$P/agents/fake.md" <<'MD'
---
name: fake
tools: Read
hooks:
  # hooks/comment-only-guard.sh is only named in this comment, never wired
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: bash "$HOME/.claude/hooks/agent-only-guard.sh"
---
Body text mentioning hooks/orphan-guard.sh does not wire it.
MD
printf '{}\n' > "$H/.claude/settings.json"
out="$(verify_wiring "$P" "$H" 2>&1)"
printf '%s' "$out" | grep -q 'orphan-guard.sh' && printf '%s' "$out" | grep -q 'comment-only-guard.sh' && ! printf '%s' "$out" | grep -q 'agent-only-guard.sh'
check "test_install_agent_wired_hook_exempt" "agent-wired guard reported missing, or unreferenced hook not reported" $?
rm -rf "$P" "$H"

# ── install.sh end to end, against a throwaway HOME ──────────────────────────
# cd out of the repo first: install-global.sh wires git hooks into the *current*
# repo, and a test must not modify the tree it is testing.
H="$(newhome)"
WORK="$(newhome)"

# check_mode_no_mutation — --check is the "tell me before you touch anything" path
( cd "$WORK" && bash "$REPO/install.sh" --check --home "$H" ) >/dev/null 2>&1
rc=$?
[ "$rc" = "0" ] && [ ! -d "$H/.claude" ]
check "check_mode_no_mutation" "--check exited $rc or created $H/.claude" $?

# records_version_state — this is what makes the next run cheap
out="$( cd "$WORK" && bash "$REPO/install.sh" --yes --no-deps --home "$H" 2>&1 )"
state="$H/.claude/devkit/install-state.json"
repo_sha="$(git -C "$REPO" rev-parse HEAD)"
[ -f "$state" ] && [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["commit"])' "$state")" = "$repo_sha" ]
check "records_version_state" "state file missing or holds the wrong commit" $?

# the install must also have produced a live, wired settings.json
[ "$(hook_count "$H/.claude/settings.json" destructive-guard.sh)" = "1" ]
check "wires_hooks_end_to_end" "destructive-guard not wired after a full install" $?

# detects_up_to_date — second run recognises the commit it already installed
out2="$( cd "$WORK" && bash "$REPO/install.sh" --yes --no-deps --home "$H" 2>&1 )"
printf '%s' "$out2" | grep -q "up to date"
check "detects_up_to_date" "second run did not report an up-to-date install" $?

rm -rf "$H" "$WORK"

# ignores_stray_git_hooks_dirs — a gitignored __pycache__ beside dup-attribution.py
# appears the first time anyone runs py_compile. cp on a directory exits non-zero,
# set -e aborted the install there, and every step after it (settings wiring
# included) silently never ran. Runs against a copy: the test must not touch the tree.
H="$(newhome)"; WORK="$(newhome)"; SRC="$(newhome)"
cp -R "$REPO/plugins" "$SRC/"
mkdir -p "$SRC/plugins/coding-pipeline/git-hooks/__pycache__"
( cd "$WORK" && HOME="$H" bash "$SRC/plugins/coding-pipeline/scripts/install-global.sh" ) >/dev/null 2>&1
rc=$?
[ "$rc" = "0" ] && [ -f "$H/.claude/git-hooks/pre-push" ] && [ ! -e "$H/.claude/git-hooks/__pycache__" ]
check "ignores_stray_git_hooks_dirs" "install exited $rc or staged the stray directory" $?
rm -rf "$H" "$WORK" "$SRC"

# stages_sensor_scripts — skills and agents run scripts/verify/*, estimate-run.py and harness-metrics.py;
# a flat install that omits them leaves /code and /validate-code citing paths that do not
# exist. break-run.sh must also find its sibling diff-lib.sh from the staged copy.
H="$(newhome)"; WORK="$(newhome)"
( cd "$WORK" && HOME="$H" bash "$PLUGIN/scripts/install-global.sh" ) >/dev/null 2>&1
D="$H/.claude/devkit/scripts"
[ -x "$D/verify/break-run.sh" ] && [ -x "$D/verify/verdict.sh" ] && [ -f "$D/verify/diff-lib.sh" ] \
    && [ -x "$D/estimate-run.py" ] && [ -x "$D/harness-metrics.py" ]
check "stages_sensor_scripts" "verify/*.sh, estimate-run.py or harness-metrics.py missing or not executable under ~/.claude/devkit/scripts" $?
rm -rf "$H" "$WORK"

# removes_retired_devkit_files — an upgrade from a 2.x flat install must not leave the
# retired auto-invoked pipeline live beside 3.x: install-global.sh only adds and updates
# same-named files, so a removed skill or agent survives unless it is deleted by exact name.
# A user's own skill, agent and hook are never touched.
H="$(newhome)"; WORK="$(newhome)"
mkdir -p "$H/.claude/skills/multi-agent/references" "$H/.claude/skills/my-skill" "$H/.claude/agents" "$H/.claude/hooks"
printf -- '---\nname: multi-agent\n---\n' > "$H/.claude/skills/multi-agent/SKILL.md"
printf 'loop\n' > "$H/.claude/skills/multi-agent/references/loop.md"
printf 'flat\n' > "$H/.claude/skills/bug-fix.md"
printf -- '---\nname: my-skill\n---\n' > "$H/.claude/skills/my-skill/SKILL.md"
printf 'old\n' > "$H/.claude/agents/orchestrator.md"
printf 'mine\n' > "$H/.claude/agents/my-agent.md"
printf '#!/bin/sh\n' > "$H/.claude/hooks/orchestrator-bash-guard.sh"
printf '#!/bin/sh\n' > "$H/.claude/hooks/my-hook.sh"
cat > "$H/.claude/settings.json" <<JSON
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash $H/.claude/hooks/orchestrator-bash-guard.sh"}]}]}}
JSON
out=$( cd "$WORK" && HOME="$H" bash "$PLUGIN/scripts/install-global.sh" 2>&1 )
[ ! -e "$H/.claude/skills/multi-agent" ] && [ ! -e "$H/.claude/skills/bug-fix.md" ] \
    && [ ! -e "$H/.claude/agents/orchestrator.md" ] && [ ! -e "$H/.claude/hooks/orchestrator-bash-guard.sh" ]
check "removes_retired_devkit_files" "a retired 2.x skill, agent or hook survived the install" $?
[ -f "$H/.claude/skills/my-skill/SKILL.md" ] && [ -f "$H/.claude/agents/my-agent.md" ] && [ -f "$H/.claude/hooks/my-hook.sh" ]
check "removes_retired_devkit_files_keeps_user_files" "a user's own skill, agent or hook was removed" $?
case "$out" in *"removed retired skills/multi-agent"*"removed retired agents/orchestrator.md"*) rc=0 ;; *) rc=1 ;; esac
check "removes_retired_devkit_files_prints_each" "a removal was not printed" $rc
[ "$(hook_count "$H/.claude/settings.json" orchestrator-bash-guard.sh)" = "0" ]
check "removes_retired_devkit_files_unwires_hook" "settings.json still wires orchestrator-bash-guard.sh" $?
rm -rf "$H" "$WORK"

echo "install tests: $pass passed, exit=$fail"
exit $fail
