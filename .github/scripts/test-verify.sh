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

# ── ST10: execution-options checkpoint and roster validation ──────────────────
# Test 1: bench-context.py rejects unrecognized roster values (capital Standard, unknown huge)
cat > "$W/manifest-bad-roster.md" <<'MANIFEST'
| Test | Input | Expected | Roster |
|---|---|---|---|
| test1 | a | b | Standard |
| test2 | c | d | huge |
MANIFEST
out=$(python3 "$ROOT/plugins/coding-pipeline/scripts/bench-context.py" --manifest "$W/manifest-bad-roster.md" 2>&1); rc=$?
check "bench: unrecognized roster value is an error" 2 "$rc" "$out" "unrecognized roster"

# Test 2: verdict roster path hides score on hard-gate fail like legacy
out=$(bash "$V/verdict.sh" --roster standard --classify-exit 0 --review 9 --stress 9 --qa 9 --hard-gate-fail lint 2>&1); rc=$?
check "verdict: roster path hides score on hard-gate fail like legacy" 1 "$rc" "$out" "NOT READY"
case "$out" in *"Overall Score"*) echo "FAIL: verdict: roster path hides score on hard-gate fail like legacy — score was printed"; fail=1 ;; *) pass=$((pass + 1)) ;; esac

# Test 3: verdict unknown roster value is usage
bash "$V/verdict.sh" --roster huge --classify-exit 0 >/dev/null 2>&1; rc=$?
check "verdict: unknown roster value is usage" 2 "$rc"

# ── security-scan --diff: diff-scoped candidates (ST2 tests) ────────────────
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

# Newline in file name is scanned (Stress ST2 CRITICAL): a `tr '\0' '\n'` split
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

# Symlink in diff is never silent (Stress ST2 MAJOR): grep does not follow a
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

# Pathspec limits the scan (Review ST2 MAJOR): a pathspec argument after the
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

# git diff failure is reported (Review ST2 MINOR): a real `git diff` failure
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

# ── tautology-scan --diff: diff-scoped tautology detection (ST3 tests) ──────

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

# Newline in test file name (same class as the ST2 Stress CRITICAL): splitting
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

# ── classify-diff.sh: verifies a declared roster against the real diff (ST4) ─

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

# ── D3 amendment: cosmetic must not trust extension/location alone (ST4) ────

# security-scan --include-docs: the flag classify-diff's cosmetic content check
# depends on — default mode filters `.md:` lines for the Reviewer's own noise
# reduction, and that filter would hide exactly the code this flag needs to see.
mkdir -p "$W/docsec"
printf 'eval(x)\n' > "$W/docsec/x.md"
out=$(bash "$V/security-scan.sh" --include-docs "$W/docsec/x.md" 2>&1); rc=$?
check "security-scan --include-docs scans markdown" 0 "$rc" "$out" "x.md:1"

# A style-extension file holding real code must not pass cosmetic just because
# of its name (ST4 Stress CRITICAL).
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
# (ST4 Stress CRITICAL) — diff-lib's own listing only ever shows the new path.
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
# candidate wins over the rename escalation (D3 amendment, ST4).
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
# Python traceback (ST3's "never a traceback" contract, extended to ST4).
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
# (same class as the ST2 Stress CRITICAL finding). A second plain file sits
# alongside it so a name split (1 real file -> 2 bogus paths) is observable:
# correctly read, this diff has 2 non-test source files (<= 2, light); split,
# it has 3 (> 2, standard) -- a real threshold difference, not just a re-run
# of ST2's own already-falsified check on the shared library.
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
# Batch A (2c9fee) — ST5 verdict.sh roster · ST9/ST10 bench-context.py
# Keep this section contiguous — a second batch appends classify-diff (ST4)
# rows separately and a merge should not have to interleave the two.
# ══════════════════════════════════════════════════════════════════════════

BENCH="$ROOT/plugins/coding-pipeline/scripts/bench-context.py"

# ── ST5: verdict.sh --roster / --classify-exit (D2) ─────────────────────────
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

# ── ST9: bench-context.py roster model (PROFILES uniform/mixed, --mix) ──────

out=$(python3 "$BENCH" --json 2>&1); rc=$?
check "bench: uniform 5-story delivery is 20 dispatches" 0 "$rc" "$out" '"delivery_dispatches": 20'

check "bench: mixed profile is 18 dispatches" 0 "$rc" "$out" '"dispatches": 18'

