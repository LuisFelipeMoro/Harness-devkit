#!/usr/bin/env bash
# Behaviour tests for scripts/verify/ — the mechanical halves of QA, Reviewer and
# Verdict. Each one replaced a model pass, so each one is now the only thing
# checking what it checks. The cases below pin the direction that matters: a
# sensor must never print PASS for something it did not actually see.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
V="$ROOT/plugins/coding-pipeline/scripts/verify"
W="$(mktemp -d "${TMPDIR:-/tmp}/devkit-verify.XXXXXX")"
pass=0; fail=0

check() {   # check <name> <want-exit> <got-exit> [<output> <needle>]
    local ok=1
    [ "$2" = "$3" ] || ok=0
    if [ $# -ge 5 ]; then case "$4" in *"$5"*) ;; *) ok=0 ;; esac; fi
    if [ "$ok" = 1 ]; then pass=$((pass + 1)); else echo "FAIL: $1 — exit $3 (want $2)${5:+, missing '$5'}"; fail=1; fi
}

mkrepo() {  # mkrepo <dir> — create test repo with main/release/feat branches
    local dir="$1"
    mkdir -p "$dir" && cd "$dir" || exit
    git init -q -b main
    printf 'base\n' > base.txt
    git -c user.email=t@t -c user.name=t add base.txt
    git -c user.email=t@t -c user.name=t commit -q -m "base"
    git checkout -q -b release/x-abc
    git checkout -q -b feat/abc-s1
    cd - >/dev/null || exit
}

write_dup_filler() {  # write_dup_filler <path> — a harmless Go file sized
    # comfortably past dup-gate's own --min-lines/--min-tokens floor, so a
    # checkpoint-m.sh fixture that must clear the duplication check isn't
    # reported as "0 lines" against a repo whose only real content is a
    # one-line test stub.
    cat > "$1" <<'GOEOF'
package main

func dupFillerA(t *testing.T) {
	x := 1
	y := 2
	z := x + y
	_ = z
}

func dupFillerB(t *testing.T) {
	x := 1
	y := 2
	z := x + y
	_ = z
}
GOEOF
}

# ── spec-coverage / falsification: names that share a prefix ────────────────
# `TestParsesToken` and `TestParsesTokenWithExpiry` is an ordinary naming pair.
# A substring match lets the longer one satisfy the shorter one's row — a PASS
# with a specified test never written.
cat > "$W/story.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestParsesToken` | a | b |
| `TestParsesTokenWithExpiry` | a | b |
MD
mkdir -p "$W/only-long" "$W/both"
printf 'func TestParsesTokenWithExpiry(t *testing.T) {}\n' > "$W/only-long/x_test.go"
printf 'func TestParsesToken(t *testing.T) {}\nfunc TestParsesTokenWithExpiry(t *testing.T) {}\n' > "$W/both/x_test.go"

out=$(bash "$V/spec-coverage.sh" "$W/story.md" "$W/only-long" 2>&1); rc=$?
check "spec-coverage: prefix-sharing test does not cover the shorter row" 1 "$rc" "$out" "MISSING ROW: TestParsesToken"
out=$(bash "$V/spec-coverage.sh" "$W/story.md" "$W/both" 2>&1); rc=$?
check "spec-coverage: both implemented passes" 0 "$rc" "$out" "2/2"

printf 'TestParsesTokenWithExpiry: FAIL expected 3 got 2\n' > "$W/done-long.txt"
out=$(bash "$V/falsification.sh" "$W/done-long.txt" "$W/story.md" 2>&1); rc=$?
check "falsification: evidence for the longer name is not evidence for the shorter" 1 "$rc" "$out" "NO EVIDENCE: TestParsesToken"
printf 'TestParsesToken: FAIL expected 1 got 0\nTestParsesTokenWithExpiry: FAIL expected 3 got 2\n' > "$W/done-both.txt"
bash "$V/falsification.sh" "$W/done-both.txt" "$W/story.md" >/dev/null 2>&1; rc=$?
check "falsification: evidence for both passes" 0 "$rc"

# ── falsification: a prose-only row gets a wiring check, not a break (AC30) ──
# A Falsified By cell starting `n/a — Markdown` needs a `wiring:` line naming the
# row and no assertion. Every other row keeps the assertion rule. The keyword
# checks read the evidence text after the row name, so a name such as "...needs
# an assertion" cannot satisfy them on its own.
cat > "$W/story-mixed.md" <<'MD'
| Test Name | Input | Expected | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| `falsification: markdown row accepts wiring evidence` | a | b | AC30 | c | n/a — Markdown, wiring check |
| `falsification: code row still needs an assertion` | a | b | AC30 | c | delete the guard |
MD
cat > "$W/story-prose.md" <<'MD'
| Test Name | Input | Expected | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| `falsification: markdown row without wiring evidence fails` | a | b | AC30 | c | n/a — Markdown, wiring check |
MD
cat > "$W/story-code.md" <<'MD'
| Test Name | Input | Expected | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| `falsification: code row still needs an assertion` | a | b | AC30 | c | delete the guard |
MD
printf '%s\n' \
    'falsification: markdown row accepts wiring evidence ← wiring: paths resolve · validate-wiring OK · verify 1 passed' \
    'falsification: code row still needs an assertion ← FAIL expected 1 got 0' > "$W/ev-mixed.txt"
printf 'falsification: code row still needs an assertion ← wiring: paths resolve · validate-wiring OK\n' > "$W/ev-code-wiring.txt"
printf 'falsification: markdown row without wiring evidence fails ← FAIL expected 1 got 0\n' > "$W/ev-assert-only.txt"
: > "$W/ev-none.txt"

out=$(bash "$V/falsification.sh" "$W/ev-mixed.txt" "$W/story-mixed.md" 2>&1); rc=$?
check "falsification: markdown row accepts wiring evidence" 0 "$rc" "$out" "1 falsified · 1 wiring-checked"
out=$(bash "$V/falsification.sh" "$W/ev-code-wiring.txt" "$W/story-code.md" 2>&1); rc=$?
check "falsification: code row still needs an assertion" 1 "$rc" "$out" "NO ASSERTION QUOTED"
out=$(bash "$V/falsification.sh" "$W/ev-none.txt" "$W/story-prose.md" 2>&1); rc=$?
check "falsification: markdown row without wiring evidence fails" 1 "$rc" "$out" "NO EVIDENCE: falsification: markdown row without wiring evidence fails"
out=$(bash "$V/falsification.sh" "$W/ev-assert-only.txt" "$W/story-prose.md" 2>&1); rc=$?
check "falsification: markdown row without wiring evidence fails" 1 "$rc" "$out" "NO WIRING EVIDENCE: falsification: markdown row without wiring evidence fails"

# ── standards: prose rows are named wherever a break used to be demanded ─────
test_markdown_wiring_standards() {  # the phrase lives in each guide that demands a break, and QA names the MAJOR
    local bad=0 f phrase='n/a — Markdown, wiring check' P="$ROOT/plugins/coding-pipeline"
    for f in CLAUDE.md agents/coder.md agents/qa.md agents/plan-reviewer.md references/plan-template.md skills/code/references/loop.md; do
        grep -qF -- "$phrase" "$P/$f" || { echo "$f does not name '$phrase'"; bad=1; }
    done
    grep -F 'MAJOR' "$P/agents/qa.md" | grep -qF 'n/a — Markdown' || { echo "qa.md does not name the MAJOR for a code row marked n/a"; bad=1; }
    [ "$bad" = 0 ]
}
test_markdown_wiring_standards; rc=$?
check "standards: markdown rows get a wiring check" 0 "$rc"

# ── progress schema (3.4.0 T8, AC10): wiring checks, prose rows ─────────────
PF="$ROOT/plugins/coding-pipeline/references/progress-file.md"
PH="$ROOT/plugins/devtools/skills/handoff/references/progress-file.md"
HS="$ROOT/plugins/devtools/skills/handoff/SKILL.md"
CM="$ROOT/plugins/coding-pipeline/CLAUDE.md"
schema_block() {  # schema_block <file> — the first fenced ```markdown block, fences excluded
    awk '/^```markdown$/ {f=1; next} /^```$/ {if (f) exit} f' "$1"
}
test_progress_entry_format() {  # the entry heading, the Lessons bullet and the append rule are all named; no _Last updated:
    grep -qF -- '## [{slug}] YYYY-MM-DD — {title}' "$PF" &&
        grep -qF -- '- Lessons:' "$PF" && grep -qF -- 'never rewritten' "$PF" &&
        ! grep -qF -- '_Last updated:' "$PF"
}
test_progress_entry_format; rc=$?
check "progress-file: schema documents the entry format" 0 "$rc"

test_progress_mirror_equal() {  # the handoff copy's fenced block is byte-equal to the canonical one, and not empty
    local a b
    a=$(schema_block "$PF"); b=$(schema_block "$PH")
    [ -n "$a" ] && [ "$a" = "$b" ] && grep -qF -- 'Canonical elsewhere' "$PH"
}
test_progress_mirror_equal; rc=$?
check "progress-file: handoff mirror carries the same schema block" 0 "$rc"

test_handoff_reads_and_appends() {  # step 1 reads row status from tasks_state; step 3 appends one entry, no rewrite
    grep -qF -- 'tasks_state.py status' "$HS" && grep -qF -- 'append one entry' "$HS" &&
        ! grep -qF -- 'rewrite `Current State`' "$HS"
}
test_handoff_reads_and_appends; rc=$?
check "handoff: reads row status and appends one entry" 0 "$rc"

test_claude_md_memory_bullet() {  # the Memory bullet names the entry heading and tasks.json; both hook rows name their new duties
    local mem
    mem=$(grep -F -- '**Memory & Progress**' "$CM")
    case "$mem" in *'## [slug]'*) ;; *) return 1 ;; esac
    case "$mem" in *tasks.json*) ;; *) return 1 ;; esac
    grep -F -- '`session-bootstrap.sh`' "$CM" | grep -qF -- 'Lessons' &&
        grep -F -- '`delivery-gate.sh`' "$CM" | grep -qF -- 'devkit-break' &&
        grep -qF -- 'pre:write:tasks-state' "$CM"
}
test_claude_md_memory_bullet; rc=$?
check "claude-md: Memory bullet names entry format and tasks.json" 0 "$rc"

# ── row state in /code and the resume protocol (3.4.0 T9, AC11 · AC12): wiring checks, prose rows ──
CS="$ROOT/plugins/coding-pipeline/skills/code/SKILL.md"
CL="$ROOT/plugins/coding-pipeline/skills/code/references/loop.md"
PT="$ROOT/plugins/coding-pipeline/references/plan-template.md"
PP="$ROOT/plugins/coding-pipeline/skills/planning/references/phases.md"
test_code_loop_resume() {  # the Resume section names bearings (verify, marker list), restore, repair and smoke
    local sec
    sec=$(awk '/^## Resume$/ {f=1; next} /^## / {f=0} f' "$CL")
    [ -n "$sec" ] || return 1
    grep -qF -- 'tasks_state.py verify' <<<"$sec" &&
        grep -qF -- "find . -name '*.devkit-break'" <<<"$sec" &&
        grep -qF -- 'pgrep -f break-run.sh' <<<"$sec" &&
        grep -qF -- 'cp -p M F && cmp -s M F && rm M' <<<"$sec" &&
        grep -qF -- 'repair, not trust' <<<"$sec" &&
        grep -qF -- '**Smoke**' <<<"$sec"
}
test_code_loop_resume; rc=$?
check "code-loop: Resume section lists bearings, restore, repair and smoke" 0 "$rc"

test_code_skill_row_state() {  # SKILL.md calls init, set (in_progress / done with an M: PASS line) and status; routes on the three states
    grep -qF -- 'tasks_state.py init' "$CS" && grep -qF -- 'set {ID} in_progress' "$CS" &&
        grep -qF -- 'set {ID} done --evidence "M: PASS' "$CS" && grep -qF -- 'tasks_state.py status' "$CS" &&
        grep -qF -- '{n}/{n} done' "$CS" && grep -qF -- 'every row `done` → Final proof' "$CS" &&
        grep -qF -- 'all `todo` → fresh run' "$CS" && grep -qF -- 'loop.md` § Resume' "$CS" &&
        grep -qF -- 'failed' "$CS"
}
test_code_skill_row_state; rc=$?
check "code-skill: row state calls init, set and status" 0 "$rc"

# ── falsification moves to Final proof (3.4.0 T13, AC17): wiring checks, prose rows ──
# Markdown wiring check: the Final proof section names the gates once, the FINAL-PROOF dispatch,
# the re-break sample and the --spec/--gates checkpoint; the per-row checkpoint runs without --gates.
test_code_loop_final_proof() {
    local fp mc
    fp=$(awk '/^## Final proof$/ {f=1; next} /^## / {f=0} f' "$CL")
    mc=$(awk '/^## Checkpoint M/ {f=1; next} /^## / {f=0} f' "$CL")
    [ -n "$fp" ] && [ -n "$mc" ] || return 1
    grep -qF -- "Gates:" <<<"$fp" &&
        grep -qF -- 'Task: FINAL-PROOF' <<<"$fp" &&
        grep -qF -- 're-break' <<<"$fp" &&
        grep -qF -- 'checkpoint-m.sh --base $START --spec docs/plans/{slug}/plan.md' <<<"$fp" &&
        grep -qF -- '--gates "<plan Gates>"' <<<"$fp" &&
        grep -qF -- 'n/a — Markdown, wiring check' <<<"$fp" &&
        grep -qF -- 'without `--gates`' <<<"$mc" &&
        ! grep -qF -- 'main session still re-breaks' "$CL"
}
test_code_loop_final_proof; rc=$?
check "code-loop: Final proof runs gates once then falsifies every code row" 0 "$rc"

test_code_loop_final_proof_language() {  # step 2 passes each row's Language, labels prose lines wiring:, routes NOT FALSIFIED to step 5
    local fp
    fp=$(awk '/^## Final proof$/ {f=1; next} /^## / {f=0} f' "$CL")
    [ -n "$fp" ] || return 1
    grep -qF -- 'Language of each row, from its Tasks row' <<<"$fp" &&
        grep -qF -- 'one dispatch per `Language`' <<<"$fp" &&
        grep -qF -- '`wiring:` line' <<<"$fp" &&
        grep -qF -- 'NOT FALSIFIED' <<<"$fp" &&
        grep -qF -- 'a `NOT FALSIFIED` line from step 2' <<<"$fp" &&
        ! grep -qF -- 'Wiring check:' <<<"$fp"
}
test_code_loop_final_proof_language; rc=$?
check "code-loop: Final proof names each row's Language and reports unfalsified rows" 0 "$rc"

test_coder_final_proof_timing() {  # the core and both overlays put Phase 3 in FINAL-PROOF; a row dispatch skips it
    local f
    for f in "$ROOT/plugins/coding-pipeline/agents/coder.md" "$ROOT/plugins/coding-pipeline/agents/coder-frontend.md" \
        "$ROOT/plugins/coding-pipeline/agents/coder-backend.md"; do
        grep -qF -- 'FINAL-PROOF' "$f" || return 1
    done
    grep -qF -- 'A row dispatch stops after Phase 2' "$ROOT/plugins/coding-pipeline/agents/coder.md" &&
        grep -qF -- 'without falsification lines' "$ROOT/plugins/coding-pipeline/agents/coder.md" &&
        grep -qF -- 'Phase 3 runs only in a `FINAL-PROOF` dispatch' "$ROOT/plugins/coding-pipeline/agents/coder.md" &&
        grep -qF -- '**Bug fixes are the one place a test comes first**' "$ROOT/plugins/coding-pipeline/agents/coder.md"
}
test_coder_final_proof_timing; rc=$?
check "coder: row dispatch skips Phase 3 and FINAL-PROOF runs it" 0 "$rc"

test_claude_md_step4_final_proof() {  # CLAUDE.md step 4 names the Final proof stage; the bug-fix exception stays
    local c="$ROOT/plugins/coding-pipeline/CLAUDE.md"
    grep -E '^4\. \*\*Falsify\*\*' "$c" | grep -qF -- "Final proof" &&
        grep -qF -- '**Bug fixes are the one exception**' "$c" &&
        grep -qF -- 'Falsify** — the evidence step that replaces RED' "$c"
}
test_claude_md_step4_final_proof; rc=$?
check "claude-md: Spec-First step 4 falsifies in Final proof" 0 "$rc"

test_plan_template_gates() {  # the first fenced block of the template carries a Gates: line in its header
    schema_block "$PT" | grep -qE '^Gates: `.+`$'
}
test_plan_template_gates; rc=$?
check "plan-template: header carries a Gates line" 0 "$rc"

test_planning_phase4_gates() {  # Phase 4 names the Gates: line and the quality-gate reference it is filled from
    local sec
    sec=$(awk '/^## Phase 4 / {f=1; next} /^## / {f=0} f' "$PP")
    [ -n "$sec" ] || return 1
    case "$sec" in *'Gates:'*) ;; *) return 1 ;; esac
    case "$sec" in *'quality-gate-reference.md'*) ;; *) return 1 ;; esac
}
test_planning_phase4_gates; rc=$?
check "planning: Phase 4 fills the Gates line" 0 "$rc"

# ── security-scan: "0 candidates" must mean scanned, not skipped ────────────
out=$(bash "$V/security-scan.sh" "" 2>&1); rc=$?
check "security-scan: empty path is UNMEASURED, not 0 candidates" 2 "$rc" "$out" "UNMEASURED"
bash "$V/security-scan.sh" "$W/does-not-exist" >/dev/null 2>&1; rc=$?
check "security-scan: missing path is UNMEASURED" 2 "$rc"
# Prose that names a dangerous call is not a call; code that makes one is.
mkdir -p "$W/sec"
printf 'Never use eval( on input.\n' > "$W/sec/guide.md"
printf 'const r = eval(userInput);\n' > "$W/sec/app.js"
out=$(bash "$V/security-scan.sh" "$W/sec" 2>&1); rc=$?
check "security-scan: code hit reported" 0 "$rc" "$out" "app.js:1"
case "$out" in *guide.md*) echo "FAIL: security-scan: markdown prose reported as a candidate"; fail=1 ;; *) pass=$((pass + 1)) ;; esac

# ── tautology-scan: zero files is unmeasured ─────────────────────────────────
mkdir -p "$W/no-tests"; printf 'x=1\n' > "$W/no-tests/app.py"
out=$(python3 "$V/tautology-scan.py" "$W/no-tests" 2>&1); rc=$?
check "tautology-scan: 0 test files is UNMEASURED, not PASS" 2 "$rc" "$out" "UNMEASURED"

# ── verdict.sh: the average must not hide a lens under its floor ─────────────
out=$(bash "$V/verdict.sh" --review 10 --stress 6.9 --qa 10 2>&1); rc=$?
check "verdict: stress below story floor is NOT READY despite 8.9 average" 1 "$rc" "$out" "below story floor"
bash "$V/verdict.sh" --review 9 --stress 9 --qa 9 >/dev/null 2>&1; rc=$?
check "verdict: all lenses over floor is PRODUCTION READY" 0 "$rc"
bash "$V/verdict.sh" --review 1.2.3 --stress 9 --qa 9 >/dev/null 2>&1; rc=$?
check "verdict: malformed score is a usage error, not a traceback" 2 "$rc"

# ── verdict.sh --no-review: /validate-code's verdict stands without a review score ──
# /review-pr is a separate skill with its own pass/block, so the code verdict renormalises
# Stress and QA instead of waiting for — or inventing — a reviewer score.
out=$(bash "$V/verdict.sh" --no-review --stress 9 --qa 9 2>&1); rc=$?
check "verdict: no-review with qa and stress over floor is PRODUCTION READY" 0 "$rc" "$out" "Overall Score: 9.00/10"
out=$(bash "$V/verdict.sh" --no-review --stress 10 --qa 6 2>&1); rc=$?
check "verdict: no-review renormalises stress 35 and qa 30 over 65" 0 "$rc" "$out" "Overall Score: 8.15/10"
out=$(bash "$V/verdict.sh" --no-review --stress 6.9 --qa 10 2>&1); rc=$?
check "verdict: no-review keeps the stress floor" 1 "$rc" "$out" "below story floor"
out=$(bash "$V/verdict.sh" --no-review --stress 9 --qa 9 --hard-gate-fail lint 2>&1); rc=$?
check "verdict: no-review hard gate fail is NOT READY" 1 "$rc" "$out" "hard gate FAIL: lint"
bash "$V/verdict.sh" --no-review --review 9 --stress 9 --qa 9 >/dev/null 2>&1; rc=$?
check "verdict: no-review rejects a review score" 2 "$rc"
bash "$V/verdict.sh" --no-review --stress 9 >/dev/null 2>&1; rc=$?
check "verdict: no-review without qa is usage" 2 "$rc"
bash "$V/verdict.sh" --no-review --qa 9 >/dev/null 2>&1; rc=$?
check "verdict: no-review without stress or --no-stress is usage" 2 "$rc"

# ── verdict.sh --no-review --no-stress: /validate-code at light depth ──────────
# classify-diff found no Stress trigger in a ≤ 2-file change, so stress is not
# dispatched; the score is QA alone (30 renormalised over 30), never a stress score
# nobody produced, and the stress floor has no lens to apply to.
out=$(bash "$V/verdict.sh" --no-review --no-stress --qa 9 2>&1); rc=$?
check "verdict: no-stress scores qa alone" 0 "$rc" "$out" "Overall Score: 9.00/10"
check "verdict: no-stress says which lenses are absent" 0 "$rc" "$out" "no review or stress lens"
out=$(bash "$V/verdict.sh" --no-review --no-stress --qa 7.5 2>&1); rc=$?
check "verdict: no-stress below 8 is READY WITH CONDITIONS" 1 "$rc" "$out" "Overall Score: 7.50/10"
out=$(bash "$V/verdict.sh" --no-review --no-stress --qa 9 --hard-gate-fail lint 2>&1); rc=$?
check "verdict: no-stress hard gate fail is NOT READY" 1 "$rc" "$out" "hard gate FAIL: lint"
out=$(bash "$V/verdict.sh" --no-review --no-stress --qa 9 --critical-security 1 2>&1); rc=$?
check "verdict: no-stress unmitigated CRITICAL security is NOT READY" 1 "$rc" "$out" "VERDICT: NOT READY"
bash "$V/verdict.sh" --no-review --no-stress --stress 9 --qa 9 >/dev/null 2>&1; rc=$?
check "verdict: no-stress rejects a stress score" 2 "$rc"
bash "$V/verdict.sh" --no-stress --roster light --classify-exit 0 --review 8 --stress 8 >/dev/null 2>&1; rc=$?
check "verdict: no-stress without no-review is usage, never silently ignored" 2 "$rc"
bash "$V/verdict.sh" --no-review --no-stress >/dev/null 2>&1; rc=$?
check "verdict: no-stress without qa is usage" 2 "$rc"

# Test 2: verdict roster path hides score on hard-gate fail like legacy
out=$(bash "$V/verdict.sh" --roster standard --classify-exit 0 --review 9 --stress 9 --qa 9 --hard-gate-fail lint 2>&1); rc=$?
check "verdict: roster path hides score on hard-gate fail like legacy" 1 "$rc" "$out" "NOT READY"
case "$out" in *"Overall Score"*) echo "FAIL: verdict: roster path hides score on hard-gate fail like legacy — score was printed"; fail=1 ;; *) pass=$((pass + 1)) ;; esac

# Test 3: verdict unknown roster value is usage
bash "$V/verdict.sh" --roster huge --classify-exit 0 >/dev/null 2>&1; rc=$?
check "verdict: unknown roster value is usage" 2 "$rc"

# ── security-scan --diff: diff-scoped candidates ────────────────
# TV-S0a: positional mode unchanged on code hit — reuses the "$W/sec" fixture
# built above (guide.md + app.js), no need to recreate it.
out=$(bash "$V/security-scan.sh" "$W/sec" 2>&1); rc=$?
check "security-scan: positional mode unchanged on code hit" 0 "$rc" "$out" "app.js:1"

# TV-S0b: empty path still UNMEASURED (preserved test)
out=$(bash "$V/security-scan.sh" "" 2>&1); rc=$?
check "security-scan: empty path still UNMEASURED" 2 "$rc" "$out" "UNMEASURED"

# Scans only changed files
repo1="$W/repo1"
mkrepo "$repo1"
cd "$repo1" || exit
# Switch to release/x-abc and add old.js
git checkout -q release/x-abc || exit
printf 'eval(x)\n' > old.js
git -c user.email=t@t -c user.name=t add old.js
git -c user.email=t@t -c user.name=t commit -q -m "release with old.js"
# Switch to feat/abc-s1 and add new.js
git checkout -q feat/abc-s1 || exit
printf 'fetch(url)\n' > new.js
git -c user.email=t@t -c user.name=t add new.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add new.js"
# Add another file with a security pattern to test multiple commits
printf 'eval(x)\n' > newer.js
git -c user.email=t@t -c user.name=t add newer.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add newer.js"
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: scans only changed files" 0 "$rc" "$out" "new.js:1"
case "$out" in *newer.js:1*) pass=$((pass + 1)) ;; *) echo "FAIL: security-scan --diff: scans only changed files — missing newer.js:1"; fail=1 ;; esac
case "$out" in *old.js*) echo "FAIL: security-scan --diff: scans only changed files — old.js (outside the diff) leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# Empty diff is UNMEASURED
repo2="$W/repo2"
mkrepo "$repo2"
cd "$repo2" || exit
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: empty diff is UNMEASURED" 2 "$rc" "$out" "empty diff"
cd - >/dev/null || exit

# Only-deleted diff is UNMEASURED
repo2b="$W/repo2b"
mkrepo "$repo2b"
cd "$repo2b" || exit
# On feat/abc-s1, delete base.txt (exists on both branches from mkrepo)
git checkout -q feat/abc-s1 || exit
git rm -q base.txt
git -c user.email=t@t -c user.name=t commit -q -m "feat: remove base.txt"
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: only-deleted diff is UNMEASURED" 2 "$rc" "$out" "empty diff"
cd - >/dev/null || exit

# Newline in file name is scanned: a `tr '\0' '\n'` split
# on the NUL-separated git diff list turns one file with an embedded newline
# into two missing paths, silently dropping it out of the scan.
repo2c="$W/repo2c"
mkrepo "$repo2c"
cd "$repo2c" || exit
nlfile=$'evil\nline.js'
printf 'eval(x)\n' > "$nlfile"
git -c user.email=t@t -c user.name=t add -- "$nlfile"
git -c user.email=t@t -c user.name=t commit -q -m "feat: add file with newline in name"
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: newline in file name is scanned" 0 "$rc" "$out" "line.js"
cd - >/dev/null || exit

# Symlink in diff is never silent: grep does not follow a
# file symlink, so handing one to grep like any other file reads as 0
# candidates instead of surfacing it for adjudication.
repo2d="$W/repo2d"
mkrepo "$repo2d"
cd "$repo2d" || exit
ln -s ../outside.js link.js
git -c user.email=t@t -c user.name=t add link.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add symlink"
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: symlink in diff is never silent" 0 "$rc" "$out" "[SYMLINK] "
case "$out" in *link.js*) pass=$((pass + 1)) ;; *) echo "FAIL: security-scan --diff: symlink in diff is never silent — link.js path missing from [SYMLINK] output"; fail=1 ;; esac
cd - >/dev/null || exit

# Pathspec limits the scan: a pathspec argument after the
# base must actually narrow the diff, not be accepted and silently ignored.
repo2e="$W/repo2e"
mkrepo "$repo2e"
cd "$repo2e" || exit
mkdir -p a b
printf 'eval(x)\n' > a/x.js
printf 'eval(x)\n' > b/y.js
git -c user.email=t@t -c user.name=t add a/x.js b/y.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add a and b"
out=$(bash "$V/security-scan.sh" --diff release/x-abc -- a 2>&1); rc=$?
check "security-scan --diff: pathspec limits the scan" 0 "$rc" "$out" "a/x.js:1"
case "$out" in *b/y.js*) echo "FAIL: security-scan --diff: pathspec limits the scan — b/y.js leaked outside the 'a' pathspec"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# git diff failure is reported: a real `git diff` failure
# must not be read as an empty diff. Stub `git` on PATH so every subcommand
# passes through to the real binary except `diff`, which exits 128.
repo2f="$W/repo2f"
mkrepo "$repo2f"
cd "$repo2f" || exit
realgit="$(command -v git)"
stubdir="$W/stubbin"
mkdir -p "$stubdir"
cat > "$stubdir/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "diff" ]; then
    exit 128
fi
exec "$realgit" "\$@"
STUB
chmod +x "$stubdir/git"
out=$(PATH="$stubdir:$PATH" bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: git diff failure is reported" 2 "$rc" "$out" "git diff failed"
cd - >/dev/null || exit

# Dirty tree is UNMEASURED
repo3="$W/repo3"
mkrepo "$repo3"
cd "$repo3" || exit
printf 'untracked\n' > untracked.js
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: dirty tree is UNMEASURED" 2 "$rc" "$out" "uncommitted"
cd - >/dev/null || exit

# Path with space
repo4="$W/repo4"
mkrepo "$repo4"
cd "$repo4" || exit
printf 'eval(x)\n' > 'a b.js'
git -c user.email=t@t -c user.name=t add 'a b.js'
git -c user.email=t@t -c user.name=t commit -q -m "add space"
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: path with space" 0 "$rc" "$out" "a b.js:1"
cd - >/dev/null || exit

# Rename scans new path
repo5="$W/repo5"
mkrepo "$repo5"
cd "$repo5" || exit
# Switch to feat/abc-s1, add old.js and rename it
printf 'eval(x)\n' > old.js
git -c user.email=t@t -c user.name=t add old.js
git -c user.email=t@t -c user.name=t commit -q -m "add old.js"
git mv old.js moved.js
git -c user.email=t@t -c user.name=t commit -q -m "rename"
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: rename scans new path" 0 "$rc" "$out" "moved.js:1"
cd - >/dev/null || exit

# Only md/tests is UNMEASURED
repo6="$W/repo6"
mkrepo "$repo6"
cd "$repo6" || exit
printf '# doc\n' > x.md
printf 'test\n' > a_test.go
git -c user.email=t@t -c user.name=t add x.md a_test.go
git -c user.email=t@t -c user.name=t commit -q -m "docs"
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan --diff: only md/tests is UNMEASURED" 2 "$rc" "$out" "no scannable source"
cd - >/dev/null || exit

# STRESS-TRIGGER yes on route
mkdir -p "$W/route"
printf 'app.get("/x"\n' > "$W/route/app.js"
out=$(bash "$V/security-scan.sh" "$W/route" 2>&1); rc=$?
check "security-scan: STRESS-TRIGGER yes on route" 0 "$rc" "$out" "STRESS-TRIGGER: yes (AUTH-SURFACE)"

# STRESS-TRIGGER no on pure logic
mkdir -p "$W/logic"
printf 'const a = b + 1;\n' > "$W/logic/app.js"
out=$(bash "$V/security-scan.sh" "$W/logic" 2>&1); rc=$?
check "security-scan: STRESS-TRIGGER no on pure logic" 0 "$rc" "$out" "STRESS-TRIGGER: no"

# SHARED-STATE tag
mkdir -p "$W/shared"
printf 'var mu sync.Mutex\n' > "$W/shared/lock.go"
out=$(bash "$V/security-scan.sh" "$W/shared" 2>&1); rc=$?
check "security-scan: SHARED-STATE tag" 0 "$rc" "$out" "[SHARED-STATE]"
case "$out" in *"STRESS-TRIGGER: yes (SHARED-STATE)"*) pass=$((pass + 1)) ;; *) fail=1 ;; esac

out=$(bash "$V/security-scan.sh" --diff -x 2>&1); rc=$?
check "security-scan --diff: rejects option-shaped base" 2 "$rc" "$out" "invalid base ref"

out=$(bash "$V/security-scan.sh" --diff 'a;touch' 2>&1); rc=$?
check "security-scan --diff: rejects metacharacter base" 2 "$rc" "$out" "invalid base ref"
[ ! -e "$W/pwn" ] || { fail=1; }

out=$(bash "$V/security-scan.sh" --diff 'main..HEAD' 2>&1); rc=$?
check "security-scan --diff: rejects range base" 2 "$rc" "$out" "invalid base ref"

out=$(bash "$V/security-scan.sh" --diff release/nope 2>&1); rc=$?
check "security-scan --diff: unknown ref" 2 "$rc" "$out" "unknown base ref"

# ── tautology-scan --diff: diff-scoped tautology detection ──────

# TV-T0: positional 0 files still UNMEASURED (preserved; reuses "$W/no-tests"
# built above for the earlier "tautology-scan: 0 test files" check).
out=$(python3 "$V/tautology-scan.py" "$W/no-tests" 2>&1); rc=$?
check "tautology-scan: positional 0 files still UNMEASURED" 2 "$rc" "$out" "UNMEASURED"

# Hit in changed test
tsr1="$W/tsr1"
mkrepo "$tsr1"
cd "$tsr1" || exit
printf 'expect(a).toBe(a);\n' > x.test.js
git -c user.email=t@t -c user.name=t add x.test.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add x.test.js"
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: hit in changed test" 1 "$rc" "$out" "SELF-ASSERT"
case "$out" in *x.test.js*) pass=$((pass + 1)) ;; *) echo "FAIL: tautology-scan --diff: hit in changed test — missing x.test.js in output"; fail=1 ;; esac
cd - >/dev/null || exit

# Unchanged tautology ignored: old.test.js is shared history (present on disk
# on both release and feat, unmodified since); only n.test.js is new on feat.
# It stays checked out in the working tree the whole time, so this fixture
# only passes because the scan is scoped by "git diff", not a filesystem walk.
tsr2="$W/tsr2"
mkrepo "$tsr2"
cd "$tsr2" || exit
printf 'expect(a).toBe(a);\n' > old.test.js
git -c user.email=t@t -c user.name=t add old.test.js
git -c user.email=t@t -c user.name=t commit -q -m "add old.test.js (shared by release and feat)"
git branch -f release/x-abc HEAD
printf 'expect(f(1)).toBe(2);\n' > n.test.js
git -c user.email=t@t -c user.name=t add n.test.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add clean n.test.js"
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: unchanged tautology ignored" 0 "$rc"
case "$out" in *old.test.js*) echo "FAIL: tautology-scan --diff: unchanged tautology ignored — old.test.js (outside the diff) leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# No test file in diff
tsr4="$W/tsr4"
mkrepo "$tsr4"
cd "$tsr4" || exit
printf 'function f(){}\n' > app.js
git -c user.email=t@t -c user.name=t add app.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add app.js"
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: no test file in diff" 2 "$rc" "$out" "UNMEASURED"
cd - >/dev/null || exit

