#!/usr/bin/env bash
# Behaviour tests for the two sanctioned edits that let the OpenCode harness be
# wired into the devkit's own sensors.
#
# 1. validate-wiring.py's BACKTICK_PATH regex must recognise a backtick-quoted
#    `opencode/...` path, and must keep matching every existing prefix. Widening
#    an alternation can only add matches; these tests prove it did not drop one.
# 2. AGENTS.md gains exactly one bullet under "## Harness-specific notes". The
#    three bullets already there are a contract with the Codex-facing guide and
#    must stay byte-identical.
#
# The regex is read out of validate-wiring.py itself, not copied here, so a
# revert of the source line is what these tests see. The AGENTS.md check compares
# against a frozen copy of the original bullets for the same reason.
#
# Failure lines start with "FAIL: <test name>" so that break-run.sh can prove a
# falsifying mutation failed each test for its own assertion.
# The fixtures are backtick-quoted spans on purpose; SC2016 is the point, not a defect.
# shellcheck disable=SC2016
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/.github/scripts/validate-wiring.py"
AGENTS="$ROOT/AGENTS.md"
WORK="${TMPDIR:-/tmp}/devkit-sanctioned-edits-tests"
pass=0
fail=0

rm -rf "$WORK"; mkdir -p "$WORK"

# check <test name> <detail> <ok: 0|1> — count one assertion under a test name.
check() {
    if [ "$3" -eq 0 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $1 — $2"
    fi
}

# capture <span> — print the path BACKTICK_PATH captures from <span>, or NOMATCH.
# Exits 2 (not NOMATCH) if the regex line cannot be found, so a removed or
# renamed regex fails the test instead of reading as "no match".
capture() {
    python3 -I -c '
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
lines = [l for l in src.splitlines() if l.startswith("BACKTICK_PATH = re.compile(")]
if len(lines) != 1:
    sys.stderr.write("BACKTICK_PATH definition not found exactly once\n")
    sys.exit(2)
ns = {"re": re}
exec(lines[0], ns)
m = ns["BACKTICK_PATH"].search(sys.argv[2])
print(m.group(1) if m else "NOMATCH")
' "$VALIDATOR" "$1"
}

# expect_capture <span> <want> — one regex assertion under the regex test name.
RX_TEST="test_backtick_path_regex_matches_opencode"
expect_capture() {
    local got rc
    got="$(capture "$1")"; rc=$?
    if [ "$rc" -ne 0 ]; then
        check "$RX_TEST" "regex could not be loaded from validate-wiring.py (exit $rc)" 1
        return
    fi
    if [ "$got" = "$2" ]; then
        check "$RX_TEST" "" 0
    else
        check "$RX_TEST" "span '$1': got '$got', want '$2'" 1
    fi
}

test_backtick_path_regex_matches_opencode() {
    # The new case: the OpenCode adapter doc, referenced the way the other docs reference theirs.
    expect_capture '`opencode/harness-adapter.md`' 'opencode/harness-adapter.md'
    expect_capture '`coding-pipeline/opencode/harness-adapter.md`' 'coding-pipeline/opencode/harness-adapter.md'
    # Regression set: every existing prefix still matches, with the same capture.
    expect_capture '`codex/harness-adapter.md`' 'codex/harness-adapter.md'
    expect_capture '`references/languages/go.md`' 'references/languages/go.md'
    expect_capture '`agents/coder.md`' 'agents/coder.md'
    expect_capture '`skills/code/SKILL.md`' 'skills/code/SKILL.md'
    expect_capture '`hooks/hooks.json`' 'hooks/hooks.json'
    expect_capture '`scripts/verify/break-run.sh`' 'scripts/verify/break-run.sh'
    expect_capture '`git-hooks/install.sh`' 'git-hooks/install.sh'
    expect_capture '`coding-pipeline/scripts/install-git-hooks.sh`' 'coding-pipeline/scripts/install-git-hooks.sh'
    expect_capture '`python3 scripts/x.py --flag`' 'scripts/x.py'
    # Negative control: a path under no recognised prefix must not match, so a
    # regex that matches everything cannot pass the set above.
    expect_capture '`docs/unrelated/file.md`' 'NOMATCH'
}

# The frozen original bullets (AGENTS.md lines 22-36 before the sanctioned edit).
ORIGINAL_BULLETS="$WORK/original-bullets.md"
cat > "$ORIGINAL_BULLETS" <<'EOF'
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
EOF

test_agents_md_gains_exactly_one_bullet() {
    local name="test_agents_md_gains_exactly_one_bullet"
    local now_head="$WORK/now-head.md" new_block new_count

    # Lines 22-36 byte-identical to the frozen original (15 lines).
    sed -n '22,36p' "$AGENTS" > "$now_head"
    if cmp -s "$ORIGINAL_BULLETS" "$now_head"; then
        check "$name" "" 0
    else
        check "$name" "AGENTS.md lines 22-36 changed; existing bullets must stay byte-identical" 1
    fi

    # Everything after the original 36 lines is one new bullet, and nothing else.
    new_block="$(sed -n '37,$p' "$AGENTS")"
    new_count="$(printf '%s\n' "$new_block" | grep -c '^- ')"
    if [ -n "$new_block" ] && [ "$new_count" -eq 1 ] && [ "$(printf '%s\n' "$new_block" | head -n 1 | cut -c1-2)" = "- " ]; then
        check "$name" "" 0
    else
        check "$name" "expected exactly one new bullet after line 36, found $new_count bullet line(s)" 1
    fi

    # The new bullet points at the installer and the adapter doc.
    if printf '%s\n' "$new_block" | grep -q 'install-opencode\.sh' \
        && printf '%s\n' "$new_block" | grep -q 'opencode/harness-adapter\.md'; then
        check "$name" "" 0
    else
        check "$name" "new bullet does not reference install-opencode.sh and opencode/harness-adapter.md" 1
    fi
}

test_backtick_path_regex_matches_opencode
test_agents_md_gains_exactly_one_bullet

echo "sanctioned-edits tests: $pass passed, exit=$fail"
[ "$fail" -eq 0 ]
