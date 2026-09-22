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

rm -rf "$W"
echo "verify tests: $pass passed, exit=$fail"
exit $fail