# Empty diff
tsr5="$W/tsr5"
mkrepo "$tsr5"
cd "$tsr5" || exit
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: empty diff" 2 "$rc" "$out" "empty diff"
cd - >/dev/null || exit

# Invalid base (TV-T4): option-shaped and metacharacter bases, both rejected
out=$(python3 "$V/tautology-scan.py" --diff -x 2>&1); rc=$?
check "tautology-scan --diff: invalid base" 2 "$rc" "$out" "invalid base ref"
out=$(python3 "$V/tautology-scan.py" --diff 'a;b' 2>&1); rc=$?
check "tautology-scan --diff: invalid base" 2 "$rc" "$out" "invalid base ref"

# Dirty tree
tsr7="$W/tsr7"
mkrepo "$tsr7"
cd "$tsr7" || exit
printf 'untracked\n' > untracked.test.js
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: dirty tree" 2 "$rc" "$out" "uncommitted"
cd - >/dev/null || exit

# Newline in test file name (a newline-split name — a known false-clean class): splitting
# the NUL-separated git diff list on "\n" instead of "\0" would break this one
# path into two missing ones and silently drop it from the scan.
tsr8="$W/tsr8"
mkrepo "$tsr8"
cd "$tsr8" || exit
nlfile=$'a\nb.test.js'
printf 'expect(a).toBe(a);\n' > "$nlfile"
git -c user.email=t@t -c user.name=t add -- "$nlfile"
git -c user.email=t@t -c user.name=t commit -q -m "feat: add test file with newline in name"
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: newline in test file name" 1 "$rc" "$out" "SELF-ASSERT"
cd - >/dev/null || exit

# Only-deleted diff: old.test.js is fast-forwarded onto release/x-abc so it is
# shared history, then removed only on feat — the deletion is excluded by
# --diff-filter=d, leaving an empty diff.
tsr9="$W/tsr9"
mkrepo "$tsr9"
cd "$tsr9" || exit
printf 'expect(a).toBe(a);\n' > old.test.js
git -c user.email=t@t -c user.name=t add old.test.js
git -c user.email=t@t -c user.name=t commit -q -m "add old.test.js (shared by release and feat)"
git branch -f release/x-abc HEAD
git rm -q old.test.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: remove old.test.js"
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: only-deleted diff" 2 "$rc" "$out" "empty diff"
cd - >/dev/null || exit

# Pathspec limits the scan
tsr10="$W/tsr10"
mkrepo "$tsr10"
cd "$tsr10" || exit
mkdir -p a b
printf 'expect(x).toBe(x);\n' > a/x.test.js
printf 'expect(y).toBe(y);\n' > b/y.test.js
git -c user.email=t@t -c user.name=t add a/x.test.js b/y.test.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add a and b test files"
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc a 2>&1); rc=$?
check "tautology-scan --diff: pathspec limits the scan" 1 "$rc" "$out" "a/x.test.js"
case "$out" in *b/y.test.js*) echo "FAIL: tautology-scan --diff: pathspec limits the scan — b/y.test.js leaked outside the 'a' pathspec"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# git diff failure is reported: reuses the stub-git dir already set up for the
# analogous security-scan --diff test above.
tsr11="$W/tsr11"
mkrepo "$tsr11"
cd "$tsr11" || exit
out=$(PATH="$stubdir:$PATH" python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: git diff failure is reported" 2 "$rc" "$out" "git diff failed"
cd - >/dev/null || exit

# Skip dirs are not scanned: testdata/x_test.go changes but must never be
# scanned in diff mode, exactly as the positional walk already skips it via
# SKIP_DIRS. y.test.js is clean, so a correct scan sees 0 hits.
tsr12="$W/tsr12"
mkrepo "$tsr12"
cd "$tsr12" || exit
mkdir -p testdata
printf 'func TestX(t *testing.T) { assert.Equal(t, x, x) }\n' > testdata/x_test.go
printf 'expect(f(1)).toBe(2);\n' > y.test.js
git -c user.email=t@t -c user.name=t add testdata/x_test.go y.test.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add testdata and clean test"
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: skip dirs are not scanned" 0 "$rc"
case "$out" in *"testdata/x_test.go"*) echo "FAIL: tautology-scan --diff: skip dirs are not scanned — testdata/x_test.go leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# Symlinked test file is never followed: the target lives outside the repo
# and contains a tautology that must never surface — surfacing it would
# prove the scan opened a file outside its own working tree.
tsr13="$W/tsr13"
mkrepo "$tsr13"
printf 'expect(TOBE_LEAKED).toBe(TOBE_LEAKED); // outside the repo\n' > "$W/outside13.txt"
cd "$tsr13" || exit
ln -s ../outside13.txt leak.test.js
git -c user.email=t@t -c user.name=t add -- leak.test.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add leak.test.js symlink"
out=$(python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: symlinked test file is never followed" 1 "$rc" "$out" "[SYMLINK] "
case "$out" in *leak.test.js*) pass=$((pass + 1)) ;; *) echo "FAIL: tautology-scan --diff: symlinked test file is never followed — missing leak.test.js in output"; fail=1 ;; esac
case "$out" in *TOBE_LEAKED*) echo "FAIL: tautology-scan --diff: symlinked test file is never followed — symlink target's content leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# Unreadable test path is UNMEASURED: dir.test.js is committed clean, then
# stripped of all permissions after the commit so the working-tree file
# cannot be opened. `git status --porcelain` itself needs to read a file to
# confirm racy-clean state, so an unreadable tracked file makes real git
# report it "modified" too — that would trip the pre-existing dirty-tree
# check instead of the path under test here, satisfying the "UNMEASURED"
# assertion for the wrong reason. `git diff <ref>...<ref>` between two
# commits never touches the working-tree file at all (confirmed: it reads
# only git's object database), so only `status` is stubbed clean; rev-parse
# and diff still run for real. (chmod 000 does not block a root reader — if
# this suite is ever run as root this row will not reproduce; that is a
# known, documented gap, not special-cased here.)
tsr14="$W/tsr14"
mkrepo "$tsr14"
cd "$tsr14" || exit
printf 'expect(f(1)).toBe(2);\n' > dir.test.js
git -c user.email=t@t -c user.name=t add dir.test.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add dir.test.js"
chmod 000 dir.test.js
stubdir14="$W/stubbin14"
mkdir -p "$stubdir14"
cat > "$stubdir14/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "status" ]; then
    exit 0
fi
exec "$realgit" "\$@"
STUB
chmod +x "$stubdir14/git"
out=$(PATH="$stubdir14:$PATH" python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
chmod 644 dir.test.js
check "tautology-scan --diff: unreadable test path is UNMEASURED" 2 "$rc" "$out" "could not read"
case "$out" in *dir.test.js*) pass=$((pass + 1)) ;; *) echo "FAIL: tautology-scan --diff: unreadable test path is UNMEASURED — missing dir.test.js in output"; fail=1 ;; esac
case "$out" in *PASS*) echo "FAIL: tautology-scan --diff: unreadable test path is UNMEASURED — printed PASS despite an unreadable file"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# Non-UTF-8 file name is not a traceback: git tracks byte-exact paths and can
# report one containing a byte that is not valid UTF-8. This filesystem
# (APFS) refuses to create such a directory entry at all — confirmed at the
# syscall level, not just the shell — so the diff output is fabricated by a
# stub git (same technique as "git diff failure is reported" above) instead
# of being committed for real. The stub replaces only `git diff`; rev-parse
# and status still run for real against an ordinary clean mkrepo checkout,
# so the base-ref and dirty-tree checks stay genuine. Because the reported
# file was never actually written to disk, the scan cannot open it and ends
# UNMEASURED rather than PASS — the story's literal "exit 0" assumes a
# filesystem (Linux) that allows the byte in a real file name. What is
# verified here is the fix's actual claim: decoding git's raw diff output no
# longer raises, and the scan fails closed instead of crashing.
tsr15="$W/tsr15"
mkrepo "$tsr15"
cd "$tsr15" || exit
stubdir15="$W/stubbin15"
mkdir -p "$stubdir15"
cat > "$stubdir15/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "diff" ]; then
    printf 't\\377.test.js\\000'
    exit 0
fi
exec "$realgit" "\$@"
STUB
chmod +x "$stubdir15/git"
out=$(PATH="$stubdir15:$PATH" python3 "$V/tautology-scan.py" --diff release/x-abc 2>&1); rc=$?
check "tautology-scan --diff: non-UTF-8 file name is not a traceback" 2 "$rc" "$out" "UNMEASURED"
case "$out" in *Traceback*) echo "FAIL: tautology-scan --diff: non-UTF-8 file name is not a traceback — a Python Traceback leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# ── classify-diff.sh: verifies a declared roster against the real diff ─

# Style-only diff passes cosmetic
repo_c1="$W/repo_c1"
mkrepo "$repo_c1"
cd "$repo_c1" || exit
mkdir -p ui
printf 'button { color: red; }\n' > ui/button.css
git -c user.email=t@t -c user.name=t add ui/button.css
git -c user.email=t@t -c user.name=t commit -q -m "feat: style tweak"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: style-only diff passes cosmetic" 0 "$rc" "$out" "required=cosmetic"
cd - >/dev/null || exit

# A .ts handler declared cosmetic is never trusted at face value
repo_c2="$W/repo_c2"
mkrepo "$repo_c2"
cd "$repo_c2" || exit
mkdir -p src
printf 'function add(a, b) { return a + b; }\n' > src/handler.ts
git -c user.email=t@t -c user.name=t add src/handler.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add handler"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: .ts handler declared cosmetic escalates" 1 "$rc" "$out" "ROSTER: ESCALATE cosmetic → light"
cd - >/dev/null || exit

# An auth route forces full regardless of the declared roster
repo_c3="$W/repo_c3"
mkrepo "$repo_c3"
cd "$repo_c3" || exit
mkdir -p src
printf 'app.post("/login", handler);\n' > src/r.ts
git -c user.email=t@t -c user.name=t add src/r.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add login route"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared standard 2>&1); rc=$?
check "classify: auth route escalates to full" 1 "$rc" "$out" "ESCALATE standard → full"
cd - >/dev/null || exit

# Empty diff is unmeasured, never a silent "cosmetic passes"
repo_c4="$W/repo_c4"
mkrepo "$repo_c4"
cd "$repo_c4" || exit
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared light 2>&1); rc=$?
check "classify: empty diff is unmeasured" 2 "$rc" "$out" "UNMEASURED"
cd - >/dev/null || exit

# Never de-escalates: a declared roster above what the diff needs is kept, not lowered
repo_c5="$W/repo_c5"
mkrepo "$repo_c5"
cd "$repo_c5" || exit
mkdir -p ui
printf 'button { color: blue; }\n' > ui/button.css
git -c user.email=t@t -c user.name=t add ui/button.css
git -c user.email=t@t -c user.name=t commit -q -m "feat: style tweak 2"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared full 2>&1); rc=$?
check "classify: never de-escalates" 0 "$rc" "$out" "required=cosmetic declared=full"
case "$out" in *"declared roster kept"*) pass=$((pass + 1)) ;; *) echo "FAIL: classify: never de-escalates — missing 'declared roster kept'"; fail=1 ;; esac
cd - >/dev/null || exit

# light is bounded at <= 2 non-test source files
repo_c6="$W/repo_c6"
mkrepo "$repo_c6"
cd "$repo_c6" || exit
mkdir -p src
printf 'const a = 1;\n' > src/a.ts
printf 'const b = 2;\n' > src/b.ts
printf 'const c = 3;\n' > src/c.ts
git -c user.email=t@t -c user.name=t add src/a.ts src/b.ts src/c.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add three files"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared light 2>&1); rc=$?
check "classify: 3 source files needs standard" 1 "$rc" "$out" "ESCALATE light → standard"
cd - >/dev/null || exit

# A new dependency is never light, even with a single source file
repo_c7="$W/repo_c7"
mkrepo "$repo_c7"
cd "$repo_c7" || exit
mkdir -p src
printf '{"name":"x","version":"1.0.0"}\n' > package.json
printf 'const a = 1;\n' > src/a.ts
git -c user.email=t@t -c user.name=t add package.json src/a.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add dependency and file"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared light 2>&1); rc=$?
check "classify: dependency manifest needs standard" 1 "$rc" "$out" "→ standard"
cd - >/dev/null || exit

# Tests-only diff still needs a reviewer, so it is never cosmetic
repo_c8="$W/repo_c8"
mkrepo "$repo_c8"
cd "$repo_c8" || exit
printf 'func TestX(t *testing.T) {}\n' > a_test.go
git -c user.email=t@t -c user.name=t add a_test.go
git -c user.email=t@t -c user.name=t commit -q -m "feat: add test"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: tests-only diff is light" 1 "$rc" "$out" "→ light"
cd - >/dev/null || exit

# Locale copy stays cosmetic
repo_c9="$W/repo_c9"
mkrepo "$repo_c9"
cd "$repo_c9" || exit
mkdir -p locales
printf '{"hello":"world"}\n' > locales/en.json
git -c user.email=t@t -c user.name=t add locales/en.json
git -c user.email=t@t -c user.name=t commit -q -m "feat: add locale"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: locale json is cosmetic" 0 "$rc" "$out" "declared=cosmetic"
cd - >/dev/null || exit

# Unknown declared roster is a usage error, not a silent default. Run inside a
# repo with a genuinely cosmetic diff so an unvalidated roster would otherwise
# reach real classification and exit 0 — never let a coincidental "unknown base
# ref" elsewhere in the arg set mask an unchecked roster value.
repo_c10="$W/repo_c10"
mkrepo "$repo_c10"
cd "$repo_c10" || exit
mkdir -p ui
printf 'button { color: green; }\n' > ui/button.css
git -c user.email=t@t -c user.name=t add ui/button.css
git -c user.email=t@t -c user.name=t commit -q -m "feat: style tweak 3"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared huge 2>&1); rc=$?
check "classify: unknown declared roster" 2 "$rc"
cd - >/dev/null || exit

# ── cosmetic must not trust extension/location alone ────

# security-scan --include-docs: the flag classify-diff's cosmetic content check
# depends on — default mode filters `.md:` lines for the Reviewer's own noise
# reduction, and that filter would hide exactly the code this flag needs to see.
mkdir -p "$W/docsec"
printf 'eval(x)\n' > "$W/docsec/x.md"
out=$(bash "$V/security-scan.sh" --include-docs "$W/docsec/x.md" 2>&1); rc=$?
check "security-scan --include-docs scans markdown" 0 "$rc" "$out" "x.md:1"

# A style-extension file holding real code must not pass cosmetic just because
# of its name .
repo_c16="$W/repo_c16"
mkrepo "$repo_c16"
cd "$repo_c16" || exit
printf "require('child_process').exec(x);\n" > evil.css
git -c user.email=t@t -c user.name=t add evil.css
git -c user.email=t@t -c user.name=t commit -q -m "feat: add evil.css"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: code in a style extension is not cosmetic" 1 "$rc" "$out" "ESCALATE cosmetic → full"
cd - >/dev/null || exit

# A rename to a style extension disguises whatever the origin file actually was
#  — diff-lib's own listing only ever shows the new path.
repo_c17="$W/repo_c17"
mkrepo "$repo_c17"
cd "$repo_c17" || exit
mkdir -p src
printf 'function handler() { return 1; }\n' > src/handler.ts
git -c user.email=t@t -c user.name=t add src/handler.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add handler.ts (shared by release and feat)"
git branch -f release/x-abc HEAD
git mv src/handler.ts src/handler.css
git -c user.email=t@t -c user.name=t commit -q -m "feat: rename handler.ts to handler.css"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: rename to a style extension is not cosmetic" 1 "$rc" "$out" "ESCALATE cosmetic → light"
cd - >/dev/null || exit

# A disguised rename whose original file is dangerous must not settle for the
# rename's own light classification — the (c) content check has to run on the
# doc/style file that still exists post-rename, and any security-scan
# candidate wins over the rename escalation (content wins over the rename rule).
repo_c21="$W/repo_c21"
mkrepo "$repo_c21"
cd "$repo_c21" || exit
mkdir -p src
printf "require('child_process').exec(x);\n" > src/run.ts
git -c user.email=t@t -c user.name=t add src/run.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add run.ts (shared by release and feat)"
git branch -f release/x-abc HEAD
git mv src/run.ts src/run.css
git -c user.email=t@t -c user.name=t commit -q -m "feat: rename run.ts to run.css"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: disguised rename with dangerous content is full" 1 "$rc" "$out" "ESCALATE cosmetic → full"
cd - >/dev/null || exit

# Markdown is filtered by security-scan's default mode; classify-diff's
# cosmetic check must reach past that with --include-docs or code in a .md
# file passes as documentation.
repo_c18="$W/repo_c18"
mkrepo "$repo_c18"
cd "$repo_c18" || exit
printf 'app.post("/admin", handler);\n' > notes.md
git -c user.email=t@t -c user.name=t add notes.md
git -c user.email=t@t -c user.name=t commit -q -m "feat: add notes.md"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: code in markdown is not cosmetic" 1 "$rc" "$out" "→ full"
cd - >/dev/null || exit

# pubspec.yaml is Flutter's dependency manifest — D3 amendment's explicit list.
repo_c19="$W/repo_c19"
mkrepo "$repo_c19"
cd "$repo_c19" || exit
printf 'name: x\n' > pubspec.yaml
printf 'void main() {}\n' > main.dart
git -c user.email=t@t -c user.name=t add pubspec.yaml main.dart
git -c user.email=t@t -c user.name=t commit -q -m "feat: add pubspec and dart file"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared light 2>&1); rc=$?
check "classify: pubspec.yaml is a dependency manifest" 1 "$rc" "$out" "→ standard"
cd - >/dev/null || exit

# A missing tautology-scan.py must fail closed with UNMEASURED, never a raw
# Python traceback (the "never a traceback" contract).
stubV2="$W/stubverify16"
mkdir -p "$stubV2"
cp "$V/classify-diff.sh" "$stubV2/classify-diff.sh"
cp "$V/diff-lib.sh" "$stubV2/diff-lib.sh"
cp "$V/security-scan.sh" "$stubV2/security-scan.sh"
chmod +x "$stubV2/classify-diff.sh"
repo_c20="$W/repo_c20"
mkrepo "$repo_c20"
cd "$repo_c20" || exit
mkdir -p ui
printf 'button { color: red; }\n' > ui/button.css
git -c user.email=t@t -c user.name=t add ui/button.css
git -c user.email=t@t -c user.name=t commit -q -m "feat: style tweak"
out=$(bash "$stubV2/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: missing tautology-scan is unmeasured, not a traceback" 2 "$rc" "$out" "UNMEASURED"
case "$out" in *Traceback*) echo "FAIL: classify: missing tautology-scan is unmeasured, not a traceback — a Python Traceback leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# TV-C7: invalid base rejected the same way as every other diff-scoped sensor
out=$(bash "$V/classify-diff.sh" --diff 'a;b' --declared light 2>&1); rc=$?
check "classify: invalid base" 2 "$rc" "$out" "invalid base ref"

# A symlink named like a style file is not classified by its name
repo_c12="$W/repo_c12"
mkrepo "$repo_c12"
cd "$repo_c12" || exit
mkdir -p src
printf 'function handler() { return 1; }\n' > src/handler.ts
git -c user.email=t@t -c user.name=t add src/handler.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add handler (shared by release and feat)"
git branch -f release/x-abc HEAD
ln -s src/handler.ts theme.css
git -c user.email=t@t -c user.name=t add theme.css
git -c user.email=t@t -c user.name=t commit -q -m "feat: add disguised symlink"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: symlink named like a style file is not cosmetic" 1 "$rc" "$out" "ROSTER: ESCALATE cosmetic → light"
cd - >/dev/null || exit

# Deleting a source file is a behaviour change, not a cosmetic no-op, and must
# not be read as an empty diff (diff-lib's --diff-filter=d hides deletions).
repo_c13="$W/repo_c13"
mkrepo "$repo_c13"
cd "$repo_c13" || exit
mkdir -p src
printf 'function old() { return 1; }\n' > src/old.ts
git -c user.email=t@t -c user.name=t add src/old.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add old.ts (shared by release and feat)"
git branch -f release/x-abc HEAD
git rm -q src/old.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: remove old.ts"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: deleting a source file is not cosmetic" 1 "$rc" "$out" "ROSTER: ESCALATE cosmetic → light"
case "$out" in *"empty diff"*) echo "FAIL: classify: deleting a source file is not cosmetic — read as empty diff instead of a deletion"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# Newline in a source file name must not be split into two missing paths
# (the newline-split false-clean class). A second plain file sits
# alongside it so a name split (1 real file -> 2 bogus paths) is observable:
# correctly read, this diff has 2 non-test source files (<= 2, light); split,
# it has 3 (> 2, standard) -- a real threshold difference, not just a re-run
# of the already-falsified check on the shared library.
repo_c14="$W/repo_c14"
mkrepo "$repo_c14"
cd "$repo_c14" || exit
nlfile=$'a\nb.ts'
printf 'return 1;\n' > "$nlfile"
printf 'const c = 1;\n' > other.ts
git -c user.email=t@t -c user.name=t add other.ts -- "$nlfile"
git -c user.email=t@t -c user.name=t commit -q -m "feat: add file with newline in name"
out=$(bash "$V/classify-diff.sh" --diff release/x-abc --declared cosmetic 2>&1); rc=$?
check "classify: newline in a source file name escalates" 1 "$rc" "$out" "→ light"
cd - >/dev/null || exit

# security-scan coming back UNMEASURED must propagate, never read as "no trigger".
# classify-diff.sh, diff-lib.sh and tautology-scan.py are copied into an isolated
# scripts dir so only security-scan.sh (the one it calls by its own path) is stubbed.
stubV="$W/stubverify15"
mkdir -p "$stubV"
cp "$V/classify-diff.sh" "$stubV/classify-diff.sh"
cp "$V/diff-lib.sh" "$stubV/diff-lib.sh"
cp "$V/tautology-scan.py" "$stubV/tautology-scan.py"
cat > "$stubV/security-scan.sh" <<'STUB'
#!/usr/bin/env bash
echo "SECURITY-SCAN: UNMEASURED — stubbed failure for classify-diff test" >&2
exit 2
STUB
chmod +x "$stubV/security-scan.sh" "$stubV/classify-diff.sh"
repo_c15="$W/repo_c15"
mkrepo "$repo_c15"
cd "$repo_c15" || exit
mkdir -p src
printf 'function f() { return 1; }\n' > src/f.ts
git -c user.email=t@t -c user.name=t add src/f.ts
git -c user.email=t@t -c user.name=t commit -q -m "feat: add source file"
out=$(bash "$stubV/classify-diff.sh" --diff release/x-abc --declared light 2>&1); rc=$?
check "classify: security-scan unmeasured propagates" 2 "$rc" "$out" "stubbed failure for classify-diff test"
cd - >/dev/null || exit
# ══════════════════════════════════════════════════════════════════════════
# verdict.sh roster checks.
# Keep this section contiguous — a second, separate batch appends
# classify-diff rows and a merge should not have to interleave the two.
# ══════════════════════════════════════════════════════════════════════════

# ── verdict.sh --roster / --classify-exit (D2) ─────────────────────────
# TV-V0a/b/c and the "no roster label" row are Preserve rows already covered
# above (lines ~76-81); this section adds the roster-specific behaviour only.

out=$(bash "$V/verdict.sh" --review 9 --stress 9 --qa 9 2>&1); rc=$?
check "verdict: legacy output has no roster label" 0 "$rc"
case "$out" in *"[folded]"*|*roster*) echo "FAIL: verdict: legacy output has no roster label — leaked roster text"; fail=1 ;; *) pass=$((pass + 1)) ;; esac

out=$(bash "$V/verdict.sh" --roster cosmetic --classify-exit 0 2>&1); rc=$?
check "verdict: cosmetic gates-only passes" 0 "$rc" "$out" "n/a (cosmetic — gates only)"

out=$(bash "$V/verdict.sh" --roster cosmetic --classify-exit 0 --hard-gate-fail lint 2>&1); rc=$?
check "verdict: cosmetic with gate fail is NOT READY" 1 "$rc" "$out" "hard gate FAIL: lint"

out=$(bash "$V/verdict.sh" --roster cosmetic --classify-exit 0 --review 9 2>&1); rc=$?
check "verdict: cosmetic rejects a score" 2 "$rc"

out=$(bash "$V/verdict.sh" --roster standard --classify-exit 1 --review 9 --stress 9 --qa 9 2>&1); rc=$?
check "verdict: unverified roster is NOT READY" 1 "$rc" "$out" "roster not verified (classify-diff exit 1)"

out=$(bash "$V/verdict.sh" --roster standard --review 9 --stress 9 --qa 9 2>&1); rc=$?
check "verdict: roster requires classify-exit" 2 "$rc"

out=$(bash "$V/verdict.sh" --roster light --classify-exit 0 --review 8 --stress 8 2>&1); rc=$?
check "verdict: light renormalises without QA" 0 "$rc" "$out" "Overall Score: 8.00"
case "$out" in *"weight renormalised"*) pass=$((pass + 1)) ;; *) echo "FAIL: verdict: light renormalises without QA — missing 'weight renormalised'"; fail=1 ;; esac

out=$(bash "$V/verdict.sh" --roster light --classify-exit 0 --review 8 --stress 8 --qa 9 2>&1); rc=$?
check "verdict: light rejects qa score" 2 "$rc"

out=$(bash "$V/verdict.sh" --roster light --classify-exit 0 --review 10 --stress 6.5 2>&1); rc=$?
check "verdict: light keeps stress floor" 1 "$rc" "$out" "below story floor"

out=$(bash "$V/verdict.sh" --roster standard --classify-exit 0 --review 9 --stress 9 --qa 9 2>&1); rc=$?
check "verdict: standard labels folded stress" 0 "$rc" "$out" "[folded]"
case "$out" in *"NOTE: Review and Stress from one agent"*) pass=$((pass + 1)) ;; *) echo "FAIL: verdict: standard labels folded stress — missing NOTE"; fail=1 ;; esac

out=$(bash "$V/verdict.sh" --roster full --classify-exit 0 --review 9 --stress 5.5 --qa 9 2>&1); rc=$?
check "verdict: full labels dispatched stress and keeps gap warning" 1 "$rc" "$out" "[dispatched]"
case "$out" in *"WARNING: Review/Stress gap"*) pass=$((pass + 1)) ;; *) echo "FAIL: verdict: full labels dispatched stress and keeps gap warning — missing WARNING"; fail=1 ;; esac

legacy_score=$(bash "$V/verdict.sh" --review 8 --stress 7.5 --qa 8.5 2>&1 | grep -o "Overall Score: [0-9.]*")
standard_score=$(bash "$V/verdict.sh" --roster standard --classify-exit 0 --review 8 --stress 7.5 --qa 8.5 2>&1 | grep -o "Overall Score: [0-9.]*")
[ -n "$legacy_score" ] && [ "$legacy_score" = "$standard_score" ] && rc=0 || rc=1
check "verdict: standard formula equals legacy" 0 "$rc"

# ── tautology-scan.py TEST_FILE — bats, hyphenated test-*.sh, tests/ dir ────
mkdir -p "$W/g5-shapes/tests"
printf 'echo hi\n' > "$W/g5-shapes/test-x.sh"
printf 'func TestX(t *testing.T) {}\n' > "$W/g5-shapes/x_test.go"
printf '@test "x" { true; }\n' > "$W/g5-shapes/a.bats"
printf 'echo hi\n' > "$W/g5-shapes/tests/t.sh"
out=$(python3 "$V/tautology-scan.py" "$W/g5-shapes" 2>&1); rc=$?
check "tautology-scan: shell and bats test names are tests" 0 "$rc" "$out" "4 test file(s)"

mkdir -p "$W/g5-data/tests/fixtures"
printf '{}\n' > "$W/g5-data/tests/fixtures/data.json"
printf '# notes\n' > "$W/g5-data/tests/README.md"
out=$(python3 "$V/tautology-scan.py" "$W/g5-data" 2>&1); rc=$?
check "tautology-scan: data under tests/ is not a test" 2 "$rc" "$out" "UNMEASURED"

mkdir -p "$W/g5-vendor/vendor/tests"
printf 'echo hi\n' > "$W/g5-vendor/vendor/tests/t.sh"
out=$(python3 "$V/tautology-scan.py" "$W/g5-vendor" 2>&1); rc=$?
check "tautology-scan: skip dirs still win over tests/" 2 "$rc" "$out" "UNMEASURED"

# security-scan diff-mode kept its own narrower test-file regex
# (_test.|.test.|.spec.), so a hyphenated test-*.sh or a .bats fixture file
# was scanned as source — a fixture string like "eval(x)" inside it read as
# a real candidate and escalated classify-diff to `full`. It must reuse
# tautology-scan.py's TEST_FILE the way classify-diff.sh already does, and a
# genuine source hit in the same diff must still be reported.
repoTF="$W/repoTF"
mkrepo "$repoTF"
cd "$repoTF" || exit
printf 'run_case "rejects eval(x) input"\n' > test-x.sh
printf '@test "rejects eval(x)" { false; }\n' > a.bats
printf 'eval(x)\n' > app.js
git -c user.email=t@t -c user.name=t add test-x.sh a.bats app.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add test fixtures and real source"
out=$(bash "$V/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan: test files use the shared TEST_FILE definition" 0 "$rc" "$out" "app.js:1"
case "$out" in *test-x.sh*) echo "FAIL: security-scan: test files use the shared TEST_FILE definition — test-x.sh leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
case "$out" in *a.bats*) echo "FAIL: security-scan: test files use the shared TEST_FILE definition — a.bats leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# ── RD2: one TEST_FILE loader for all sensors (diff-lib.sh) ─────────────────
# The importlib extraction used to live twice, copy-pasted into
# classify-diff.sh and security-scan.sh, and could drift the moment one copy
# was edited and the other was not. It now lives once, as diff-lib.sh's
# load_test_file_re, and both callers use it instead of importing directly.
def_count=$(grep -c '^load_test_file_re()' "$V/diff-lib.sh")
importlib_count=$(( $(grep -c 'importlib\.util' "$V/classify-diff.sh") + $(grep -c 'importlib\.util' "$V/security-scan.sh") ))
ok=1
[ "$def_count" = "1" ] || ok=0
[ "$importlib_count" = "0" ] || ok=0
if [ "$ok" = 1 ]; then pass=$((pass + 1)); else
    echo "FAIL: diff-lib: one TEST_FILE loader for all sensors — def_count=$def_count (want 1) importlib_count=$importlib_count (want 0)"; fail=1
fi

# security-scan.sh must fail closed the same way classify-diff.sh already
# does (tested above as "classify: missing tautology-scan is unmeasured, not
# a traceback") when tautology-scan.py is missing beside it — its own
# fail-closed path was untested before this.
stubV3="$W/stubverify17"
mkdir -p "$stubV3"
cp "$V/security-scan.sh" "$stubV3/security-scan.sh"
cp "$V/diff-lib.sh" "$stubV3/diff-lib.sh"
chmod +x "$stubV3/security-scan.sh"
repo_c22="$W/repo_c22"
mkrepo "$repo_c22"
cd "$repo_c22" || exit
printf 'eval(x)\n' > app.js
git -c user.email=t@t -c user.name=t add app.js
git -c user.email=t@t -c user.name=t commit -q -m "feat: add app.js"
out=$(bash "$stubV3/security-scan.sh" --diff release/x-abc 2>&1); rc=$?
check "security-scan: missing TEST_FILE source fails closed" 2 "$rc" "$out" "UNMEASURED"
case "$out" in *Traceback*) echo "FAIL: security-scan: missing TEST_FILE source fails closed — a Python Traceback leaked into output"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# ══════════════════════════════════════════════════════════════════════════
# scripts/verify/checkpoint-m.sh + scripts/verify/break-run.sh
# Every fixture here is synthetic (mkrepo style) — never a reference to any
# one delivery's own files or numbers, per the Hardening section's own rule.
# ══════════════════════════════════════════════════════════════════════════

# ── checkpoint-m.sh: missing spec row fails ──────────────────────────────────
cp1="$W/cp1"
mkrepo "$cp1"
cd "$cp1" || exit
printf 'func TestRowA(t *testing.T) {}\n' > impl_test.go
cat > "$W/cp1-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestRowA` | a | b |
| `TestRowB` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp1-spec.md" --tests impl_test.go --expect impl_test.go 2>&1); rc=$?
check "checkpoint-m: missing spec row fails" 1 "$rc" "$out" "M: FAIL spec-rows"
case "$out" in *TestRowB*) pass=$((pass + 1)) ;; *) echo "FAIL: checkpoint-m: missing spec row fails — missing row name TestRowB in output"; fail=1 ;; esac
cd - >/dev/null || exit

# ── checkpoint-m.sh: bats and check harness names count ──────────────────────
cp2="$W/cp2"
mkrepo "$cp2"
cd "$cp2" || exit
cat > cp2_test.sh <<'EOF'
@test "RowBats" {
  true
}
check "RowCheck" 0 0
EOF
write_dup_filler filler.go
cat > "$W/cp2-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `RowBats` | a | b |
| `RowCheck` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp2-spec.md" --tests cp2_test.sh --expect cp2_test.sh filler.go 2>&1); rc=$?
check "checkpoint-m: bats and check harness names count" 0 "$rc" "$out" "M: PASS"
cd - >/dev/null || exit

# ── checkpoint-m.sh: extra file fails ────────────────────────────────────────
cp3="$W/cp3"
mkrepo "$cp3"
cd "$cp3" || exit
printf 'func TestX(t *testing.T) {}\n' > a_test.go
printf 'stray\n' > b.go
cat > "$W/cp3-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestX` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp3-spec.md" --tests a_test.go --expect a_test.go 2>&1); rc=$?
check "checkpoint-m: extra file fails" 1 "$rc" "$out" "M: FAIL file-set"
case "$out" in *"extra b.go"*) pass=$((pass + 1)) ;; *) echo "FAIL: checkpoint-m: extra file fails — missing 'extra b.go' in output"; fail=1 ;; esac
cd - >/dev/null || exit

