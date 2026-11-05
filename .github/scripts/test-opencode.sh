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
    local n missing="" name src rc=0
    n="$(find "$OUT/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l)"
    for src in "$ROOT"/plugins/*/skills/*/SKILL.md; do
        name="$(basename "$(dirname "$src")")"
        [ -f "$OUT/skills/$name/SKILL.md" ] || missing="$missing $name"
    done
    [ "$gen_rc" -eq 0 ]; rc=$?
    check "test_generate_writes_all_24_skills" "generator exit $gen_rc: $(cat "$WORK/gen-err.txt")" "$rc"
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

test_concurrent_installs_do_not_corrupt_manifest() {
    # Six trials, each two generator runs racing on one fresh target. Without the target lock the
    # last manifest writer erases the other run's entries, so an overlapping trial exposes the race.
    local trial dir pid_a pid_b rc_a=0 rc_b=0 files entries kept_count out
    for trial in 1 2 3 4 5 6; do
        dir="$WORK/concurrent-$trial"
        gen "$dir" >/dev/null 2>&1 & pid_a=$!
        # Start the second run once the first is mid-write, so the two genuinely overlap. The bounded
        # poll only makes the overlap likely; the assertions below hold whether or not it happened.
        for _ in $(seq 1 300); do [ -d "$dir/skills" ] && break; sleep 0.01; done
        gen "$dir" >/dev/null 2>&1 & pid_b=$!
        wait "$pid_a" || rc_a=$?
        wait "$pid_b" || rc_b=$?
        [ "$rc_a" -eq 0 ] && [ "$rc_b" -eq 0 ]
        check "test_concurrent_installs_do_not_corrupt_manifest" "trial $trial: racing runs exited a=$rc_a b=$rc_b" $?
        files="$(find "$dir" -type f ! -name .devkit-opencode-manifest.json | wc -l)"
        entries="$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["entries"]))' \
            "$dir/.devkit-opencode-manifest.json" 2>/dev/null)" || entries=-1
        [ "$entries" -eq "$files" ]
        check "test_concurrent_installs_do_not_corrupt_manifest" "trial $trial: manifest lists $entries entries but $files files are on disk" $?
        out="$(gen "$dir" 2>&1)" || true
        kept_count="$(printf '%s\n' "$out" | grep -cF "kept (not the devkit's)")" || true
        [ "$kept_count" -eq 0 ]
        check "test_concurrent_installs_do_not_corrupt_manifest" "trial $trial: sequential re-run kept $kept_count devkit files as not-the-devkit's" $?
    done
}

test_symlink_at_manifest_path_not_followed() {
    local dir="$WORK/symlink-manifest" sentinel="$WORK/sentinel-outside-target.txt" out rc=0
    mkdir -p "$dir"
    printf 'EXTERNAL SENTINEL, must never be overwritten\n' >"$sentinel"
    cp "$sentinel" "$WORK/sentinel-before.txt"
    ln -s "$sentinel" "$dir/.devkit-opencode-manifest.json"
    out="$(gen "$dir" 2>&1)" || rc=$?
    cmp -s "$sentinel" "$WORK/sentinel-before.txt"
    check "test_symlink_at_manifest_path_not_followed" "file behind the manifest symlink was overwritten" $?
    printf '%s\n' "$out" | grep -qxF "kept (not the devkit's): .devkit-opencode-manifest.json"
    check "test_symlink_at_manifest_path_not_followed" "stdout lacks the kept line; got: $out" $?
    check "test_symlink_at_manifest_path_not_followed" "generator exit $rc" "$rc"
}

test_killed_mid_write_leaves_no_torn_file() {
    # The driver loads the real generator and makes os.replace fail for one devkit-owned path, which
    # is what a kill between the temp-file write and the rename looks like to the generator.
    local dir="$WORK/torn" rel="skills/map/SKILL.md" driver="$WORK/fault-driver.py" old="$WORK/torn-old.txt" out rc=0 same=0
    gen "$dir" >/dev/null 2>&1
    printf 'OLD CONTENT from before the run\n' >"$old"
    cat >"$driver" <<'PY'
import hashlib, importlib.util, json, os, sys
gen_path, target, rel, old_path = sys.argv[1:5]
dest = os.path.join(target, rel)
manifest = os.path.join(target, ".devkit-opencode-manifest.json")
old = open(old_path, "rb").read()
open(dest, "wb").write(old)
doc = json.load(open(manifest, encoding="utf-8"))
for entry in doc["entries"]:
    if entry["path"] == rel:
        entry["sha256"] = hashlib.sha256(old).hexdigest()
open(manifest, "w", encoding="utf-8").write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
spec = importlib.util.spec_from_file_location("generate_opencode", gen_path)
gen = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = gen
spec.loader.exec_module(gen)
real_replace = os.replace
def dying_replace(src, dst):
    if os.path.abspath(os.fspath(dst)) == os.path.abspath(dest):
        raise OSError("injected kill before rename")
    return real_replace(src, dst)
os.replace = dying_replace
sys.exit(gen.main(["--target", target, "--model-cheap", "test-provider/cheap-model",
                   "--model-standard", "test-provider/standard-model",
                   "--model-deep", "test-provider/deep-model"]))
PY
    out="$(python3 -I "$driver" "$GEN" "$dir" "$rel" "$old" 2>&1)" || rc=$?
    has "$out" "injected kill"
    check "test_killed_mid_write_leaves_no_torn_file" "fault never fired, so the test proves nothing; got: $out" $?
    cmp -s "$dir/$rel" "$old"; same=$?
    check "test_killed_mid_write_leaves_no_torn_file" "destination changed after an interrupted write (generator exit $rc)" "$same"
}

test_broken_symlink_at_skill_dir_kept_not_crashed() {
    # SEC-7: a broken link at skills/<name> made the old mkdir(exist_ok=True) raise FileExistsError.
    local dir="$WORK/broken-skill-dir" target="$WORK/no-such-directory" out rc=0 link_target
    mkdir -p "$dir/skills"
    ln -s "$target" "$dir/skills/map"
    out="$(gen "$dir" 2>&1)" || rc=$?
    check "test_broken_symlink_at_skill_dir_kept_not_crashed" "generator exit $rc, want 0; got: $out" "$rc"
    printf '%s\n' "$out" | grep -qxF "kept (not the devkit's): skills/map"
    check "test_broken_symlink_at_skill_dir_kept_not_crashed" "stdout lacks the kept line; got: $out" $?
    link_target="$(readlink "$dir/skills/map" 2>/dev/null)"
    [ -L "$dir/skills/map" ] && [ "$link_target" = "$target" ]
    check "test_broken_symlink_at_skill_dir_kept_not_crashed" "the broken symlink was deleted or replaced" $?
}

test_valid_symlink_at_skill_dir_not_followed() {
    # SEC-7: a valid link at skills/<name> was followed by mkdir and SKILL.md was written into the external directory.
    local dir="$WORK/valid-skill-dir" ext="$WORK/external-skill-dir" sentinel out rc=0 listing
    mkdir -p "$dir/skills" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    cp "$sentinel" "$WORK/valid-sentinel-before.txt"
    ln -s "$ext" "$dir/skills/map"
    out="$(gen "$dir" 2>&1)" || rc=$?
    check "test_valid_symlink_at_skill_dir_not_followed" "generator exit $rc, want 0; got: $out" "$rc"
    printf '%s\n' "$out" | grep -qxF "kept (not the devkit's): skills/map"
    check "test_valid_symlink_at_skill_dir_not_followed" "stdout lacks the kept line; got: $out" $?
    cmp -s "$sentinel" "$WORK/valid-sentinel-before.txt"
    check "test_valid_symlink_at_skill_dir_not_followed" "sentinel content in the external directory changed" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_valid_symlink_at_skill_dir_not_followed" "a file was written into the external directory: $listing" $?
}

test_valid_symlink_at_top_level_output_dir_not_followed() {
    # SEC-7: a valid link at the whole agents/ directory was followed by mkdir, so agent files landed outside the target.
    local dir="$WORK/valid-agents-dir" ext="$WORK/external-agents-dir" sentinel out rc=0 listing
    mkdir -p "$dir" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    cp "$sentinel" "$WORK/agents-sentinel-before.txt"
    ln -s "$ext" "$dir/agents"
    out="$(gen "$dir" 2>&1)" || rc=$?
    check "test_valid_symlink_at_top_level_output_dir_not_followed" "generator exit $rc, want 0; got: $out" "$rc"
    printf '%s\n' "$out" | grep -qxF "kept (not the devkit's): agents"
    check "test_valid_symlink_at_top_level_output_dir_not_followed" "stdout lacks the kept line; got: $out" $?
    cmp -s "$sentinel" "$WORK/agents-sentinel-before.txt"
    check "test_valid_symlink_at_top_level_output_dir_not_followed" "sentinel content in the external directory changed" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_valid_symlink_at_top_level_output_dir_not_followed" "a file was written into the external directory: $listing" $?
}

test_symlinked_target_root_rejected() {
    # SEC-8: a symlinked --target root was followed by mkdir, so the whole install wrote into the external directory.
    local dir="$WORK/symlinked-target-root" ext="$WORK/symlinked-target-root-ext" link="$WORK/symlinked-target-root-link"
    local sentinel out rc=0 listing
    mkdir -p "$dir" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    cp "$sentinel" "$dir/sentinel-before.txt"
    ln -s "$ext" "$link"
    out="$(python3 -I "$GEN" --target "$link" --plugins-root "$ROOT/plugins" --model-cheap test-provider/cheap-model \
        --model-standard test-provider/standard-model --model-deep test-provider/deep-model 2>&1)" || rc=$?
    [ "$rc" -ne 0 ]
    check "test_symlinked_target_root_rejected" "generator exit $rc, want non-zero; got: $out" $?
    has "$out" "$link"
    check "test_symlinked_target_root_rejected" "output does not name the symlinked target path; got: $out" $?
    cmp -s "$sentinel" "$dir/sentinel-before.txt"
    check "test_symlinked_target_root_rejected" "sentinel content in the external directory changed" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_symlinked_target_root_rejected" "a file was written through the symlinked target: $listing" $?
}

test_symlinked_project_dir_rejected() {
    # SEC-9: --project DIR is a symlink and DIR/.opencode does not exist yet, so SEC-8's TARGET check cannot see it.
    local dir="$WORK/symlinked-project-dir" ext="$WORK/symlinked-project-dir-ext" link="$WORK/symlinked-project-dir-link"
    local sentinel rc=0 err listing
    mkdir -p "$dir" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    ln -s "$ext" "$link"
    inst --project "$link" "${TIERS[@]}" --no-git-hooks --yes >"$dir/stdout.txt" 2>"$dir/stderr.txt" || rc=$?
    err="$(cat "$dir/stderr.txt")"
    [ "$rc" -ne 0 ]
    check "test_symlinked_project_dir_rejected" "installer exit $rc, want non-zero; stderr: $err" $?
    has "$err" "$link"
    check "test_symlinked_project_dir_rejected" "stderr does not name the symlinked project dir; got: $err" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_symlinked_project_dir_rejected" "a file was written through the symlinked project dir: $listing" $?
}

test_symlinked_default_config_dir_rejected() {
    # SEC-9: XDG_CONFIG_HOME is a symlink on the zero-flag default path; opencode/ does not exist under it yet.
    local dir="$WORK/symlinked-default-config" ext="$WORK/symlinked-default-config-ext" link="$WORK/symlinked-default-config-link"
    local sentinel rc=0 err listing
    mkdir -p "$dir" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    ln -s "$ext" "$link"
    XDG_CONFIG_HOME="$link" inst "${TIERS[@]}" --no-git-hooks --yes >"$dir/stdout.txt" 2>"$dir/stderr.txt" || rc=$?
    err="$(cat "$dir/stderr.txt")"
    [ "$rc" -ne 0 ]
    check "test_symlinked_default_config_dir_rejected" "installer exit $rc, want non-zero; stderr: $err" $?
    has "$err" "$link"
    check "test_symlinked_default_config_dir_rejected" "stderr does not name the symlinked config directory; got: $err" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_symlinked_default_config_dir_rejected" "a file was written through the symlinked config dir: $listing" $?
}

test_symlinked_target_ancestor_rejected() {
    # SEC-9: --target DIR/newdir with DIR a symlink. SEC-8 only checks the leaf, which does not exist yet, so it passes.
    local dir="$WORK/symlinked-target-ancestor" ext="$WORK/symlinked-target-ancestor-ext" link="$WORK/symlinked-target-ancestor-link"
    local sentinel rc=0 err listing
    mkdir -p "$dir" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    ln -s "$ext" "$link"
    inst --target "$link/newdir" "${TIERS[@]}" --no-git-hooks --yes >"$dir/stdout.txt" 2>"$dir/stderr.txt" || rc=$?
    err="$(cat "$dir/stderr.txt")"
    [ "$rc" -ne 0 ]
    check "test_symlinked_target_ancestor_rejected" "installer exit $rc, want non-zero; stderr: $err" $?
    has "$err" "$link"
    check "test_symlinked_target_ancestor_rejected" "stderr does not name the symlinked ancestor; got: $err" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_symlinked_target_ancestor_rejected" "a file was written through the symlinked ancestor: $listing" $?
}

test_multi_level_symlinked_ancestor_rejected() {
    # SEC-9: the symlink sits two levels above the leaf (--target LINK/mid/newdir), so only a full ancestor walk sees it.
    local dir="$WORK/multi-level-ancestor" ext="$WORK/multi-level-ancestor-ext" link="$WORK/multi-level-ancestor-link"
    local sentinel rc=0 err listing
    mkdir -p "$dir" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    ln -s "$ext" "$link"
    inst --target "$link/mid/newdir" "${TIERS[@]}" --no-git-hooks --yes >"$dir/stdout.txt" 2>"$dir/stderr.txt" || rc=$?
    err="$(cat "$dir/stderr.txt")"
    [ "$rc" -ne 0 ]
    check "test_multi_level_symlinked_ancestor_rejected" "installer exit $rc, want non-zero; stderr: $err" $?
    has "$err" "$link"
    check "test_multi_level_symlinked_ancestor_rejected" "stderr does not name the symlinked ancestor; got: $err" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_multi_level_symlinked_ancestor_rejected" "a file was written through the symlinked ancestor: $listing" $?
}

test_dotdot_through_missing_dir_rejected() {
    # SEC-10: "missing_subdir/../link" — the walk's is_symlink() reports False for the ENOENT prefix, so only the
    # literal ".." check stops mkdir creating missing_subdir and the kernel then resolving ../link through the symlink.
    local dir="$WORK/dotdot-missing" ext="$WORK/dotdot-missing-ext" link="$WORK/dotdot-missing/link"
    local sentinel out rc=0 listing
    mkdir -p "$dir" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    ln -s "$ext" "$link"
    out="$(python3 -I "$GEN" --target "$dir/missing_subdir/../link/opencode" --plugins-root "$ROOT/plugins" \
        --model-cheap test-provider/cheap-model --model-standard test-provider/standard-model \
        --model-deep test-provider/deep-model 2>&1)" || rc=$?
    [ "$rc" -ne 0 ]
    check "test_dotdot_through_missing_dir_rejected" "generator exit $rc, want non-zero; got: $out" $?
    has "$out" "$dir/missing_subdir/../link/opencode"
    check "test_dotdot_through_missing_dir_rejected" "output does not name the rejected path; got: $out" $?
    [ ! -e "$dir/missing_subdir" ]
    check "test_dotdot_through_missing_dir_rejected" "missing_subdir was created before the rejection" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_dotdot_through_missing_dir_rejected" "a file was written through the symlink: $listing" $?
}

test_dotdot_with_preexisting_dir_still_caught_by_walk() {
    # SEC-10 control: real_subdir pre-exists, so SEC-9's ancestor walk alone can lstat the symlink and refuse.
    # Defense-in-depth, not independence: either SEC-9 or SEC-10 alone still catches this specific
    # pre-existing-intermediate shape. The falsifying break is disabling both simultaneously.
    local dir="$WORK/dotdot-preexisting" ext="$WORK/dotdot-preexisting-ext" link="$WORK/dotdot-preexisting/link"
    local sentinel out rc=0 listing
    mkdir -p "$dir/real_subdir" "$ext"
    sentinel="$ext/sentinel.txt"
    printf 'EXTERNAL SENTINEL, must never be written into\n' >"$sentinel"
    ln -s "$ext" "$link"
    out="$(python3 -I "$GEN" --target "$dir/real_subdir/../link/opencode" --plugins-root "$ROOT/plugins" \
        --model-cheap test-provider/cheap-model --model-standard test-provider/standard-model \
        --model-deep test-provider/deep-model 2>&1)" || rc=$?
    [ "$rc" -ne 0 ]
    check "test_dotdot_with_preexisting_dir_still_caught_by_walk" "generator exit $rc, want non-zero; got: $out" $?
    listing="$(ls -A "$ext")"
    [ "$listing" = "sentinel.txt" ]
    check "test_dotdot_with_preexisting_dir_still_caught_by_walk" "a file was written through the symlink: $listing" $?
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
test_concurrent_installs_do_not_corrupt_manifest
test_symlink_at_manifest_path_not_followed
test_killed_mid_write_leaves_no_torn_file
test_broken_symlink_at_skill_dir_kept_not_crashed
test_valid_symlink_at_skill_dir_not_followed
test_valid_symlink_at_top_level_output_dir_not_followed
test_symlinked_target_root_rejected

# ── Part B: installer-CLI tests — install-opencode.sh end-to-end ─────────────
# Every installer run here passes --no-git-hooks so the repository's own .git/hooks is never touched,
# and clears the operator's DEVKIT_OPENCODE_MODEL_* variables so only the flags under test pick the tiers.
# The real `opencode` binary is never invoked; it is not installed in CI and nothing here needs it.
INSTALL="$ROOT/plugins/coding-pipeline/scripts/install-opencode.sh"
TIERS=(--model-cheap test-provider/cheap-model --model-standard test-provider/standard-model --model-deep test-provider/deep-model)

# inst <args...> — run the installer with the operator's model-tier environment cleared.
inst() {
    env -u DEVKIT_OPENCODE_MODEL_CHEAP -u DEVKIT_OPENCODE_MODEL_STANDARD -u DEVKIT_OPENCODE_MODEL_DEEP \
        bash "$INSTALL" "$@"
}

# snap_tree <root> [skip] — sorted path, mtime and size listing; "absent" when root does not exist.
snap_tree() {
    local root="$1" skip="${2:-}"
    if [ ! -e "$root" ]; then
        echo "absent $root"
        return 0
    fi
    if [ -n "$skip" ]; then
        find "$root" -path "$skip" -prune -o -printf '%p %T@ %s\n' | LC_ALL=C sort
    else
        find "$root" -printf '%p %T@ %s\n' | LC_ALL=C sort
    fi
}

test_missing_model_tier_exits_nonzero_naming_tier() {
    local dir="$WORK/missing-tier" rc=0 err
    mkdir -p "$dir"
    inst --target "$dir/cfg" --model-standard test-provider/standard-model \
        --model-deep test-provider/deep-model --no-git-hooks --yes >/dev/null 2>"$dir/err.txt" || rc=$?
    err="$(cat "$dir/err.txt")"
    [ "$rc" -eq 2 ]; check "test_missing_model_tier_exits_nonzero_naming_tier" "exit $rc, want 2" $?
    has "$err" 'model tier "cheap" is not set'; check "test_missing_model_tier_exits_nonzero_naming_tier" "stderr does not name the cheap tier: $err" $?
    [ ! -e "$dir/cfg" ]; check "test_missing_model_tier_exits_nonzero_naming_tier" "files written before the tier check failed" $?
}

test_malformed_model_string_rejected() {
    local dir="$WORK/malformed-tier" rc=0 err
    mkdir -p "$dir"
    inst --target "$dir/cfg" --model-cheap haiku --model-standard test-provider/standard-model \
        --model-deep test-provider/deep-model --no-git-hooks --yes >/dev/null 2>"$dir/err.txt" || rc=$?
    err="$(cat "$dir/err.txt")"
    [ "$rc" -eq 2 ]; check "test_malformed_model_string_rejected" "exit $rc, want 2" $?
    has "$err" 'model tier "cheap" is malformed'; check "test_malformed_model_string_rejected" "stderr does not name the cheap tier as malformed: $err" $?
    has "$err" "provider/model"; check "test_malformed_model_string_rejected" "stderr omits the expected provider/model shape: $err" $?
    [ ! -e "$dir/cfg" ]; check "test_malformed_model_string_rejected" "files written for a malformed tier" $?
}

# The generator is invoked directly, bypassing install-opencode.sh's bash-side validate_tier, so an
# empty value must be refused by the generator itself before any file is written (AC4).
test_generator_direct_invocation_empty_tier_writes_nothing() {
    local dir="$WORK/empty-tier-direct" rc=0 err leftover
    mkdir -p "$dir/target"
    python3 -I "$GEN" --target "$dir/target" --model-cheap "test/cheap" \
        --model-standard "test/standard" --model-deep "" >/dev/null 2>"$dir/err.txt" || rc=$?
    err="$(cat "$dir/err.txt")"
    [ "$rc" -ne 0 ]; check "test_generator_direct_invocation_empty_tier_writes_nothing" "generator exited 0 on an empty deep tier" $?
    has "$err" "model tier 'deep' is not set"; check "test_generator_direct_invocation_empty_tier_writes_nothing" "stderr does not name the empty deep tier: $err" $?
    leftover="$(find "$dir/target" -mindepth 1 -print | head -n 5)"
    [ -z "$leftover" ]; check "test_generator_direct_invocation_empty_tier_writes_nothing" "files written before the tier check failed: $leftover" $?
}

test_opencode_json_mtime_unchanged() {
    local dir="$WORK/mtime" cfg="$WORK/mtime/cfg" rc=0 rc_bad=0 before_sha before_mt after_sha after_mt
    mkdir -p "$cfg"
    printf '{"provider": {"test": {"apiKey": "sentinel-key"}}}\n' >"$cfg/opencode.json"
    touch -d '2001-09-09 00:00:00 UTC' "$cfg/opencode.json"
    before_sha="$(sha256sum "$cfg/opencode.json" | cut -d' ' -f1)"
    before_mt="$(stat -c %Y "$cfg/opencode.json")"

    inst --target "$cfg" "${TIERS[@]}" --no-git-hooks --yes >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] && [ -f "$cfg/devkit/commands.json.sample" ]
    check "test_opencode_json_mtime_unchanged" "happy-path install did not complete (exit $rc)" $?
    after_sha="$(sha256sum "$cfg/opencode.json" | cut -d' ' -f1)"
    after_mt="$(stat -c %Y "$cfg/opencode.json")"
    [ "$after_sha" = "$before_sha" ] && [ "$after_mt" = "$before_mt" ]
    check "test_opencode_json_mtime_unchanged" "happy path changed opencode.json (mtime $before_mt -> $after_mt)" $?

    inst --target "$cfg" --model-cheap haiku --model-standard test-provider/standard-model \
        --model-deep test-provider/deep-model --no-git-hooks --yes >/dev/null 2>&1 || rc_bad=$?
    [ "$rc_bad" -eq 2 ]; check "test_opencode_json_mtime_unchanged" "error-path run exit $rc_bad, want 2" $?
    after_sha="$(sha256sum "$cfg/opencode.json" | cut -d' ' -f1)"
    after_mt="$(stat -c %Y "$cfg/opencode.json")"
    [ "$after_sha" = "$before_sha" ] && [ "$after_mt" = "$before_mt" ]
    check "test_opencode_json_mtime_unchanged" "error path changed opencode.json (mtime $before_mt -> $after_mt)" $?
}

test_check_and_dry_run_write_nothing() {
    local dir="$WORK/check" tgt="$WORK/check/target" mode label want rc before after
    local -a tiers
    mkdir -p "$tgt"
    printf 'user file\n' >"$tgt/user-file.txt"
    for mode in --check --dry-run; do
        for label in valid invalid; do
            if [ "$label" = valid ]; then
                tiers=("${TIERS[@]}"); want=0
            else
                tiers=(--model-cheap haiku --model-standard test-provider/standard-model --model-deep test-provider/deep-model); want=2
            fi
            before="$(snap_tree "$tgt")"
            rc=0
            inst --target "$tgt/install" "$mode" "${tiers[@]}" --no-git-hooks --yes >/dev/null 2>&1 || rc=$?
            [ "$rc" -eq "$want" ]; check "test_check_and_dry_run_write_nothing" "$mode with $label tiers: exit $rc, want $want" $?
            after="$(snap_tree "$tgt")"
            [ "$before" = "$after" ]; check "test_check_and_dry_run_write_nothing" "$mode with $label tiers changed the target tree" $?
            [ ! -e "$tgt/install" ]; check "test_check_and_dry_run_write_nothing" "$mode with $label tiers created the install directory" $?
        done
    done
}

test_project_and_target_mutually_exclusive() {
    local dir="$WORK/mutex" rc=0 err
    mkdir -p "$dir"
    inst --project "$dir/p" --target "$dir/t" "${TIERS[@]}" --no-git-hooks --yes >/dev/null 2>"$dir/err.txt" || rc=$?
    err="$(cat "$dir/err.txt")"
    [ "$rc" -eq 2 ]; check "test_project_and_target_mutually_exclusive" "exit $rc, want 2: $err" $?
    has "$err" "mutually exclusive"; check "test_project_and_target_mutually_exclusive" "stderr lacks the mutual-exclusion message: $err" $?
    ! has "$err" "model tier"; check "test_project_and_target_mutually_exclusive" "a model-tier message appeared before the flag error: $err" $?
    [ ! -e "$dir/p" ] && [ ! -e "$dir/t" ]; check "test_project_and_target_mutually_exclusive" "a target directory was created" $?
}

test_no_shell_injection_from_target_path() {
    local dir="$WORK/inject" sentinel="$WORK/inject/cwd/sentinel-pwned" rc=0
    mkdir -p "$dir/cwd"
    (cd "$dir/cwd" && inst --target "$dir/cwd/x; touch sentinel-pwned" "${TIERS[@]}" --no-git-hooks --yes >/dev/null 2>&1) || rc=$?
    [ ! -e "$sentinel" ]; check "test_no_shell_injection_from_target_path" "injected command ran: $sentinel exists (installer exit $rc)" $?
}

test_no_writes_outside_target() {
    local dir="$WORK/outside" target="$WORK/outside/target/install" rc=0 before after repo_before repo_after
    local home="$WORK/outside/home" xdg="$WORK/outside/xdg" tmp="$WORK/outside/tmp" cwd="$WORK/outside/cwd"
    mkdir -p "$home" "$xdg" "$tmp" "$cwd" "$WORK/outside/target"
    before="$(snap_tree "$home")$(snap_tree "$xdg")$(snap_tree "$tmp")$(snap_tree "$cwd")"
    repo_before="$(snap_tree "$ROOT" "$ROOT/.git")"
    (cd "$cwd" && env -u DEVKIT_OPENCODE_MODEL_CHEAP -u DEVKIT_OPENCODE_MODEL_STANDARD -u DEVKIT_OPENCODE_MODEL_DEEP \
        HOME="$home" XDG_CONFIG_HOME="$xdg" TMPDIR="$tmp" \
        bash "$INSTALL" --target "$target" "${TIERS[@]}" --no-git-hooks --yes >/dev/null 2>&1) || rc=$?
    [ "$rc" -eq 0 ] && [ -f "$target/devkit/commands.json.sample" ]
    check "test_no_writes_outside_target" "install did not complete into the target (exit $rc)" $?
    after="$(snap_tree "$home")$(snap_tree "$xdg")$(snap_tree "$tmp")$(snap_tree "$cwd")"
    repo_after="$(snap_tree "$ROOT" "$ROOT/.git")"
    # The status is captured before any command substitution in a detail string runs, or it would be diff's.
    local same=0 repo_same=0
    [ "$before" = "$after" ] || same=$?
    check "test_no_writes_outside_target" "paths changed outside the target (HOME/XDG/TMPDIR/cwd): $(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -3)" "$same"
    [ "$repo_before" = "$repo_after" ] || repo_same=$?
    check "test_no_writes_outside_target" "repository tree changed: $(diff <(printf '%s\n' "$repo_before") <(printf '%s\n' "$repo_after") | head -3)" "$repo_same"
}

test_commands_sample_written_and_never_merged() {
    local dir="$WORK/sample" cfg="$WORK/sample/cfg" out="$WORK/sample/stdout.txt" rc=0
    local sample="$cfg/devkit/commands.json.sample" snippet stdout err before_sha before_mt after_sha after_mt
    mkdir -p "$cfg"
    printf '{"provider": {"test": {"apiKey": "sentinel-key"}}}\n' >"$cfg/opencode.json"
    touch -d '2001-09-09 00:00:00 UTC' "$cfg/opencode.json"
    before_sha="$(sha256sum "$cfg/opencode.json" | cut -d' ' -f1)"
    before_mt="$(stat -c %Y "$cfg/opencode.json")"

    inst --target "$cfg" "${TIERS[@]}" --no-git-hooks --yes >"$out" 2>"$dir/stderr.txt" || rc=$?
    err="$(cat "$dir/stderr.txt")"
    [ "$rc" -eq 0 ]; check "test_commands_sample_written_and_never_merged" "installer exit $rc: $err" $?
    [ -f "$sample" ]; check "test_commands_sample_written_and_never_merged" "devkit/commands.json.sample not written" $?
    grep -qF '"command"' "$sample" 2>/dev/null; check "test_commands_sample_written_and_never_merged" "sample lacks the command JSON snippet" $?

    snippet="$(cat "$sample" 2>/dev/null)"
    stdout="$(cat "$out")"
    case "$stdout" in
        *"$snippet"*) check "test_commands_sample_written_and_never_merged" "" 0 ;;
        *) check "test_commands_sample_written_and_never_merged" "installer stdout lacks the sample snippet" 1 ;;
    esac

    after_sha="$(sha256sum "$cfg/opencode.json" | cut -d' ' -f1)"
    after_mt="$(stat -c %Y "$cfg/opencode.json")"
    [ "$after_sha" = "$before_sha" ] && [ "$after_mt" = "$before_mt" ]
    check "test_commands_sample_written_and_never_merged" "opencode.json was merged into or rewritten" $?
}

