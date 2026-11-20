#!/usr/bin/env bash
# QA lens 1, mechanically: every test carries falsification evidence, and the
# quoted failure is an assertion failure rather than a build break.
#
# A row whose Falsified By cell starts `n/a — Markdown` is prose-only (AC30): it
# has no break to make, so its evidence line carries a `wiring:` check instead,
# and no assertion is required. Every other row keeps the assertion rule.
#
# Whether the break *corresponds to the behaviour* stays with QA — that is
# real judgment. Whether an evidence line exists at all, and whether the thing
# quoted is an assertion rather than a compile error, is pattern matching, and
# it is the half that catches the common miss.
#
# Usage: falsification.sh <coder-done.txt> <story.md>
# Exit 0 = every row has a well-formed evidence line. Exit 1 = gap.
# Exit 2 = usage, or an input file cannot be read.
set -u

evidence="${1:-}"
story="${2:-}"
if [ ! -f "$evidence" ] || [ ! -f "$story" ]; then
    echo "usage: falsification.sh <coder-done.txt> <story.md>" >&2
    exit 2
fi

# Each Test Case row becomes "name<TAB>Falsified By cell". The column is found by
# its header name, so it may sit anywhere; a table without that column gives
# every row an empty cell, and an empty cell is a code row.
specified=$(awk '
    function trim(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    /^\| *Test Name *\|/ {
        intable=1; fbcol=0
        line=$0; gsub(/\\\|/, "\001", line)
        n=split(line, h, "|")
        for (i=2; i<=n; i++) if (trim(h[i]) == "Falsified By") fbcol=i
        next
    }
    intable && /^\| *-/    { next }
    intable && !/^\|/      { intable=0 }
    intable {
        name=$0
        sub(/^\| */, "", name); sub(/ *\|.*/, "", name)
        gsub(/`/, "", name)
        if (!length(name)) next
        fb=""
        if (fbcol) {
            line=$0; gsub(/\\\|/, "\001", line)
            n=split(line, c, "|")
            if (fbcol <= n) { fb=trim(c[fbcol]); gsub(/\001/, "|", fb) }
        }
        print name "\t" fb
    }
' "$story" | sort -u)

# A build break is not falsification: the test never ran, so nothing was proven.
BUILD_BREAK='cannot find|undefined:|SyntaxError|error TS[0-9]|compilation (failed|error)|cannot be resolved|no such module|ImportError|ModuleNotFoundError|panic: runtime|unresolved reference|build failed'
ASSERTION='assert|expect|want .*got|got .*want|Expected|FAIL|AssertionError|to (be|equal|contain)|not equal'
WIRING_PREFIX='n/a — Markdown'

fails=0
total=0
falsified=0
wired=0
while IFS=$'\t' read -r row fb; do
    [ -n "$row" ] || continue
    total=$((total + 1))

    # Whole-word: evidence for `ParsesTokenWithExpiry` is not evidence for `ParsesToken`.
    line=$(grep -iwF -- "$row" "$evidence" || true)
    if [ -z "$line" ]; then
        echo "NO EVIDENCE: $row"
        fails=$((fails + 1))
        continue
    fi

    # The keyword checks read the evidence text, not the row name: a name such as
    # "...needs an assertion" would otherwise satisfy ASSERTION on its own.
    detail=$(printf '%s\n' "$line" | awk -v r="$row" '{
        s=$0; l=tolower(s); k=tolower(r); out=""
        while ((i=index(l, k)) > 0) { out=out substr(s, 1, i-1); s=substr(s, i+length(k)); l=tolower(s) }
        print out s
    }')

    case "$fb" in
        "$WIRING_PREFIX"*)
            if printf '%s' "$detail" | grep -qiF 'wiring:'; then
                wired=$((wired + 1))
            else
                echo "NO WIRING EVIDENCE: $row — a prose row's evidence line must carry a wiring: check"
                fails=$((fails + 1))
            fi
            continue
            ;;
    esac

    if printf '%s' "$detail" | grep -qiE "$BUILD_BREAK"; then
        echo "BUILD-BREAK NOT FALSIFICATION: $row — quoted failure is a compile/import error, not an assertion"
        fails=$((fails + 1))
        continue
    fi

    if ! printf '%s' "$detail" | grep -qiE "$ASSERTION"; then
        echo "NO ASSERTION QUOTED: $row — evidence line shows no assertion failure"
        fails=$((fails + 1))
        continue
    fi
    falsified=$((falsified + 1))
done <<EOF
$specified
EOF

if [ "$fails" -gt 0 ]; then
    echo "FALSIFICATION: FAIL — $((total - fails))/$total tests have valid evidence"
    exit 1
fi

echo "FALSIFICATION: PASS — $total/$total tests have valid evidence · $falsified falsified · $wired wiring-checked"
echo "NOTE: QA still spot-checks that each break matches the behaviour under test (every security test + 2-3 core-logic tests)."
exit 0