# ── checkpoint-m.sh: missing expected file fails ─────────────────────────────
cp4="$W/cp4"
mkrepo "$cp4"
cd "$cp4" || exit
printf 'func TestY(t *testing.T) {}\n' > y_test.go
cat > "$W/cp4-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestY` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp4-spec.md" --tests y_test.go --expect y_test.go never_touched.go 2>&1); rc=$?
check "checkpoint-m: missing expected file fails" 1 "$rc" "$out" "M: FAIL file-set"
case "$out" in *"missing never_touched.go"*) pass=$((pass + 1)) ;; *) echo "FAIL: checkpoint-m: missing expected file fails — missing 'missing never_touched.go' in output"; fail=1 ;; esac
cd - >/dev/null || exit

# ── checkpoint-m.sh: rename must list both paths ─────────────────────────────
cp5="$W/cp5"
mkrepo "$cp5"
cd "$cp5" || exit
printf 'func TestZ(t *testing.T) {}\n' > a_test.go
git -c user.email=t@t -c user.name=t add a_test.go
git -c user.email=t@t -c user.name=t commit -q -m "add a_test.go (shared by release and feat)"
git branch -f release/x-abc HEAD
git mv a_test.go b_test.go
cat > "$W/cp5-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestZ` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp5-spec.md" --tests b_test.go --expect b_test.go 2>&1); rc=$?
check "checkpoint-m: rename must list both paths" 1 "$rc" "$out" "M: FAIL file-set"
case "$out" in *"a_test.go"*) pass=$((pass + 1)) ;; *) echo "FAIL: checkpoint-m: rename must list both paths — the old path a_test.go is not named in output"; fail=1 ;; esac
cd - >/dev/null || exit

# ── checkpoint-m.sh: deletion must be listed ─────────────────────────────────
cp6="$W/cp6"
mkrepo "$cp6"
cd "$cp6" || exit
printf 'stray\n' > old.go
git -c user.email=t@t -c user.name=t add old.go
git -c user.email=t@t -c user.name=t commit -q -m "add old.go (shared by release and feat)"
git branch -f release/x-abc HEAD
git rm -q old.go
printf 'func TestW(t *testing.T) {}\n' > w_test.go
cat > "$W/cp6-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestW` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp6-spec.md" --tests w_test.go --expect w_test.go 2>&1); rc=$?
check "checkpoint-m: deletion must be listed" 1 "$rc" "$out" "M: FAIL file-set"
case "$out" in *"old.go"*) pass=$((pass + 1)) ;; *) echo "FAIL: checkpoint-m: deletion must be listed — the deleted path old.go is not named in output"; fail=1 ;; esac
cd - >/dev/null || exit

# ── checkpoint-m.sh: unexpected commit fails ─────────────────────────────────
cp7="$W/cp7"
mkrepo "$cp7"
cd "$cp7" || exit
printf 'func TestC(t *testing.T) {}\n' > c_test.go
git -c user.email=t@t -c user.name=t add c_test.go
git -c user.email=t@t -c user.name=t commit -q -m "feat: add c_test.go"
cat > "$W/cp7-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestC` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp7-spec.md" --tests c_test.go --expect c_test.go 2>&1); rc=$?
check "checkpoint-m: unexpected commit fails" 1 "$rc" "$out" "M: FAIL commits"
cd - >/dev/null || exit

# ── checkpoint-m.sh: leftover break marker fails ─────────────────────────────
cp8="$W/cp8"
mkrepo "$cp8"
cd "$cp8" || exit
printf 'func TestM(t *testing.T) {}\n' > m_test.go
printf 'leftover\n' > m_test.go.devkit-break
cat > "$W/cp8-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestM` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp8-spec.md" --tests m_test.go --expect m_test.go m_test.go.devkit-break 2>&1); rc=$?
check "checkpoint-m: leftover break marker fails" 1 "$rc" "$out" "M: FAIL break-marker"
case "$out" in *"m_test.go.devkit-break"*) pass=$((pass + 1)) ;; *) echo "FAIL: checkpoint-m: leftover break marker fails — missing marker path in output"; fail=1 ;; esac
cd - >/dev/null || exit

# ── checkpoint-m.sh: reports every failure at once ───────────────────────────
cp9="$W/cp9"
mkrepo "$cp9"
cd "$cp9" || exit
printf 'func TestN(t *testing.T) {}\n' > filler_test.go
write_dup_filler filler.go
cat > "$W/cp9-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestN` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp9-spec.md" --tests filler_test.go --expect filler_test.go filler.go never_here.go --gates false 2>&1); rc=$?
check "checkpoint-m: reports every failure at once" 1 "$rc" "$out" "M: FAIL (2)"
# The summary line "M: FAIL (2)" itself starts with "M: FAIL " — matched
# separately (a check name followed by an em-dash) so it is never counted
# as one of the individual failures it is summarising.
fail_lines=$(printf '%s\n' "$out" | grep -cE '^M: FAIL [a-z-]+ — ')
[ "$fail_lines" = "2" ] && pass=$((pass + 1)) || { echo "FAIL: checkpoint-m: reports every failure at once — expected 2 'M: FAIL' lines, got $fail_lines"; fail=1; }
cd - >/dev/null || exit

# ── checkpoint-m.sh: gates command failure is reported ───────────────────────
cp10="$W/cp10"
mkrepo "$cp10"
cd "$cp10" || exit
printf 'func TestG(t *testing.T) {}\n' > g_test.go
cat > "$W/cp10-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestG` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp10-spec.md" --tests g_test.go --expect g_test.go --gates false 2>&1); rc=$?
check "checkpoint-m: gates command failure is reported" 1 "$rc" "$out" "M: FAIL gates"
cd - >/dev/null || exit

# ── checkpoint-m.sh: all green passes ────────────────────────────────────────
cp11="$W/cp11"
mkrepo "$cp11"
cd "$cp11" || exit
printf 'func TestOK(t *testing.T) {}\n' > filler_test.go
write_dup_filler filler.go
cat > "$W/cp11-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestOK` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp11-spec.md" --tests filler_test.go --expect filler_test.go filler.go --gates true 2>&1); rc=$?
check "checkpoint-m: all green passes" 0 "$rc" "$out" "M: PASS"
cd - >/dev/null || exit

# ── break-run.sh: mutate-run-restore with proof the row failed for itself ───
cat > "$W/br_check.sh" <<'EOF'
#!/usr/bin/env bash
# Exits 0 either way and only prints the verdict: mirrors the harness `check`
# helpers this repo already uses, where a row's own PASS/FAIL is carried in
# the text, not the process exit code — so evidence must come from the
# needle, never from run_rc alone (F2's "accept any non-zero test exit").
if grep -q '^ENABLED=yes$' "$1"; then
    echo "PASS: guard-enabled"
else
    echo "FAIL: guard-enabled"
fi
exit 0
EOF
chmod +x "$W/br_check.sh"

# Every fixture in this section lives under $W, deliberately outside any git
# repository — plain scratch files break-run.sh's own mutate/restore/marker
# mechanics are exercised against, never meant to model "the repo under
# test". break-run.sh's containment check resolves its cwd-fallback
# base only when the invoking shell's cwd isn't itself a repo; without these
# wrappers every fixture here would instead be judged against the real repo
# this suite runs from and refused as "outside" it. `run_br` runs
# break-run.sh with cwd=$W without disturbing this script's own cwd; `bg_br`
# does the same for a backgrounded run, needed so `$!` still names
# break-run.sh's own pid directly (a subshell wrapper would make `$!` name
# the subshell instead, breaking every `pgrep -P` below it). The one
# exception is the "path outside the repository" row itself, which needs a
# real repo and manages its own cd.
run_br() { ( cd "$W" && bash "$V/break-run.sh" "$@" ); }
bg_br() {
    cd "$W" || exit
    bash "$V/break-run.sh" "$@" &
    bg_br_pid=$!
    cd - >/dev/null || exit
}

