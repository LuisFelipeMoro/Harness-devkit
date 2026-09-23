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

rm -rf "$W"
echo "verify tests: $pass passed, exit=$fail"
exit $fail
