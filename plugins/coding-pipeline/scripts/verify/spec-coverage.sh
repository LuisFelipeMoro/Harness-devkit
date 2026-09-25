#!/usr/bin/env bash
# QA lens 0, mechanically: every Test Cases row implemented, no unspecified extras.
#
# Quinn used to read the story table and the whole test suite and compare them by
# hand. That is string matching dressed as judgment: it costs a model pass over
# every test file and it is exactly the kind of check that degrades as context
# fills. Here it is a diff of two name lists.
#
# Contract: spec-coverage proves a row is NAMED in a test file; break-run.sh
# proves it RUNS (it requires "FAIL: <row>" printed at runtime); checkpoint-m.sh requires both.
#
# Usage: spec-coverage.sh <story.md> <test-path>...
# Exit 0 = every row implemented and no unflagged extras. Exit 1 = gap.
set -u

story="${1:-}"
shift || true
if [ -z "$story" ] || [ ! -f "$story" ] || [ $# -eq 0 ]; then
    echo "usage: spec-coverage.sh <story.md> <test-path>..." >&2
    exit 2
fi

# Column 1 of the Test Cases table. The table is bounded by its header row and
# the next blank line, so a later table in the story cannot bleed in.
specified=$(awk '
    /^\| *Test Name *\|/ { intable=1; next }
    intable && /^\| *-/    { next }
    intable && !/^\|/      { intable=0 }
    intable {
        sub(/^\| */, ""); sub(/ *\|.*/, "")
        gsub(/`/, "")
        if (length($0)) print $0
    }
' "$story" | sort -u)

if [ -z "$specified" ]; then
    echo "SPEC-COVERAGE: FAIL — no Test Cases table found in $story"
    exit 1
fi

# Implemented test names across the common frameworks. One grep per family beats
# parsing each language's AST, and a false positive here is visible in the diff.
# The last two alternatives are non-language harnesses used inside this repo's
# own verify/ suite: bats' `@test "name" { ... }` and the hand-rolled `check
# "name" ...` convention test-verify.sh uses for every row — anchored to the
# start of the line (optionally indented) so an ordinary use of the English
# word "check" elsewhere in a line is never mistaken for a harness call.
implemented=$(grep -rhoE \
    "func (Test[A-Za-z0-9_]+)|(it|test|describe)\([\"'\`][^\"'\`]+|def (test_[a-z0-9_]+)|fn (test_[a-z0-9_]+)|@Test[[:space:]]+[a-z]*[[:space:]]*(void )?([A-Za-z0-9_]+)|@test[[:space:]]+[\"'][^\"']+|^[[:space:]]*check[[:space:]]+\"[^\"]+" \
    "$@" 2>/dev/null \
    | sed -E "s/^func //; s/^(it|test|describe)\([\"'\`]//; s/^def //; s/^fn //; s/^@Test[[:space:]]+//; s/^@test[[:space:]]+[\"']//; s/^[[:space:]]*check[[:space:]]+\"//" \
    | sort -u)

# Boundary-aware "any test helper" match, additive to the language patterns
# above: a row's exact name still has to appear as a string literal
# somewhere, but not every harness spells the call the same way. Two shapes
# cover it — the name passed as the FIRST argument to a call/command whose
# own name reads as test-shaped (`expect_says "<name>" …`, `helper("<name>"`,
# `t.Run("<name>"`, `it('<name>'`, `gate_check("<name>"`) and the name
# printed inside a FAIL line (`echo "FAIL: <name> — …"`, the convention this
# repo's own test-verify.sh uses for every row). A bare quoted literal with
# no such call in front of it does NOT count — an unrelated log line
# (`logger.Info("x fails")`, `print("x fails")`) must never satisfy a row.
# The call's own name only has to CONTAIN one of check/expect/assert/test/
# it/describe/should/verify/run (case-insensitive) ANYWHERE in the
# identifier — `expect_says` (prefix), `t.Run` (after a `.`), `gate_check`
# (suffix after `_`) all qualify. `\b` cannot express this: `_` is a word
# character, so a word-boundary anchor never fires between `gate` and
# `check` in `gate_check`, which is exactly the shape that needs to match.
# Requiring the keyword as a literal substring, with no boundary condition
# at all, covers prefix/suffix/dotted forms uniformly; `logger`/`Info` and
# `print` simply don't contain any of the nine keywords as a substring, so
# log-style calls stay rejected without a separate rule for them.
# FAIL-line trimming stops at the first " — "/" - " separator rather than any
# bare "-" or ":", because row names in this repo routinely carry their own
# internal hyphens and colons (`checkpoint-m: ...`) with no surrounding
# spaces — a bare-character cut would truncate those legitimately.
#
# A row's name sitting inside a comment is dead code, not a test — it never
# runs, so it must not satisfy the row. Strip comment lines (first
# non-whitespace characters `#`, `//`, `--` or `;` — shell/Python, the
# C-family, SQL/Lua, and Lisp/ini) before either extraction below. This is a
# static, line-level filter only; no attempt is made to detect a dead branch
# of otherwise-live code.
code_lines=$(grep -rhvE '^[[:space:]]*(#|//|--|;)' "$@" 2>/dev/null)
kw='(check|expect|assert|test|it|describe|should|verify|run)'
call_dq=$(printf '%s\n' "$code_lines" \
    | grep -oiE "[A-Za-z0-9_.]*${kw}[A-Za-z0-9_]*[[:space:]]*\\(?[[:space:]]*\"[^\"]+\"" \
    | sed -E 's/^[^"]*"//; s/"$//')
call_sq=$(printf '%s\n' "$code_lines" \
    | grep -oiE "[A-Za-z0-9_.]*${kw}[A-Za-z0-9_]*[[:space:]]*\\(?[[:space:]]*'[^']+'" \
    | sed -E "s/^[^']*'//; s/'\$//")
quoted=$(printf '%s\n%s\n' "$call_dq" "$call_sq")
raw_fail=$(printf '%s\n' "$code_lines" | grep -oE 'FAIL: [^"]*')
fail_named=$(printf '%s\n%s\n' "$quoted" "$raw_fail" \
    | grep -E '^FAIL: ' \
    | sed -E 's/^FAIL: //; s/ (—|-) .*$//')
implemented=$(printf '%s\n%s\n%s\n' "$implemented" "$quoted" "$fail_named" | sort -u)

missing=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    # Whole-line match: a substring match let `ParsesToken` be satisfied by
    # `ParsesTokenWithExpiry`, a PASS with the specified test never written.
    if ! printf '%s\n' "$implemented" | grep -qixF -- "$row"; then
        echo "MISSING ROW: $row"
        missing=$((missing + 1))
    fi
done <<EOF
$specified
EOF

spec_count=$(printf '%s\n' "$specified" | grep -c . || true)
impl_count=$(printf '%s\n' "$implemented" | grep -c . || true)
extra=$((impl_count - spec_count + missing))

if [ "$missing" -gt 0 ]; then
    echo "SPEC-COVERAGE: FAIL — $((spec_count - missing))/$spec_count rows implemented"
    exit 1
fi

echo "SPEC-COVERAGE: PASS — $spec_count/$spec_count rows implemented"
[ "$extra" -gt 0 ] && echo "NOTE: $extra test(s) beyond the table — each needs a 'Gap found' line in CODER DONE"
exit 0