br1="$W/br1"
mkdir -p "$br1"
printf 'X=1\nX=1\n' > "$br1/dup.txt"
before=$(cat "$br1/dup.txt")
out=$(run_br --file "$br1/dup.txt" --old "X=1" --new "X=2" --row "whatever" -- true 2>&1); rc=$?
check "break-run: ambiguous pattern refused" 2 "$rc" "$out" "occurs 2"
after=$(cat "$br1/dup.txt")
[ "$before" = "$after" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: ambiguous pattern refused — file was modified despite refusal"; fail=1; }
[ ! -f "$br1/dup.txt.devkit-break" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: ambiguous pattern refused — marker left behind"; fail=1; }

br2="$W/br2"
mkdir -p "$br2"
printf 'Y=1\n' > "$br2/f.txt"
out=$(run_br --file "$br2/f.txt" --old "X=1" --new "X=2" --row "whatever" -- true 2>&1); rc=$?
check "break-run: absent pattern refused" 2 "$rc" "$out" "occurs 0"

br3="$W/br3"
mkdir -p "$br3"
printf 'ENABLED=yes\n' > "$br3/cfg.txt"
out=$(run_br --file "$br3/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- bash "$W/br_check.sh" "$br3/cfg.txt" 2>&1); rc=$?
check "break-run: passes only when the row fails by name" 0 "$rc" "$out" "FAIL: guard-enabled"
restored=$(cat "$br3/cfg.txt")
[ "$restored" = "ENABLED=yes" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: passes only when the row fails by name — file not restored"; fail=1; }
[ ! -f "$br3/cfg.txt.devkit-break" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: passes only when the row fails by name — marker left behind"; fail=1; }

br4="$W/br4"
mkdir -p "$br4"
printf 'ENABLED=yes\n' > "$br4/cfg.txt"
out=$(run_br --file "$br4/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- bash -c 'exit 1' 2>&1); rc=$?
check "break-run: unnamed failure is not evidence" 1 "$rc"
if printf '%s\n' "$out" | grep -qx "FAIL: guard-enabled"; then
    echo "FAIL: break-run: unnamed failure is not evidence — falsely treated a silent failure as evidence"
    fail=1
else
    pass=$((pass + 1))
fi
restored4=$(cat "$br4/cfg.txt")
[ "$restored4" = "ENABLED=yes" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: unnamed failure is not evidence — file not restored"; fail=1; }

br5="$W/br5"
mkdir -p "$br5"
printf 'ENABLED=yes\n' > "$br5/cfg.txt"
pristine5=$(cat "$br5/cfg.txt")
# `bash -c 'kill -TERM $$'` (the prior version of this row) signals the
# subshell's own PID, never break-run.sh — the mutation restores through the
# ordinary EXIT path regardless of whether break-run.sh's own INT/TERM trap
# exists, so that row was unfalsifiable and duplicated "unnamed failure is
# not evidence". This version signals break-run.sh's own PID (via $!) while
# it is genuinely blocked on its test command, so removing its `trap ...
# INT TERM` (break-run.sh:~123) changes the observable exit code from the
# deliberate 2 to a raw signal-death 143 — that is what this row falsifies.
bg_br --file "$br5/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- sleep 60 >/dev/null 2>&1
br5_pid=$bg_br_pid

# Poll (bounded — 5s max) for the pristine-copy marker: it appears only once
# break-run.sh has mutated the file and is blocked running the test command,
# which is the one moment a TERM sent to $br5_pid actually exercises its
# INT/TERM handler instead of racing its startup.
br5_tries=0
while [ ! -f "$br5/cfg.txt.devkit-break" ] && [ "$br5_tries" -lt 300 ]; do
    sleep 0.1
    br5_tries=$((br5_tries + 1))
done

if [ ! -f "$br5/cfg.txt.devkit-break" ]; then
    echo "FAIL: break-run: restores after interruption — marker never appeared, could not signal mid-run"
    fail=1
    kill -TERM "$br5_pid" 2>/dev/null
    wait "$br5_pid" 2>/dev/null
else
    # Best-effort: also reap the still-running `sleep 60` child so nothing
    # outlives this test — bounded regardless (it self-exits within 5s).
    br5_child=$(pgrep -P "$br5_pid" 2>/dev/null | head -1)
    kill -TERM "$br5_pid"
    wait "$br5_pid"
    br5_rc=$?
    [ -n "$br5_child" ] && kill -TERM "$br5_child" 2>/dev/null
    check "break-run: restores after interruption" 2 "$br5_rc"
    restored5=$(cat "$br5/cfg.txt")
    [ "$restored5" = "$pristine5" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: restores after interruption — file not restored"; fail=1; }
    [ ! -f "$br5/cfg.txt.devkit-break" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: restores after interruption — marker left behind"; fail=1; }
fi

# ── spec-coverage.sh: a row named inside any test helper counts ─────────────
# Dogfooding checkpoint-m.sh on a repository whose tests name rows inside
# `expect_says "<name>" …` and inside `echo "FAIL: <name> — …"` produced
# false "missing row" lines — spec-coverage.sh knew only language patterns
# plus `check "…"` and bats `@test "…"`, never a generic quoted-literal call.
# `gate_check("<name>"` pins a second dogfooding finding: the keyword can
# land as a SUFFIX after `_` (`gate_check`), where `\b` never fires because
# `_` is itself a word character — the matcher has to treat the keyword as a
# substring of the identifier, not just its start.
cat > "$W/sc-helper-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `helper-quoted row` | a | b |
| `helper-fail row` | a | b |
| `dup-gate: base resolution shared with the release guard` | a | b |
MD
mkdir -p "$W/sc-helper"
cat > "$W/sc-helper/helper_test.sh" <<'EOF'
expect_says "helper-quoted row" "some value"
echo "FAIL: helper-fail row — detail message"
gate_check "dup-gate: base resolution shared with the release guard" "$ok"
EOF
out=$(bash "$V/spec-coverage.sh" "$W/sc-helper-spec.md" "$W/sc-helper" 2>&1); rc=$?
check "spec-coverage: a row named inside any test helper counts" 0 "$rc" "$out" "3/3"

# ── spec-coverage.sh: a longer name does not satisfy a shorter row ──────────
# The prefix lesson (TestParsesToken vs TestParsesTokenWithExpiry) has to
# survive the wider matcher too, not just the original language patterns.
cat > "$W/sc-helper2-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `x fails` | a | b |
MD
mkdir -p "$W/sc-helper2"
cat > "$W/sc-helper2/helper2_test.sh" <<'EOF'
echo "FAIL: x fails loudly — detail"
EOF
out=$(bash "$V/spec-coverage.sh" "$W/sc-helper2-spec.md" "$W/sc-helper2" 2>&1); rc=$?
check "spec-coverage: a longer name does not satisfy a shorter row" 1 "$rc" "$out" "MISSING ROW: x fails"

# ── spec-coverage.sh: a row named only in a comment does not count ──────────
# The generic matcher (quoted-literal + `FAIL: <name>` extraction) reads every
# line of every file, so a row's name sitting inside a comment — dead code
# that never runs — satisfied it just as well as a real call. spec-coverage
# proves a row is *named*; a comment is not a test.
cat > "$W/sc-comment-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `comment-only row` | a | b |
MD
mkdir -p "$W/sc-comment"
cat > "$W/sc-comment/comment_test.sh" <<'EOF'
# FAIL: comment-only row — this line is commented out and never runs
EOF
out=$(bash "$V/spec-coverage.sh" "$W/sc-comment-spec.md" "$W/sc-comment" 2>&1); rc=$?
check "spec-coverage: a row named only in a comment does not count" 1 "$rc" "$out" "MISSING ROW: comment-only row"

# ── break-run.sh: symlink target is refused ──────────────────────────────────
# A --file that is a symlink must be refused before any copy or mutation —
# following it would let a killed run corrupt whatever the link points to,
# including a target outside the repository entirely.
brsym="$W/brsym"
mkdir -p "$brsym"
printf 'ENABLED=yes\n' > "$brsym/target.txt"
target_before=$(cat "$brsym/target.txt")
ln -s "$brsym/target.txt" "$brsym/link.txt"
out=$(run_br --file "$brsym/link.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- true 2>&1); rc=$?
check "break-run: symlink target is refused" 2 "$rc" "$out" "symlink"
target_after=$(cat "$brsym/target.txt")
[ "$target_before" = "$target_after" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: symlink target is refused — link target was modified despite refusal"; fail=1; }
[ ! -f "$brsym/link.txt.devkit-break" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: symlink target is refused — marker left behind"; fail=1; }

# ── break-run.sh: path outside the repository is refused ────────────────────
# A falsification tool must only ever touch the code under test — refuse any
# --file whose real path resolves outside the git toplevel (or outside cwd
# when not in a repo), before any copy or mutation.
brout="$W/brout"
mkrepo "$brout"
printf 'ENABLED=yes\n' > "$W/brout-outside.txt"
outside_before=$(cat "$W/brout-outside.txt")
cd "$brout" || exit
out=$(bash "$V/break-run.sh" --file "../brout-outside.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- true 2>&1); rc=$?
check "break-run: path outside the repository is refused" 2 "$rc" "$out" "outside"
cd - >/dev/null || exit
outside_after=$(cat "$W/brout-outside.txt")
[ "$outside_before" = "$outside_after" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: path outside the repository is refused — file outside the repo was modified"; fail=1; }
[ ! -f "$W/brout-outside.txt.devkit-break" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: path outside the repository is refused — marker left behind"; fail=1; }

# ── break-run.sh: concurrent run on the same file is refused ────────────────
# A plain `cp -p` over an existing marker let a second run silently overwrite
# the first run's pristine copy — the one thing standing between an
# interrupted run and a permanently mutated file.
brconc="$W/brconc"
mkdir -p "$brconc"
printf 'ENABLED=yes\n' > "$brconc/cfg.txt"
printf 'PRISTINE-FROM-RUN-ONE\n' > "$brconc/cfg.txt.devkit-break"
marker_before=$(cat "$brconc/cfg.txt.devkit-break")
out=$(run_br --file "$brconc/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- true 2>&1); rc=$?
check "break-run: concurrent run on the same file is refused" 2 "$rc" "$out" "held by another run"
marker_after=$(cat "$brconc/cfg.txt.devkit-break")
[ "$marker_before" = "$marker_after" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: concurrent run on the same file is refused — first run's pristine copy was overwritten"; fail=1; }
rm -f "$brconc/cfg.txt.devkit-break"

# ── break-run.sh: interrupted run leaves no temp output ─────────────────────
# The test command's output is buffered through a mktemp file so on_interrupt
# can kill the still-running command first; an interrupted run must not leave
# that temp file behind — they accumulated under repeated
# interrupts.
brtmp="$W/brtmp"
mkdir -p "$brtmp"
printf 'ENABLED=yes\n' > "$brtmp/cfg.txt"
tmpdir_for_test="${TMPDIR:-/tmp}"
before_tmp=$(find "$tmpdir_for_test" -maxdepth 1 -name 'break-run.out.*' 2>/dev/null | sort)
bg_br --file "$brtmp/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- sleep 60 >/dev/null 2>&1
brtmp_pid=$bg_br_pid
brtmp_tries=0
while [ ! -f "$brtmp/cfg.txt.devkit-break" ] && [ "$brtmp_tries" -lt 300 ]; do
    sleep 0.1
    brtmp_tries=$((brtmp_tries + 1))
done
if [ ! -f "$brtmp/cfg.txt.devkit-break" ]; then
    echo "FAIL: break-run: interrupted run leaves no temp output — marker never appeared, could not signal mid-run"
    fail=1
    kill -TERM "$brtmp_pid" 2>/dev/null
    wait "$brtmp_pid" 2>/dev/null
else
    brtmp_child=$(pgrep -P "$brtmp_pid" 2>/dev/null | head -1)
    kill -TERM "$brtmp_pid"
    wait "$brtmp_pid"
    brtmp_rc=$?
    [ -n "$brtmp_child" ] && kill -TERM "$brtmp_child" 2>/dev/null
    check "break-run: interrupted run leaves no temp output" 2 "$brtmp_rc"
    after_tmp=$(find "$tmpdir_for_test" -maxdepth 1 -name 'break-run.out.*' 2>/dev/null | sort)
    if [ "$before_tmp" = "$after_tmp" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL: break-run: interrupted run leaves no temp output — leftover break-run.out.* file(s) in $tmpdir_for_test"
        fail=1
    fi
fi

# ── spec-coverage.sh: an unrelated string literal does not count ────────────
# The old generic matcher counted ANY quoted literal in the file — an
# unrelated log line could satisfy a row that was never actually tested.
# Only `FAIL: <name>` or a quoted name that is the first
# argument of a test-shaped call (check/expect/assert/test/it/describe/
# should/verify/run in the callee name) may satisfy a row.
cat > "$W/sc-unrelated-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `x fails` | a | b |
MD
mkdir -p "$W/sc-unrelated"
cat > "$W/sc-unrelated/unrelated_test.go" <<'EOF'
logger.Info("x fails")
EOF
out=$(bash "$V/spec-coverage.sh" "$W/sc-unrelated-spec.md" "$W/sc-unrelated" 2>&1); rc=$?
check "spec-coverage: an unrelated string literal does not count" 1 "$rc" "$out" "MISSING ROW: x fails"

# ── checkpoint-m.sh: a crashed sub-sensor is unmeasured, not pass ───────────
# dup-gate exiting 127 (command not found / crashed) is neither the
# documented 0 (pass), 1 (fail) nor 2 (UNENFORCED) — it must never fall
# through to "M: PASS" the way only checking `-eq 1` would let it.
cp12="$W/cp12"
mkrepo "$cp12"
cd "$cp12" || exit
printf 'func TestOK(t *testing.T) {}\n' > ok_test.go
cat > "$W/cp12-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestOK` | a | b |
MD
cat > "$W/stub-dup-gate-crash.sh" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$W/stub-dup-gate-crash.sh"
out=$(DEVKIT_DUP_GATE="$W/stub-dup-gate-crash.sh" bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp12-spec.md" --tests ok_test.go --expect ok_test.go 2>&1); rc=$?
check "checkpoint-m: a crashed sub-sensor is unmeasured, not pass" 2 "$rc" "$out" "UNMEASURED"
case "$out" in *"M: PASS"*) echo "FAIL: checkpoint-m: a crashed sub-sensor is unmeasured, not pass — printed M: PASS despite dup-gate exit 127"; fail=1 ;; *) pass=$((pass + 1)) ;; esac
cd - >/dev/null || exit

# ── break-run.sh: CRLF file keeps its line endings ───────────────────────────
# Only the matched literal on the mutated line may change — a text-mode
# read/write without newline="" would translate every "\r\n" in the file to
# "\n" on read and never put the "\r" back on write, corrupting every other
# line's ending as a side effect of mutating just one of them.
cat > "$W/crlf_check.py" <<'PY'
import sys
with open(sys.argv[1], "rb") as fh:
    data = fh.read()
lines = data.split(b"\n")
ok = len(lines) >= 3 and lines[0] == b"A=1\r" and lines[2] == b"C=3\r"
print("CRLF-OK" if ok else "CRLF-BAD")
PY
brcrlf="$W/brcrlf"
mkdir -p "$brcrlf"
printf 'A=1\r\nB=2\r\nC=3\r\n' > "$brcrlf/f.txt"
cp -p "$brcrlf/f.txt" "$brcrlf/f.orig"
out=$(run_br --file "$brcrlf/f.txt" --old "B=2" --new "B=9" --row "crlf-check" -- python3 "$W/crlf_check.py" "$brcrlf/f.txt" 2>&1); rc=$?
check "break-run: CRLF file keeps its line endings" 1 "$rc" "$out" "CRLF-OK"
if cmp -s "$brcrlf/f.orig" "$brcrlf/f.txt"; then
    pass=$((pass + 1))
else
    echo "FAIL: break-run: CRLF file keeps its line endings — file not byte-identical to its pristine copy after restore"
    fail=1
fi
[ ! -f "$brcrlf/f.txt.devkit-break" ] && pass=$((pass + 1)) || { echo "FAIL: break-run: CRLF file keeps its line endings — marker left behind"; fail=1; }

# ── break-run.sh: failed restore keeps the backup ────────────────────────────
# The marker is the only pristine copy. If cp/cmp cannot put it back (here:
# the test command itself makes the target read-only), deleting the marker
# on the way out would leave the mutated file as the only copy in existence.
brfail="$W/brfail"
mkdir -p "$brfail"
printf 'ENABLED=yes\n' > "$brfail/cfg.txt"
out=$(run_br --file "$brfail/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "restore-fail" -- bash -c 'chmod 444 "$1"' _ "$brfail/cfg.txt" 2>&1); rc=$?
chmod 644 "$brfail/cfg.txt" 2>/dev/null
check "break-run: failed restore keeps the backup" 2 "$rc" "$out" "RESTORE FAILED"
if [ -f "$brfail/cfg.txt.devkit-break" ]; then
    pass=$((pass + 1))
else
    echo "FAIL: break-run: failed restore keeps the backup — pristine copy marker not kept"
    fail=1
fi
rm -f "$brfail/cfg.txt.devkit-break"

# ── break-run.sh: interrupted run kills its test command ─────────────────────
# Repeated interrupts must not leak processes: a foreground `$(cmd)` leaves
# the test command running to its own natural end even after break-run.sh
# itself has been signalled and exited.
brkill="$W/brkill"
mkdir -p "$brkill"
printf 'ENABLED=yes\n' > "$brkill/cfg.txt"
bg_br --file "$brkill/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- sleep 60 >/dev/null 2>&1
brkill_pid=$bg_br_pid
brkill_tries=0
while [ ! -f "$brkill/cfg.txt.devkit-break" ] && [ "$brkill_tries" -lt 300 ]; do
    sleep 0.1
    brkill_tries=$((brkill_tries + 1))
done
# The marker appears once break-run.sh has created it, but its `sleep 60`
# child is forked slightly later — after the mutation and the out_tmp
# mktemp both run — so a single pgrep right on the marker's heels can race
# ahead of the fork and find nothing. Poll a bounded extra 5s for the child
# to actually appear before concluding it never was.
brkill_child=""
brkill_tries3=0
while [ -z "$brkill_child" ] && [ "$brkill_tries3" -lt 50 ]; do
    brkill_child=$(pgrep -P "$brkill_pid" 2>/dev/null | head -1)
    [ -n "$brkill_child" ] && break
    sleep 0.1
    brkill_tries3=$((brkill_tries3 + 1))
done
if [ -z "$brkill_child" ]; then
    echo "FAIL: break-run: interrupted run kills its test command — marker never appeared, could not locate the sleep 60 child"
    fail=1
    kill -TERM "$brkill_pid" 2>/dev/null
    wait "$brkill_pid" 2>/dev/null
else
    kill -TERM "$brkill_pid"
    wait "$brkill_pid" 2>/dev/null
    brkill_gone=0
    brkill_tries2=0
    while [ "$brkill_tries2" -lt 100 ]; do
        kill -0 "$brkill_child" 2>/dev/null || { brkill_gone=1; break; }
        sleep 0.1
        brkill_tries2=$((brkill_tries2 + 1))
    done
    if [ "$brkill_gone" -eq 1 ]; then
        pass=$((pass + 1))
    else
        echo "FAIL: break-run: interrupted run kills its test command — sleep 60 child (pid $brkill_child) survived the interrupt"
        fail=1
        kill -TERM "$brkill_child" 2>/dev/null
    fi
fi

# ── estimate-run.py: /code run options from the plan's Tasks table ──────────
# The user picks a run mode from these numbers, so a mis-parsed table or a
# parallel-safety call that misses a shared file is a wrong choice made on
# the script's word. A table it cannot read must say so (exit 2), never print
# an estimate for zero rows.
ER="$ROOT/plugins/coding-pipeline/scripts/estimate-run.py"
cat > "$W/est-plan.md" <<'MD'
## Tasks
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | money | `a/money.go`, `a/money_test.go` | TestA, TestB | Go 1.26 | Backend | — |
| T2 | coupon | `b/coupon.go` | TestC | Go 1.26 | Backend | — |
| T3 | totals | `c/totals.go` | TestD | Go 1.26 | Backend | T1, T2 |
| T4 | docs | `b/coupon.go`, `docs/x.md` | TestE | Go 1.26 | Backend | — |
MD
out=$(python3 "$ER" --plan "$W/est-plan.md" 2>&1); rc=$?
check "estimate-run: parses the Tasks table" 0 "$rc" "$out" "4 rows · 5 files · 5 test rows"
# A Tasks row that does not match the header must stop the estimate, not be counted as a row.
printf '%s\n' '## Tasks' '| ID | Task | Files | Test rows | Language | Tier | Depends on |' '|---|---|---|---|---|---|---|' '| T1 | money | `a/money.go` | TestA | Go 1.26 | Backend |' > "$W/est-bad.md"
bad_out=$(python3 "$ER" --plan "$W/est-bad.md" 2>&1); bad_rc=$?
check "estimate-run: a malformed Tasks row exits 2 UNMEASURED" 2 "$bad_rc" "$bad_out" "ESTIMATE: UNMEASURED — malformed Tasks row"
check "estimate-run: lists the independent disjoint rows as parallel-safe" 0 "$rc" "$out" "Parallel-safe: T1, T2"
check "estimate-run: a row with a dependency is not parallel-safe" 0 "$rc" "$out" "T3 — depends on T1, T2"
check "estimate-run: a row sharing a file is not parallel-safe" 0 "$rc" "$out" "T4 — shares b/coupon.go with T2"
inline_row=$(printf '%s\n' "$out" | grep '^| Inline' || true)
seq_row=$(printf '%s\n' "$out" | grep '^| Sequential coders' || true)
check "estimate-run: a mode with no measured constant is labelled assumed" 0 "$rc" "$inline_row" "| assumed |"
check "estimate-run: a mode mixing measured and assumed constants is partly measured" 0 "$rc" "$seq_row" "| partly measured |"
# 4 rows × (coder 137k measured + main 5k) = 568k, spread by the measured coder range 59k–215k.
check "estimate-run: sequential range comes from the measured coder dispatch" 0 "$rc" "$seq_row" "245k–891k"
check "estimate-run: fix rounds carry the measured rework factors" 0 "$rc" "$out" "full ×1.5 measured (n=3)"
check "estimate-run: names the downstream validation cost by depth" 0 "$rc" "$out" "/validate-code — light: qa 99k · standard/full: qa + stress 184k"
# The label rule itself: measured only when every constant a mode uses is measured.
out=$(python3 - "$ER" "$W/est-plan.md" <<'PY' 2>&1
import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("er", sys.argv[1])
er = importlib.util.module_from_spec(spec)
spec.loader.exec_module(er)
er.MAIN_PER_ROW = er.Const(5_000, 2)
er.main(["--plan", sys.argv[2]])
print("BASIS-ALL-ASSUMED:", er.basis([er.Const(1, 0), er.Const(2, 0)]))
print("BASIS-ALL-MEASURED:", er.basis([er.Const(1, 1), er.Const(2, 4)]))
PY
); rc=$?
seq_row=$(printf '%s\n' "$out" | grep '^| Sequential coders' || true)
check "estimate-run: a mode whose every constant is measured is labelled measured" 0 "$rc" "$seq_row" "| measured |"
check "estimate-run: basis of all-assumed constants is assumed" 0 "$rc" "$out" "BASIS-ALL-ASSUMED: assumed"
check "estimate-run: basis of all-measured constants is measured" 0 "$rc" "$out" "BASIS-ALL-MEASURED: measured"
cat > "$W/est-bad.md" <<'MD'
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | money | `a.go` | TestA | Go |
MD
out=$(python3 "$ER" --plan "$W/est-bad.md" 2>&1); rc=$?
check "estimate-run: malformed Tasks row is UNMEASURED" 2 "$rc" "$out" "malformed Tasks row"
printf '# Plan\nno tasks here\n' > "$W/est-none.md"
out=$(python3 "$ER" --plan "$W/est-none.md" 2>&1); rc=$?
check "estimate-run: plan without a Tasks table is UNMEASURED" 2 "$rc" "$out" "no Tasks table"
cat > "$W/est-dep.md" <<'MD'
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | money | `a.go` | TestA | Go | Backend | T9 |
MD
out=$(python3 "$ER" --plan "$W/est-dep.md" 2>&1); rc=$?
check "estimate-run: unknown dependency is UNMEASURED" 2 "$rc" "$out" "unknown task 'T9'"
# Two coders on a directory and a file inside it, or on a glob and a file it matches, edit the
# same file in parallel; an exact string compare of the Files cells calls them disjoint.
cat > "$W/est-overlap.md" <<'MD'
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | pkg | `src/` | TestA | Go | Backend | — |
| T2 | file | `./src/a.go` | TestB | Go | Backend | — |
| T3 | glob | `lib/*.go` | TestC | Go | Backend | — |
| T4 | inglob | `lib/b.go` | TestD | Go | Backend | — |
| T5 | sibling | `srcx/c.go` | TestE | Go | Backend | — |
| T6 | dirnoslash | `docs` | TestF | Go | Backend | — |
| T7 | indir | `docs/x.md` | TestG | Go | Backend | — |
| T8 | filefirst | `pkg/x.go` | TestH | Go | Backend | — |
| T9 | dirlater | `pkg/` | TestI | Go | Backend | — |
MD
out=$(python3 "$ER" --plan "$W/est-overlap.md" 2>&1); rc=$?
check "estimate-run: a file inside a claimed directory clashes (./ and trailing slash normalised)" 0 "$rc" "$out" "T2 — shares ./src/a.go with T1"
check "estimate-run: a file matched by a claimed glob clashes" 0 "$rc" "$out" "T4 — shares lib/b.go with T3"
check "estimate-run: a directory without trailing slash still contains its files" 0 "$rc" "$out" "T7 — shares docs/x.md with T6"
check "estimate-run: a directory claimed after a file inside it clashes" 0 "$rc" "$out" "T9 — shares pkg/ with T8"
check "estimate-run: a name-prefix sibling (src/ vs srcx/) stays parallel-safe" 0 "$rc" "$out" "Parallel-safe: T1, T3, T5, T6, T8"

# ── Measured $ column: median code cost per run mode, from run-state.json ──
# The run-state reader is headless.load_runs, read from the working directory. A fixture
# run-state.json is written in the schema headless.py checks, so the reader is the real one.
mkrun() {  # mkrun <repo> <slug> <mode> <json list of stage overrides> — writes docs/plans/<slug>/run-state.json
    mkdir -p "$1/docs/plans/$2" || return 1
    python3 - "$1/docs/plans/$2/run-state.json" "$3" "$4" <<'PY'
import datetime, json, os, sys
path, mode, overrides = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
base_stage = dict(stage="code", status="ok", exit_code=0, subtype="success", model="sonnet", cost_usd=0.0,
                  input_tokens=0, output_tokens=0, cache_read=0, cache_creation=0, turns=1,
                  session_id="s", sentinel=None, wall_s=1, finished_at=now)
stages = [{**base_stage, **o} for o in overrides]
slug = os.path.basename(os.path.dirname(path))
state = dict(schema=1, plan=f"docs/plans/{slug}/plan.md", slug=slug, branch=f"feat/{slug}", base="main",
             mode=mode, stages=stages, status="done", stop_reason=None)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(state, fh)
PY
}

mc1="$W/mc1"; mkrun "$mc1" run-a sequential '[{"cost_usd": 0.30}]' && mkrun "$mc1" run-b sequential '[{"cost_usd": 0.40}, {"stage": "validate", "cost_usd": 5.00}]'
out=$(cd "$mc1" && python3 "$ER" --plan "$W/est-plan.md" 2>&1); rc=$?
seq_row=$(printf '%s\n' "$out" | grep '^| Sequential coders' || true)
check "estimate-run: measured column from run-state" 0 "$rc" "$seq_row" '| $0.35 (n=2) |'
dash=$(printf '%s\n' "$out" | grep -E '^\| (Inline|Single coder|Parallel coders)' | grep -c '| — (n=0) |' || true)
[ "$dash" = 3 ] && pass=$((pass + 1)) || { echo "FAIL: estimate-run: measured column from run-state — other modes did not read '— (n=0)' ($dash of 3)"; fail=1; }

mc0="$W/mc0"; mkdir -p "$mc0"
out=$(cd "$mc0" && python3 "$ER" --plan "$W/est-plan.md" 2>&1); rc=$?
check "estimate-run: measured column absent runs" 0 "$rc" "$out" "| Mode | Coder dispatches | Tokens | Basis | Measured $ | Notes |"
dash=$(printf '%s\n' "$out" | grep -E '^\| (Inline|Single coder|Sequential coders|Parallel coders)' | grep -c '| — (n=0) |' || true)
[ "$dash" = 4 ] && pass=$((pass + 1)) || { echo "FAIL: estimate-run: measured column absent runs — rows not all '— (n=0)' ($dash of 4)"; fail=1; }

# ── estimate-run.py --guides: guide token cost, measured from the files ──────
# The devkit's guide-cost measurement. A fixture tree with files of a
# known size pins the arithmetic (360 chars = 100 tokens at 3.6 chars/token); the
# real tree pins the dispatch graph to files that exist, so a renamed agent or
# reference fails here instead of being counted as zero.
gr="$W/guides/plugins/coding-pipeline"
mk_guide() { mkdir -p "$(dirname "$1")"; python3 -c "import sys; open(sys.argv[1],'w').write('x' * int(sys.argv[2]))" "$1" "$2"; }
for f in CLAUDE.md agents/coder.md agents/coder-backend.md agents/qa.md agents/stress.md agents/reviewer.md \
         agents/plan-reviewer.md agents/bug-investigator.md references/languages/go.md \
         skills/map/references/map-procedure.md skills/planning/SKILL.md skills/code/SKILL.md \
         skills/validate-code/SKILL.md skills/bugfix/SKILL.md; do mk_guide "$gr/$f" 360; done
mk_guide "$W/guides/plugins/pr-workflow/skills/review-code/SKILL.md" 360
out=$(python3 "$ER" --guides --root "$gr" 2>&1); rc=$?
check "estimate-run --guides: always-on CLAUDE.md is counted per session" 0 "$rc" "$out" "| CLAUDE.md (every session) | 100 |"
check "estimate-run --guides: a skill's total is its SKILL.md plus each dispatch's guides" 0 "$rc" "$out" "| /validate-code (full depth) | 100 | 2 | 200 | 300 |"
check "estimate-run --guides: a dispatch's guides sum every file it loads" 0 "$rc" "$out" "| coder (core + backend overlay + one language file) | 300 |"
python3 "$ER" --guides --root "$gr" --json > "$W/guides-before.json" 2>&1
mk_guide "$gr/CLAUDE.md" 720
out=$(python3 "$ER" --guides --root "$gr" --baseline "$W/guides-before.json" 2>&1); rc=$?
check "estimate-run --guides: baseline delta is printed" 0 "$rc" "$out" "| always-on / session | 100 | 200 | +100 |"
rm -f "$gr/agents/qa.md"
out=$(python3 "$ER" --guides --root "$gr" 2>&1); rc=$?
check "estimate-run --guides: a missing guide is UNMEASURED, never counted as zero" 2 "$rc" "$out" "agents/qa.md"
# Flat install: ~/.claude/devkit holds CLAUDE.md; agents, references and skills sit one level up.
fl="$W/flat/.claude"
mk_guide "$fl/devkit/CLAUDE.md" 360
for f in agents/coder.md agents/coder-backend.md agents/qa.md agents/stress.md agents/reviewer.md \
         agents/plan-reviewer.md agents/bug-investigator.md references/languages/go.md \
         skills/map/references/map-procedure.md skills/planning/SKILL.md skills/code/SKILL.md \
         skills/validate-code/SKILL.md skills/bugfix/SKILL.md skills/review-code/SKILL.md; do mk_guide "$fl/$f" 360; done
out=$(python3 "$ER" --guides --root "$fl/devkit" 2>&1); rc=$?
check "estimate-run --guides: resolves a flat install's layout" 0 "$rc" "$out" "| /review-code | 100 | 1 | 200 | 300 |"
out=$(python3 "$ER" --guides 2>&1); rc=$?
check "estimate-run --guides: every guide in the real dispatch graph exists" 0 "$rc" "$out" "| CLAUDE.md (every session) |"

# ── harness-metrics.py: the five Harness health signals, counted where they can be ──
# A diagnostic a human reads quarterly, never a gate. What matters here is that a count
# is a count of the reference's own definition, and that a signal the artifacts cannot
# answer says "needs judgement" instead of printing a number nobody measured.
HM="$ROOT/plugins/coding-pipeline/scripts/harness-metrics.py"
hm="$W/hm-repo"
mkdir -p "$hm" && cd "$hm" || exit
g() { git -c user.email=t@t -c user.name=t "$@"; }
git init -q -b main
mkdir -p src docs/plans/cart
printf 'package a\n' > src/a.go
cat > docs/plans/cart/plan.md <<'MD'
# Plan — cart
## Requirements & ACs
- AC1 — total is the sum of line prices
- AC2 — an empty cart totals zero
## Test Case table
| Test Name | Input / Precondition | Expected Observable Result | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| `TestTotalSums` | two lines | 3 | AC1 | money | drop the add |
| `TestEmptyIsZero` | no lines | 0 | AC2 | money | return 1 |
## Review log
- round 1: 8/10
MD
g add -A && g commit -q -m "chore: plan"
hm_base=$(git rev-parse HEAD)
git checkout -q -b feat/cart
sed -i.bak 's/^- AC2 — an empty cart totals zero/- AC2 — an empty cart totals 0/' docs/plans/cart/plan.md && rm -f docs/plans/cart/plan.md.bak
g commit -q -am "docs: AC2 wording before any code"
printf 'package a\nfunc A() {}\n' > src/a.go; printf 'package a\n' > src/b.go
g add -A && g commit -q -m "feat(cart): totals"
printf 'package a\nfunc B() {}\n' > src/b.go
g commit -q -am "fix(cart): b on the branch"
sed -i.bak 's/^- AC1 — total is the sum of line prices/- AC1 — total is the sum of line prices, rounded half-even/' docs/plans/cart/plan.md && rm -f docs/plans/cart/plan.md.bak
g commit -q -am "docs: AC1 changed after code"
printf -- '- round 2: 9/10\n' >> docs/plans/cart/plan.md
g commit -q -am "docs: review log only"
cat > docs/plans/cart/evidence.md <<'MD'
## T1
TestTotalSums ← broke src/a.go:2 → FAILED: expected 3 got 2 → restored → GREEN
Gap found: rounding mode was not in the table
Gap found: none
MD
g add -A && g commit -q -m "docs: evidence"
git checkout -q main
g merge -q --no-ff -m "Merge branch 'feat/cart'" feat/cart
printf 'package a\nfunc A() { _ = 1 }\n' > src/a.go
g commit -q -am "fix(cart): total after the merge"
printf 'x\n' > other.txt; g add other.txt; g commit -q -m "fix: unrelated file"
printf 'tmp\n' > tmp.txt; g add tmp.txt; g commit -q -m "chore: tmp"
g revert --no-edit HEAD >/dev/null
cat > PROGRESS.md <<'MD'
# PROGRESS
## Done
- [cart] T1 — CI green
## Failed
- [cart] pre-push coverage gate failed at 80%
- [cart] unit test flaked locally
- [cart] CI lint job failed on unused import
## Next
- [cart] nothing
MD
out=$(python3 "$HM" --base "$hm_base" 2>&1); rc=$?
check "harness-metrics: rework counts files touched by 2+ commits" 0 "$rc" "$out" "4 file(s) touched by 2+ commits"
check "harness-metrics: rework counts fix commits that touch a merged feature's files" 0 "$rc" "$out" "1 fix commit(s) after a feature merge"
check "harness-metrics: rework counts reverts" 0 "$rc" "$out" "1 revert(s)"
check "harness-metrics: question timing counts only AC edits after code started" 0 "$rc" "$out" "1 AC edit(s) after code started"
check "harness-metrics: question timing counts Gap found lines that are not none" 0 "$rc" "$out" "1 Gap found"
check "harness-metrics: sensor escape counts Failed entries caught at pre-push or CI" 0 "$rc" "$out" "2 of 3 Failed entries"
check "harness-metrics: test honesty counts rows without valid falsification evidence" 0 "$rc" "$out" "1 of 2 Test Case rows"
check "harness-metrics: scope creep is judgement, not a guessed number" 0 "$rc" "$out" "| Scope creep | n/a — needs judgement:"
check "harness-metrics: says it is a diagnostic, never a gate" 0 "$rc" "$out" "diagnostics, never gates"
rm -f PROGRESS.md
out=$(python3 "$HM" --base "$hm_base" 2>&1); rc=$?
check "harness-metrics: no PROGRESS.md leaves sensor escape to judgement" 0 "$rc" "$out" "| Sensor escape | n/a — needs judgement:"
# T7 / AC9: sensor escape counts `- Failed:` bullets in `## [` entries (a "none" label is not a failure)
# and still reads a legacy `## Failed` section. Each fixture carries only the shape its row names.
cat > PROGRESS.md <<'MD'
# PROGRESS
## Done
## [cart] T1 — pre-push caught it
- Failed: pre-push dup-gate red
## [cart] T2 — clean
- Failed: none
MD
out=$(python3 "$HM" --base "$hm_base" 2>&1); rc=$?
check "harness-metrics: sensor escape counts Failed bullets in entries" 0 "$rc" "$out" "1 of 1 Failed entries"
cat > PROGRESS.md <<'MD'
# PROGRESS
## Done
- [cart] T1 — CI green
## Failed
- [cart] CI lint job failed on unused import
MD
out=$(python3 "$HM" --base "$hm_base" 2>&1); rc=$?
check "harness-metrics: sensor escape still reads a Failed section" 0 "$rc" "$out" "1 of 1 Failed entries"
rm -f PROGRESS.md
cd - >/dev/null || exit
mkdir -p "$W/hm-not-git"
out=$(cd "$W/hm-not-git" && GIT_CEILING_DIRECTORIES="$W" python3 "$HM" 2>&1); rc=$?
check "harness-metrics: outside a git repository is UNMEASURED" 2 "$rc" "$out" "not a git repository"

# ── Cache hit row: prefix stability over the run-state stages in the window ──
hmc1="$W/hmc1"; mkdir -p "$hmc1" && (cd "$hmc1" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base)
mkrun "$hmc1" run-c sequential '[{"input_tokens": 10, "cache_read": 900, "cache_creation": 90}]'
out=$(cd "$hmc1" && python3 "$HM" 2>&1); rc=$?
check "harness-metrics: cache hit from run-state" 0 "$rc" "$out" "| Cache hit (driven stages) | 90.0% (n=1 stages) |"
hmc0="$W/hmc0"; mkdir -p "$hmc0" && (cd "$hmc0" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base)
out=$(cd "$hmc0" && python3 "$HM" 2>&1); rc=$?
check "harness-metrics: cache hit no runs" 0 "$rc" "$out" "| Cache hit (driven stages) | n/a — no driven runs |"

# ── new-file discipline: the rule text the validators read, and the parser beside it ──
# The rule has no mechanical sensor (the plan's decision), so these rows pin that
# the text stays in every mirror. They prove the rule is stated, not that it is obeyed.
PT="$ROOT/plugins/coding-pipeline/references/plan-template.md"
CDF="$ROOT/plugins/coding-pipeline/references/change-discipline.md"
RVW="$ROOT/plugins/coding-pipeline/agents/reviewer.md"
RCK="$ROOT/plugins/pr-workflow/skills/review-code/references/review-checklist.md"
STD="$ROOT/plugins/coding-pipeline/CLAUDE.md"

out=$(cat "$PT")
check "new-file discipline: plan template declares the New files table" 0 0 "$out" "| New path | Closest existing file | Why it cannot live there |"
check "new-file discipline: Tasks rule covers mini-plans" 0 0 "$out" 'gets a `### New files` row, in a mini-plan too'
check "new-file discipline: plan template exempts only tests beside new source" 0 0 "$out" "Exempt, no row: a test file beside a new source file"

cat > "$W/nf-plan.md" <<'MD'
## Tasks
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | money | `a/money.go` | TestA | Go 1.26 | Backend | — |

### New files
| New path | Closest existing file | Why it cannot live there |
|---|---|---|
| `a/money.go` | none | nothing comparable exists |
MD
out=$(python3 "$ER" --plan "$W/nf-plan.md" 2>&1); rc=$?
check "new-file discipline: estimate-run stops before the New files table" 0 "$rc" "$out" "T1"

out=$(cat "$ROOT/plugins/coding-pipeline/skills/planning/references/phases.md")
check "new-file discipline: planning phase 4 asks for New files" 0 0 "$out" 'A path not yet in the repo gets a `### New files` row.'
out=$(cat "$ROOT/plugins/coding-pipeline/agents/plan-reviewer.md")
check "new-file discipline: PR2 reviews new paths" 0 0 "$out" "(CD8 at plan time)"

out=$(cat "$CDF")
check "new-file discipline: CD8 row sets its severities" 0 0 "$out" "a reason that does not hold | MAJOR | HIGH |"
check "new-file discipline: CD8 example holds without a plan" 0 0 "$out" "stays in force without a plan"
check "new-file discipline: CD8 finding cites both paths" 0 0 "$out" "cites both the new path and the closest existing file"
check "new-file discipline: CD8 exempts only tests beside new source" 0 0 "$out" "Exempt: a test file beside a new source file"
check "new-file discipline: change-discipline title names rule 11" 0 0 "$out" "rules 1–3, 5, 6, 11"

out=$(cat "$RVW")
check "new-file discipline: reviewer mirrors CD8 as MAJOR" 0 0 "$out" "citing both paths (MAJOR)"
check "new-file discipline: reviewer puts CD8 on the Standards axis" 0 0 "$out" "CD2 / CD4 / CD5 / CD6 / CD8"
out=$(cat "$RCK")
check "new-file discipline: checklist mirrors CD8 as HIGH" 0 0 "$out" "cite both paths → HIGH"
check "new-file discipline: checklist puts CD8 on the Standards axis" 0 0 "$out" "CD2/CD4/CD5/CD6/CD8"
out=$(cat "$ROOT/plugins/pr-workflow/skills/review-code/references/diff-verdict-and-rules.md")
check "new-file discipline: diff verdict lists CD8 as MAJOR" 0 0 "$out" "could hold (CD8) are MAJOR"

out=$(cat "$STD")
check "new-file discipline: rule 11 states the rule" 0 0 "$out" "any new file, source included, states why it cannot (CD8)"
check "new-file discipline: CLAUDE.md range matches plan-reviewer" 0 0 "$out" "PR1–PR11"
grep -q 'PR1–PR10' "$STD"; rc=$?
check "new-file discipline: CLAUDE.md no longer says PR1–PR10" 1 "$rc"
grep -rlq 'CD1–CD7' "$ROOT/plugins"; rc=$?
check "new-file discipline: no guide still says CD1–CD7" 1 "$rc"
n=$(grep -r --include='*.md' 'CD1–CD8' "$ROOT/plugins" | wc -l | tr -d ' ')
check "new-file discipline: guides state CD1–CD8 at all 5 mentions" 5 "$n"

latest=$(grep -m1 -oE '^## \[[0-9.]+\]' "$ROOT/CHANGELOG.md" | tr -d '#[] ')
rc=0
for m in "$ROOT"/plugins/*/.claude-plugin/plugin.json; do
    [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$m")" = "$latest" ] || rc=1
done
check "release: every plugin manifest matches the newest CHANGELOG heading" 0 "$rc"
out=$(cat "$ROOT/README.md")
check "new-file discipline: README states the rule" 0 0 "$out" "**New files are justified.**"
out=$(awk '/^## \[3\.1\.0\]/{f=1;next} /^## \[/{f=0} f' "$ROOT/CHANGELOG.md")
check "new-file discipline: CHANGELOG 3.1.0 names CD8" 0 0 "$out" "CD8"

# ── checkpoint-m.sh: a new Go test file names the source file it tests ──────
cat > "$W/tfn-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestRow` | a | b |
MD
# These fixtures are one-liners, too small for dup-gate to measure, and duplication is not what they test.
printf 'exit 0\n' > "$W/tfn-dup-ok.sh"
tfn_run() {  # tfn_run <fixture> <commit|worktree> <path>... — creates each path, then runs the checkpoint
    local dir="$W/tfn-$1" mode="$2" p
    shift 2
    mkrepo "$dir"
    cd "$dir" || exit
    for p in "$@"; do
        mkdir -p "$(dirname "$p")"
        printf 'func TestRow(t *testing.T) {}\n' > "$p"
    done
    if [ "$mode" = commit ]; then
        git -c user.email=t@t -c user.name=t add -A
        git -c user.email=t@t -c user.name=t commit -q -m "fixture"
    fi
    out=$(DEVKIT_DUP_GATE="$W/tfn-dup-ok.sh" bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/tfn-spec.md" --tests "$@" --expect "$@" --allow-commits 2>&1); rc=$?
    cd "$ROOT" || exit
}
tfn_run orphan commit other.go orphan_test.go
check "checkpoint-m: new test file with no same-name source fails" 1 "$rc" "$out" "M: FAIL test-file-name"
tfn_run pair commit cart.go cart_test.go
check "checkpoint-m: new test file beside its source passes" 0 "$rc" "$out" "M: PASS"
tfn_run otherdir commit a/cart.go b/other.go b/cart_test.go
check "checkpoint-m: same name in another directory does not count" 1 "$rc" "$out" "M: FAIL test-file-name"
tfn_run benchfuzz commit other.go bench_test.go fuzz_test.go
check "checkpoint-m: bench file fails" 1 "$rc" "$out" "bench_test.go — no bench.go"
check "checkpoint-m: fuzz file fails" 1 "$rc" "$out" "fuzz_test.go — no fuzz.go"
tfn_run exempt commit other.go main_test.go export_test.go example_test.go
check "checkpoint-m: main export and example test files are exempt" 0 "$rc" "$out" "M: PASS"
tfn_run integration commit store.go store_integration_test.go
check "checkpoint-m: integration suffix pairs with its source" 0 "$rc" "$out" "M: PASS"
tfn_run ghost commit other.go ghost_integration_test.go
check "checkpoint-m: integration suffix with no source fails" 1 "$rc" "$out" "M: FAIL test-file-name"
# Each tree holds a source file too, so only the path skip can pass them, not the test-only exemption.
tfn_run ignored commit testdata/other.go testdata/orphan_test.go vendor/x/other.go vendor/x/orphan_test.go
check "checkpoint-m: testdata and vendor are ignored" 0 "$rc" "$out" "M: PASS"
tfn_run testonly commit stress/stress_test.go
check "checkpoint-m: test-only directory is exempt" 0 "$rc" "$out" "M: PASS"
tfn_run uncommitted worktree other.go orphan_test.go
check "checkpoint-m: uncommitted new test file is checked" 1 "$rc" "$out" "M: FAIL test-file-name"
tfn_pre="$W/tfn-pre"
mkrepo "$tfn_pre"
cd "$tfn_pre" || exit
printf 'func TestRow(t *testing.T) {}\n' > old_test.go
printf 'package x\n' > other.go
git -c user.email=t@t -c user.name=t add -A
git -c user.email=t@t -c user.name=t commit -q -m "misnamed before this change"
printf '// edited\n' >> old_test.go
out=$(DEVKIT_DUP_GATE="$W/tfn-dup-ok.sh" bash "$V/checkpoint-m.sh" --base HEAD --spec "$W/tfn-spec.md" --tests old_test.go --expect old_test.go 2>&1); rc=$?
cd "$ROOT" || exit
check "checkpoint-m: pre-existing misnamed test file is not flagged" 0 "$rc" "$out" "M: PASS"

# ── Go test rules: the guides state one pattern ─────────────────────────────
GO="$ROOT/plugins/coding-pipeline/references/languages/go.md"
out=$(cat "$GO")
check "go rules: test file pairing stated" 0 0 "$out" '`foo.go` is tested by `foo_test.go`'
check "go rules: test function form stated" 0 0 "$out" 'TestMyFunction_WhatIsBeingTested'
check "go rules: table variables stated" 0 0 "$out" '`tests`, each case `tt`'
check "go rules: loop copy uses tt" 0 0 "$out" '`tt := tt`'
grep -q 'tc := tc' "$GO"; rc=$?
check "go rules: no tc copy left" 1 "$rc"
check "go rules: table limits stated" 0 0 "$out" 'no `shouldCallX`, no `setupMocks func`'
check "go rules: subtest name stated" 0 0 "$out" 't.Run(tt.give'
check "go rules: setup failure stated" 0 0 "$out" '`t.Fatal`/`t.FailNow`, never `panic`'
check "go rules: review flags stated" 0 0 "$out" 'not named after its source file (`bench_test.go`, `wiring_test.go`) | MAJOR |'
check "go rules: priority order stated" 0 0 "$out" 'correctness → readability → simplification → optimization'
grep -rqE --include='*.md' 'Test_CreateOrder|for _, tc := range tests' "$ROOT/plugins"; rc=$?
check "guides: no conflicting Go test examples" 1 "$rc"
out=$(cat "$ROOT/plugins/coding-pipeline/agents/qa.md")
check "qa: test file name rule stated" 0 0 "$out" "a test file's name says what it tests"
out=$(awk '/^## \[3\.1\.1\]/{f=1;next} /^## \[/{f=0} f' "$ROOT/CHANGELOG.md")
check "release: 3.1.1 entry names the test file rule" 0 0 "$out" '`foo_test.go`'
out=$(cat "$ROOT/README.md")
check "release: README states the test file rule" 0 0 "$out" '**Go test files are paired.**'

# ── Go error and safety topic files (T13) ───────────────────────────────────
# Each test_go_topic_* helper prints `FAIL: <row>` on any miss. A grep that
# cannot read its file counts as a miss, so unmeasured text never passes.
T13_ERR="$ROOT/plugins/coding-pipeline/references/go-error-handling.md"
T13_SAFE="$ROOT/plugins/coding-pipeline/references/go-safety.md"
T13_GOMD="$ROOT/plugins/coding-pipeline/references/languages/go.md"
T13_CODER="$ROOT/plugins/coding-pipeline/agents/coder.md"
T13_BACKEND="$ROOT/plugins/coding-pipeline/agents/coder-backend.md"
T13_REVIEW="$ROOT/plugins/coding-pipeline/agents/reviewer.md"

test_go_topic_has() {  # test_go_topic_has <row> <file> <needle>... — every needle present, or the row FAILs
    local row="$1" f="$2" n miss=""
    shift 2
    for n in "$@"; do grep -qF -- "$n" "$f" || miss="$miss [$n]"; done
    if [ -z "$miss" ]; then pass=$((pass + 1)); else echo "FAIL: $row — $(basename "$f") missing:$miss"; fail=1; fi
}
test_go_topic_row() {  # test_go_topic_row <row> <file> <issue> <severity> — one Review Flags line holds both
    local row="$1" f="$2" issue="$3" sev="$4"
    if grep -F -- "$issue" "$f" | grep -qF -- "| $sev |"; then pass=$((pass + 1)); else echo "FAIL: $row — no '$issue' row at $sev in $(basename "$f")"; fail=1; fi
}
test_go_topic_once() {  # test_go_topic_once <row> <file> <literal> — exactly one occurrence
    local row="$1" f="$2" n
    n=$(grep -cF -- "$3" "$f" 2>/dev/null)
    if [ "${n:-0}" = 1 ]; then pass=$((pass + 1)); else echo "FAIL: $row — '$3' occurs ${n:-unreadable} time(s) in $(basename "$f"), want 1"; fail=1; fi
}
test_go_topic_absent() {  # test_go_topic_absent <row> <file>... — no severity cell in any named topic file
    local row="$1" f rc hit=""
    shift
    for f in "$@"; do
        grep -qF -e '| MAJOR' -e '| MINOR' -e '| CRITICAL' -e '| NIT' -- "$f"; rc=$?
        [ "$rc" = 1 ] || hit="$hit $(basename "$f")(rc=$rc)"
    done
    if [ -z "$hit" ]; then pass=$((pass + 1)); else echo "FAIL: $row — severity cell or unreadable file:$hit"; fail=1; fi
}

test_go_topic_has "go: error-handling topic file" "$T13_ERR" 'log it or return it, never both' 'errors.Join' 'nilerr' '%v' 'errors.AsType' 'samber/cc-skills-golang (MIT)'
test_go_topic_has "go: safety topic file" "$T13_SAFE" 'typed nil' 's[:len(s):len(s)]' 'comma-ok' 'defer' 'loop' 'samber/cc-skills-golang (MIT)'
test_go_topic_has "go: flags and topic links" "$T13_GOMD" 'go-error-handling.md' 'go-safety.md' '`foo.go` is tested by `foo_test.go`' 'not named after its source file (`bench_test.go`, `wiring_test.go`) | MAJOR |'
test_go_topic_row "go: flags and topic links" "$T13_GOMD" 'logged and returned' MAJOR
test_go_topic_row "go: flags and topic links" "$T13_GOMD" 'typed nil' MAJOR
test_go_topic_row "go: flags and topic links" "$T13_GOMD" 'no golangci-lint config' MINOR
test_go_topic_once "go: flags and topic links" "$T13_GOMD" 'Narrowing integer conversion with no bounds check (gosec G115)'
test_go_topic_once "go: flags and topic links" "$T13_GOMD" '`defer` inside a hot loop'
test_go_topic_absent "go: flags and topic links" "$T13_ERR" "$T13_SAFE"
test_go_topic_has "go: agents load topic files" "$T13_CODER" 'references/go-error-handling.md' 'references/go-safety.md'
test_go_topic_has "go: agents load topic files" "$T13_BACKEND" 'references/go-error-handling.md' 'references/go-safety.md'
test_go_topic_has "go: agents load topic files" "$T13_REVIEW" 'references/go-error-handling.md' 'references/go-safety.md'

# ── Go services topic file and os.Root idiom (T14) ──────────────────────────
T14_SERV="$ROOT/plugins/coding-pipeline/references/go-services.md"
T14_MODERN="$ROOT/plugins/coding-pipeline/references/go-modern-idioms.md"
test_go_topic_has "go: services topic file" "$T14_SERV" '`context.WithoutCancel`' '`sql.ErrNoRows`' '`rows.Err()`' '`SetMaxOpenConns`' '`MaxIdleConnsPerHost`' '`status.Errorf`' '`Histogram`' 'samber/cc-skills-golang (MIT)'
test_go_topic_has "go: services flags and links" "$T13_GOMD" 'go-services.md' 'rows.Err() unchecked after iteration'
test_go_topic_row "go: services flags and links" "$T13_GOMD" '`WithCancel`/`WithTimeout` not called on every path' MAJOR
test_go_topic_row "go: services flags and links" "$T13_GOMD" 'request context used for work that must outlive the request' MAJOR
test_go_topic_row "go: services flags and links" "$T13_GOMD" 'outbound `http.Client` with no `Timeout` (any URL)' MAJOR
test_go_topic_row "go: services flags and links" "$T13_GOMD" 'gRPC handler returns a raw `error`' MAJOR
test_go_topic_row "go: services flags and links" "$T13_GOMD" 'rows.Err() unchecked after iteration' MAJOR
test_go_topic_absent "go: services flags and links" "$T14_SERV"
test_go_topic_has "go: services flags and links" "$T13_CODER" 'references/go-services.md'
test_go_topic_has "go: services flags and links" "$T13_BACKEND" 'references/go-services.md'
test_go_topic_has "go: services flags and links" "$T13_REVIEW" 'references/go-services.md'
test_go_topic_row "go: os.Root idiom row" "$T14_MODERN" '`os.Root`' 1.24

# ── Go patterns at plan time and the review's topic-files line (T17) ─────────
T17_PHASES="$ROOT/plugins/coding-pipeline/skills/planning/references/phases.md"
T17_PLAN_REVIEWER="$ROOT/plugins/coding-pipeline/agents/plan-reviewer.md"
T17_REVIEWER="$ROOT/plugins/coding-pipeline/agents/reviewer.md"
check_all_needles() {  # check_all_needles <row> <file> <needle>... — every needle present, or the row FAILs
    local row="$1" f="$2" n miss=""
    shift 2
    for n in "$@"; do grep -qF -- "$n" "$f" || miss="$miss [$n]"; done
    if [ -z "$miss" ]; then pass=$((pass + 1)); else echo "FAIL: $row — $(basename "$f") missing:$miss"; fail=1; fi
}
check_all_needles "planning: language rules at design time" "$T17_PHASES" 'Language rules at design time' 'references/languages/<language>.md' 'go-error-handling.md' 'go-safety.md' 'go-services.md'
check_all_needles "plan-reviewer: language rules contradiction" "$T17_PLAN_REVIEWER" 'Also MAJOR under PR3' 'contradicts the plan' 'references/languages/<language>.md' 'go-error-handling.md' 'go-safety.md' 'go-services.md'
check_all_needles "reviewer: topic files line" "$T17_REVIEWER" 'Topic files: {paths loaded | none}' 'Language {name}: references/languages/{name}.md'

# ── Responsive and accessibility: rules exist and each stack points at them ──
FH="$ROOT/plugins/coding-pipeline/references/frontend-hardening-reference.md"
out=$(cat "$FH")
check "frontend: reflow floor stated" 0 0 "$out" 'Usable at 320 CSS px wide with no horizontal page scroll'
check "frontend: zoom may not be disabled" 0 0 "$out" 'never `user-scalable=no` or a `maximum-scale` below 2'
check "frontend: target size stated" 0 0 "$out" 'at least 24×24 CSS px'
check "frontend: keyboard and focus stated" 0 0 "$out" 'not hidden by sticky headers or banners'
check "frontend: status messages stated" 0 0 "$out" '`role="status"`'
check "frontend: jsdom cannot prove layout" 0 0 "$out" 'jsdom, which computes no layout'
check "frontend: scan does not replace keyboard row" 0 0 "$out" 'A clean scan does not prove keyboard operation'
check "frontend: review flags set severity" 0 0 "$out" 'Horizontal page scroll at 320 CSS px | MAJOR |'
out=$(cat "$ROOT/plugins/coding-pipeline/references/plan-template.md")
check "frontend: plans require UI rows" 0 0 "$out" '**Rendered UI gets responsive and accessibility rows**'
out=$(cat "$ROOT/plugins/coding-pipeline/agents/coder-frontend.md")
check "frontend: coder must test in a real browser" 0 0 "$out" '**Responsive is a real-browser test**'
out=$(cat "$ROOT/plugins/coding-pipeline/agents/qa.md")
check "frontend: qa audits the rows" 0 0 "$out" 'real-browser reflow, axe and keyboard rows'
LG="$ROOT/plugins/coding-pipeline/references/languages"
out=$(cat "$LG/html-css.md")
check "frontend: html-css states responsive rule" 0 0 "$out" '| Responsive | Mobile-first `min-width` breakpoints'
out=$(cat "$LG/react.md")
check "frontend: react states focus rule" 0 0 "$out" '| Focus | A client route change'
check "frontend: react div onClick is MAJOR" 0 0 "$out" '(`div onClick` instead of `button`) | MAJOR |'
out=$(cat "$LG/nextjs.md")
check "frontend: nextjs bans zoom-blocking viewport" 0 0 "$out" '`userScalable: false` or a `maximumScale` below 2 in `viewport` | MAJOR |'
out=$(cat "$LG/htmx.md")
check "frontend: htmx states focus after swap" 0 0 "$out" '| Focus after swap | htmx keeps focus only on inputs with an `id`'
out=$(cat "$LG/flutter.md")
check "frontend: flutter states responsive rule" 0 0 "$out" '| Responsive | `LayoutBuilder` or `MediaQuery.sizeOf`'
check "frontend: flutter states accessibility rule" 0 0 "$out" '`androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline`'
out=$(awk '/^## \[3\.1\.1\]/{f=1;next} /^## \[/{f=0} f' "$ROOT/CHANGELOG.md")
check "release: 3.1.1 entry names the front-end floor" 0 0 "$out" 'WCAG 2.2 AA'
out=$(cat "$ROOT/README.md")
check "release: README states the front-end floor" 0 0 "$out" '**Front-end work is tested for reach.**'

# ── 3.1.2: review findings on the test file check ───────────────────────────
tfn_run platform commit foo_linux.go foo_windows.go foo_test.go
check "checkpoint-m: test file pairs with a platform-split source" 0 "$rc" "$out" "M: PASS"
tfn_run e2e commit store.go store_e2e_test.go
check "checkpoint-m: e2e suffix pairs with its source" 0 "$rc" "$out" "M: PASS"
tfn_run e2eghost commit other.go ghost_e2e_test.go
check "checkpoint-m: e2e suffix with no source fails" 1 "$rc" "$out" "M: FAIL test-file-name"
tfn_mv="$W/tfn-mv"
mkrepo "$tfn_mv"
cd "$tfn_mv" || exit
printf 'func TestRow(t *testing.T) {}\nfunc helperA() {}\nfunc helperB() {}\nfunc helperC() {}\n' > old_test.go
printf 'package x\n' > other.go
git -c user.email=t@t -c user.name=t add -A
git -c user.email=t@t -c user.name=t commit -q -m "misnamed before this change"
git mv old_test.go moved_test.go
out=$(DEVKIT_DUP_GATE="$W/tfn-dup-ok.sh" bash "$V/checkpoint-m.sh" --base HEAD --spec "$W/tfn-spec.md" --tests moved_test.go --expect old_test.go moved_test.go 2>&1); rc=$?
cd "$ROOT" || exit
check "checkpoint-m: renamed test file is not judged as new" 0 "$rc" "$out" "M: PASS"

# ── checkpoint-m.sh: zoom blocking and rendered UI rows ─────────────────────
cat > "$W/ui-full.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestRow_320_axe_keyboard` | a | b |
MD
ui_run() {  # ui_run <fixture> <spec> <path|content>... — writes each file, then runs the checkpoint
    local dir="$W/ui-$1" spec="$2" item path paths
    shift 2
    mkrepo "$dir"
    cd "$dir" || exit
    printf 'func TestRow(t *testing.T) {}\nfunc TestRow_320_axe_keyboard(t *testing.T) {}\n' > main_test.go
    paths=(main_test.go)
    for item in "$@"; do
        path="${item%%|*}"
        mkdir -p "$(dirname "$path")"
        printf '%s\n' "${item#*|}" > "$path"
        paths+=("$path")
    done
    out=$(DEVKIT_DUP_GATE="$W/tfn-dup-ok.sh" bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$spec" --tests main_test.go --expect "${paths[@]}" 2>&1); rc=$?
    cd "$ROOT" || exit
}
ui_run zoomno "$W/ui-full.md" 'index.html|<meta name="viewport" content="width=device-width, user-scalable=no">'
check "checkpoint-m: user-scalable=no fails" 1 "$rc" "$out" "M: FAIL viewport-zoom"
ui_run zoomone "$W/ui-full.md" 'index.html|<meta name="viewport" content="maximum-scale=1">'
check "checkpoint-m: maximum-scale below 2 fails" 1 "$rc" "$out" "M: FAIL viewport-zoom"
ui_run zoomfive "$W/ui-full.md" 'index.html|<meta name="viewport" content="maximum-scale=5">'
check "checkpoint-m: maximum-scale of 5 passes" 0 "$rc" "$out" "M: PASS"
ui_run zoomnext "$W/ui-full.md" 'app/layout.tsx|export const viewport = { userScalable: false }'
check "checkpoint-m: nextjs userScalable false fails" 1 "$rc" "$out" "M: FAIL viewport-zoom"
ui_run zoomtest "$W/ui-full.md" 'page.test.tsx|const blocked = "user-scalable=no"'
check "checkpoint-m: zoom string in a test file is not flagged" 0 "$rc" "$out" "M: PASS"
zoom_old="$W/ui-zoomold"
mkrepo "$zoom_old"
cd "$zoom_old" || exit
printf 'func TestRow_320_axe_keyboard(t *testing.T) {}\n' > main_test.go
printf '<meta name="viewport" content="user-scalable=no">\n<p>old</p>\n' > index.html
git -c user.email=t@t -c user.name=t add -A
git -c user.email=t@t -c user.name=t commit -q -m "zoom blocked before this change"
printf '<p>new</p>\n' >> index.html
out=$(DEVKIT_DUP_GATE="$W/tfn-dup-ok.sh" bash "$V/checkpoint-m.sh" --base HEAD --spec "$W/ui-full.md" --tests main_test.go --expect index.html 2>&1); rc=$?
cd "$ROOT" || exit
check "checkpoint-m: zoom block already at base is not flagged" 0 "$rc" "$out" "M: PASS"
ui_run uimissing "$W/tfn-spec.md" 'ui/button.css|button { color: red; }'
check "checkpoint-m: rendered UI with no reach rows fails" 1 "$rc" "$out" "M: FAIL ui-rows"
check "checkpoint-m: ui-rows names each missing word" 1 "$rc" "$out" "names 'keyboard'"
ui_run uifull "$W/ui-full.md" 'ui/button.css|button { color: red; }'
check "checkpoint-m: rendered UI with reach rows passes" 0 "$rc" "$out" "M: PASS"
# The test file sits before the base: a cosmetic diff holds the stylesheet alone, or the roster check escalates it.
ui_cos="$W/ui-cosmetic"
mkrepo "$ui_cos"
cd "$ui_cos" || exit
printf 'func TestRow(t *testing.T) {}\n' > main_test.go
git -c user.email=t@t -c user.name=t add -A
git -c user.email=t@t -c user.name=t commit -q -m "test file before the base"
ui_cos_base=$(git rev-parse HEAD)
mkdir -p ui
printf 'button { color: red; }\n' > ui/button.css
git -c user.email=t@t -c user.name=t add -A
git -c user.email=t@t -c user.name=t commit -q -m "style only"
out=$(DEVKIT_DUP_GATE="$W/tfn-dup-ok.sh" bash "$V/checkpoint-m.sh" --base "$ui_cos_base" --spec "$W/tfn-spec.md" --tests main_test.go --expect ui/button.css --declared cosmetic --allow-commits 2>&1); rc=$?
cd "$ROOT" || exit
check "checkpoint-m: cosmetic depth skips ui-rows" 0 "$rc" "$out" "M: PASS"
ui_run uigo "$W/tfn-spec.md" 'cart.go|package cart'
check "checkpoint-m: non-UI change needs no reach rows" 0 "$rc" "$out" "M: PASS"

# ── 3.1.2: guide corrections ────────────────────────────────────────────────
out=$(cat "$FH")
check "frontend: scale floor is 2" 0 0 "$out" 'a `maximum-scale` below 2 |'
check "frontend: reflow catches clipped overflow" 0 0 "$out" 'no visible element outside a scroll container'
check "frontend: enforcement is stated" 0 0 "$out" 'M: FAIL ui-rows'
out=$(cat "$LG/htmx.md")
check "frontend: htmx non-semantic HTML is MAJOR" 0 0 "$out" '| Non-semantic HTML (div-soup, missing landmarks) | MAJOR |'
out=$(cat "$LG/flutter.md")
check "frontend: flutter tap target floor is stated" 0 0 "$out" 'enforces 48dp'
out=$(cat "$ROOT/plugins/coding-pipeline/agents/coder-backend.md")
check "guides: coder-backend limits tables" 0 0 "$out" 'table-driven where the logic repeats'
check "go rules: platform and e2e pairing stated" 0 0 "$(cat "$GO")" 'such as `foo_linux.go`'
out=$(awk '/^## \[3\.1\.2\]/{f=1;next} /^## \[/{f=0} f' "$ROOT/CHANGELOG.md")
check "release: 3.1.2 entry names the new checks" 0 0 "$out" 'M: FAIL ui-rows'
check "release: README states the enforcement" 0 0 "$(cat "$ROOT/README.md")" 'fails a change that omits them or blocks zoom'

rm -rf "$W"
# --- /review-code: posted comments read like a person wrote them
RC="$ROOT/plugins/pr-workflow/skills/review-code"
out=$(cat "$RC/references/posting.md")
check "review voice: posting.md leads with what breaks" 0 0 "$out" "Start with what actually breaks, then say how to fix it."
check "review voice: seriousness is carried by wording" 0 0 "$out" "this needs to change before merge because"
check "review voice: a skipped sensor is still stated in the summary" 0 0 "$out" "a sensor that did not run or a review with no spec is always stated"
check "review voice: severity still decides the review event" 0 0 "$out" '`event`: `REQUEST_CHANGES` if any CRITICAL or hard-gate FAIL, else `COMMENT`'
LC_ALL=C grep -qE '\[Standards\]|\[Spec\]|\[OWASP|Terse|Conventional Comments|score \{X\}|CRITICAL \{a\}|\xF0\x9F\x9F|\xF0\x9F\x94\xB4' "$RC/references/posting.md"; rc=$?
check "review voice: posting.md has no label, emoji, old style or score template" 1 "$rc"
out=$(cat "$RC/SKILL.md")
check "review voice: the style question offers the two styles" 0 0 "$out" "Style — Short (a sentence or two) / With suggestions"
check "review voice: terminal output keeps both axes" 0 0 "$out" 'under `## Standards` and `## Spec` exactly as the reviewer ranked them'
grep -qE 'Terse|Conventional Comments' "$RC/SKILL.md"; rc=$?
check "review voice: SKILL.md drops the old styles" 1 "$rc"
out=$(cat "$RC/references/output-format.md")
check "review voice: output-format.md points to Voice" 0 0 "$out" 'references/posting.md` § Voice'
check "review voice: printed findings keep severity" 0 0 "$out" "path/to/file.go:42: 🔴 CRITICAL: [OWASP A03]"
grep -qF '[SEVERITY]' "$RC/references/output-format.md"; rc=$?
check "review voice: output-format.md drops the [SEVERITY] template" 1 "$rc"

# ── gate-filter contract: the opt-in rewrite hook is wired and documented ──
out=$(python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
hj = os.path.join(root, "plugins", "coding-pipeline", "hooks", "hooks.json")
sh = os.path.join(root, "plugins", "coding-pipeline", "hooks", "gate-filter.sh")
with open(hj, encoding="utf-8") as fh:
    groups = json.load(fh).get("hooks", {}).get("PreToolUse", [])
wired = any(
    g.get("matcher") == "Bash"
    and any("gate-filter.sh" in h.get("command", "") and h.get("timeout") == 3 for h in g.get("hooks", []))
    for g in groups
)
if wired and os.access(sh, os.X_OK):
    print("gate-filter wired: Bash matcher, timeout 3, executable")
    sys.exit(0)
print("gate-filter not wired: needs a Bash PreToolUse entry with timeout 3, and an executable script")
sys.exit(1)
PY
); rc=$?
check "gate-filter: wired in hooks.json" 0 "$rc" "$out" "gate-filter wired"

out=$(python3 - "$ROOT" <<'PY'
import os, sys
root = sys.argv[1]
with open(os.path.join(root, "README.md"), encoding="utf-8") as fh:
    lines = fh.read().splitlines()
row = any(l.startswith("| `gate-filter.sh` |") and "PreToolUse(Bash)" in l for l in lines)
off = any("DEVKIT_DISABLED_HOOKS" in l and "pre:bash:gate-filter" in l for l in lines)
if row and off:
    print("readme gate-filter ok: hook-table row and off-switch id present")
    sys.exit(0)
print("readme gate-filter missing: hook-table row or pre:bash:gate-filter off-switch id")
sys.exit(1)
PY
); rc=$?
check "readme: gate-filter id listed" 0 "$rc" "$out" "readme gate-filter ok"

# ── go-test-guard contract: the Write guard is wired and its off-switch is documented ──
out=$(python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
hj = os.path.join(root, "plugins", "coding-pipeline", "hooks", "hooks.json")
sh = os.path.join(root, "plugins", "coding-pipeline", "hooks", "go-test-name-guard.sh")
with open(hj, encoding="utf-8") as fh:
    groups = json.load(fh).get("hooks", {}).get("PreToolUse", [])
wired = any(
    g.get("matcher") == "Write"
    and any("go-test-name-guard.sh" in h.get("command", "") and h.get("timeout") == 3 for h in g.get("hooks", []))
    for g in groups
)
if wired and os.access(sh, os.X_OK):
    print("go-test-guard wired: Write matcher, timeout 3, executable")
    sys.exit(0)
print("go-test-guard not wired: needs a Write PreToolUse entry with timeout 3, and an executable script")
sys.exit(1)
PY
); rc=$?
check "go-test-guard: wired in hooks.json" 0 "$rc" "$out" "go-test-guard wired"

out=$(python3 - "$ROOT" <<'PY'
import os, sys
root = sys.argv[1]
with open(os.path.join(root, "README.md"), encoding="utf-8") as fh:
    lines = fh.read().splitlines()
row = any(l.startswith("| `go-test-name-guard.sh` |") and "PreToolUse(Write)" in l for l in lines)
off = any("DEVKIT_DISABLED_HOOKS" in l and "pre:write:go-test-name" in l for l in lines)
if row and off:
    print("readme go-test-guard ok: hook-table row and off-switch id present")
    sys.exit(0)
print("readme go-test-guard missing: hook-table row or pre:write:go-test-name off-switch id")
sys.exit(1)
PY
); rc=$?
check "readme: go-test-guard id listed" 0 "$rc" "$out" "readme go-test-guard ok"

# ── headless contract: answers clause, sentinels, keys, report paths ─────────
HC_CODE="$ROOT/plugins/coding-pipeline/skills/code/SKILL.md"
HC_VLOOP="$ROOT/plugins/coding-pipeline/skills/validate-code/references/validation-loop.md"
HC_VSKILL="$ROOT/plugins/coding-pipeline/skills/validate-code/SKILL.md"
HC_REVIEW="$ROOT/plugins/pr-workflow/skills/review-code/SKILL.md"
HC_RUNS="$ROOT/plugins/coding-pipeline/references/headless-runs.md"
HC_RELEX="$ROOT/.devkit/release-exclude"
HC_PA="$ROOT/plugins/coding-pipeline/references/pipeline-artifacts.md"

hc_clause=1
for hc_f in "$HC_CODE" "$HC_VLOOP" "$HC_REVIEW"; do
    grep -qF 'references/headless-runs.md' "$hc_f" && grep -qF 'NEEDS_USER:' "$hc_f" || hc_clause=0
done
[ "$hc_clause" = 1 ]; rc=$?
check "headless-runs: answers clause in skills" 0 "$rc"

grep -qF 'VERDICT_LINE:' "$HC_RUNS" && grep -qF 'REVIEW_SCORE:' "$HC_RUNS" \
    && grep -qF 'VERDICT_LINE:' "$HC_VSKILL" && grep -qF 'REVIEW_SCORE:' "$HC_REVIEW"; rc=$?
check "headless-runs: sentinels pinned" 0 "$rc"

hc_keys=0
for hc_k in plan_not_approved uncommitted run_mode fix_rounds_exhausted validate_low_score \
        review_post review_language review_style review_low_score; do
    grep -qF "\`$hc_k\`" "$HC_RUNS" && hc_keys=$((hc_keys + 1))
done
[ "$hc_keys" = 9 ] && grep -qF 'PRODUCTION READY' "$HC_RUNS"; rc=$?
check "headless-runs: every key mapped" 0 "$rc"

grep -qF 'plain last line' "$HC_RUNS" && grep -qF 'no markdown' "$HC_RUNS" \
    && grep -qF 'plain last line' "$HC_VSKILL" && grep -qF 'no markdown' "$HC_VSKILL" \
    && grep -qF 'plain last line' "$HC_REVIEW" && grep -qF 'no markdown' "$HC_REVIEW"; rc=$?
check "headless-runs: sentinel is a plain last line" 0 "$rc"

grep -qF 'docs/plans/{slug}/validation/' "$HC_VSKILL" && grep -qF 'top 3' "$HC_VSKILL"; rc=$?
check "validate-code: reports written to plan dir" 0 "$rc"

grep -qxF 'docs/plans/*/validation/**' "$HC_RELEX" && grep -qxF 'bench/results/**' "$HC_RELEX" \
    && grep -qxF '**/run-state.json' "$HC_RELEX"; rc=$?
check "release-exclude: validation and bench results" 0 "$rc"

grep -qF 'validation/' "$HC_PA" && grep -qF 'run-state.json' "$HC_PA"; rc=$?
check "pipeline-artifacts: validation and run-state listed" 0 "$rc"

# ── score loop: numbers once in thresholds.md, one procedure, headless keys answer it ──
SL_TH="$ROOT/plugins/coding-pipeline/references/thresholds.md"
SL_QG="$ROOT/plugins/coding-pipeline/references/quality-gate-reference.md"
SL_HR="$ROOT/plugins/coding-pipeline/references/headless-runs.md"
sl_section() {  # sl_section <file> — the "## Score Loop" heading through the next "## " heading
    awk 'index($0, "## Score Loop") == 1 {on = 1; print; next} on && /^## / {exit} on {print}' "$1"
}

grep '^| Score loop |' "$SL_TH" | grep -qF '< 8.0' \
    && grep '^| Score loop |' "$SL_TH" | grep -qF 'the human'; rc=$?
check "score-loop: thresholds row" 0 "$rc"

grep -qF '| Plan-review rounds | 3' "$SL_TH" && ! grep -qF '| Plan-review rounds | 2 |' "$SL_TH"; rc=$?
check "score-loop: plan-review rounds 3" 0 "$rc"

sl_sec=$(sl_section "$SL_QG")
sl_line=$(grep -nF '## Score Loop' "$SL_QG" | head -1 | cut -d: -f1)
li_line=$(grep -nF '## Loop Integrity' "$SL_QG" | head -1 | cut -d: -f1)
sl_ok=1
[ -n "$sl_line" ] && [ -n "$li_line" ] && [ "$sl_line" -lt "$li_line" ] || sl_ok=0
for sl_n in 'Fix the gaps yourself' 'Accept with known issues' 'Stop' 'identical' 'thresholds.md'; do
    case "$sl_sec" in *"$sl_n"*) ;; *) sl_ok=0 ;; esac
done
[ "$sl_ok" = 1 ]; rc=$?
check "score-loop: shared section" 0 "$rc"

sl_trig=$(printf '%s\n' "$sl_sec" | grep -F 'Trigger')
sl_never=$(printf '%s\n' "$sl_sec" | grep -F 'Never a trigger')
printf '%s\n' "$sl_trig" | grep -qF 'hard-gate FAIL' && printf '%s\n' "$sl_trig" | grep -qF 'CRITICAL' \
    && printf '%s\n' "$sl_never" | grep -qF 'UNMEASURED' && printf '%s\n' "$sl_never" | grep -qF 'lens floor'; rc=$?
check "score-loop: gate fail and critical trigger the loop" 0 "$rc"

sl_fix=$(printf '%s\n' "$sl_sec" | grep -F 'Fix the gaps yourself')
printf '%s\n' "$sl_fix" | grep -qF 'one narrow re-check'; rc=$?
check "score-loop: fix yourself re-checks once" 0 "$rc"

grep -F '| `validate_low_score` |' "$SL_HR" | grep -qF 'Score Loop' \
    && grep -F '| `review_low_score` |' "$SL_HR" | grep -qF 'Score Loop'; rc=$?
check "score-loop: headless keys answer exhaustion" 0 "$rc"

# ── score loop, T2: /planning and /validate-code loop text ──────────────────
SL_PLAN_SKILL="$ROOT/plugins/coding-pipeline/skills/planning/SKILL.md"
SL_PLAN_PH="$ROOT/plugins/coding-pipeline/skills/planning/references/phases.md"
SL_PR="$ROOT/plugins/coding-pipeline/agents/plan-reviewer.md"
SL_VS="$ROOT/plugins/coding-pipeline/skills/validate-code/SKILL.md"
SL_VL="$ROOT/plugins/coding-pipeline/skills/validate-code/references/validation-loop.md"
SL_VE="$ROOT/plugins/coding-pipeline/skills/validate-code/references/execution-and-report.md"

grep -qF 'Score Loop' "$SL_PLAN_SKILL" && grep -qF 'Score Loop' "$SL_PLAN_PH" \
    && grep -qF 'plan-reviewer Score below 8.0' "$SL_PLAN_SKILL" && grep -qF 'plan-reviewer Score below 8.0' "$SL_PLAN_PH" \
    && ! grep -qF -e 'max 2' -e 'Maximum 2' "$SL_PLAN_SKILL" "$SL_PLAN_PH"; rc=$?
check "score-loop: planning loops on score" 0 "$rc"

grep -qF '3 re-review rounds' "$SL_PR" && ! grep -qF '2 re-review rounds' "$SL_PR"; rc=$?
check "score-loop: plan-reviewer rounds" 0 "$rc"

grep -qF 'Score Loop' "$SL_VL" && grep -qF 'coder' "$SL_VL" \
    && ! grep -qF -e 'report-only' -e 'without fixing anything' "$SL_VS" "$SL_VL" "$SL_VE"; rc=$?
check "score-loop: validate-code dispatches coder" 0 "$rc"

sl_vl_sec=$(sl_section "$SL_VL")
printf '%s\n' "$sl_vl_sec" | grep -qF 'only the tests that changed' \
    && printf '%s\n' "$sl_vl_sec" | grep -qF 'only its own prior findings'; rc=$?
check "score-loop: validate-code narrow re-check" 0 "$rc"

sl_crit=$(grep -F 'CRITICAL security |' "$SL_VL")
printf '%s\n' "$sl_crit" | grep -qF 'Score Loop' && ! printf '%s\n' "$sl_crit" | grep -qF 'via /code'; rc=$?
check "score-loop: validate critical loops" 0 "$rc"

# ── score loop, T3: /review-code and /pr-fix loop text ──────────────────────
SL_RC="$ROOT/plugins/pr-workflow/skills/review-code/SKILL.md"
SL_RV="$ROOT/plugins/pr-workflow/skills/review-code/references/diff-verdict-and-rules.md"
SL_PF="$ROOT/plugins/pr-workflow/skills/pr-fix/SKILL.md"

sl_low=$(grep -F '| < 8.0 | No CRITICAL |' "$SL_RV")
grep -qF 'coding-pipeline/references/quality-gate-reference.md' "$SL_RC" \
    && grep -qF 'coding-pipeline/references/quality-gate-reference.md' "$SL_RV" \
    && grep -qF 'Score Loop' "$SL_RC" && grep -qF 'Score Loop' "$SL_RV" \
    && printf '%s\n' "$sl_low" | grep -qF 'Score Loop' \
    && ! printf '%s\n' "$sl_low" | grep -qF 'push with known issues?'; rc=$?
check "score-loop: review-code loop" 0 "$rc"

sl_crit_hi=$(grep -F '| ≥ 8.0 | CRITICAL' "$SL_RV")
sl_crit_lo=$(grep -F '| < 8.0 | CRITICAL' "$SL_RV")
sl_blk=1
for sl_row in "$sl_crit_hi" "$sl_crit_lo"; do
    printf '%s\n' "$sl_row" | grep -qF 'BLOCK' || sl_blk=0
    printf '%s\n' "$sl_row" | grep -qF 'Score Loop' || sl_blk=0
done
[ "$sl_blk" = 1 ]; rc=$?
check "score-loop: review CRITICAL still blocks" 0 "$rc"

grep -qF 'Score Loop needs the branch checked out' "$SL_RC" \
    && grep -qF 'runs only for the current branch' "$SL_RC"; rc=$?
check "score-loop: review loop needs checked-out branch" 0 "$rc"

sl_pf_boundary=$(grep -F '**Boundary**' "$SL_PF")
grep -qF 'FIX_BASE' "$SL_PF" && grep -qF 'subagent_type: "reviewer"' "$SL_PF" \
    && grep -qF 'Score Loop' "$SL_PF" \
    && printf '%s\n' "$sl_pf_boundary" | grep -qF 'reviewer'; rc=$?
check "score-loop: pr-fix reviewer pass" 0 "$rc"

grep -qF 'only the fix diff' "$SL_PF" \
    && grep -qF 'remaining gaps are listed in the confirm step' "$SL_PF" \
    && grep -qF 'never posted' "$SL_PF"; rc=$?
check "score-loop: pr-fix scope and accept" 0 "$rc"

grep -qF 'vs FIX_BASE · Comments: {ids' "$SL_PF" \
    && grep -F 'Findings:' "$SL_RC" | grep -qF 'paths' \
    && grep -F 'Findings:' "$SL_PF" | grep -qF 'paths' \
    && grep -F 'Findings:' "$SL_VL" | grep -qF 'paths'; rc=$?
check "score-loop: dispatch prompts paths only" 0 "$rc"

# ── headless runner: classify, argv, sentinels, state ───────────────────────
# headless.py is driven through python3 with an injected fake runner — the real
# `claude` is never called. Each snippet prints the observed values on one line;
# the needle is that exact line, so a wrong status fails by its own row name.
HL_DIR="$ROOT/plugins/coding-pipeline/scripts"
hl_py() {  # hl_py — reads a snippet on stdin; headless.py is importable from HL_DIR
    PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); exec(sys.stdin.read())' "$HL_DIR" 2>&1
}

out=$(hl_py <<'PY'
from headless import classify
payload = {'subtype': 'success', 'result': "You've hit your 5-hour limit"}
print(f"status={classify(1, payload)}")
PY
); rc=$?
check "headless: classify limit" 0 "$rc" "$out" "status=limit"

out=$(hl_py <<'PY'
from headless import classify
payload = {'subtype': 'success', 'result': "You've hit your weekly limit"}
print(f"status={classify(0, payload)}")
PY
); rc=$?
check "headless: classify limit on exit 0" 0 "$rc" "$out" "status=limit"

out=$(hl_py <<'PY'
from headless import classify
print(f"status={classify(1, {'subtype': 'success', 'result': 'boom'})}")
PY
); rc=$?
check "headless: exit 1 without limit text" 0 "$rc" "$out" "status=error"

out=$(hl_py <<'PY'
from headless import classify
result = "Working on it.\nYou've hit your 5-hour limit\nNEEDS_USER: x"
print(f"status={classify(0, {'subtype': 'success', 'result': result})}")
PY
); rc=$?
check "headless: limit beats needs_user" 0 "$rc" "$out" "status=limit"

out=$(hl_py <<'PY'
from headless import classify, last_sentinel
result = "Two plans are open.\nNEEDS_USER: which plan?"
status = classify(0, {'subtype': 'success', 'result': result})
print(f"status={status} sentinel={last_sentinel(result, 'NEEDS_USER')}")
PY
); rc=$?
check "headless: classify needs_user" 0 "$rc" "$out" "status=needs_user sentinel=NEEDS_USER: which plan?"

out=$(hl_py <<'PY'
from headless import classify
print(f"status={classify(1, {'subtype': 'error_max_budget_usd', 'result': ''})}")
PY
); rc=$?
check "headless: classify budget" 0 "$rc" "$out" "status=budget"

out=$(hl_py <<'PY'
import subprocess
from headless import run_stage
def timed_out(argv, cwd):
    raise subprocess.TimeoutExpired(argv, 3600)
def missing(argv, cwd):
    raise FileNotFoundError(2, "No such file or directory", "claude")
kw = dict(budget_usd=3.0, tmp_dir=".", allowed_tools="Bash")
t = run_stage("code", "P", "sonnet", ".", runner=timed_out, **kw)
m = run_stage("code", "P", "sonnet", ".", runner=missing, **kw)
print(f"timeout={t.status}:{t.reason} missing={m.status}:{m.reason}")
PY
); rc=$?
check "headless: timeout and missing binary" 0 "$rc" "$out" "timeout=error:timeout after 3600s missing=error:claude not found"

# ── T6: reason field, schema 2 (schema 1 still read), anchored limit line, typed reader ──
# hl_state <root> <schema> <stage overrides JSON> — one run-state record at <root>/docs/plans/x/
hl_state() {
    mkdir -p "$1/docs/plans/x" && python3 - "$1/docs/plans/x/run-state.json" "$2" "$3" <<'PY'
import json, sys
path, schema, over = sys.argv[1], int(sys.argv[2]), json.loads(sys.argv[3])
stage = dict(stage="code", status="ok", exit_code=0, subtype="success", reason="", model="sonnet",
             cost_usd=0.5, input_tokens=1, output_tokens=1, cache_read=0, cache_creation=0, turns=1,
             session_id="s", sentinel=None, wall_s=1, finished_at="2026-11-18T00:00:00+00:00")
if schema == 1:
    del stage["reason"]
stage.update(over)
state = dict(schema=schema, plan="docs/plans/x/plan.md", slug="x", branch="feat/x", base="main",
             mode="sequential", stages=[stage], status="done", stop_reason=None)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(state, fh)
PY
}

out=$(hl_py <<'PY'
import subprocess
from headless import run_stage
def timed_out(argv, cwd):
    raise subprocess.TimeoutExpired(argv, 5)
r = run_stage("code", "P", "sonnet", ".", budget_usd=3.0, tmp_dir=".", allowed_tools="Bash",
              timeout_s=5, runner=timed_out)
print(f"reason={r.reason!r} subtype={r.subtype!r}")
PY
); rc=$?
check "headless: unrun reason in reason field" 0 "$rc" "$out" "reason='timeout after 5s' subtype=''"

out=$(hl_py <<'PY'
import json, os, shutil, tempfile
from headless import RunState, StageResult, write_state
stage = StageResult(stage="code", status="ok", exit_code=0, subtype="success", reason="", model="sonnet",
                    cost_usd=1.5, input_tokens=10, output_tokens=20, cache_read=30, cache_creation=40,
                    turns=3, session_id="s1", sentinel=None, wall_s=12, finished_at="2026-11-18T00:00:00+00:00")
state = RunState(plan="p", slug="x", branch="b", base="m", mode="sequential", stages=[stage],
                 status="running", stop_reason=None)
root = tempfile.mkdtemp(prefix="hl-schema2-")
try:
    path = os.path.join(root, "run-state.json")
    write_state(path, state)
    with open(path, encoding="utf-8") as fh:
        rec = json.load(fh)
    print(f"schema={rec['schema']} reason_on_every_stage={all('reason' in s for s in rec['stages'])}")
finally:
    shutil.rmtree(root, ignore_errors=True)
PY
); rc=$?
check "headless: state written as schema 2" 0 "$rc" "$out" "schema=2 reason_on_every_stage=True"

hl_s1="$W/hl-schema1"; hl_state "$hl_s1" 1 '{}'
out=$(hl_py <<PY
from headless import load_runs
runs = load_runs("$hl_s1")
print(f"runs={len(runs)} reasons={[s.reason for r in runs for s in r.stages]}")
PY
); rc=$?
check "headless: schema 1 record still read" 0 "$rc" "$out" "runs=1 reasons=['']"

out=$(hl_py <<'PY'
import json
from headless import run_stage
def res(text):
    payload = json.dumps({"subtype": "success", "result": text, "total_cost_usd": 0.1,
                          "num_turns": 1, "session_id": "s"})
    return run_stage("code", "P", "sonnet", ".", budget_usd=3.0, tmp_dir=".", allowed_tools="Bash",
                     runner=lambda argv, cwd: (0, payload, ""))
print(f"status={res('If you hit your limit, retry later.').status}")
PY
); rc=$?
check "headless: limit text mid-sentence is not a limit" 0 "$rc" "$out" "status=ok"

out=$(hl_py <<'PY'
import json
from headless import run_stage
def res(text):
    payload = json.dumps({"subtype": "success", "result": text, "total_cost_usd": 0.1,
                          "num_turns": 1, "session_id": "s"})
    return run_stage("code", "P", "sonnet", ".", budget_usd=3.0, tmp_dir=".", allowed_tools="Bash",
                     runner=lambda argv, cwd: (0, payload, ""))
print(f"status={res('Working.\nYou' + chr(39) + 've hit your 5-hour limit').status}")
PY
); rc=$?
check "headless: limit line opening a later line still a limit" 0 "$rc" "$out" "status=limit"

hl_bad="$W/hl-badcost"; hl_state "$hl_bad" 2 '{"cost_usd": "x"}'
out=$(hl_py <<PY
import contextlib, io
from headless import load_runs
err = io.StringIO()
with contextlib.redirect_stderr(err):
    runs = load_runs("$hl_bad")
msg = err.getvalue()
print(f"returned={len(runs)} named={'UNMEASURED' in msg and 'cost_usd is str, expected int|float' in msg}")
PY
); rc=$?
check "headless: wrong field type skips record" 0 "$rc" "$out" "returned=0 named=True"

hl_st="$W/hl-badstatus"; hl_state "$hl_st" 2 '{"status": "maybe"}'
out=$(hl_py <<PY
import contextlib, io
from headless import load_runs
err = io.StringIO()
with contextlib.redirect_stderr(err):
    runs = load_runs("$hl_st")
msg = err.getvalue()
named = 'UNMEASURED' in msg and "status is 'maybe'" in msg
print(f"returned={len(runs)} named={named}")
PY
); rc=$?
check "headless: unknown status skips record" 0 "$rc" "$out" "returned=0 named=True"

hl_bool="$W/hl-bool"; hl_state "$hl_bool" 2 '{"turns": true}'
out=$(hl_py <<PY
import contextlib, io
from headless import load_runs
err = io.StringIO()
with contextlib.redirect_stderr(err):
    runs = load_runs("$hl_bool")
msg = err.getvalue()
print(f"returned={len(runs)} named={'UNMEASURED' in msg and 'turns is bool, expected int' in msg}")
PY
); rc=$?
check "headless: bool rejected as int" 0 "$rc" "$out" "returned=0 named=True"

out=$(hl_py <<'PY'
from headless import run_stage
payload = '{"result": "x", "usage": {"input_tokens": 1e999}, "total_cost_usd": 0}'
r = run_stage("code", "P", "sonnet", ".", budget_usd=3.0, tmp_dir=".", allowed_tools="Bash",
              runner=lambda argv, cwd: (0, payload, ""))
print(f"status={r.status} input_tokens={r.input_tokens}")
PY
); rc=$?
check "headless: non-finite usage number recorded as zero" 0 "$rc" "$out" "status=ok input_tokens=0"

out=$(hl_py <<'PY'
import json, os, shutil, tempfile
from headless import RunState, run_stage, write_state
payload = '{"result": "x", "total_cost_usd": NaN, "num_turns": 1, "session_id": "s"}'
r = run_stage("code", "P", "sonnet", ".", budget_usd=3.0, tmp_dir=".", allowed_tools="Bash",
              runner=lambda argv, cwd: (0, payload, ""))
root = tempfile.mkdtemp(prefix="hl-nonfinite-")
try:
    path = os.path.join(root, "run-state.json")
    state = RunState(plan="p", slug="x", branch="b", base="m", mode="sequential", stages=[r],
                     status="running", stop_reason=None)
    write_state(path, state)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    def refuse(token):
        raise ValueError(f"non-standard JSON constant {token}")
    json.loads(text, parse_constant=refuse)
    print(f"cost={r.cost_usd} strict=ok")
finally:
    shutil.rmtree(root, ignore_errors=True)
PY
); rc=$?
check "headless: non-finite cost recorded as zero" 0 "$rc" "$out" "cost=0.0 strict=ok"

out=$(hl_py <<'PY'
from headless import build_argv
a = build_argv("P", "sonnet", 3.0, "/t", "Bash,Read", None)
print(f"argv2={a[2]} allowed_after={a.index('--allowedTools') > 2}")
PY
); rc=$?
check "headless: prompt before flags" 0 "$rc" "$out" "argv2=P allowed_after=True"

out=$(hl_py <<'PY'
from headless import last_sentinel
result = "VERDICT_LINE: NOT READY 4.0\nfix the gap\nVERDICT_LINE: PRODUCTION READY 8.9"
print(f"last={last_sentinel(result, 'VERDICT_LINE')}")
PY
); rc=$?
check "headless: last sentinel wins" 0 "$rc" "$out" "last=VERDICT_LINE: PRODUCTION READY 8.9"

out=$(hl_py <<'PY'
from headless import last_sentinel
results = [
    "done\n`VERDICT_LINE: PRODUCTION READY 8.5`",
    "done\n**VERDICT_LINE: NOT READY 4.0**",
    "done\n> VERDICT_LINE: READY WITH CONDITIONS 7.6",
]
print("|".join(str(last_sentinel(r, 'VERDICT_LINE')) for r in results))
PY
); rc=$?
check "headless: sentinel tolerates markdown wrapping" 0 "$rc" "$out" "VERDICT_LINE: PRODUCTION READY 8.5|VERDICT_LINE: NOT READY 4.0|VERDICT_LINE: READY WITH CONDITIONS 7.6"

out=$(hl_py <<'PY'
import os, shutil, sys, tempfile
from unittest import mock
from headless import RunState, StageResult, load_runs, write_state
def state(status):
    stage = StageResult(stage="code", status=status, exit_code=0, subtype="success", reason="", model="sonnet",
                        cost_usd=1.5, input_tokens=10, output_tokens=20, cache_read=30, cache_creation=40,
                        turns=3, session_id="s1", sentinel=None, wall_s=12, finished_at="2026-11-12T00:00:00+00:00")
    return RunState(plan="docs/plans/x/plan.md", slug="x", branch="feat/x-s1", base="abc",
                    mode="sequential", stages=[stage], status="running", stop_reason=None)
root = tempfile.mkdtemp(prefix="hl-atomic-")
try:
    plan_dir = os.path.join(root, "docs", "plans", "x")
    os.makedirs(plan_dir)
    path = os.path.join(plan_dir, "run-state.json")
    a, b = state("ok"), state("limit")
    try:
        write_state(path, a)
        first = load_runs(root) == [a]
    except OSError:
        first = False
    crashed = False
    with mock.patch("headless.os.replace", side_effect=OSError("simulated crash")):
        try:
            write_state(path, b)
        except OSError:
            crashed = True
    kept = load_runs(root) == [a]
    try:
        write_state(path, b)
        replaced = load_runs(root) == [b]
    except OSError:
        replaced = False
    leftovers = [n for n in os.listdir(plan_dir) if n.endswith(".tmp")]
    ok = first and crashed and kept and replaced and not leftovers
    print("atomic=ok" if ok else f"atomic=FAIL first={first} crashed={crashed} kept={kept} replaced={replaced} leftovers={leftovers}")
    sys.exit(0 if ok else 1)
finally:
    shutil.rmtree(root, ignore_errors=True)
PY
); rc=$?
check "headless: atomic state write" 0 "$rc" "$out" "atomic=ok"

out=$(hl_py <<'PY'
import contextlib, io, os, shutil, tempfile
from headless import load_runs
root = tempfile.mkdtemp(prefix="hl-malformed-")
try:
    plan_dir = os.path.join(root, "docs", "plans", "x")
    os.makedirs(plan_dir)
    with open(os.path.join(plan_dir, "run-state.json"), "w", encoding="utf-8") as fh:
        fh.write('{"schema":2}')
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        runs = load_runs(root)
    print(f"loaded={len(runs)} unmeasured={'UNMEASURED — ' in err.getvalue() and 'fields' in err.getvalue()}")
finally:
    shutil.rmtree(root, ignore_errors=True)
PY
); rc=$?
check "headless: rejects malformed state" 0 "$rc" "$out" "loaded=0 unmeasured=True"

out=$(hl_py <<'PY'
import json, os, shutil, tempfile
from headless import RunState, run_stage, write_state
payload = json.dumps({"subtype": "success", "result": "Did the work. SECRET-x in the log.",
                      "total_cost_usd": 0.5, "num_turns": 2, "session_id": "s1"})
stage = run_stage("code", "P", "sonnet", ".", budget_usd=3.0, tmp_dir=".", allowed_tools="Bash",
                  runner=lambda argv, cwd: (0, payload, ""))
state = RunState(plan="p", slug="x", branch="b", base="m", mode="sequential",
                 stages=[stage], status="running", stop_reason=None)
root = tempfile.mkdtemp(prefix="hl-fields-")
try:
    path = os.path.join(root, "run-state.json")
    write_state(path, state)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    rec = json.loads(text)
    top = {"schema", "plan", "slug", "branch", "base", "mode", "stages", "status", "stop_reason"}
    per_stage = {"stage", "status", "exit_code", "subtype", "reason", "model", "cost_usd", "input_tokens",
                 "output_tokens", "cache_read", "cache_creation", "turns", "session_id", "sentinel",
                 "wall_s", "finished_at"}
    keys_ok = set(rec) == top and all(set(s) == per_stage for s in rec["stages"])
    print(f"keys={'declared' if keys_ok else 'MISMATCH'} secret={'absent' if 'SECRET-x' not in text else 'LEAKED'}")
finally:
    shutil.rmtree(root, ignore_errors=True)
PY
); rc=$?
check "headless: state holds only declared fields" 0 "$rc" "$out" "keys=declared secret=absent"

# The default runner's stage PATH carries $(go env GOPATH)/bin when go is on PATH
# and the directory exists, because golangci-lint and govulncheck live there. A
# fake go prints a real GOPATH; with no go on PATH the PATH passes through unchanged.
out=$(hl_py <<'PY'
import os, shlex, shutil, tempfile
from unittest import mock
import headless

root = tempfile.mkdtemp(prefix="hl-gopath-")
try:
    gopath = os.path.join(root, "gp")
    os.makedirs(os.path.join(gopath, "bin"))
    stubs = os.path.join(root, "stubs")
    empty = os.path.join(root, "empty")
    os.makedirs(stubs)
    os.makedirs(empty)
    go = os.path.join(stubs, "go")
    with open(go, "w", encoding="utf-8") as fh:
        fh.write("#!/bin/sh\necho " + shlex.quote(gopath) + "\n")
    os.chmod(go, 0o755)
    seen = []

    def capture(argv, cwd, *, timeout_s, env):
        seen.append(env["PATH"])
        return 0, "{}", ""

    with mock.patch.object(headless, "_subprocess_runner", capture):
        os.environ["PATH"] = stubs + os.pathsep + empty
        headless.run_stage("code", "P", "sonnet", root, budget_usd=1.0, tmp_dir=root,
                           allowed_tools="Bash")
        os.environ["PATH"] = empty
        headless.run_stage("code", "P", "sonnet", root, budget_usd=1.0, tmp_dir=root,
                           allowed_tools="Bash")
    with_go = seen[0].split(os.pathsep)[0] == os.path.join(gopath, "bin")
    no_go = seen[1] == empty
    print(f"gopath={'ok' if with_go else 'MISSING'} nogo={'ok' if no_go else 'CHANGED'}")
finally:
    shutil.rmtree(root, ignore_errors=True)
PY
); rc=$?
check "headless: stage PATH includes GOPATH bin" 0 "$rc" "$out" "gopath=ok nogo=ok"

# ── go test naming guidance: plan, reviewer, coder and go.md name the rule ──
out=$(cat "$ROOT/plugins/coding-pipeline/references/plan-template.md")
check "go-test-name: plan-template rule" 0 0 "$out" "never a second test file for the same source"
out=$(cat "$ROOT/plugins/coding-pipeline/agents/plan-reviewer.md")
check "go-test-name: plan-reviewer flags unpaired test path" 0 0 "$out" 'MAJOR breach of the rule in `references/languages/go.md:119`'
out=$(cat "$ROOT/plugins/coding-pipeline/agents/coder.md")
check "go-test-name: coder pairs before writing" 0 0 "$out" "extend the existing one instead of creating another"
out=$(cat "$ROOT/plugins/coding-pipeline/references/languages/go.md")
check "go-test-name: go.md names the gates" 0 0 "$out" 'the `pre:write:go-test-name` guard hook and git pre-commit'

# ── go-test-name.sh: the shared pairing rule, judged per path ───────────────
# Every fixture is a real directory under $W, so the script's find/test/-f calls
# judge the tree the way checkpoint-m and pre-commit will see it.
GTN="$ROOT/plugins/coding-pipeline/git-hooks/go-test-name.sh"

g1="$W/gtn-paired"; mkdir -p "$g1"
printf 'package x\n' > "$g1/foo.go"; printf 'package x\n' > "$g1/foo_test.go"
out=$(cd "$g1" && bash "$GTN" foo_test.go 2>&1); rc=$?
silent=no; [ -z "$out" ] && silent=yes
check "go-test-name: paired file passes" 0 "$rc" "silent=$silent" "silent=yes"

g2="$W/gtn-unpaired"; mkdir -p "$g2"
printf 'package x\n' > "$g2/foo.go"; printf 'package x\n' > "$g2/foo_test.go"
printf 'package x\n' > "$g2/bar.go"; printf 'package x\n' > "$g2/baz_test.go"
out=$(cd "$g2" && bash "$GTN" baz_test.go 2>&1); rc=$?
check "go-test-name: unpaired file fails with candidates" 1 "$rc" "$out" "no baz.go in .; rename it after the source it tests or add the tests to foo_test.go"

g3="$W/gtn-exempt"; mkdir -p "$g3/plat" "$g3/stress" "$g3/testdata" "$g3/vendor/x"
printf 'package x\n' > "$g3/foo.go"
for f in main_test.go export_test.go example_test.go foo_integration_test.go; do printf 'package x\n' > "$g3/$f"; done
printf 'package x\n' > "$g3/plat/foo_linux.go"; printf 'package x\n' > "$g3/plat/foo_test.go"
printf 'package x\n' > "$g3/stress/stress_test.go"
printf 'package x\n' > "$g3/testdata/other.go"; printf 'package x\n' > "$g3/testdata/x_test.go"
printf 'package x\n' > "$g3/vendor/x/other.go"; printf 'package x\n' > "$g3/vendor/x/x_test.go"
out=$(cd "$g3" && bash "$GTN" main_test.go export_test.go example_test.go foo_integration_test.go plat/foo_test.go stress/stress_test.go testdata/x_test.go vendor/x/x_test.go 2>&1); rc=$?
check "go-test-name: exemptions pass" 0 "$rc" "$out"

g4="$W/gtn-suffix"; mkdir -p "$g4"
printf 'package x\n' > "$g4/foo.go"; printf 'package x\n' > "$g4/bar_integration_test.go"
out=$(cd "$g4" && bash "$GTN" bar_integration_test.go 2>&1); rc=$?
check "go-test-name: integration suffix needs source" 1 "$rc" "$out" "bar_integration_test.go — no bar.go"

out=$(bash "$GTN" 2>&1); rc=$?
check "go-test-name: no path argument is unmeasured" 2 "$rc" "$out" "usage: go-test-name.sh"

# ── bench ───────────────────────────────────────────────────────────────────
# bench/run.py is loaded from its file and driven with an injected fake runner,
# so the real `claude` is never called. Results go to a temp directory.
br_py() {  # br_py <root> — snippet on stdin; run.py is loaded by file path
    PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys; exec(sys.stdin.read())' "$1" 2>&1
}

out=$(br_py "$ROOT" <<'PY'
import importlib.util, io, os, re, sys, tempfile
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("bench_run", os.path.join(root, "bench", "run.py"))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
calls = []
def fake(argv, cwd):
    calls.append(argv)
    return 0, "", ""
buf, err = io.StringIO(), io.StringIO()
with tempfile.TemporaryDirectory() as tmp:
    out = os.path.join(tmp, "results")
    rc = mod.main(["--arms", "B-haiku", "--reps", "1", "--fixtures", "go-gap", "--out", out],
                  runner=fake, stdout=buf, stderr=err)
    runs = re.search(r"runs=(\d+)", buf.getvalue())
    usd = re.search(r"estimated cost: USD ([0-9.]+)", buf.getvalue())
    print(f"exit={rc} runs={runs.group(1) if runs else 'none'} cost={usd.group(1) if usd else 'none'} "
          f"calls={len(calls)} written={os.path.exists(out)}")
PY
); rc=$?
check "bench: refuses without yes" 0 "$rc" "$out" "exit=2 runs=1 cost=0.28 calls=0 written=False"

out=$(br_py "$ROOT" <<'PY'
import importlib.util, io, json, os, sys, tempfile
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("bench_run", os.path.join(root, "bench", "run.py"))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
PAYLOAD = {"type": "result", "subtype": "success", "is_error": False, "total_cost_usd": 0.1,
           "num_turns": 1, "session_id": "s",
           "usage": {"input_tokens": 1, "output_tokens": 1, "cache_read_input_tokens": 0,
                     "cache_creation_input_tokens": 0}}
def fake(argv, cwd):
    # Rep 2 of go-gap fails its code stage; rep 1 writes a file so the stage changed something.
    stage = argv[2].split(" ", 1)[0]
    if stage == "/code":
        if "/go-gap-r2/" in cwd:
            return 1, "", "simulated failure"
        open(os.path.join(cwd, "marker.txt"), "w").write("code stage output\n")
        text = "CODER DONE"
    elif stage == "/validate-code":
        text = "VERDICT_LINE: READY 8.80"
    else:
        text = "REVIEW_SCORE: 9.0 pass"
    return 0, json.dumps({**PAYLOAD, "result": text}), ""
buf, err = io.StringIO(), io.StringIO()
with tempfile.TemporaryDirectory() as tmp:
    out = os.path.join(tmp, "results")
    rc = mod.main(["--arms", "B-haiku", "--reps", "2", "--yes", "--fixtures", "go-gap", "--out", out],
                  runner=fake, stdout=buf, stderr=err)
    if rc != 0:
        print(f"rc={rc} {err.getvalue().strip()}")
    else:
        with open(os.path.join(out, "B-haiku.summary.json"), encoding="utf-8") as fh:
            agg = json.load(fh)["aggregates"]
        sc = agg["score"]
        print(f"pass_rate={agg['pass_rate']:.2f} score={sc['median']:.2f}/{sc['min']:.2f}/{sc['max']:.2f} "
              f"flipped={json.dumps(agg['flipped'])}")
PY
); rc=$?
check "bench: aggregates and flips" 0 "$rc" "$out" 'pass_rate=0.50 score=8.80/8.80/8.80 flipped=["go-gap"]'

out=$(br_py "$ROOT" <<'PY'
import json, os, re, sys
root = sys.argv[1]
fx = os.path.join(root, "bench", "fixtures")
dirs = sorted(d for d in os.listdir(fx) if os.path.isdir(os.path.join(fx, d)))
bad = [] if len(dirs) == 6 else [f"count={len(dirs)}"]
for d in dirs:
    p = os.path.join(fx, d)
    if not os.path.isdir(os.path.join(p, "seed")):
        bad.append(f"{d}: no seed/")
    with open(os.path.join(p, "plan.md"), encoding="utf-8") as fh:
        if not re.search(r"^Status: approved\b", fh.read(), re.M):
            bad.append(f"{d}: plan.md not approved")
    try:
        with open(os.path.join(p, "expected.json"), encoding="utf-8") as fh:
            exp = json.load(fh)
    except (OSError, ValueError):
        bad.append(f"{d}: expected.json unreadable")
        continue
    if not isinstance(exp, dict) or set(exp) != {"gates_green", "plan_gap", "depth"}:
        bad.append(f"{d}: expected.json fields")
    elif (not isinstance(exp["gates_green"], bool) or not isinstance(exp["plan_gap"], bool)
          or exp["depth"] not in ("cosmetic", "light", "standard", "full")):
        bad.append(f"{d}: expected.json values")
print("fixtures=6 ok" if not bad else "bad: " + "; ".join(bad))
PY
); rc=$?
check "bench: fixtures complete" 0 "$rc" "$out" "fixtures=6 ok"

# Real node and git, real temp-dir seeds: the TS gate must run node's test runner
# for a passing and a failing suite, the doc gate must read the diff against main,
# and a non-markdown change or a missing node must stay UNMEASURED (None).
out=$(br_py "$ROOT" <<'PY'
import importlib.util, os, pathlib, subprocess, sys, tempfile
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("bench_run", os.path.join(root, "bench", "run.py"))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
PASS_T = 'import { it } from "node:test";\nimport assert from "node:assert/strict";\n\nit("adds", () => { assert.equal(1 + 1, 2); });\n'
FAIL_T = PASS_T.replace("assert.equal(1 + 1, 2)", "assert.equal(1 + 1, 3)")
def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
def git(repo, *args):
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", *args],
                   cwd=repo, check=True, capture_output=True, stdin=subprocess.DEVNULL)
def ts_seed(base, test_text):
    write(os.path.join(base, "package.json"), '{"name": "seed", "private": true, "type": "module"}\n')
    write(os.path.join(base, "src", "x.test.ts"), test_text)
    return pathlib.Path(base)
def repo_on_branch(base, files):
    os.makedirs(base, exist_ok=True)
    git(base, "init", "-q", "-b", "main")
    write(os.path.join(base, "README.md"), "seed\n")
    git(base, "add", "-A"); git(base, "commit", "-q", "-m", "seed")
    git(base, "checkout", "-q", "-b", "feat/x")
    for name, text in files.items():
        write(os.path.join(base, name), text)
    git(base, "add", "-A"); git(base, "commit", "-q", "-m", "change")
    return pathlib.Path(base)
with tempfile.TemporaryDirectory() as tmp:
    ts_ok = mod.gate_green(ts_seed(os.path.join(tmp, "ts-ok"), PASS_T))
    ts_red = mod.gate_green(ts_seed(os.path.join(tmp, "ts-red"), FAIL_T))
    doc = mod.gate_green(repo_on_branch(os.path.join(tmp, "doc"), {"NOTES.md": "# notes\n"}))
    third = mod.gate_green(repo_on_branch(os.path.join(tmp, "third"), {"x.go": "package x\n"}))
    saved = os.environ["PATH"]
    os.environ["PATH"] = os.path.join(tmp, "no-bin")  # node cannot be found
    try:
        no_node = mod.gate_green(ts_seed(os.path.join(tmp, "ts-nonode"), PASS_T))
    finally:
        os.environ["PATH"] = saved
    print(f"ts={ts_ok} ts_red={ts_red} doc={doc} third={third} no_node={no_node}")
PY
); rc=$?
check "bench: scores ts and doc seeds" 0 "$rc" "$out" "ts=True ts_red=False doc=True third=None no_node=None"

out=$(br_py "$ROOT" <<'PY'
import importlib.util, os, sys
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("bench_run", os.path.join(root, "bench", "run.py"))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
s = "VERDICT_LINE: NOT READY 4.0/10"
print(f"score={mod.verdict_score(s)} verdict={mod.verdict_name(s)}")
PY
); rc=$?
check "bench: verdict score tolerates /10" 0 "$rc" "$out" "score=4.0 verdict=NOT READY"

out=$(br_py "$ROOT" <<'PY'
import importlib.util, io, json, os, sys, tempfile
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("bench_run", os.path.join(root, "bench", "run.py"))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
PAYLOAD = {"type": "result", "subtype": "success", "is_error": False, "total_cost_usd": 0.1,
           "num_turns": 1, "session_id": "s",
           "usage": {"input_tokens": 1, "output_tokens": 1, "cache_read_input_tokens": 0,
                     "cache_creation_input_tokens": 0}}
BIG = "".join(str(i % 10) for i in range(2000))
TEXTS = {"code": BIG, "validate": BIG[:1960] + "\nVERDICT_LINE: PRODUCTION READY 8.80",
         "review": BIG[:1500] + "\nREVIEW_SCORE: 9.0 pass"}
def fake(argv, cwd):
    stage = argv[2].split(" ", 1)[0]
    if stage == "/code":
        open(os.path.join(cwd, "marker.txt"), "w").write("code stage output\n")
        text = TEXTS["code"]
    elif stage == "/validate-code":
        text = TEXTS["validate"]
    else:
        text = TEXTS["review"]
    return 0, json.dumps({**PAYLOAD, "result": text}), ""
buf, err = io.StringIO(), io.StringIO()
with tempfile.TemporaryDirectory() as tmp:
    out = os.path.join(tmp, "results")
    rc = mod.main(["--arms", "B-haiku", "--reps", "1", "--yes", "--fixtures", "go-gap", "--out", out],
                  runner=fake, stdout=buf, stderr=err)
    if rc != 0:
        print(f"rc={rc} {err.getvalue().strip()}")
    else:
        with open(os.path.join(out, "B-haiku.summary.json"), encoding="utf-8") as fh:
            run = json.load(fh)["runs"][0]
        tails_ok = all(st.get("result_tail") == TEXTS[st["stage"]][-500:] for st in run["stages"])
        longest = max(len(st.get("result_tail", "")) for st in run["stages"])
        print(f"verdict={run.get('verdict')} tails={'ok' if tails_ok else 'bad'} max={longest}")
PY
); rc=$?
check "bench: run records verdict and result tail" 0 "$rc" "$out" "verdict=PRODUCTION READY tails=ok max=500"

out=$(br_py "$ROOT" <<'PY'
import importlib.util, io, json, os, subprocess, sys, tempfile
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("bench_run", os.path.join(root, "bench", "run.py"))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
def timed_out(argv, cwd):
    raise subprocess.TimeoutExpired(argv, 1)
buf, err = io.StringIO(), io.StringIO()
with tempfile.TemporaryDirectory() as tmp:
    out = os.path.join(tmp, "results")
    mod.main(["--arms", "B-haiku", "--reps", "1", "--yes", "--fixtures", "go-gap", "--out", out],
             runner=timed_out, stdout=buf, stderr=err)
    with open(os.path.join(out, "B-haiku.summary.json"), encoding="utf-8") as fh:
        st = json.load(fh)["runs"][0]["stages"][0]
    print(f"reason_ok={st.get('reason', '').startswith('timeout after')} subtype={st.get('subtype')!r}")
PY
); rc=$?
check "bench: stage record carries reason" 0 "$rc" "$out" "reason_ok=True subtype=''"

# ── drive: refusals before any stage, and --resume-from state ───────────────
# drive.py runs in temp git repos. `claude` is a fake on PATH that leaves a
# marker if it is ever called, so "no runner call" is observed, not assumed.
# DR_RC is 99 when the marker exists, so a refused row that called claude fails.
DR_PY="$ROOT/plugins/coding-pipeline/scripts/drive.py"
DR_BIN="$W/drive-bin"
mkdir -p "$DR_BIN"
printf '#!/usr/bin/env bash\ntouch "$DRIVE_MARK"\nexit 9\n' > "$DR_BIN/claude"
chmod +x "$DR_BIN/claude"

dr_repo() {  # dr_repo <dir> <branch> — a repo with one commit on <branch>
    mkdir -p "$1" && cd "$1" || exit
    git init -q -b "$2"
    # drive.py commits with the repo's own identity; a CI runner has none, so the fixture sets one.
    git config user.email t@t
    git config user.name t
    printf 'base\n' > base.txt
    git -c user.email=t@t -c user.name=t add base.txt
    git -c user.email=t@t -c user.name=t commit -q -m base
    cd - >/dev/null || exit
}
dr_plan() {  # dr_plan <repo> <slug> <status> — an untracked plan under docs/plans/<slug>/
    mkdir -p "$1/docs/plans/$2"
    printf '# Plan — fixture\n\nStatus: %s · Branch: feat/x\n' "$3" > "$1/docs/plans/$2/plan.md"
}
dr_go() {  # dr_go <repo> <drive args...> — sets DR_OUT and DR_RC
    local repo="$1" mark="$W/claude-called"
    shift
    rm -f "$mark"
    DR_OUT=$(cd "$repo" && PYTHONDONTWRITEBYTECODE=1 DRIVE_MARK="$mark" PATH="$DR_BIN:$PATH" \
        python3 "$DR_PY" "$@" 2>&1); DR_RC=$?
    [ -e "$mark" ] && DR_RC=99
    return 0
}

r="$W/dr-draft"; dr_repo "$r" feat/x; dr_plan "$r" alpha draft
dr_go "$r" --plan docs/plans/alpha/plan.md
check "drive: refuses unapproved plan" 2 "$DR_RC" "$DR_OUT" "drive: REFUSED — plan Status is 'draft'"

r="$W/dr-main"; dr_repo "$r" main; dr_plan "$r" alpha approved
dr_go "$r" --plan docs/plans/alpha/plan.md
dr_rc_main=$DR_RC; dr_out_main=$DR_OUT
r="$W/dr-master"; dr_repo "$r" master; dr_plan "$r" alpha approved
dr_go "$r" --plan docs/plans/alpha/plan.md
[ "$dr_rc_main" = 2 ] && [ "$DR_RC" = 2 ]; rc=$?
check "drive: refuses main and master" 0 "$rc" "$dr_out_main$DR_OUT" "drive: REFUSED — branch 'main' is a mainline"
case "$DR_OUT" in *"branch 'master' is a mainline"*) ;; *) rc=1 ;; esac
check "drive: refuses main and master" 0 "$rc" "$DR_OUT" "branch 'master' is a mainline"

r="$W/dr-dirty"; dr_repo "$r" feat/x; dr_plan "$r" alpha approved
mkdir -p "$r/src" && printf 'package x\n' > "$r/src/x.go"
dr_go "$r" --plan docs/plans/alpha/plan.md
check "drive: refuses dirty tree" 2 "$DR_RC" "$DR_OUT" "drive: REFUSED — uncommitted paths outside docs/: src/x.go"

r="$W/dr-slug"; dr_repo "$r" feat/x; dr_plan "$r" "Bad Slug" approved
dr_go "$r" --plan "docs/plans/Bad Slug/plan.md"
check "drive: refuses bad slug" 2 "$DR_RC" "$DR_OUT" "drive: REFUSED — plan slug 'Bad Slug' does not match"

r="$W/dr-bad-state"; dr_repo "$r" feat/x; dr_plan "$r" alpha approved
printf '{"schema":2}\n' > "$r/docs/plans/alpha/run-state.json"
dr_go "$r" --plan docs/plans/alpha/plan.md --resume-from validate
check "drive: resume-from malformed state" 2 "$DR_RC" "$DR_OUT" "is not a schema-valid record"

r="$W/dr-no-state"; dr_repo "$r" feat/x; dr_plan "$r" alpha approved
dr_go "$r" --plan docs/plans/alpha/plan.md --resume-from validate
check "drive: resume-from missing state" 2 "$DR_RC" "$DR_OUT" "nothing to resume from"

# ── drive: stage loop, commit, stops, never pushes ──────────────────────────
# The stages run through the real headless.run_stage path. `claude` on PATH is a fake: it logs
# each call's argv (NUL-separated) and replays the canned payload for its stage. `git` on PATH is
# a spy: it logs every git call and makes `commit` fail with DRIVE_GIT_FAIL_COMMIT on stderr when
# set; otherwise it runs the real git. The real claude is never run.
DS_BIN="$W/drive-spy-bin"
DS_REAL_GIT="$(command -v git)"
mkdir -p "$DS_BIN"
cat > "$DS_BIN/claude" <<'EOF'
#!/usr/bin/env bash
# fake claude: log this call's argv, write the stage's change if asked, replay its canned payload
n=$(( $(cat "$DRIVE_SPY/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$DRIVE_SPY/count"
printf '%s\0' "$@" > "$DRIVE_SPY/call-$n.argv"
case "$2" in
    /validate-code*) stage=validate ;;
    /review-code*) stage=review ;;
    *) stage=code ;;
esac
if [ -f "$DRIVE_FIX/$stage.write" ]; then
    while IFS= read -r p; do
        mkdir -p "$(dirname "$p")" && echo "change" > "$p"
    done < "$DRIVE_FIX/$stage.write"
fi
cat "$DRIVE_FIX/$stage.json"
EOF
cat > "$DS_BIN/git" <<'EOF'
#!/usr/bin/env bash
# git spy: log every call; a commit fails with hook output when DRIVE_GIT_FAIL_COMMIT is set
printf '%s\n' "$*" >> "$DRIVE_GIT_LOG"
if [ "$1" = commit ] && [ -n "${DRIVE_GIT_FAIL_COMMIT:-}" ]; then
    echo "$DRIVE_GIT_FAIL_COMMIT" >&2
    exit 1
fi
exec "$DRIVE_REAL_GIT" "$@"
EOF
chmod +x "$DS_BIN/claude" "$DS_BIN/git"

# Inspects one run: argv facts from the claude spy, and the run-state record.
cat > "$W/ds-inspect.py" <<'PY'
import glob, json, os, sys
spy, state_path = sys.argv[1], sys.argv[2]
calls = []
for path in glob.glob(os.path.join(spy, "call-*.argv")):
    with open(path, "rb") as fh:
        calls.append((int(os.path.basename(path)[5:-5]), fh.read().decode("utf-8").split("\0")[:-1]))
calls = [argv for _, argv in sorted(calls)]
GRANT = "Bash,Agent,Glob,Grep,Skill,Read(~/.claude/**)"
ANSWERS = ("Answers: plan_not_approved=stop; uncommitted=stop; run_mode=sequential; "
           "fix_rounds_exhausted=stop; validate_low_score=stop; review_post=no; "
           "review_language=English; review_style=short; review_low_score=stop")
def value(argv, flag):
    i = argv.index(flag) if flag in argv else -1
    return argv[i + 1] if 0 <= i < len(argv) - 1 else None
def prompt(argv):
    return argv[argv.index("-p") + 1]
def stage(argv):
    return {"/code": "code", "/validate-code": "validate", "/review-code": "review"}.get(prompt(argv).split(" ")[0], "?")
grant = bool(calls) and all(
    value(a, "--permission-mode") == "acceptEdits"
    and value(a, "--allowedTools") == GRANT
    and not ({"--dangerously-skip-permissions", "--bare"} & set(a))
    for a in calls)
answers = bool(calls) and all(ANSWERS in prompt(a) for a in calls)
resume = sum(1 for a in calls for x in a if x.startswith("--resume"))
state, recs = "none", 0
if os.path.exists(state_path):
    with open(state_path, encoding="utf-8") as fh:
        data = json.load(fh)
    state, recs = data["status"], len(data["stages"])
print(f"calls={len(calls)} stages={','.join(stage(a) for a in calls)} resume={resume} "
      f"grant={'ok' if grant else 'bad'} answers={'ok' if answers else 'bad'} state={state} recs={recs}")
PY

ds_fix() {  # ds_fix <fix-dir> <stage> <result text> [subtype] — the canned payload one stage returns
    python3 -c '
import json, os, sys
d, stage, text, subtype = sys.argv[1:5]
payload = {"type": "result", "subtype": subtype, "is_error": False, "result": text,
           "session_id": "s-" + stage, "total_cost_usd": 0.25, "num_turns": 4,
           "usage": {"input_tokens": 10, "output_tokens": 20,
                     "cache_read_input_tokens": 30, "cache_creation_input_tokens": 5}}
with open(os.path.join(d, stage + ".json"), "w", encoding="utf-8") as fh:
    fh.write(json.dumps(payload) + "\n")
' "$1" "$2" "$3" "${4:-success}"
}
ds_new() {  # ds_new <name> <branch> — a repo with an approved plan and a happy-path fixture; sets DS_*
    local base="$W/ds-$1"
    rm -rf "$base"
    DS_R="$base/repo"; DS_FIX="$base/fix"; DS_SPY="$base/spy"; DS_GLOG="$base/git.log"
    mkdir -p "$DS_FIX"
    dr_repo "$DS_R" "$2"; dr_plan "$DS_R" alpha approved
    ds_fix "$DS_FIX" code "Implemented alpha."
    ds_fix "$DS_FIX" validate "Validated alpha.
VERDICT_LINE: PRODUCTION READY 8.5"
    ds_fix "$DS_FIX" review "Reviewed alpha.
REVIEW_SCORE: 9 pass"
    echo "src/a.go" > "$DS_FIX/code.write"
    DS_FAIL=""
}
ds_go() {  # ds_go <drive args...> — run drive.py in DS_R with the spies first on PATH; sets DS_OUT, DS_RC
    rm -rf "$DS_SPY"; mkdir -p "$DS_SPY"; : > "$DS_GLOG"
    DS_OUT=$(cd "$DS_R" && PYTHONDONTWRITEBYTECODE=1 DRIVE_FIX="$DS_FIX" DRIVE_SPY="$DS_SPY" \
        DRIVE_GIT_LOG="$DS_GLOG" DRIVE_REAL_GIT="$DS_REAL_GIT" DRIVE_GIT_FAIL_COMMIT="$DS_FAIL" \
        PATH="$DS_BIN:$PATH" python3 "$DR_PY" "$@" 2>&1); DS_RC=$?
}
ds_happy() { ds_new happy feat/x; ds_go --plan docs/plans/alpha/plan.md; }
ds_facts() { python3 "$W/ds-inspect.py" "$DS_SPY" "$DS_R/docs/plans/alpha/run-state.json"; }
ds_calls() { ls "$DS_SPY" 2>/dev/null | grep -c '^call-'; }
ds_commits() { git -C "$DS_R" rev-list --count HEAD; }
ds_stop() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("stop_reason") or "")' "$DS_R/docs/plans/alpha/run-state.json"; }

ds_new detached feat/x; git -C "$DS_R" checkout -q --detach
ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 2 ] && [ "$(ds_calls)" = 0 ]; rc=$?
check "drive: refuses detached HEAD" 0 "$rc" "$DS_OUT" "drive: REFUSED — HEAD is detached"

ds_new docs-only feat/x
mkdir -p "$DS_R/docs/plans/alpha" && printf 'notes\n' > "$DS_R/docs/plans/alpha/notes.md"
rm -f "$DS_FIX/code.write"
ds_go --plan docs/plans/alpha/plan.md
rc=1; case "$DS_OUT" in *"drive: REFUSED"*) ;; *) rc=0 ;; esac
check "drive: docs-only changes allowed" 0 "$rc" "$(ds_facts) $DS_OUT" "calls=1 stages=code"

ds_happy
check "drive: answers line" 0 "$DS_RC" "$(ds_facts)" "answers=ok"

ds_happy
check "drive: exact grant" 0 "$DS_RC" "$(ds_facts)" "grant=ok"

ds_new resume feat/x
ds_fix "$DS_FIX" validate "VERDICT_LINE: NOT READY 4.0"
ds_go --plan docs/plans/alpha/plan.md
cp "$DS_R/docs/plans/alpha/run-state.json" "$W/ds-resume-before.json"
ds_fix "$DS_FIX" validate "VERDICT_LINE: PRODUCTION READY 8.5"
ds_go --plan docs/plans/alpha/plan.md --resume-from validate
same=$(python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["stages"][0]; b=json.load(open(sys.argv[2]))["stages"][0]; print("same" if a == b else "changed")' "$W/ds-resume-before.json" "$DS_R/docs/plans/alpha/run-state.json")
[ "$DS_RC" = 0 ] && [ "$(ds_calls)" = 2 ] && [ "$same" = same ]; rc=$?
check "drive: resume-from validate" 0 "$rc" "$DS_OUT $(ds_facts) code_record=$same" "calls=2 stages=validate,review resume=0 grant=ok answers=ok state=done recs=3 code_record=same"

# AC12b: a resume past the code stage needs a code commit, a code record, and (for review) a validate record.
ds_new nothing feat/x; rm -f "$DS_FIX/code.write"
ds_go --plan docs/plans/alpha/plan.md
setup=$(ds_stop)
ds_go --plan docs/plans/alpha/plan.md --resume-from validate
[ "$setup" = "code stage changed nothing" ] && [ "$DS_RC" = 2 ] && [ "$(ds_calls)" = 0 ]; rc=$?
check "drive: resume refused when code committed nothing" 0 "$rc" "$DS_OUT" "--resume-from validate: HEAD is still the recorded base; the code stage committed nothing"

ds_happy
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["stages"]=[]; json.dump(d, open(p,"w"))' "$DS_R/docs/plans/alpha/run-state.json"
ds_go --plan docs/plans/alpha/plan.md --resume-from validate
[ "$DS_RC" = 2 ] && [ "$(ds_calls)" = 0 ]; rc=$?
check "drive: resume refused without code record" 0 "$rc" "$DS_OUT" "--resume-from validate: the recorded run has no code stage record"

ds_happy
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["stages"]=[s for s in d["stages"] if s["stage"]=="code"]; json.dump(d, open(p,"w"))' "$DS_R/docs/plans/alpha/run-state.json"
ds_go --plan docs/plans/alpha/plan.md --resume-from review
[ "$DS_RC" = 2 ] && [ "$(ds_calls)" = 0 ]; rc=$?
check "drive: resume-from review refused without validate record" 0 "$rc" "$DS_OUT" "--resume-from review: the recorded run has no validate stage record"

ds_new conditions feat/x; ds_fix "$DS_FIX" validate "VERDICT_LINE: READY WITH CONDITIONS 7.6"
ds_go --plan docs/plans/alpha/plan.md
setup=$(ds_stop)
ds_go --plan docs/plans/alpha/plan.md --resume-from review
[ "$setup" = "validate verdict READY WITH CONDITIONS 7.6" ] && [ "$DS_RC" = 0 ] && [ "$(ds_calls)" = 1 ]; rc=$?
check "drive: resume-from review after conditions" 0 "$rc" "$DS_OUT $(ds_facts)" "calls=1 stages=review resume=0 grant=ok answers=ok state=done recs=3"

ds_new happy feat/x; c0=$(ds_commits); ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 0 ] && [ "$(ds_commits)" = $((c0 + 1)) ] && [ "$(ds_calls)" = 3 ]; rc=$?
check "drive: happy path three fresh stages" 0 "$rc" "$DS_OUT $(ds_facts)" "calls=3 stages=code,validate,review resume=0 grant=ok answers=ok state=done recs=3"

ds_new conditions feat/x; ds_fix "$DS_FIX" validate "VERDICT_LINE: READY WITH CONDITIONS 7.6"
ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 1 ] && [ "$(ds_calls)" = 2 ]; rc=$?
check "drive: stops on conditions" 0 "$rc" "$DS_OUT" "STOPPED — validate verdict READY WITH CONDITIONS 7.6"

ds_new nosentinel feat/x; ds_fix "$DS_FIX" validate "Validated alpha; looks fine."
ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 1 ] && [ "$(ds_calls)" = 2 ]; rc=$?
check "drive: stops on missing sentinel" 0 "$rc" "$DS_OUT" "STOPPED — no VERDICT_LINE"

ds_new block feat/x; ds_fix "$DS_FIX" review "REVIEW_SCORE: 6 block"
ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 1 ] && [ "$(ds_calls)" = 3 ]; rc=$?
check "drive: stops on review block" 0 "$rc" "$DS_OUT" "STOPPED — review block: REVIEW_SCORE: 6 block"

ds_new limit feat/x; ds_fix "$DS_FIX" code "You've hit your limit · resets 5am"
ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 1 ] && [ "$(ds_calls)" = 1 ]; rc=$?
check "drive: halts on limit" 0 "$rc" "$DS_OUT" "STOPPED — usage limit: stopped, not retried"

ds_new needsuser feat/x; ds_fix "$DS_FIX" code "NEEDS_USER: which plan?"
ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 1 ] && [ "$(ds_calls)" = 1 ]; rc=$?
check "drive: stops on needs_user" 0 "$rc" "$DS_OUT" "STOPPED — needs user: which plan?"

ds_new emptydiff feat/x; rm -f "$DS_FIX/code.write"; c0=$(ds_commits)
ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 1 ] && [ "$(ds_commits)" = "$c0" ] && [ "$(ds_calls)" = 1 ]; rc=$?
check "drive: stops on empty code diff" 0 "$rc" "$DS_OUT" "STOPPED — code stage changed nothing"

ds_new rejected feat/x; DS_FAIL="BLOCKED x"; c0=$(ds_commits)
ds_go --plan docs/plans/alpha/plan.md
DS_FAIL=""
reason=$(ds_stop)
[ "$DS_RC" = 1 ] && [ "$(ds_commits)" = "$c0" ] && [ "${#reason}" -le 300 ] \
    && case "$reason" in "commit rejected: "*"BLOCKED x") true ;; *) false ;; esac; rc=$?
