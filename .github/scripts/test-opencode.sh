#!/usr/bin/env bash
# Part A of the OpenCode tests: generate-opencode.py invoked directly into temp targets.
# Installer-CLI tests (install-opencode.sh end-to-end) are Part B, appended later to this file.
#
# The generator is the only place OpenCode output is produced, so these tests read its output
# tree and the real plugins/ sources it transforms. Generated output is inspected where the
# source file is itself emitted (skills/<name>/SKILL.md, agents/*.md). Skill-local
# references/*.md are emitted too, so the dispatch-prose fixtures that live there are read
# from the generated tree.
#
# Failure lines start with "FAIL: <test name>" so that break-run.sh can prove a falsifying
# mutation failed each test for its own assertion.
# The grep patterns below contain literal backticks and quotes on purpose; SC2016 is the point.
# shellcheck disable=SC2016
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEN="$ROOT/plugins/coding-pipeline/scripts/generate-opencode.py"
WORK="${TMPDIR:-/tmp}/devkit-opencode-tests"
OUT="$WORK/out"
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

# gen <target> — run the generator directly with three valid tiers; its stdout and stderr pass through.
gen() {
    python3 -I "$GEN" --target "$1" --model-cheap "test-provider/cheap-model" \
        --model-standard "test-provider/standard-model" --model-deep "test-provider/deep-model"
}

# has <text> <fixed string> — 0 when the fixed string occurs in the text.
has() {
    printf '%s\n' "$1" | grep -qF -- "$2"
}

# zero_hits <ERE> <dir-or-file> — prints any hit; 0 when there are none, 1 on a hit, 2 on a grep error.
zero_hits() {
    local hits rc=0
    hits="$(grep -rnE -- "$1" "$2")" || rc=$?
    if [ "$rc" -eq 1 ]; then
        return 0
    fi
    if [ "$rc" -eq 0 ]; then
        printf '%s\n' "$hits" | head -3
        return 1
    fi
    return 2
}

gen_rc=0
gen "$OUT" >"$WORK/gen-out.txt" 2>"$WORK/gen-err.txt" || gen_rc=$?

test_generate_writes_all_24_skills() {
    local n missing="" name src
    n="$(find "$OUT/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l)"
    for src in "$ROOT"/plugins/*/skills/*/SKILL.md; do
        name="$(basename "$(dirname "$src")")"
        [ -f "$OUT/skills/$name/SKILL.md" ] || missing="$missing $name"
    done
    [ "$gen_rc" -eq 0 ]; check "test_generate_writes_all_24_skills" "generator exit $gen_rc: $(cat "$WORK/gen-err.txt")" $?
    [ "$n" -eq 24 ]; check "test_generate_writes_all_24_skills" "found $n skill files under skills/ (want 24)" $?
    [ -z "$missing" ]; check "test_generate_writes_all_24_skills" "skills not generated:$missing" $?
}

test_generate_writes_12_agents_with_coder_merge() {
    local n
    n="$(find "$OUT/agents" -maxdepth 1 -name '*.md' | wc -l)"
    [ "$n" -eq 12 ]; check "test_generate_writes_12_agents_with_coder_merge" "found $n agent files (want 12)" $?
    grep -qF "## Scope Discipline" "$OUT/agents/coder-backend.md"; check "test_generate_writes_12_agents_with_coder_merge" "coder-backend.md lacks the shared coder.md body" $?
    grep -qF "## Scope Discipline" "$OUT/agents/coder-frontend.md"; check "test_generate_writes_12_agents_with_coder_merge" "coder-frontend.md lacks the shared coder.md body" $?
}