test_commands_sample_covers_every_generated_skill() {
    local dir="$WORK/cmds-cover" rc=0 msg
    mkdir -p "$dir"
    gen "$dir/out" >/dev/null 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 0 ]; check "test_commands_sample_covers_every_generated_skill" "generator exit $rc: $(cat "$dir/stderr.txt")" $?
    msg="$(python3 -I - "$dir/out" 2>&1 <<'PY'
import json, pathlib, sys
sys.excepthook = lambda kind, exc, tb: (print(f"{kind.__name__}: {exc}"), sys.exit(1))
out = pathlib.Path(sys.argv[1])
cmds = set(json.loads((out / "devkit/commands.json.sample").read_text(encoding="utf-8"))["command"])
skills = {p.name for p in (out / "skills").iterdir() if p.is_dir()}
if not skills or cmds != skills:
    print(f"sample keys {len(cmds)} != skill dirs {len(skills)}; missing={sorted(skills - cmds)}")
    sys.exit(1)
PY
)"
    [ -z "$msg" ]; check "test_commands_sample_covers_every_generated_skill" "$msg" $?
}

test_commands_sample_description_matches_frontmatter_dequoted() {
    local dir="$WORK/cmds-desc" rc=0 msg
    mkdir -p "$dir"
    gen "$dir/out" >/dev/null 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 0 ]; check "test_commands_sample_description_matches_frontmatter_dequoted" "generator exit $rc: $(cat "$dir/stderr.txt")" $?
    msg="$(python3 -I - "$dir/out" 2>&1 <<'PY'