check "drive: stops on rejected commit" 0 "$rc" "$DS_OUT $reason" "STOPPED — commit rejected: BLOCKED x"

ds_new scope feat/x
mkdir -p "$DS_R/docs/plans/alpha/validation" && printf 'qa\n' > "$DS_R/docs/plans/alpha/validation/qa.md"
ds_go --plan docs/plans/alpha/plan.md
committed=$(git -C "$DS_R" diff-tree --no-commit-id --name-only -r HEAD)
[ "$DS_RC" = 0 ] && [ "$committed" = "src/a.go" ]; rc=$?
check "drive: commit stages only outside docs" 0 "$rc" "$DS_OUT $committed" "src/a.go"

# AC11b / SEC-5: a credential the code stage wrote through Bash is never committed. The env-file
# name is assembled from pieces so this script's own text holds no literal env-file name.
DS_SECRET="config/$(printf '.%s.local' env)"
ds_new deny feat/x; c0=$(ds_commits)
printf 'src/a.go\n%s\n' "$DS_SECRET" > "$DS_FIX/code.write"
ds_go --plan docs/plans/alpha/plan.md
staged=$(git -C "$DS_R" diff --cached --name-only)
reason=$(ds_stop)
[ "$DS_RC" = 1 ] && [ "$(ds_commits)" = "$c0" ] && [ -z "$staged" ] && [ -f "$DS_R/$DS_SECRET" ] \
    && [ "$(ds_calls)" = 1 ] \
    && case "$reason" in "staged file matches deny list: $DS_SECRET") true ;; *) false ;; esac; rc=$?