test_readonly_agents_get_permission_deny_and_tools_false() {
    python3 -I - "$ROOT/plugins/coding-pipeline/agents" "$OUT/agents" <<'PY'
import sys
from pathlib import Path

src_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
read_only = []
for src in sorted(src_dir.glob("*.md")):
    if src.stem == "coder":
        continue
    tools = ""
    for line in src.read_text(encoding="utf-8").split("\n")[1:]:
        if line.strip() == "---":
            break
        if line.startswith("tools:"):
            tools = line.partition(":")[2]
    names = {t.strip() for t in tools.split(",")}
    if not names & {"Edit", "Write", "Patch"}:
        read_only.append(src.stem)

problems = []
if len(read_only) != 9:
    problems.append(f"expected 9 read-only source agents, found {len(read_only)}: {read_only}")
for stem in read_only:
    text = (out_dir / f"{stem}.md").read_text(encoding="utf-8")
    front = text[3 : text.index("\n---\n", 3)]
    if 'permission:\n  edit: "deny"' not in front:
        problems.append(f"{stem}: permission.edit is not deny")
    if "tools:\n  edit: false\n  write: false\n  patch: false" not in front:
        problems.append(f"{stem}: tools edit/write/patch are not all false")
if problems:
    print("; ".join(problems))
    sys.exit(1)
PY
    check "test_readonly_agents_get_permission_deny_and_tools_false" "read-only agents lack deny/false (see detail above)" $?
}