import json, pathlib, re, sys
sys.excepthook = lambda kind, exc, tb: (print(f"{kind.__name__}: {exc}"), sys.exit(1))
out = pathlib.Path(sys.argv[1])
cmds = json.loads((out / "devkit/commands.json.sample").read_text(encoding="utf-8"))["command"]

def written_description(name):
    text = (out / "skills" / name / "SKILL.md").read_text(encoding="utf-8")
    value = re.search(r"^description:\s*(.*)$", text.split("\n---", 1)[0], re.M).group(1).strip()
    if len(value) >= 2 and value[0] in "'\"" and value[-1] == value[0]:
        value = value[1:-1]
    return value

for name in ("retro", "map"):
    got, want = cmds[name]["description"], written_description(name)
    if got != want:
        print(f"{name}: sample {got[:60]!r} != written SKILL.md {want[:60]!r}")
        sys.exit(1)
    if got[:1] in ("'", '"') and got[-1:] == got[:1]:
        print(f"{name}: outer quote left in {got[:40]!r}")
        sys.exit(1)
if "CLAUDE.md" in cmds["retro"]["description"]:
    print("retro sample describes CLAUDE.md, which is absent from the install")
    sys.exit(1)
PY
)"
    [ -z "$msg" ]; check "test_commands_sample_description_matches_frontmatter_dequoted" "$msg" $?
}