check "drive: refuses to commit a deny-listed file" 0 "$rc" "$DS_OUT $reason staged=[$staged]" "STOPPED — staged file matches deny list: $DS_SECRET"

ds_happy
rc=1; [ "$DS_RC" = 0 ] && ! grep -q '^push' "$DS_GLOG" && rc=0
check "drive: never pushes" 0 "$rc" "$DS_OUT $(cat "$DS_GLOG")" "commit -m"

# ── drive: resume ancestry, failed code record, driver lock, stale tmp, template exemption ──
# AC9 / AC18 / AC15 / SEC-3 / SEC-5. Every git call here sets its own identity, so nothing relies
# on a global or repo config (CI runs with user.useConfigOnly=true).
gitc() { git -c user.email=t@t -c user.name=t "$@"; }
# Env-file names are assembled from pieces so this script's own text holds no literal env name.
ENV_TPL="$(printf '.env.%s' example)"
ENV_LOOK="$(printf '.env.%s' examples)"

ds_happy
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["stages"][0]["status"]="error"; json.dump(d, open(p,"w"))' "$DS_R/docs/plans/alpha/run-state.json"
ds_go --plan docs/plans/alpha/plan.md --resume-from validate
[ "$DS_RC" = 2 ] && [ "$(ds_calls)" = 0 ]; rc=$?
check "drive: resume refused when code record failed" 0 "$rc" "$DS_OUT" "--resume-from validate: the recorded code stage ended error; rerun from code"