out2=$(python3 "$BENCH" --mix full=1 --json 2>&1)
rc2json=$(printf '%s' "$out2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(0 if d['profiles']['mixed']['dispatches'] == 9 else 1)
")
check "bench: full story adds a stress dispatch" 0 "$rc2json"

rc3=$(printf '%s' "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
root = '$ROOT/plugins/coding-pipeline'
files = ['agents/reviewer.md', 'references/change-discipline.md', 'references/languages/go.md']
base = sum(int(len(open(root + '/' + f, encoding='utf-8').read()) / 3.6) for f in files)
p = d['paths']['story: reviewer']
ok = p['per_load'] > base and 'story: reviewer' not in d.get('missing', [])
print(0 if ok else 1)
")
check "bench: reviewer path loads stress.md" 0 "$rc3"

baseline_dir="$W/baseline-c342347"
mkdir -p "$baseline_dir"
git -C "$ROOT" archive c342347 plugins | tar -x -C "$baseline_dir"
python3 "$baseline_dir/plugins/coding-pipeline/scripts/bench-context.py" \
    --root "$baseline_dir/plugins/coding-pipeline" --json > "$W/bench-before.json"
out=$(python3 "$BENCH" --baseline "$W/bench-before.json" 2>&1); rc=$?
check "bench: baseline JSON from c342347 still loads" 0 "$rc" "$out" "| 40 | 20 | -20 |"

out=$(python3 "$BENCH" --mix 'light=x' --json 2>&1); rc=$?
check "bench: malformed mix" 2 "$rc"

# ── ST10: execution-options checkpoint (bench-context.py --manifest) ────────
# The `contract: planning offers execution options` row (validate-wiring §7)
# is a separate batch's responsibility — not added here.

manifest_fixture="$W/manifest.md"
cat > "$manifest_fixture" <<'MD'
| Sub-Task | Stories/ACs | Security ACs | Key Constraints | Projected diff | Language | Tier | Roster |
|----------|-------------|--------------|-----------------|----------------|----------|------|--------|
| ST-A: does X | R1 | — | none | ~10 lines | Bash | Backend | light |
| ST-B: does Y | R2 | SEC-1 | none | ~10 lines | Bash | Backend | full |
| ST-C: does Z | R3 | — | none | ~10 lines | Bash | Backend | standard |
MD

out=$(python3 "$BENCH" --manifest "$manifest_fixture" 2>&1); rc=$?
check "bench: manifest options listed" 0 "$rc" "$out" "as planned"
case "$out" in *"all standard"*) pass=$((pass + 1)) ;; *) echo "FAIL: bench: manifest options listed — missing 'all standard'"; fail=1 ;; esac
case "$out" in *"legacy full loop"*) pass=$((pass + 1)) ;; *) echo "FAIL: bench: manifest options listed — missing 'legacy full loop'"; fail=1 ;; esac

# ST10: test with custom fixture COST where qa has n=0 (unsampled)
out=$(python3 -c "
import sys
sys.dont_write_bytecode = True
import importlib.util
spec = importlib.util.spec_from_file_location('bench', '$BENCH')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)

# Create fixture COST with qa at n=0 (unsampled) and others sampled
fixture_cost = {
    'map': (77000, 1),
    'architect': (184000, 1),
    'plan-reviewer': (165000, 1),
    'reviewer': (106000, 9),
    'coder': (137000, 9),
    'qa': (99000, 0),  # unsampled
    'stress': (85000, 3),
    'scrum-master': (40000, 0),
    'verdict': (20000, 0),
    'pr-review': (90000, 0),
    'devops': (60000, 0),
}

# Parse manifest and render with fixture COST
rosters = bench.parse_manifest_rosters('$manifest_fixture')
options = bench.compute_options(rosters, cost=fixture_cost)
output = bench.render_manifest(rosters, options, cost=fixture_cost)
print(output)
" 2>&1); rc=$?
check "bench: unsampled cost says assumed — fixture COST provided" 0 "$rc" "$out" "assumed"
qa_line=$(printf '%s' "$out" | grep '| qa ' || true)
case "$qa_line" in *measured*) echo "FAIL: bench: unsampled cost says assumed — qa row says measured instead of assumed"; fail=1 ;; *) pass=$((pass + 1)) ;; esac

json_out=$(python3 "$BENCH" --manifest "$manifest_fixture" --json 2>&1); rc=$?
rc_planned=$(printf '%s' "$json_out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(0 if d['options']['as planned']['dispatches'] == 14 else 1)
")
check "bench: as-planned dispatches follow rosters" 0 "$rc_planned"

rc_legacy=$(printf '%s' "$json_out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(0 if d['options']['legacy full loop']['dispatches'] == 26 else 1)
")
check "bench: legacy option counts 7 per row" 0 "$rc_legacy"

manifest_noroster="$W/manifest-noroster.md"
cat > "$manifest_noroster" <<'MD'
| Sub-Task | Tier |
|----------|------|
| ST-A: does X | Backend |
MD
out=$(python3 "$BENCH" --manifest "$manifest_noroster" 2>&1); rc=$?
check "bench: manifest without Roster column" 2 "$rc" "$out" "no Roster column"

rm -rf "$W"
echo "verify tests: $pass passed, exit=$fail"
exit $fail