test_commands_sample_is_valid_json_despite_embedded_quotes() {
    local dir="$WORK/cmds-json" rc=0 msg
    mkdir -p "$dir"
    gen "$dir/out" >/dev/null 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 0 ]; check "test_commands_sample_is_valid_json_despite_embedded_quotes" "generator exit $rc: $(cat "$dir/stderr.txt")" $?
    msg="$(python3 -I - "$dir/out" 2>&1 <<'PY'
import json, pathlib, re, sys
sys.excepthook = lambda kind, exc, tb: (print(f"{kind.__name__}: {exc}"), sys.exit(1))
out = pathlib.Path(sys.argv[1])
try:
    cmds = json.loads((out / "devkit/commands.json.sample").read_text(encoding="utf-8"))["command"]
except (ValueError, KeyError) as exc:
    print(f"sample is not valid command JSON: {exc}")
    sys.exit(1)
text = (out / "skills" / "devkit-help" / "SKILL.md").read_text(encoding="utf-8")
want = re.search(r"^description:\s*(.*)$", text.split("\n---", 1)[0], re.M).group(1).strip()
if len(want) >= 2 and want[0] in "'\"" and want[-1] == want[0]:
    want = want[1:-1]
got = cmds["devkit-help"]["description"]
if '"' not in got:
    print("devkit-help description has no embedded quote; the row's precondition is not exercised")
    sys.exit(1)