ds_happy
base_sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["base"])' "$DS_R/docs/plans/alpha/run-state.json")
git -C "$DS_R" checkout -q -b other "$base_sha"
gitc -C "$DS_R" commit -q --allow-empty -m other
other_sha=$(git -C "$DS_R" rev-parse HEAD)
git -C "$DS_R" checkout -q feat/x
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["base"]=sys.argv[2]; json.dump(d, open(p,"w"))' "$DS_R/docs/plans/alpha/run-state.json" "$other_sha"
ds_go --plan docs/plans/alpha/plan.md --resume-from validate
[ "$DS_RC" = 2 ] && [ "$(ds_calls)" = 0 ]; rc=$?
check "drive: resume refused when HEAD does not descend from base" 0 "$rc" "$DS_OUT" "--resume-from validate: HEAD does not descend from the recorded base $other_sha; the branch was rewritten"

ds_happy
ds_go --plan docs/plans/alpha/plan.md --resume-from validate
[ "$DS_RC" != 2 ] && [ "$(ds_calls)" = 2 ]; rc=$?
check "drive: resume allowed when HEAD descends from base" 0 "$rc" "$DS_OUT $(ds_facts)" "calls=2 stages=validate,review"

ds_new locked feat/x
lock_ready="$W/drive-lock-ready"; rm -f "$lock_ready"
python3 -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1], os.O_RDWR|os.O_CREAT); fcntl.flock(fd, fcntl.LOCK_EX); print("ready", flush=True); time.sleep(60)' \
    "$DS_R/docs/plans/alpha/run-state.lock" > "$lock_ready" &
lock_pid=$!
for _ in $(seq 1 100); do grep -q ready "$lock_ready" 2>/dev/null && break; sleep 0.1; done
ds_go --plan docs/plans/alpha/plan.md
kill "$lock_pid" 2>/dev/null; wait "$lock_pid" 2>/dev/null
[ "$DS_RC" = 2 ] && [ "$(ds_calls)" = 0 ]; rc=$?
check "drive: second driver refused while lock held" 0 "$rc" "$DS_OUT" "another drive.py run holds"

ds_new stale feat/x
printf 'partial\n' > "$DS_R/docs/plans/alpha/run-state.json.99999.tmp"
ds_go --plan docs/plans/alpha/plan.md
[ "$DS_RC" = 0 ] && [ ! -e "$DS_R/docs/plans/alpha/run-state.json.99999.tmp" ]; rc=$?
check "drive: stale run-state tmp removed" 0 "$rc" "$DS_OUT" "drive: removed stale run-state.json.99999.tmp"

ds_new symlink feat/x
outside="$W/ds-symlink/outside.txt"; printf 'keep\n' > "$outside"
ln -s "$outside" "$DS_R/docs/plans/alpha/run-state.json.1.tmp"
ds_go --plan docs/plans/alpha/plan.md
[ -L "$DS_R/docs/plans/alpha/run-state.json.1.tmp" ] && [ "$(cat "$outside")" = keep ]; rc=$?
check "drive: stale tmp cleanup leaves symlink target" 0 "$rc" "$DS_OUT"

sw_file="$W/drive-sweep-file"; printf 'x\n' > "$sw_file"
sw_out=$(PYTHONDONTWRITEBYTECODE=1 python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import drive
try:
    drive.sweep_stale_tmp(sys.argv[2])
except drive.Refused as exc:
    print(f"refused: {exc}")
    sys.exit(0)
print("no refusal")
sys.exit(1)
' "$(dirname "$DR_PY")" "$sw_file" 2>&1); sw_rc=$?
check "drive: sweep error refused" 0 "$sw_rc" "$sw_out" "cannot sweep stale run-state tmp"

ds_new envtpl feat/x
printf 'src/a.go\n%s\n' "$ENV_TPL" > "$DS_FIX/code.write"
ds_go --plan docs/plans/alpha/plan.md
committed=$(git -C "$DS_R" diff-tree --no-commit-id --name-only -r HEAD)
[ "$DS_RC" = 0 ] && [ "$(ds_calls)" = 3 ] && printf '%s\n' "$committed" | grep -qxF "$ENV_TPL"; rc=$?
check "drive: commits env template file" 0 "$rc" "$DS_OUT $committed" "$ENV_TPL"

ds_new lookalike feat/x; c0=$(ds_commits)
printf 'src/a.go\n%s\n' "$ENV_LOOK" > "$DS_FIX/code.write"
ds_go --plan docs/plans/alpha/plan.md
reason=$(ds_stop)
[ "$DS_RC" = 1 ] && [ "$(ds_commits)" = "$c0" ] \
    && case "$reason" in "staged file matches deny list: $ENV_LOOK") true ;; *) false ;; esac; rc=$?
check "drive: template exemption is exact" 0 "$rc" "$DS_OUT $reason" "STOPPED — staged file matches deny list: $ENV_LOOK"

rx="$ROOT/.devkit/release-exclude"
grep -qxF '**/run-state.lock' "$rx" && grep -qxF '**/run-state.json.*.tmp' "$rx"; rc=$?
check "release-exclude: run-state lock and tmp" 0 "$rc"

# drive: a stage that never ran to an exit stops the run with its reason, not an empty subtype (AC11)
dr_rs="$W/dr-reason"; rm -rf "$dr_rs"
( dr_repo "$dr_rs/repo" feat/x && dr_plan "$dr_rs/repo" alpha approved )
out=$(hl_py <<PY
import json, os, subprocess
import drive
os.chdir("$dr_rs/repo")
def timed_out(argv, cwd):
    raise subprocess.TimeoutExpired(argv, 3600)
rc = drive.main(["--plan", "docs/plans/alpha/plan.md"], runner=timed_out)
with open("docs/plans/alpha/run-state.json", encoding="utf-8") as fh:
    stop = json.load(fh)["stop_reason"]
print(f"rc={rc} stop={stop}")
PY
); rc=$?
check "drive: stage error stop shows reason" 0 "$rc" "$out" "rc=1 stop=stage error: timeout after 3600s"

# ── T7: run_stage reports stdout; drive takes caps and stdout from headless's public API ──
out=$(hl_py <<'PY'
from headless import run_stage
collected = []
S = '{"type": "result", "subtype": "success", "is_error": false, "result": "done", "total_cost_usd": 0.1}'
def fake(argv, cwd):
    return 0, S, ""
r = run_stage("code", "P", "sonnet", ".", budget_usd=1.0, tmp_dir=".", allowed_tools="Bash",
              runner=fake, on_stdout=collected.append)
print(f"collected_ok={collected == [S]} status={r.status}")
PY
); rc=$?
check "headless: run_stage reports stdout" 0 "$rc" "$out" "collected_ok=True status=ok"

out=$(python3 - "$ROOT/plugins/coding-pipeline/scripts/drive.py" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
private = sorted(a.name for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module == "headless"
                 for a in n.names if a.name.startswith("_"))
print(f"private={private}")
PY
); rc=$?
check "drive: imports no private headless names" 0 "$rc" "$out" "private=[]"

dr_b="$W/dr-t7"; rm -rf "$dr_b"
( dr_repo "$dr_b/repo" feat/x && dr_plan "$dr_b/repo" alpha approved )
out=$(hl_py <<PY
import os, subprocess
import drive
os.chdir("$dr_b/repo")
seen = []
def record_then_stop(argv, cwd):
    seen.append(argv)
    raise subprocess.TimeoutExpired(argv, 1)
rc = drive.main(["--plan", "docs/plans/alpha/plan.md"], runner=record_then_stop)
i = seen[0].index("--max-budget-usd")
print(f"budget={seen[0][i + 1]}")
PY
); rc=$?
check "drive: default budget 8" 0 "$rc" "$out" "budget=8.00"

out=$(hl_py <<PY
import json, os, subprocess
import drive
os.chdir("$dr_b/repo")
def timed_out(argv, cwd):
    raise subprocess.TimeoutExpired(argv, 1)
rc = drive.main(["--plan", "docs/plans/alpha/plan.md"], runner=timed_out)
with open("docs/plans/alpha/run-state.json", encoding="utf-8") as fh:
    stop = json.load(fh)["stop_reason"]
print(f"rc={rc} stop={stop}")
PY
); rc=$?
check "drive: stage timeout 3600" 0 "$rc" "$out" "rc=1 stop=stage error: timeout after 3600s"

out=$(python3 - "$ROOT" <<'PY'
import os, sys
root = sys.argv[1]
bad = []
for f in ["plugins/coding-pipeline/scripts/drive.py",
          "plugins/coding-pipeline/references/headless-runs.md", "README.md"]:
    text = open(os.path.join(root, f), encoding="utf-8").read()
    if "[--budget-usd 8]" not in text or "--budget-usd 3" in text:
        bad.append(f)
for f in ["bench/arms.json", "bench/README.md"]:
    text = open(os.path.join(root, f), encoding="utf-8").read()
    if "capped at USD 3" in text or "capped at USD 8" not in text:
        bad.append(f)
print(f"stale={bad}")
PY
); rc=$?
check "drive: budget default stated as 8 everywhere" 0 "$rc" "$out" "stale=[]"

out=$(br_py "$ROOT" <<'PY'
import importlib.util, os, sys
root = sys.argv[1]
spec = importlib.util.spec_from_file_location("bench_run", os.path.join(root, "bench", "run.py"))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
import headless
caps_ok = (mod.STAGE_BUDGET_USD == headless.DEFAULT_BUDGET_USD == 8.0
           and mod.STAGE_TIMEOUT_S == headless.DEFAULT_TIMEOUT_S == 3600)
print(f"caps_ok={caps_ok}")
PY
); rc=$?
check "bench: caps follow headless defaults" 0 "$rc" "$out" "caps_ok=True"

# ── lang-detect.sh: which languages a diff touches (AC20, SEC-7) ─────────────
# Every fixture is a throwaway repo under $W with a repo-level identity, so no
# test depends on the global git config. ld_check_exact compares the whole output,
# because a line-level claim ("go counted 2") is a substring trap otherwise.
LD="$V/lang-detect.sh"
ld_repo() {  # ld_repo <dir> — a repo with one committed base file and no other state
    mkdir -p "$1" && (
        cd "$1" || exit
        git init -q -b main
        printf 'base\n' > base.txt
        git add base.txt
        git -c user.email=t@t -c user.name=t commit -q -m base
    )
}
ld_check_exact() {  # ld_check_exact <name> <want-exit> <got-exit> <got-output> <want-output>
    if [ "$2" = "$3" ] && [ "$4" = "$5" ]; then pass=$((pass + 1)); else echo "FAIL: $1 — exit $3 (want $2), output: $4"; fail=1; fi
}

ld_maps="$W/ld-maps"
ld_repo "$ld_maps"
(
    cd "$ld_maps" || exit
    printf 'package x\n' > a.go
    printf 'package x\n' > a_test.go
    for f in c.ts d.tsx e.kt f.rs g.php h.java i.dart j.css README.md; do printf 'x\n' > "$f"; done
)
out=$(cd "$ld_maps" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: maps extensions" 0 "$rc" "$out" "LANGUAGE: flutter references/languages/flutter.md 1
LANGUAGE: go references/languages/go.md 2
LANGUAGE: html-css references/languages/html-css.md 1
LANGUAGE: java references/languages/java.md 1
LANGUAGE: kotlin references/languages/kotlin.md 1
LANGUAGE: php references/languages/php.md 1
LANGUAGE: react references/languages/react.md 1
LANGUAGE: rust references/languages/rust.md 1
LANGUAGE: typescript references/languages/typescript.md 1
LANGUAGES: flutter go html-css java kotlin php react rust typescript"

ld_next="$W/ld-next"
ld_repo "$ld_next"
(
    cd "$ld_next" || exit
    printf 'export default {}\n' > next.config.mjs
    git add next.config.mjs
    git -c user.email=t@t -c user.name=t commit -q -m "next config"
    mkdir app && printf 'x\n' > app/page.tsx
)
out=$(cd "$ld_next" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: nextjs replaces react" 0 "$rc" "$out" "LANGUAGE: nextjs references/languages/nextjs.md 1
LANGUAGES: nextjs"

ld_htmx="$W/ld-htmx"
ld_repo "$ld_htmx"
(
    cd "$ld_htmx" || exit
    printf '<button hx-get="/x">go</button>\n' > p.html
    printf '<p>plain</p>\n' > q.html
)
out=$(cd "$ld_htmx" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: htmx by content" 0 "$rc" "$out" "LANGUAGE: html-css references/languages/html-css.md 1
LANGUAGE: htmx references/languages/htmx.md 1
LANGUAGES: html-css htmx"

ld_docs="$W/ld-docs"
ld_repo "$ld_docs"
printf 'docs\n' > "$ld_docs/README.md"
out=$(cd "$ld_docs" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: docs only" 0 "$rc" "$out" "LANGUAGES: none"

ld_bad="$W/ld-bad"
ld_repo "$ld_bad"
out=$(cd "$ld_bad" && bash "$LD" --diff nosuchref 2>&1); rc=$?
check "lang-detect: invalid base" 2 "$rc" "$out" "lang-detect: invalid base nosuchref"

ld_opt="$W/ld-opt"
ld_repo "$ld_opt"
out=$(cd "$ld_opt" && bash "$LD" --diff --output=x 2>&1); rc=$?
check "lang-detect: option-looking base refused" 2 "$rc" "$out" "lang-detect: invalid base"
[ ! -e "$ld_opt/x" ] && pass=$((pass + 1)) || { echo "FAIL: lang-detect: option-looking base refused — file x was created"; fail=1; }

ld_tmpl="$W/ld-tmpl"
ld_repo "$ld_tmpl"
(
    cd "$ld_tmpl" || exit
    printf '<button hx-post="/x">go</button>\n' > a.tmpl
    printf '<div>plain</div>\n' > b.tmpl
    printf '{{.Name}}\n{{ if a<b }}x{{ end }}\n' > c.tmpl
)
out=$(cd "$ld_tmpl" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: tmpl by content" 0 "$rc" "$out" "LANGUAGE: html-css references/languages/html-css.md 1
LANGUAGE: htmx references/languages/htmx.md 1
LANGUAGES: html-css htmx"

ld_unc="$W/ld-unc"
ld_repo "$ld_unc"
(
    cd "$ld_unc" || exit
    printf 'package x\n' > a.go
    git add a.go
    git -c user.email=t@t -c user.name=t commit -q -m "add a.go"
    printf 'package y\n' > a.go
    printf 'fn main() {}\n' > b.rs
)
out=$(cd "$ld_unc" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: uncommitted and untracked counted" 0 "$rc" "$out" "LANGUAGE: go references/languages/go.md 1
LANGUAGE: rust references/languages/rust.md 1
LANGUAGES: go rust"

ld_odd="$W/ld-odd"
ld_repo "$ld_odd"
nl_name=$(printf 'x\ny.rs')
(
    cd "$ld_odd" || exit
    printf 'package x\n' > "a b.go"
    printf 'fn main() {}\n' > "$nl_name"
)
out=$(cd "$ld_odd" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: odd file names" 0 "$rc" "$out" "LANGUAGE: go references/languages/go.md 1
LANGUAGE: rust references/languages/rust.md 1
LANGUAGES: go rust"

ld_norepo="$W/ld-norepo"
mkdir -p "$ld_norepo"
out=$(cd "$ld_norepo" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: outside a git repo" 2 "$rc" "$out" "lang-detect: not inside a git repository"

ld_unr="$W/ld-unreadable"
ld_repo "$ld_unr"
printf '<p>plain</p>\n' > "$ld_unr/p.html"
chmod 000 "$ld_unr/p.html"
out=$(cd "$ld_unr" && bash "$LD" --diff HEAD 2>&1); rc=$?
chmod 600 "$ld_unr/p.html"
check "lang-detect: unreadable content file" 2 "$rc" "$out" "lang-detect: cannot read p.html"

ld_sub="$W/ld-subdir"
ld_repo "$ld_sub"
mkdir -p "$ld_sub/sub"
printf 'package x\n' > "$ld_sub/sub/a.go"
printf 'package x\n' > "$ld_sub/b.go"
out=$(cd "$ld_sub/sub" && bash "$LD" --diff HEAD 2>&1); rc=$?
ld_check_exact "lang-detect: untracked counted from a subdirectory" 0 "$rc" "$out" "LANGUAGE: go references/languages/go.md 2
LANGUAGES: go"

# ── review wiring (T12, AC21/AC22): languages reach the reviewer, proof line ─
RW_SK="$ROOT/plugins/pr-workflow/skills/review-code/SKILL.md"
RW_DV="$ROOT/plugins/pr-workflow/skills/review-code/references/diff-verdict-and-rules.md"
RW_RV="$ROOT/plugins/coding-pipeline/agents/reviewer.md"
RW_CD="$ROOT/plugins/coding-pipeline/agents/coder.md"
RW_LR="$ROOT/plugins/coding-pipeline/references/language-rules-reference.md"

# The sensor line and the dispatch line are each one line of SKILL.md; the
# checks read those lines, so a field moved elsewhere does not count as wired.
grep -F '**Sensors**' "$RW_SK" | grep -qF 'lang-detect.sh --diff $BASE' \
    && grep -F '**Sensors**' "$RW_SK" | grep -qF 'lang-detect: UNMEASURED — script not found' \
    && grep -F '**Sensors**' "$RW_SK" | grep -qF 'lang-detect: UNMEASURED — exit' \
    && grep -F '**Dispatch**' "$RW_SK" | grep -qF 'Languages: {names from the LANGUAGES line | none | unknown}'; rc=$?
check "review-code: languages reach the reviewer" 0 "$rc"

# The proof line sits inside the End-with block, and the text names its source.
sed -n '/^End with:/,/^Recommendation:/p' "$RW_RV" \
    | grep -qF 'Language {name}: references/languages/{name}.md · {K} findings' \
    && grep -qF "for exactly the names in the dispatch's \`Languages:\` field" "$RW_RV"; rc=$?
check "reviewer: language proof line" 0 "$rc"

rw_mis=$(cat "$RW_SK" "$RW_DV"); rw_ok=1
for rw_s in 'Language review missing:' 'Language {name}: UNMEASURED' 'only the Standards return' 'first pass'; do
    printf '%s\n' "$rw_mis" | grep -qF -- "$rw_s" || rw_ok=0
done
[ "$rw_ok" = 1 ]; rc=$?
check "review-code: missing language line handled" 0 "$rc"

# Exit 1 is the only pass: 0 means a stale claim was found, 2 means a file was
# unreadable — both fail closed.
grep -qF -e '60–155 lines' -e '~870 lines' -e '~340' "$RW_RV" "$RW_CD" "$RW_LR"; rc=$?
check "agents: no stale language size claims" 1 "$rc"

# ── language error-handling gaps (AC28): one home per rule ──────────────────
# Each language file must carry its missing error rule (needle) in its own
# text. kotlin.md and htmx.md alone own a `## Error Handling` section; the
# existing rows that AC28 cites (`Missing error boundary`, `!!` operator) must
# still occur exactly once, so no rule is restated under a second severity.
check_language_error_gaps() {  # returns 0 only when every needle, heading and count holds
    local dir="$ROOT/plugins/coding-pipeline/references/languages" bad=0 f n
    while IFS='|' read -r f n; do
        grep -qF -- "$n" "$dir/$f.md" || { echo "missing '$n' in $f.md"; bad=1; }
    done <<'NEEDLES'
java|new XException(msg, e)
typescript|throw a string
rust|.context(
php|$previous
flutter|PlatformDispatcher.instance.onError
react|event handlers
nextjs|global-error.tsx
kotlin|CancellationException
htmx|htmx:responseError
NEEDLES
    for f in kotlin htmx; do
        grep -qxF -- '## Error Handling' "$dir/$f.md" || { echo "no '## Error Handling' in $f.md"; bad=1; }
    done
    for f in java typescript rust php flutter react nextjs; do
        grep -qxF -- '## Error Handling' "$dir/$f.md" && { echo "'## Error Handling' must not be in $f.md"; bad=1; }
    done
    # Counted as table rows (`| ...`): the kotlin Coding Rules prose also says "No `!!` operator".
    [ "$(grep -cF -- '| Missing error boundary' "$dir/react.md")" = 1 ] || { echo "react.md: 'Missing error boundary' row must occur once"; bad=1; }
    [ "$(grep -cF -- '| `!!` operator' "$dir/kotlin.md")" = 1 ] || { echo "kotlin.md: '\`!!\` operator' row must occur once"; bad=1; }
    [ "$bad" = 0 ]
}
check_language_error_gaps; rc=$?
check "languages: error handling gaps filled" 0 "$rc"

# Release 3.4.0 wiring (AC13). Each helper returns 0 only when every needle holds.
check_release_version() {  # every shipped plugin.json is 3.4.0 and CHANGELOG has the heading
    local p bad=0
    for p in coding-pipeline pr-workflow devtools engineering; do
        python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("version") == "3.4.0" else 1)' \
            "$ROOT/plugins/$p/.claude-plugin/plugin.json" || { echo "$p plugin.json is not 3.4.0"; bad=1; }
    done
    grep -q '^## \[3\.4\.0\]' "$ROOT/CHANGELOG.md" || { echo "CHANGELOG has no ## [3.4.0] heading"; bad=1; }
    [ "$bad" = 0 ]
}
check_release_version; rc=$?
check "release: version 3.4.0" 0 "$rc"

check_changelog_340() {  # the 3.4.0 section names the source paper and the resume protocol
    local sec bad=0 n
    sec=$(awk '/^## \[3\.4\.0\]/{f=1;next} /^## \[/{f=0} f' "$ROOT/CHANGELOG.md")
    [ -n "$sec" ] || { echo "no ## [3.4.0] section"; return 1; }
    for n in effective-harnesses-for-long-running-agents tasks.json Resume; do
        printf '%s\n' "$sec" | grep -qF -- "$n" || { echo "[3.4.0] does not name $n"; bad=1; }
    done
    [ "$bad" = 0 ]
}
check_changelog_340; rc=$?
check "release: CHANGELOG 3.4.0 names the paper and the resume protocol" 0 "$rc"

check_readme_tasks() {  # README: the guard row, its disable id, and the tasks.json / Resume / Final proof / autocompact facts
    local f="$ROOT/README.md" bad=0 v
    grep -F '| `tasks-state-guard.sh`' "$f" | grep -qF 'PreToolUse' || { echo "README hooks table has no tasks-state-guard.sh row"; bad=1; }
    grep -F 'DEVKIT_DISABLED_HOOKS=id,id' "$f" | grep -qF 'pre:write:tasks-state' || { echo "README id list lacks pre:write:tasks-state"; bad=1; }
    for v in tasks.json Resume 'Final proof' '/autocompact 300k'; do
        grep -qF -- "$v" "$f" || { echo "README does not name $v"; bad=1; }
    done
    [ "$bad" = 0 ]
}
check_readme_tasks; rc=$?
check "readme: hooks, ids, tasks.json, resume and autocompact" 0 "$rc"

gate_timeout_missing() {  # gate_timeout_missing <file> <needle>... — prints each needle the file lacks (a missing file lacks all)
    local f="$1" n
    shift
    for n in "$@"; do grep -qF -- "$n" "$f" 2>/dev/null || printf '[%s] ' "$n"; done
}
check_gate_timeout_docs() {  # check_gate_timeout_docs <row> — the stall rule and both timeout knobs are stated where coder, validator and operator read them
    local row="$1" R="$ROOT" miss="" sec
    miss="$miss$(gate_timeout_missing "$R/plugins/coding-pipeline/skills/code/references/loop.md" '`</dev/null`' '10 minutes is a stall')"
    miss="$miss$(gate_timeout_missing "$R/plugins/coding-pipeline/skills/validate-code/references/execution-and-report.md" '`</dev/null`' '10 minutes is a stall')"
    miss="$miss$(gate_timeout_missing "$R/plugins/coding-pipeline/references/thresholds.md" '`DEVKIT_GATE_TIMEOUT`, positive integer; unset or invalid → 900' '10 s per line (`DEVKIT_PUSH_STDIN_TIMEOUT`' 'Background run stall | 10 minutes with no change to its output file')"
    sec=$(awk '/^## \[3\.4\.0\]/{f=1;next} /^## \[/{f=0} f' "$R/CHANGELOG.md")
    printf '%s\n' "$sec" | grep -qF -- 'DEVKIT_GATE_TIMEOUT' || miss="${miss}[CHANGELOG [3.4.0]: DEVKIT_GATE_TIMEOUT] "
    miss="$miss$(gate_timeout_missing "$R/README.md" 'DEVKIT_GATE_TIMEOUT')"
    if [ -z "$miss" ]; then pass=$((pass + 1)); else echo "FAIL: $row — missing: $miss"; fail=1; fi
}
check_gate_timeout_docs "gate timeout docs state the stall rule"

check_readme_fixes_in_rounds() {  # README no longer says validate-code reports only; its row names the Score Loop
    local f="$ROOT/README.md" bad=0
    grep -qF 'Reports, never fixes' "$f" && { echo "README still says 'Reports, never fixes'"; bad=1; }
    grep -F '| `/validate-code' "$f" | grep -qF 'Score Loop' || { echo "README /validate-code row does not mention Score Loop"; bad=1; }
    [ "$bad" = 0 ]
}
check_readme_fixes_in_rounds; rc=$?
check "readme: validate-code fixes in rounds" 0 "$rc"

check_readme_reader_structure() {  # README: a first-time reader finds install, first run, flow diagram, skills, gates, Score Loop, hooks, driver, config, troubleshooting
    local f="$ROOT/README.md" bad=0 h v
    for h in '## Install' '## Your first run' '## How a change flows' '## Skills' '## Quality gates' '### The Score Loop' '## Hooks' '## Headless driver' '## Configuration' '## Troubleshooting'; do
        grep -qF -- "$h" "$f" || { echo "README lacks heading: $h"; bad=1; }
    done
    grep -qF '```mermaid' "$f" || { echo "README has no mermaid diagram"; bad=1; }
    for v in DEVKIT_HOOK_PROFILE DEVKIT_DISABLED_HOOKS DEVKIT_GATE_FILTER DEVKIT_DISPATCH_BUDGET; do
        grep -qF -- "$v" "$f" || { echo "README does not name $v"; bad=1; }
    done
    [ "$bad" = 0 ]
}
check_readme_reader_structure; rc=$?
check "readme: reader structure" 0 "$rc"

check_readme_links_and_facts() {  # README: relative links resolve; the facts it states match the code
    local f="$ROOT/README.md" bad=0 t n
    grep -oE '\]\(([^)#:]+)(#[^)]*)?\)' "$f" | sed -E 's/^\]\(//; s/(#[^)]*)?\)$//' | sort -u | while IFS= read -r t; do
        [ -e "$ROOT/$t" ] || echo "broken README link: $t"
    done | grep -q . && { echo "README has a broken relative link"; bad=1; }
    grep -qF 'default 20' "$f" || { echo "README lacks the dispatch budget default 20"; bad=1; }
    grep -qF '[--budget-usd 8]' "$f" || { echo "README lacks [--budget-usd 8]"; bad=1; }
    grep -qF '**Go test files are paired.**' "$f" || { echo "README lacks the Go test pairing rule"; bad=1; }
    grep -qF 'Reports, never fixes' "$f" && { echo "README still says 'Reports, never fixes'"; bad=1; }
    n=$(grep -c . "$f"); [ "$n" -gt 0 ] || { echo "README is empty"; bad=1; }
    [ "$bad" = 0 ]
}
check_readme_links_and_facts; rc=$?
check "readme: links and facts hold" 0 "$rc"

check_changelog_names() {  # the 3.3.0 Added names the new files, Fixed names the pre-commit flag
    local sec added fixed bad=0 n
    sec=$(awk '/^## \[3\.3\.0\]/{f=1;next} /^## \[/{f=0} f' "$ROOT/CHANGELOG.md")
    [ -n "$sec" ] || { echo "no ## [3.3.0] section"; return 1; }
    added=$(printf '%s\n' "$sec" | awk '/^### /{s=$0} s=="### Added"')
    fixed=$(printf '%s\n' "$sec" | awk '/^### /{s=$0} s=="### Fixed"')
    for n in lang-detect.sh go-error-handling.md golangci.yml; do
        printf '%s\n' "$added" | grep -qF -- "$n" || { echo "Added does not name $n"; bad=1; }
    done
    printf '%s\n' "$fixed" | grep -qF -- '--fast-only' || { echo "Fixed does not name --fast-only"; bad=1; }
    [ "$bad" = 0 ]
}
check_changelog_names; rc=$?
check "release: changelog names the new work" 0 "$rc"

check_changelog_measured() {  # the 3.3.0 Measured section is the release's end-to-end evidence
    local measured bad=0 n
    measured=$(awk '/^## \[3\.3\.0\]/{f=1;next} /^## \[/{f=0} f' "$ROOT/CHANGELOG.md" \
        | awk '/^### /{s=$0} s=="### Measured"')
    [ -n "$measured" ] || { echo "no ### Measured in ## [3.3.0]"; return 1; }
    printf '%s\n' "$measured" | grep -qE 'bench/results/[0-9]{8}T[0-9]{6}Z' || { echo "no bench/results directory named"; bad=1; }
    printf '%s\n' "$measured" | grep -qF 'B-sonnet' || { echo "arm B-sonnet not named"; bad=1; }
    printf '%s\n' "$measured" | grep -qE 'total cost \$[0-9]+\.[0-9]{2}' || { echo "no total cost"; bad=1; }
    for n in doc-cosmetic go-concurrency go-gap go-simple ts-handler ts-validator; do
        printf '%s\n' "$measured" | grep -qF -- "$n" || { echo "no verdict for fixture $n"; bad=1; }
    done
    [ "$bad" = 0 ]
}
check_changelog_measured; rc=$?
check "release: changelog measured section" 0 "$rc"

# ── tasks_state.py: init / status / verify (tasks.json row state, T2) ──────
TS="$ROOT/plugins/coding-pipeline/scripts/tasks_state.py"
tsd="$W/tasks-state"; mkdir -p "$tsd"

check_tasks_plan() {  # check_tasks_plan <plan.md> <ID[:dep,dep]>... — writes a plan with a Tasks table
    local plan="$1" spec id deps
    shift
    {
        printf '%s\n' '# Plan' '' '## Tasks' '| ID | Task | Files | Test rows | Language | Tier | Depends on |' '|---|---|---|---|---|---|---|'
        for spec in "$@"; do
            id=${spec%%:*}; deps=-
            case "$spec" in *:*) deps=${spec#*:} ;; esac
            printf '| %s | task | `f/file.go` | TestX | Go 1.26 | Backend | %s |\n' "$id" "$deps"
        done
    } > "$plan"
}

check_tasks_edit() {  # check_tasks_edit <tasks.json> <restamp 0|1> <python stmt on rows> — a state the tool did not write
    python3 -c '
import hashlib, json, sys
p, restamp, stmt = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
doc = json.load(open(p, encoding="utf-8"))
rows = doc["rows"]
exec(stmt)
if restamp:
    text = json.dumps(doc["rows"], sort_keys=True, separators=(",", ":"))
    doc["sum"] = hashlib.sha256(text.encode("utf-8")).hexdigest()
with open(p, "w", encoding="utf-8") as f:
    f.write(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
' "$@"
}

d="$tsd/init-order"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2 T3:T1
out=$(python3 "$TS" init "$d/plan.md" 2>&1); rc=$?
python3 - "$d/tasks.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc["schema"] == 1
assert [r["id"] for r in doc["rows"]] == ["T1", "T2", "T3"]
assert all(r["status"] == "todo" for r in doc["rows"])
PY
bad=$(( rc != 0 || $? != 0 ))
check "tasks-state: init writes one todo row per Tasks row in plan order" 0 "$bad"

d="$tsd/init-append"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2 T3
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 1 "rows[0]['status']='done'; rows[0]['evidence']='M: PASS'"
check_tasks_plan "$d/plan.md" T1 T2 T3 T4:T1
out=$(python3 "$TS" init "$d/plan.md" 2>&1); rc=$?
python3 - "$d/tasks.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
rows = doc["rows"]
assert [r["id"] for r in rows] == ["T1", "T2", "T3", "T4"]
assert rows[0]["status"] == "done" and rows[0]["evidence"] == "M: PASS"
assert rows[3]["status"] == "todo"
PY
bad=$(( rc != 0 || $? != 0 ))
check "tasks-state: init on an existing file appends new plan rows and keeps statuses" 0 "$bad"

d="$tsd/init-gone"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
cp "$d/tasks.json" "$d/before.json"
check_tasks_plan "$d/plan.md" T1
out=$(python3 "$TS" init "$d/plan.md" 2>&1); rc=$?
bad=0; [ "$rc" = 1 ] || bad=1
case "$out" in *T2*) ;; *) bad=1 ;; esac
cmp -s "$d/tasks.json" "$d/before.json" || bad=1
check "tasks-state: init refuses when a stored row is gone from the plan" 0 "$bad" "$out" "T2"

d="$tsd/init-unsafe-none"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" 'T1;x'
out=$(python3 "$TS" init "$d/plan.md" 2>&1); rc=$?
bad=0; [ "$rc" = 1 ] || bad=1; [ -e "$d/tasks.json" ] && bad=1
case "$out" in *"T1;x"*) ;; *) bad=1 ;; esac
d="$tsd/init-unsafe-existing"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1; cp "$d/tasks.json" "$d/before.json"
check_tasks_plan "$d/plan.md" 'T1;x'
out2=$(python3 "$TS" init "$d/plan.md" 2>&1); rc2=$?
[ "$rc2" = 1 ] || bad=1
case "$out2" in *"T1;x"*) ;; *) bad=1 ;; esac
cmp -s "$d/tasks.json" "$d/before.json" || bad=1
check "tasks-state: row id with unsafe characters refused" 0 "$bad" "$out" "T1;x"

d="$tsd/s1/demo"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2 T3:T2 T4:T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 1 "rows[0]['status']='done'; rows[1]['status']='in_progress'"
out=$(python3 "$TS" status "$d/plan.md" 2>&1); rc=$?
bad=0; [ "$rc" = 0 ] || bad=1
[ "$out" = "[demo] 1/4 done · in_progress: T2 · failed: — · next: T4" ] || bad=1
check "tasks-state: status line counts and names next row" 0 "$bad" "$out" "next: T4"

d="$tsd/verify-pass"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2 T3:T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
out=$(python3 "$TS" verify "$d/plan.md" 2>&1); rc=$?
check "tasks-state: verify passes a consistent file" 0 "$rc" "$out" "TASKS: PASS"

d="$tsd/verify-reordered"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2 T3
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 1 "rows[0], rows[1] = rows[1], rows[0]"
out=$(python3 "$TS" verify "$d/plan.md" 2>&1); rc=$?
check "tasks-state: verify fails a reordered file" 1 "$rc" "$out" "TASKS: FAIL"

d="$tsd/verify-status"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 1 "rows[0]['status']='passed'"
out_s=$(python3 "$TS" verify "$d/plan.md" 2>&1); rc_s=$?
d="$tsd/verify-field"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 1 "rows[0]['note']='x'"
out_f=$(python3 "$TS" verify "$d/plan.md" 2>&1); rc_f=$?
bad=0; [ "$rc_s" = 1 ] || bad=1; [ "$rc_f" = 1 ] || bad=1
case "$out_s" in *"TASKS: FAIL"*) ;; *) bad=1 ;; esac
case "$out_f" in *"TASKS: FAIL"*) ;; *) bad=1 ;; esac
check "tasks-state: verify fails an unknown status or field" 0 "$bad" "$out_s" "TASKS: FAIL"

