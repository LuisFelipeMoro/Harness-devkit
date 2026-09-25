#!/usr/bin/env bash
# Candidate finder for the Reviewer's security pass.
#
# The Reviewer's job on security is adjudication — is this reachable, is the input
# attacker-controlled, is the control adequate. Finding the *candidates* is not:
# every row in reviewer.md's vulnerability table has a literal shape in source.
# Reading every changed file to locate them costs a full model pass over the diff;
# grepping for them costs nothing, and the model then reads only the hits.
#
# This is a narrowing pass, never a verdict. No hits does NOT mean secure — an
# authz check missing entirely has no pattern to match, and the Reviewer still
# traces auth on every new route. Hits are candidates, and a candidate cleared
# with a reason is a normal outcome.
#
# Usage: security-scan.sh [--include-docs] <path>... | security-scan.sh --diff <base> [<pathspec>...]
# Exit 0 — it reports, it does not gate; the Reviewer gates.
# Exit 2 — a path was empty or unreadable, invalid diff base, or no scannable source.
#          "0 candidates" must mean "scanned and found nothing", never "scanned nothing".
set -u
[ $# -gt 0 ] || { echo "usage: security-scan.sh <path>... | --diff <base> [<pathspec>...]" >&2; exit 2; }

# Diff-mode symlinks are reported as their own candidates, never scanned —
# BSD/GNU `grep -r` does not follow a file symlink, so passing one to grep
# would silently produce nothing. Declared here so it is always defined
# under `set -u`, even in positional mode where it stays empty.
symlink_lines=()

# --include-docs (positional mode, before the path list): classify-diff.sh's
# D3-amendment cosmetic check needs to see INSIDE a file that only *looks* like
# doc/style (a `.md` holding real code) — the default filters below exist for
# the Reviewer's own noise reduction and would hide exactly that content. The
# flag disables only the `.md` and self filters for this one call; every other
# exclusion (tests, fixtures, vendor, node_modules) still applies, and a call
# without the flag stays byte-identical to before the flag existed.
include_docs=0
if [ "${1-}" = "--include-docs" ]; then
    include_docs=1
    shift
    [ $# -gt 0 ] || { echo "usage: security-scan.sh --include-docs <path>..." >&2; exit 2; }
fi

# Determine if we are in diff mode
if [ "$1" = "--diff" ]; then
    [ $# -ge 2 ] || { echo "usage: security-scan.sh --diff <base> [<pathspec>...]" >&2; exit 2; }
    shift
    base="$1"
    shift

    # Source diff-lib for validation and file listing
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/diff-lib.sh"

    # Get diff files; diff_files will exit with code 2 if there's an error
    if ! diff_files "SECURITY-SCAN" "$base" "$@"; then
        exit 2
    fi

    # Reused, not re-typed: the test-file shape lives once, in
    # tautology-scan.py's TEST_FILE constant, loaded once via diff-lib.sh's
    # load_test_file_re so this script and classify-diff.sh can never drift
    # on what a test file looks like. A narrower private regex here
    # (_test.|.test.|.spec.) missed test-*.sh and .bats, so a fixture string
    # like "eval(x)" inside one was scanned as source and escalated
    # classify-diff to `full` on stories that only touched test fixtures.
    load_test_file_re "SECURITY-SCAN" || exit 2

    # Filter out non-source files that don't need security scanning: test
    # files (shared TEST_FILE_RE, matched against the basename like
    # classify-diff.sh) and docs/fixtures/vendored code.
    filtered=()
    for f in "${DIFF_FILES[@]}"; do
        # A symlink is reported as [SYMLINK] and never handed to grep — grep
        # would silently skip it and produce a false "clean" read.
        if [ -L "$f" ]; then
            symlink_lines+=("[SYMLINK] $f -> $(readlink "$f")")
            continue
        fi
        if [[ "$(basename "$f")" =~ $TEST_FILE_RE ]]; then
            continue
        fi
        if ! [[ "$f" =~ /testdata/|/vendor/|/node_modules/|\.md$ ]]; then
            filtered+=("$f")
        fi
    done

    # If nothing left after filtering (not even a symlink candidate), it's no
    # scannable source
    if [ ${#filtered[@]} -eq 0 ] && [ ${#symlink_lines[@]} -eq 0 ]; then
        echo "SECURITY-SCAN: UNMEASURED — no scannable source in diff" >&2
        exit 2
    fi

    # bash 3.2 (macOS system bash) treats "${arr[@]}" on a zero-element array
    # as an unbound-variable error under `set -u`; guard the expansion rather
    # than rely on 4.4+ semantics.
    paths=()
    if [ ${#filtered[@]} -gt 0 ]; then
        paths=("${filtered[@]}")
    fi
else
    # Positional mode: validate paths as before
    for p in "$@"; do
        if [ -z "$p" ] || [ ! -r "$p" ]; then
            echo "SECURITY-SCAN: UNMEASURED — path empty or unreadable: '$p'" >&2
            exit 2
        fi
    done
    paths=("$@")
fi
total=0
found_tags=()  # Track which tags found matches for STRESS-TRIGGER output
emit() {
    local label="$1" pattern="$2" out exclude
    exclude="_test\.|\.test\.|\.spec\.|/testdata/|/vendor/|/node_modules/"
    if [ "$include_docs" -eq 0 ]; then
        exclude="$exclude|\.md:[0-9]+:|verify/security-scan\.sh:"
    fi
    out=$(grep -rnE --binary-files=without-match "$pattern" "${paths[@]}" 2>/dev/null \
        | grep -vE "$exclude" \
        || true)
    if [ -n "$out" ]; then
        printf '%s\n' "$out" | sed "s|^|[$label] |"
        total=$((total + $(printf '%s\n' "$out" | grep -c .)))
        found_tags+=("$label")
    fi
}

echo "## security-scan — candidates for Reviewer adjudication"
echo

# `paths` is empty only when a diff-mode scan is entirely symlinks (each one
# already routed to symlink_lines above) — grep with zero path args reads
# stdin and hangs, so it is never invoked in that case.
if [ ${#paths[@]} -gt 0 ]; then
    # Two shapes: the concat at the call site, and the far more common case of a query
    # string built on one line and executed on another. The second is what a call-site
    # grep misses, and it is the one that ships.
    emit INJECTION-SQL       "(Query|Exec|QueryRow|prepare|execute|raw)\(.*(\+|\\\$\{|%s|%v|format|f\")"
    emit INJECTION-SQL-BUILD "(SELECT|INSERT|UPDATE|DELETE|WHERE|FROM)[^\"']*[\"'][[:space:]]*(\+|\.|%|\\\$\{|\|\|)"
    emit INJECTION-CMD       "(exec\.Command|os/exec|child_process|subprocess\.|system\(|popen|shell_exec|eval\()"
    emit XSS                 "(innerHTML|outerHTML|document\.write|dangerouslySetInnerHTML|v-html|\|safe\b|Html\.raw)"
    emit SSRF                "(http\.Get|http\.Post|fetch\(|axios\.|requests\.(get|post)|HttpClient)"
    emit PATH-TRAVERSAL      "(os\.Open|ioutil\.ReadFile|readFile|open\(|File\()\(?[^)]*(req|request|param|query|input|user|argv)"
    emit WEAK-CRYPTO         "(md5|sha1|MD5|SHA1|DES|ECB|Math\.random\(|rand\.Int\(|mt_rand)"
    emit HARDCODED-SECRET    "(password|passwd|secret|api_?key|token|private_?key)[[:space:]]*(:?=|:)[[:space:]]*[\"'][^\"']{8,}"
    emit DESERIALIZATION     "(ObjectInputStream|unserialize\(|pickle\.loads|yaml\.load\(|Marshal\.load|eval\()"
    emit AUTH-SURFACE        "(router\.(Get|Post|Put|Delete|Patch)|app\.(get|post|put|delete)|@(Get|Post|Put|Delete)Mapping|@app\.route)"
    emit SECRET-IN-LOG       "(log|logger|console|print|fmt\.Print)[A-Za-z.]*\(.*(password|token|secret|api_?key|ssn|card)"
    emit DEBUG-IN-PROD       "(debug[[:space:]]*(:?=|:)[[:space:]]*(true|True|1)|DEBUG[[:space:]]*=[[:space:]]*True|\.set\(\"debug\")"
    emit MISSING-TIMEOUT     "(http\.Client\{\}|new HttpClient\(\)|requests\.(get|post)\([^,)]*\)$)"
    emit SHARED-STATE        "(sync\.(Mutex|RWMutex|Map|Once)|go func|atomic\.|threading\.|multiprocessing\.|synchronized|ConcurrentHashMap|volatile[[:space:]]|^[[:space:]]*global[[:space:]]|SharedArrayBuffer|new Worker\()"
fi

if [ ${#symlink_lines[@]} -gt 0 ]; then
    printf '%s\n' "${symlink_lines[@]}"
    total=$((total + ${#symlink_lines[@]}))
fi

echo
if [ "$total" -eq 0 ]; then
    echo "0 candidates. This is NOT a pass — a missing authz check has no pattern."
    echo "Reviewer still traces auth/authz on every new route and follows one error to its exit."
else
    echo "$total candidate(s). Adjudicate each: reachable? attacker-controlled? control adequate?"
    echo "AUTH-SURFACE hits are routes, not defects — each needs its authz check traced."
fi

# Stress trigger if any of these tags were found: SHARED-STATE, AUTH-SURFACE, SSRF,
# MISSING-TIMEOUT, INJECTION-CMD, INJECTION-SQL, INJECTION-SQL-BUILD, PATH-TRAVERSAL,
# DESERIALIZATION
stress_triggers=("SHARED-STATE" "AUTH-SURFACE" "SSRF" "MISSING-TIMEOUT" "INJECTION-CMD" "INJECTION-SQL" "INJECTION-SQL-BUILD" "PATH-TRAVERSAL" "DESERIALIZATION")
trigger_tags=()
if [ ${#found_tags[@]} -gt 0 ]; then
    for tag in "${stress_triggers[@]}"; do
        for found in "${found_tags[@]}"; do
            if [ "$tag" = "$found" ]; then
                trigger_tags+=("$tag")
                break
            fi
        done
    done
fi

if [ ${#trigger_tags[@]} -gt 0 ]; then
    echo "STRESS-TRIGGER: yes ($(IFS=' '; echo "${trigger_tags[*]}"))"
else
    echo "STRESS-TRIGGER: no"
fi

exit 0