if got != want:
    print(f"devkit-help description not byte-identical: {got[:60]!r} vs {want[:60]!r}")
    sys.exit(1)
PY
)"
    [ -z "$msg" ]; check "test_commands_sample_is_valid_json_despite_embedded_quotes" "$msg" $?
}

# mk_fixture_plugins <root> <skill description value> — the smallest plugins tree generate-opencode.py
# accepts, with one synthetic skill whose frontmatter description is the given raw YAML value.
mk_fixture_plugins() {
    local root="$1" desc="$2"
    mkdir -p "$root/coding-pipeline/git-hooks" "$root/coding-pipeline/agents" \
        "$root/coding-pipeline/scripts/verify" "$root/devtools/skills/fixture"
    printf '# Standards\n' >"$root/coding-pipeline/CLAUDE.md"
    printf -- '---\nname: coder\ndescription: core\nmodel: sonnet\n---\nbody\n' >"$root/coding-pipeline/agents/coder.md"
    printf 'x = 1\n' >"$root/coding-pipeline/scripts/estimate-run.py"
    printf 'x = 1\n' >"$root/coding-pipeline/scripts/harness-metrics.py"
    printf -- '---\nname: fixture\ndescription: %s\n---\nbody\n' "$desc" >"$root/devtools/skills/fixture/SKILL.md"
}

