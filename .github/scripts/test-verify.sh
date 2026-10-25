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
printf 'func TestN(t *testing.T) {}\n' > n_test.go
write_dup_filler filler.go
cat > "$W/cp9-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestN` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp9-spec.md" --tests n_test.go --expect n_test.go filler.go never_here.go --gates false 2>&1); rc=$?
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
printf 'func TestOK(t *testing.T) {}\n' > ok_test.go
write_dup_filler filler.go
cat > "$W/cp11-spec.md" <<'MD'
| Test Name | Input | Expected |
|---|---|---|
| `TestOK` | a | b |
MD
out=$(bash "$V/checkpoint-m.sh" --base release/x-abc --spec "$W/cp11-spec.md" --tests ok_test.go --expect ok_test.go filler.go --gates true 2>&1); rc=$?
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
cd - >/dev/null || exit
mkdir -p "$W/hm-not-git"
out=$(cd "$W/hm-not-git" && GIT_CEILING_DIRECTORIES="$W" python3 "$HM" 2>&1); rc=$?
check "harness-metrics: outside a git repository is UNMEASURED" 2 "$rc" "$out" "not a git repository"

rm -rf "$W"
echo "verify tests: $pass passed, exit=$fail"
exit $fail