test_no_literal_subagent_type_or_dispatch_agent_param_survives() {
    local d rc
    d="$(zero_hits 'subagent_type:\s*"' "$OUT")"; rc=$?
    check "test_no_literal_subagent_type_or_dispatch_agent_param_survives" "surviving subagent_type: $d" "$rc"
    d="$(zero_hits '\bagent:\s*"[^"]+"' "$OUT")"; rc=$?
    check "test_no_literal_subagent_type_or_dispatch_agent_param_survives" "surviving bare agent: $d" "$rc"
}

test_conditional_dispatch_preserves_all_alternatives_and_comment() {
    local got
    got="$(cat "$OUT/skills/bugfix/references/dispatch.md")"
    has "$got" 'dispatch whichever of the `coder-backend`, `coder-frontend`, or `coder` agents fits'
    check "test_conditional_dispatch_preserves_all_alternatives_and_comment" "alternatives not all kept: $got" $?
    has "$got" "— the bug's tier; the overlay loads agents/coder.md"
    check "test_conditional_dispatch_preserves_all_alternatives_and_comment" "comment-derived clause lost: $got" $?
    ! has "$got" 'subagent_type:'
    check "test_conditional_dispatch_preserves_all_alternatives_and_comment" "subagent_type: survived: $got" $?
}

test_inline_embedded_dispatch_clause_rewritten() {
    local got
    got="$(cat "$OUT/skills/map/references/map-procedure.md")"
    ! has "$got" 'subagent_type:'
    check "test_inline_embedded_dispatch_clause_rewritten" "subagent_type: survived: $got" $?
    has "$got" 'dispatch the `explore` agent'
    check "test_inline_embedded_dispatch_clause_rewritten" "alias not applied (want \`explore\`): $got" $?
    has "$got" 'agent", description: "map {topic}"'
    check "test_inline_embedded_dispatch_clause_rewritten" "comma or description clause lost: $got" $?
}

test_inline_prose_dispatch_mention_rewritten_except_dangling_continuation() {
    local got
    got="$(cat "$OUT/skills/rote-adapter/references/dispatch.md")"
    ! has "$got" 'subagent_type:'
    check "test_inline_prose_dispatch_mention_rewritten_except_dangling_continuation" "subagent_type: survived: $got" $?
    has "$got" 'dispatch the `rote-adapter` agent'
    check "test_inline_prose_dispatch_mention_rewritten_except_dangling_continuation" "first clause not rewritten: $got" $?
    has "$got" '`"rote-adapter"` in a flat'
    check "test_inline_prose_dispatch_mention_rewritten_except_dangling_continuation" "accepted-unrewritten second clause changed shape: $got" $?
}

test_backtick_adjacent_model_clause_swept() {
    local line d
    line="$(grep -F '`reviewer` agent' "$OUT/skills/review-code/SKILL.md")"
    [ -n "$line" ]; check "test_backtick_adjacent_model_clause_swept" "review-code dispatch line not generated" $?
    ! has "$line" 'model: "sonnet"'
    check "test_backtick_adjacent_model_clause_swept" "review-code model clause stranded: $line" $?

    d="$(zero_hits 'subagent_type:' "$OUT/skills/validate-code/SKILL.md")"; rc=$?
    check "test_backtick_adjacent_model_clause_swept" "validate-code subagent_type: survived: $d" "$rc"
    grep -qF 'dispatch the `qa` agent' "$OUT/skills/validate-code/SKILL.md"; check "test_backtick_adjacent_model_clause_swept" "validate-code qa dispatch not rewritten" $?
    grep -qF 'dispatch the `stress` agent' "$OUT/skills/validate-code/SKILL.md"; check "test_backtick_adjacent_model_clause_swept" "validate-code stress dispatch not rewritten" $?
    # Accepted limitation: one shared model clause serving two dispatches joined by "and"/"both" stays unswept.
    grep -qF '`model: "sonnet"`' "$OUT/skills/validate-code/SKILL.md"; check "test_backtick_adjacent_model_clause_swept" "shared model clause swept, accepted-limitation shape changed" $?
}

test_rerun_byte_identical() {
    local dir="$WORK/rerun" rc1=0 rc2=0 out2 diff_rc=0
    gen "$dir" >/dev/null 2>&1 || rc1=$?
    cp -a "$dir" "$WORK/rerun-first"
    out2="$(gen "$dir" 2>&1)" || rc2=$?
    diff -r "$WORK/rerun-first" "$dir" >/dev/null || diff_rc=$?
    check "test_rerun_byte_identical" "first run exit $rc1" "$rc1"
    check "test_rerun_byte_identical" "second run exit $rc2: $out2" "$rc2"
    check "test_rerun_byte_identical" "tree bytes differ between the two runs (diff exit $diff_rc)" "$diff_rc"
}

test_non_devkit_collision_kept_and_reported() {
    # skills/qa/SKILL.md is not a generated path (qa is an agent), so the collision is staged on
    # skills/map/SKILL.md, a path the generator does write, with no manifest owning it.
    local dir="$WORK/collision" rel="skills/map/SKILL.md" out rc=0
    mkdir -p "$dir/skills/map"
    printf 'user-owned map skill\n' >"$dir/$rel"
    out="$(gen "$dir" 2>&1)" || rc=$?
    grep -qxF 'user-owned map skill' "$dir/$rel"; check "test_non_devkit_collision_kept_and_reported" "user-owned file was overwritten" $?
    printf '%s\n' "$out" | grep -qxF "kept (not the devkit's): $rel"; check "test_non_devkit_collision_kept_and_reported" "stdout lacks the kept line; got: $out" $?
    check "test_non_devkit_collision_kept_and_reported" "generator exit $rc" "$rc"
}

test_hand_edited_devkit_file_kept_and_reported() {
    local dir="$WORK/handedit" rel="skills/map/SKILL.md" out rc=0
    gen "$dir" >/dev/null 2>&1
    printf '\nHAND EDIT\n' >>"$dir/$rel"
    out="$(gen "$dir" 2>&1)" || rc=$?
    grep -qxF 'HAND EDIT' "$dir/$rel"; check "test_hand_edited_devkit_file_kept_and_reported" "hand edit was clobbered" $?
    printf '%s\n' "$out" | grep -qxF "kept (modified since install): $rel"; check "test_hand_edited_devkit_file_kept_and_reported" "stdout lacks the kept line; got: $out" $?
    check "test_hand_edited_devkit_file_kept_and_reported" "generator exit $rc" "$rc"
}

test_generate_writes_all_24_skills
test_generate_writes_12_agents_with_coder_merge
test_readonly_agents_get_permission_deny_and_tools_false
test_no_literal_subagent_type_or_dispatch_agent_param_survives
test_conditional_dispatch_preserves_all_alternatives_and_comment
test_inline_embedded_dispatch_clause_rewritten
test_inline_prose_dispatch_mention_rewritten_except_dangling_continuation
test_backtick_adjacent_model_clause_swept
test_rerun_byte_identical
test_non_devkit_collision_kept_and_reported
test_hand_edited_devkit_file_kept_and_reported

echo "opencode tests: $pass passed, exit=$fail"
[ "$fail" -eq 0 ]