# gen_fixture <target> <plugins root> — the generator run against a synthetic tree (AC12 fixtures).
gen_fixture() {
    python3 -I "$GEN" --target "$1" --plugins-root "$2" --model-cheap "test-provider/cheap-model" \
        --model-standard "test-provider/standard-model" --model-deep "test-provider/deep-model"
}

test_commands_sample_unescapes_double_quoted_yaml_scalar() {
    local dir="$WORK/cmds-unescape" rc=0 msg
    mkdir -p "$dir"
    mk_fixture_plugins "$dir/pr" '"foo \"bar\" baz"'
    gen_fixture "$dir/out" "$dir/pr" >/dev/null 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 0 ]; check "test_commands_sample_unescapes_double_quoted_yaml_scalar" "generator exit $rc: $(cat "$dir/stderr.txt")" $?
    msg="$(python3 -I - "$dir/out" 2>&1 <<'PY'
import json, pathlib, sys
sys.excepthook = lambda kind, exc, tb: (print(f"{kind.__name__}: {exc}"), sys.exit(1))
out = pathlib.Path(sys.argv[1])
got = json.loads((out / "devkit/commands.json.sample").read_text(encoding="utf-8"))["command"]["fixture"]["description"]
want = 'foo "bar" baz'
if got != want:
    print(f"sample description {got!r} != {want!r}")
    sys.exit(1)
