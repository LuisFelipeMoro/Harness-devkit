#!/usr/bin/env bash
# QA lens 0, mechanically: every Test Cases row implemented, no unspecified extras.
#
# Quinn used to read the story table and the whole test suite and compare them by
# hand. That is string matching dressed as judgment: it costs a model pass over
# every test file and it is exactly the kind of check that degrades as context
# fills. Here it is a diff of two name lists.
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
implemented=$(grep -rhoE \
    "func (Test[A-Za-z0-9_]+)|(it|test|describe)\([\"'\`][^\"'\`]+|def (test_[a-z0-9_]+)|fn (test_[a-z0-9_]+)|@Test[[:space:]]+[a-z]*[[:space:]]*(void )?([A-Za-z0-9_]+)" \
    "$@" 2>/dev/null \
    | sed -E "s/^func //; s/^(it|test|describe)\([\"'\`]//; s/^def //; s/^fn //; s/^@Test[[:space:]]+//" \
    | sort -u)

missing=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    if ! printf '%s\n' "$implemented" | grep -qiF "$row"; then
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