d="$tsd/verify-outside"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 0 "rows[0]['status']='done'"
out=$(python3 "$TS" verify "$d/plan.md" 2>&1); rc=$?
check "tasks-state: verify fails when rows changed outside the tool" 1 "$rc" "$out" "tasks.json changed outside tasks_state.py"

d="$tsd/verify-none"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
out=$(python3 "$TS" verify "$d/plan.md" 2>&1); rc=$?
check "tasks-state: verify without tasks.json is unmeasured" 2 "$rc" "$out" "TASKS: UNMEASURED"

d="$tsd/init-symlink"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
echo "outside" > "$d/outside.json"; cp "$d/outside.json" "$d/before.json"
ln -s outside.json "$d/tasks.json"
out=$(python3 "$TS" init "$d/plan.md" 2>&1); rc=$?
out_set=$(python3 "$TS" set "$d/plan.md" T1 in_progress 2>&1); rc_set=$?
bad=0; [ "$rc" = 2 ] || bad=1; [ "$rc_set" = 2 ] || bad=1; cmp -s "$d/outside.json" "$d/before.json" || bad=1
case "$out_set" in *symlink*) ;; *) bad=1 ;; esac
check "tasks-state: symlinked tasks.json refused" 0 "$bad" "$out" "symlink"

d="$tsd/s2/demo"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2 T3:T2
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 1 "rows[0]['status']='done'; rows[1]['status']='failed'; rows[1]['evidence']='stopped'"
out=$(python3 "$TS" status "$d/plan.md" 2>&1); rc=$?
bad=0; [ "$rc" = 0 ] || bad=1
[ "$out" = "[demo] 1/3 done · in_progress: — · failed: T2 · next: —" ] || bad=1
check "tasks-state: status line lists failed rows" 0 "$bad" "$out" "failed: T2"

# ── tasks_state.py set: transitions, deps, evidence, head, lock (tasks.json row state, T3) ──
check_row_field() {  # check_row_field <tasks.json> <ID> <field> — prints one stored field of that row
    python3 - "$@" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
print(next(r[sys.argv[3]] for r in doc["rows"] if r["id"] == sys.argv[2]))
PY
}

check_sum_matches() {  # check_sum_matches <tasks.json> — true when the embedded sum is the canonical hash of its rows and no .sum file exists
    python3 - "$1" <<'PY'
import hashlib, json, os, sys
p = sys.argv[1]
doc = json.load(open(p, encoding="utf-8"))
want = hashlib.sha256(json.dumps(doc["rows"], sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
sys.exit(0 if doc.get("sum") == want and not os.path.lexists(p + ".sum") else 1)
PY
}

d="$tsd/set-deps"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2 T3:T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
out=$(python3 "$TS" set "$d/plan.md" T3 in_progress 2>&1); rc=$?
bad=0; [ "$rc" = 1 ] || bad=1
case "$out" in *"T3 depends on T1 (todo)"*) ;; *) bad=1 ;; esac
check "tasks-state: in_progress refused while a dependency is not done" 0 "$bad" "$out" "T3 depends on T1"

d="$tsd/set-pass"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
python3 "$TS" set "$d/plan.md" T1 in_progress >/dev/null 2>&1
out=$(python3 "$TS" set "$d/plan.md" T1 done --evidence "looks fine" 2>&1); rc=$?
bad=0; [ "$rc" = 1 ] || bad=1; [ "$(check_row_field "$d/tasks.json" T1 status)" = in_progress ] || bad=1
check "tasks-state: done refused without M: PASS evidence" 0 "$bad" "$out" "M: PASS"

d="$tsd/set-illegal"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
out=$(python3 "$TS" set "$d/plan.md" T1 done --evidence "M: PASS" 2>&1); rc=$?
bad=0; [ "$rc" = 1 ] || bad=1; [ "$(check_row_field "$d/tasks.json" T1 status)" = todo ] || bad=1
check "tasks-state: illegal transition todo to done refused" 0 "$bad" "$out" "illegal transition todo → done"

r="$tsd/set-head"; d="$r/demo"; mkdir -p "$d"; git -C "$r" init -q
git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
python3 "$TS" set "$d/plan.md" T1 in_progress >/dev/null 2>&1
out=$(python3 "$TS" set "$d/plan.md" T1 done --evidence "M: PASS" 2>&1); rc=$?
want=$(git -C "$r" rev-parse --short HEAD)
bad=0; [ "$rc" = 0 ] || bad=1; [ -n "$want" ] || bad=1
[ "$(check_row_field "$d/tasks.json" T1 head)" = "$want" ] || bad=1
[ "$(check_row_field "$d/tasks.json" T1 evidence)" = "M: PASS" ] || bad=1
case "$(check_row_field "$d/tasks.json" T1 updated)" in ????-??-??T??:??:??Z) ;; *) bad=1 ;; esac
check "tasks-state: done records HEAD sha and evidence" 0 "$bad"

d="$tsd/set-regress"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 1 "rows[0]['status']='done'; rows[0]['evidence']='M: PASS'"
out1=$(python3 "$TS" set "$d/plan.md" T1 todo 2>&1); rc1=$?
out2=$(python3 "$TS" set "$d/plan.md" T1 todo --evidence "MISSING ROW x" 2>&1); rc2=$?
bad=0; [ "$rc1" = 1 ] || bad=1; [ "$rc2" = 0 ] || bad=1; [ "$(check_row_field "$d/tasks.json" T1 status)" = todo ] || bad=1
check "tasks-state: done to todo regression needs evidence" 0 "$bad" "$out1" "evidence"

d="$tsd/set-long"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
python3 "$TS" set "$d/plan.md" T1 in_progress >/dev/null 2>&1; cp "$d/tasks.json" "$d/before.json"
long=$(python3 -c 'print("M: PASS" + "x" * 294, end="")')
out=$(python3 "$TS" set "$d/plan.md" T1 done --evidence "$long" 2>&1); rc=$?
bad=0; [ "${#long}" = 301 ] || bad=1; [ "$rc" = 2 ] || bad=1; cmp -s "$d/tasks.json" "$d/before.json" || bad=1
check "tasks-state: evidence over 300 chars refused" 0 "$bad" "$out" "300"

d="$tsd/set-ctrl"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
python3 "$TS" set "$d/plan.md" T1 in_progress >/dev/null 2>&1
ev=$(printf 'M: PASS\033[31m\nX')
out=$(python3 "$TS" set "$d/plan.md" T1 done --evidence "$ev" 2>&1); rc=$?
bad=0; [ "$rc" = 0 ] || bad=1; [ "$(check_row_field "$d/tasks.json" T1 evidence)" = "M: PASS[31mX" ] || bad=1
check "tasks-state: control characters stripped from evidence" 0 "$bad" "$out"

d="$tsd/set-locked"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1; cp "$d/tasks.json" "$d/before.json"
python3 -c '
import fcntl, sys, time
f = open(sys.argv[1], "a+")
fcntl.flock(f, fcntl.LOCK_EX)
print("held", flush=True)
time.sleep(30)
' "$d/tasks.json.lock" > "$d/holder.out" 2>&1 &
holder=$!
for _ in $(seq 1 100); do grep -q held "$d/holder.out" 2>/dev/null && break; sleep 0.1; done
out=$(DEVKIT_TASKS_LOCK_TIMEOUT=0.2 python3 "$TS" set "$d/plan.md" T1 in_progress 2>&1); rc=$?
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
bad=0; [ "$rc" = 2 ] || bad=1; cmp -s "$d/tasks.json" "$d/before.json" || bad=1
check "tasks-state: set refuses while another writer holds the lock" 0 "$bad" "$out" "TASKS: locked"

d="$tsd/set-sum"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
bad=0; check_sum_matches "$d/tasks.json" || bad=1
python3 "$TS" set "$d/plan.md" T1 in_progress >/dev/null 2>&1 || bad=1
check_sum_matches "$d/tasks.json" || bad=1
python3 "$TS" verify "$d/plan.md" >/dev/null 2>&1 || bad=1
check "tasks-state: init and set write a matching embedded sum" 0 "$bad"

d="$tsd/one-file"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
bad=0
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1 || bad=1
python3 "$TS" set "$d/plan.md" T1 in_progress >/dev/null 2>&1 || bad=1
python3 "$TS" set "$d/plan.md" T1 done --evidence "M: PASS" >/dev/null 2>&1 || bad=1
python3 - "$d/tasks.json" <<'PY' || bad=1
import json, os, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert sorted(doc) == ["plan", "rows", "schema", "slug", "sum"], sorted(doc)
assert not os.path.lexists(sys.argv[1] + ".sum")
PY
check "tasks-state: rows and sum live in one atomic file" 0 "$bad"

d="$tsd/status-forged"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1 T2
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
check_tasks_edit "$d/tasks.json" 0 "rows[0]['status']='done'"
out=$(python3 "$TS" status "$d/plan.md" 2>&1); rc=$?
check "tasks-state: status refuses a forged file" 1 "$rc" "$out" "tasks.json changed outside tasks_state.py"

d="$tsd/set-unicode"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
python3 "$TS" set "$d/plan.md" T1 in_progress >/dev/null 2>&1
ev=$(printf 'M: PASS\xe2\x80\xa8X\xe2\x80\xaeY\xe2\x81\xa6Z')
out=$(python3 "$TS" set "$d/plan.md" T1 done --evidence "$ev" 2>&1); rc=$?
bad=0; [ "$rc" = 0 ] || bad=1; [ "$(check_row_field "$d/tasks.json" T1 evidence)" = "M: PASSXYZ" ] || bad=1
check "tasks-state: unicode separators and bidi controls stripped from evidence" 0 "$bad" "$out"

d="$tsd/set-restore"; mkdir -p "$d"; check_tasks_plan "$d/plan.md" T1
python3 "$TS" init "$d/plan.md" >/dev/null 2>&1
python3 "$TS" set "$d/plan.md" T1 in_progress >/dev/null 2>&1
out1=$(python3 "$TS" set "$d/plan.md" T1 failed 2>&1); rc1=$?
out2=$(python3 "$TS" set "$d/plan.md" T1 failed --evidence "stopped" 2>&1); rc2=$?
out3=$(python3 "$TS" set "$d/plan.md" T1 in_progress 2>&1); rc3=$?
out4=$(python3 "$TS" set "$d/plan.md" T1 todo 2>&1); rc4=$?
out5=$(python3 "$TS" set "$d/plan.md" T1 todo --evidence "MISSING ROW x" 2>&1); rc5=$?
bad=0; [ "$rc1" = 1 ] || bad=1; [ "$rc2" = 0 ] || bad=1; [ "$rc3" = 0 ] || bad=1
[ "$rc4" = 1 ] || bad=1; [ "$rc5" = 0 ] || bad=1; [ "$(check_row_field "$d/tasks.json" T1 status)" = todo ] || bad=1
check "tasks-state: failed and restore transitions follow the table" 0 "$bad" "$out1" "evidence"

# ── thresholds: the flat-install auto-compact window has one stated number (T11, AC15 d) ──
grep -qF '| Auto-compact window (flat install) | 300000 ' "$ROOT/plugins/coding-pipeline/references/thresholds.md"; rc=$?
check "thresholds: auto-compact window row" 0 "$rc"

# ── grilling: decision questions offer three options with trade-offs (T12, AC16) ──
# Markdown wiring check: the section names the rule, and no "yes accepts" wording survives under plugins/.
G="$ROOT/plugins/coding-pipeline/references/grilling.md"
bad=0
grep -qF '## Decision questions' "$G" || bad=1
grep -qF 'at least 3' "$G" || bad=1
grep -qF 'trade-off' "$G" || bad=1
grep -qF 'Recommended' "$G" || bad=1
grep -qF 'confirms one already-decided action' "$G" || bad=1
[ -z "$(grep -rl -- '"yes" accepts' "$ROOT/plugins")" ] || bad=1
check "grilling: decision questions need three options with trade-offs" 0 "$bad"

# ── grilling: planning, grill-me and CLAUDE.md point to the rule (T12, AC16) ──
bad=0
grep -qF 'coding-pipeline/references/grilling.md` § Decision questions' "$ROOT/plugins/devtools/skills/grill-me/SKILL.md" || bad=1
grep -qF 'grilling.md` § Decision questions' "$ROOT/plugins/coding-pipeline/skills/planning/SKILL.md" || bad=1
grep -qF 'grilling.md` § Decision questions' "$ROOT/plugins/coding-pipeline/skills/planning/references/phases.md" || bad=1
grep '^6\. \*\*Surface conflicts' "$ROOT/plugins/coding-pipeline/CLAUDE.md" | grep -qF 'grilling.md` § Decision questions' || bad=1
check "grilling: planning, grill-me and CLAUDE.md point to the rule" 0 "$bad"

# ── context-budget doc: plugin users told how to set the window (T14, AC15 b) ──
# Markdown wiring check: each name a plugin user needs to set the window is present.
C="$ROOT/plugins/coding-pipeline/references/context-budget.md"
bad=0
grep -qF '/autocompact 300k' "$C" || bad=1
grep -qF 'autoCompactWindow' "$C" || bad=1
grep -qF 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' "$C" || bad=1
grep -qF 'settings.local.json' "$C" || bad=1
grep -qF 'DEVKIT_CONTEXT_WINDOW=200000' "$C" || bad=1
check "context-budget-doc: plugin users told how to set the window" 0 "$bad"

# ── gate runs cannot hang (AC19): checkpoint-m --gates and break-run watchdog ──
# Each fixture reuses the all-green shape (cp11) so only the gates command differs.
cp_gates_fixture() {  # cp_gates_fixture <name> — leaves cwd in a passing repo
    local n="$1"
    mkrepo "$W/$n"
    cd "$W/$n" || exit
    printf 'func TestOK(t *testing.T) {}\n' > filler_test.go
    write_dup_filler filler.go
    cat > "$W/$n-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestOK` | a | b |
MD
}
cp_gates() {  # cp_gates <name> <gates cmd> — runs checkpoint-m.sh, stdin closed
    bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/$1-spec.md" --tests filler_test.go \
        --expect filler_test.go filler.go --gates "$2" 2>&1 </dev/null
}

cp_gates_fixture cp13
t0=$(date +%s)
out=$(DEVKIT_GATE_TIMEOUT=1 cp_gates cp13 "sleep 20"); rc=$?
t1=$(date +%s)
check "checkpoint-m: gates timeout is unmeasured" 2 "$rc" "$out" "M: UNMEASURED — gates: TIMEOUT after 1s"
[ $((t1 - t0)) -lt 8 ] && pass=$((pass + 1)) || { echo "FAIL: checkpoint-m: gates timeout is unmeasured — took $((t1 - t0))s"; fail=1; }
cd - >/dev/null || exit

# stdin of the checkpoint is a FIFO a `sleep 15` holds open read-write and never writes to
cp_gates_fixture cp14
mkfifo "$W/cp14.fifo"
sleep 15 <>"$W/cp14.fifo" &
holder=$!
t0=$(date +%s)
out=$(DEVKIT_GATE_TIMEOUT=10 bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp14-spec.md" --tests filler_test.go \
    --expect filler_test.go filler.go --gates "cat >/dev/null" 2>&1 <"$W/cp14.fifo"); rc=$?
t1=$(date +%s)
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
check "checkpoint-m: gates get closed stdin" 0 "$rc" "$out" "M: PASS"
[ $((t1 - t0)) -lt 8 ] && pass=$((pass + 1)) || { echo "FAIL: checkpoint-m: gates get closed stdin — took $((t1 - t0))s"; fail=1; }
cd - >/dev/null || exit

cp_gates_fixture cp15
bad=""
for v in abc 0 -3 1e3; do
    out=$(DEVKIT_GATE_TIMEOUT="$v" cp_gates cp15 "sleep 2"); rc=$?
    case "$out" in *"M: PASS"*) [ "$rc" = 0 ] || bad="$bad $v" ;; *) bad="$bad $v" ;; esac
done
check "checkpoint-m: invalid gate timeout falls back to default" 0 "$([ -z "$bad" ] && echo 0 || echo 1)" "$bad" ""
cd - >/dev/null || exit

# br_timeout fixtures live under $W like every other break-run row
br6="$W/br6"
mkdir -p "$br6"
printf 'ENABLED=yes\n' > "$br6/cfg.txt"
cp "$br6/cfg.txt" "$br6/cfg.orig"
t0=$(date +%s)
out=$(DEVKIT_GATE_TIMEOUT=1 run_br --file "$br6/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- sleep 20 2>&1); rc=$?
t1=$(date +%s)
check "break-run: test command timeout restores and reports" 2 "$rc" "$out" "break-run: TIMEOUT after 1s"
cmp -s "$br6/cfg.txt" "$br6/cfg.orig" && [ ! -f "$br6/cfg.txt.devkit-break" ] && [ $((t1 - t0)) -lt 8 ] \
    && pass=$((pass + 1)) || { echo "FAIL: break-run: test command timeout restores and reports — file not restored, marker left, or took $((t1 - t0))s"; fail=1; }

# Every row below names its sleep with a per-run unique argument, so a match can only be
# this run's own child, never another process on the machine; survivors are always reaped.
br7="$W/br7"
mkdir -p "$br7"
printf 'ENABLED=yes\n' > "$br7/cfg.txt"
u7="$$$RANDOM"
printf '#!/usr/bin/env bash\nsleep 47.%s\ntrue\n' "$u7" > "$br7/slow.sh"
DEVKIT_GATE_TIMEOUT=1 run_br --file "$br7/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- bash "$br7/slow.sh" >/dev/null 2>&1
sleep 1
if pgrep -f "sleep 47.$u7" >/dev/null 2>&1; then
    echo "FAIL: break-run: timeout kills the test command's children — a 'sleep 47.$u7' survived"; fail=1
    pkill -f "sleep 47.$u7" 2>/dev/null
else
    pass=$((pass + 1))
fi

# run_bounded <limit s> <outfile> <cmd...> — run with stdin closed, KILL it if it outlives the limit
# (sets bounded_rc, 124 on expiry), so a hung watchdog fails its row instead of hanging the suite.
run_bounded() {
    local lim="$1" of="$2" p n=0
    shift 2
    "$@" </dev/null >"$of" 2>&1 &
    p=$!
    while kill -0 "$p" 2>/dev/null && [ "$n" -lt $((lim * 5)) ]; do sleep 0.2; n=$((n + 1)); done
    if kill -0 "$p" 2>/dev/null; then
        pkill -KILL -P "$p" 2>/dev/null
        kill -KILL "$p" 2>/dev/null
        wait "$p" 2>/dev/null
        bounded_rc=124
    else
        wait "$p"
        bounded_rc=$?
    fi
}

# a command that ignores TERM (and passes that on to its child) must still die: TERM, 5 s, KILL
br8="$W/br8"
mkdir -p "$br8"
printf 'ENABLED=yes\n' > "$br8/cfg.txt"
cp "$br8/cfg.txt" "$br8/cfg.orig"
u8="$$$RANDOM"
printf '#!/usr/bin/env bash\ntrap "" TERM\nsleep 18.%s\n' "$u8" > "$br8/stubborn.sh"
t0=$(date +%s)
DEVKIT_GATE_TIMEOUT=1 run_bounded 25 "$br8/out" bash -c 'cd "$1" && shift && exec bash "$@"' _ "$W" "$V/break-run.sh" \
    --file "$br8/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- bash "$br8/stubborn.sh"
rc=$bounded_rc; out=$(cat "$br8/out")
t1=$(date +%s)
check "break-run: TERM-ignoring test command is killed and the file restored" 2 "$rc" "$out" "break-run: TIMEOUT after 1s"
if cmp -s "$br8/cfg.txt" "$br8/cfg.orig" && [ ! -f "$br8/cfg.txt.devkit-break" ] && [ $((t1 - t0)) -lt 12 ] \
    && ! pgrep -f "sleep 18.$u8" >/dev/null 2>&1; then
    pass=$((pass + 1))
else
    echo "FAIL: break-run: TERM-ignoring test command is killed and the file restored — file not restored, marker left, survivor, or took $((t1 - t0))s"; fail=1
fi
pkill -f "sleep 18.$u8" 2>/dev/null

cp_gates_fixture cp16
u16="$$$RANDOM"
printf '#!/usr/bin/env bash\ntrap "" TERM\nsleep 17.%s\n' "$u16" > "$W/stubborn-gate.sh"
t0=$(date +%s)
DEVKIT_GATE_TIMEOUT=1 run_bounded 25 "$W/cp16.out" bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp16-spec.md" \
    --tests filler_test.go --expect filler_test.go filler.go --gates "bash $W/stubborn-gate.sh"
rc=$bounded_rc; out=$(cat "$W/cp16.out")
t1=$(date +%s)
check "checkpoint-m: TERM-ignoring gate is killed" 2 "$rc" "$out" "M: UNMEASURED — gates: TIMEOUT after 1s"
if [ $((t1 - t0)) -lt 12 ] && ! pgrep -f "sleep 17.$u16" >/dev/null 2>&1; then
    pass=$((pass + 1))
else
    echo "FAIL: checkpoint-m: TERM-ignoring gate is killed — survivor or took $((t1 - t0))s"; fail=1
fi
pkill -f "sleep 17.$u16" 2>/dev/null
cd - >/dev/null || exit

# wait_for_child <unique sleep arg> — poll (bounded, ~10 s) until the child exists
wait_for_child() {
    local n=0
    while ! pgrep -f "$1" >/dev/null 2>&1 && [ "$n" -lt 50 ]; do sleep 0.2; n=$((n + 1)); done
    pgrep -f "$1" >/dev/null 2>&1
}

br9="$W/br9"
mkdir -p "$br9"
printf 'ENABLED=yes\n' > "$br9/cfg.txt"
cp "$br9/cfg.txt" "$br9/cfg.orig"
u9="$$$RANDOM"
printf '#!/usr/bin/env bash\nsleep 16.%s\n' "$u9" > "$br9/child.sh"
bg_br --file "$br9/cfg.txt" --old "ENABLED=yes" --new "ENABLED=no" --row "guard-enabled" -- bash "$br9/child.sh" >/dev/null 2>&1
if wait_for_child "sleep 16.$u9"; then
    kill -TERM "$bg_br_pid" 2>/dev/null
    wait "$bg_br_pid" 2>/dev/null; rc=$?
    if [ "$rc" = 2 ] && cmp -s "$br9/cfg.txt" "$br9/cfg.orig" && [ ! -f "$br9/cfg.txt.devkit-break" ] \
        && ! pgrep -f "sleep 16.$u9" >/dev/null 2>&1; then
        pass=$((pass + 1))
    else
        echo "FAIL: break-run: interrupt stops the test command's children — rc=$rc, file not restored, or the child survived"; fail=1
    fi
else
    echo "FAIL: break-run: interrupt stops the test command's children — the child never started"; fail=1
    kill -KILL "$bg_br_pid" 2>/dev/null
fi
pkill -f "sleep 16.$u9" 2>/dev/null

cp_gates_fixture cp17
u17="$$$RANDOM"
printf '#!/usr/bin/env bash\nsleep 15.%s\n' "$u17" > "$W/child-gate.sh"
bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp17-spec.md" --tests filler_test.go \
    --expect filler_test.go filler.go --gates "bash $W/child-gate.sh" </dev/null >/dev/null 2>&1 &
cp17_pid=$!
if wait_for_child "sleep 15.$u17"; then
    kill -TERM "$cp17_pid" 2>/dev/null
    wait "$cp17_pid" 2>/dev/null; rc=$?
    if [ "$rc" = 2 ] && ! pgrep -f "sleep 15.$u17" >/dev/null 2>&1; then
        pass=$((pass + 1))
    else
        echo "FAIL: checkpoint-m: interrupt stops the gate tree — rc=$rc or the gate's child survived"; fail=1
    fi
else
    echo "FAIL: checkpoint-m: interrupt stops the gate tree — the gate never started"; fail=1
    kill -KILL "$cp17_pid" 2>/dev/null
fi
pkill -f "sleep 15.$u17" 2>/dev/null
cd - >/dev/null || exit

echo "verify tests: $pass passed, exit=$fail"
exit $fail