PY
)"
    [ -z "$msg" ]; check "test_commands_sample_unescapes_double_quoted_yaml_scalar" "$msg" $?
}

test_commands_sample_preserves_non_ascii_literally() {
    local dir="$WORK/cmds-nonascii" rc=0 msg
    mkdir -p "$dir"
    mk_fixture_plugins "$dir/pr" 'café résumé 日本語'
    gen_fixture "$dir/out" "$dir/pr" >/dev/null 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 0 ]; check "test_commands_sample_preserves_non_ascii_literally" "generator exit $rc: $(cat "$dir/stderr.txt")" $?
    msg="$(python3 -I - "$dir/out" 2>&1 <<'PY'
import pathlib, sys
sys.excepthook = lambda kind, exc, tb: (print(f"{kind.__name__}: {exc}"), sys.exit(1))
text = (pathlib.Path(sys.argv[1]) / "devkit/commands.json.sample").read_text(encoding="utf-8")
if "\\u" in text:
    print("sample holds \\uXXXX escapes instead of the literal UTF-8 characters")
    sys.exit(1)
if "café résumé 日本語" not in text:
    print("sample lacks the literal non-ASCII description")
    sys.exit(1)
PY
)"
    [ -z "$msg" ]; check "test_commands_sample_preserves_non_ascii_literally" "$msg" $?
}

