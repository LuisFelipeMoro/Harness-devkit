#!/usr/bin/env bash
# QA lens 1, mechanically: every test carries falsification evidence, and the
# quoted failure is an assertion failure rather than a build break.
#
# Whether the break *corresponds to the behaviour* stays with Quinn — that is
# real judgment. Whether an evidence line exists at all, and whether the thing
# quoted is an assertion rather than a compile error, is pattern matching, and
# it is the half that catches the common miss.
#
# Usage: falsification.sh <coder-done.txt> <story.md>
# Exit 0 = every row has a well-formed evidence line. Exit 1 = gap.
set -u

evidence="${1:-}"
story="${2:-}"
if [ ! -f "$evidence" ] || [ ! -f "$story" ]; then
    echo "usage: falsification.sh <coder-done.txt> <story.md>" >&2
    exit 2
fi

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

# A build break is not falsification: the test never ran, so nothing was proven.
BUILD_BREAK='cannot find|undefined:|SyntaxError|error TS[0-9]|compilation (failed|error)|cannot be resolved|no such module|ImportError|ModuleNotFoundError|panic: runtime|unresolved reference|build failed'
ASSERTION='assert|expect|want .*got|got .*want|Expected|FAIL|AssertionError|to (be|equal|contain)|not equal'

fails=0
total=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    total=$((total + 1))

    line=$(grep -iF -- "$row" "$evidence" || true)
    if [ -z "$line" ]; then
        echo "NO EVIDENCE: $row"
        fails=$((fails + 1))
        continue
    fi

    if printf '%s' "$line" | grep -qiE "$BUILD_BREAK"; then
        echo "BUILD-BREAK NOT FALSIFICATION: $row — quoted failure is a compile/import error, not an assertion"
        fails=$((fails + 1))
        continue
    fi

    if ! printf '%s' "$line" | grep -qiE "$ASSERTION"; then
        echo "NO ASSERTION QUOTED: $row — evidence line shows no assertion failure"
        fails=$((fails + 1))
    fi
done <<EOF
$specified
EOF

if [ "$fails" -gt 0 ]; then
    echo "FALSIFICATION: FAIL — $((total - fails))/$total tests have valid evidence"
    exit 1
fi

echo "FALSIFICATION: PASS — $total/$total tests have valid evidence"
echo "NOTE: Quinn still spot-checks that each break matches the behaviour under test (every security test + 2-3 core-logic tests)."
exit 0