test_commands_sample_template_explicitly_invokes_skill_tool() {
    local dir="$WORK/cmds-skill-tool" rc=0 msg
    mkdir -p "$dir"
    gen "$dir/out" >/dev/null 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 0 ]; check "test_commands_sample_template_explicitly_invokes_skill_tool" "generator exit $rc: $(cat "$dir/stderr.txt")" $?
    msg="$(python3 -I - "$dir/out" 2>&1 <<'PY'
import json, pathlib, sys
sys.excepthook = lambda kind, exc, tb: (print(f"{kind.__name__}: {exc}"), sys.exit(1))
out = pathlib.Path(sys.argv[1])
cmds = json.loads((out / "devkit/commands.json.sample").read_text(encoding="utf-8"))["command"]
template = cmds["planning"]["template"]
if "skill tool" not in template or '"planning"' not in template:
    print(f"template does not explicitly name the skill tool and id: {template!r}")
    sys.exit(1)
PY
)"
    [ -z "$msg" ]; check "test_commands_sample_template_explicitly_invokes_skill_tool" "$msg" $?
}

test_bare_plugin_root_reference_rewritten_to_devkit_path() {
    local dir="$WORK/bare-ref-rewrite" rc=0
    mkdir -p "$dir"
    gen "$dir/out" >/dev/null 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 0 ]; check "test_bare_plugin_root_reference_rewritten_to_devkit_path" "generator exit $rc: $(cat "$dir/stderr.txt")" $?
    has "$(cat "$dir/out/skills/planning/SKILL.md")" '`<devkit>/references/branching.md`'
    check "test_bare_plugin_root_reference_rewritten_to_devkit_path" "planning/SKILL.md still has the bare, unresolvable \`references/branching.md\` mention" $?
}

test_skill_local_reference_mention_left_unrewritten() {
    local dir="$WORK/skill-local-ref-unrewritten" rc=0
    mkdir -p "$dir"
    gen "$dir/out" >/dev/null 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 0 ]; check "test_skill_local_reference_mention_left_unrewritten" "generator exit $rc: $(cat "$dir/stderr.txt")" $?
    has "$(cat "$dir/out/skills/code/SKILL.md")" '`references/loop.md`'
    check "test_skill_local_reference_mention_left_unrewritten" "code/SKILL.md's own skill-local \`references/loop.md\` mention was rewritten (should be untouched)" $?
}

test_unresolvable_bare_reference_fails_loudly() {
    local dir="$WORK/unresolvable-ref" rc=0
    mkdir -p "$dir/pr"
    mk_fixture_plugins "$dir/pr" "fixture skill"
    printf -- '---\nname: fixture\ndescription: fixture skill\n---\nSee `references/does-not-exist.md` for details.\n' \
        >"$dir/pr/devtools/skills/fixture/SKILL.md"
    gen_fixture "$dir/out" "$dir/pr" >"$dir/stdout.txt" 2>"$dir/stderr.txt" || rc=$?
    [ "$rc" -eq 1 ]; check "test_unresolvable_bare_reference_fails_loudly" "generator exit $rc (want 1)" $?
    has "$(cat "$dir/stderr.txt")" "does-not-exist.md"
    check "test_unresolvable_bare_reference_fails_loudly" "stderr does not name the unresolved reference: $(cat "$dir/stderr.txt")" $?
    [ ! -d "$dir/out" ] || [ -z "$(ls -A "$dir/out" 2>/dev/null)" ]
    check "test_unresolvable_bare_reference_fails_loudly" "target holds files despite the unresolvable reference: $(ls -RA "$dir/out" 2>/dev/null)" $?
}

test_missing_model_tier_exits_nonzero_naming_tier
test_malformed_model_string_rejected
test_generator_direct_invocation_empty_tier_writes_nothing
test_opencode_json_mtime_unchanged
test_check_and_dry_run_write_nothing
test_project_and_target_mutually_exclusive
test_no_shell_injection_from_target_path
test_no_writes_outside_target
test_commands_sample_written_and_never_merged
test_symlinked_project_dir_rejected
test_symlinked_default_config_dir_rejected
test_symlinked_target_ancestor_rejected
test_multi_level_symlinked_ancestor_rejected
test_dotdot_through_missing_dir_rejected
test_dotdot_with_preexisting_dir_still_caught_by_walk
test_commands_sample_covers_every_generated_skill
test_commands_sample_description_matches_frontmatter_dequoted
test_commands_sample_is_valid_json_despite_embedded_quotes
test_commands_sample_unescapes_double_quoted_yaml_scalar
test_commands_sample_preserves_non_ascii_literally
test_commands_sample_template_explicitly_invokes_skill_tool
test_bare_plugin_root_reference_rewritten_to_devkit_path
test_skill_local_reference_mention_left_unrewritten
test_unresolvable_bare_reference_fails_loudly

echo "opencode tests: $pass passed, exit=$fail"
[ "$fail" -eq 0 ]
