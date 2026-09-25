# shellcheck shell=bash
# diff-lib.sh — shared diff validation and file listing for diff-scoped sensors
#
# Validates a base ref and returns a NUL-safe array of changed files (repo-root
# absolute paths), accounting for renames and excluding deletions. Failures exit 2
# and print UNMEASURED to stderr so the caller can be minimal.
#
# Sourced, not executed. Sets DIFF_FILES array; returns 0 or 2.
# Usage: diff_files <prefix> <base> [--] [<pathspec>...]
#
# Reasons for UNMEASURED:
#  - invalid base ref (leading dash, contains .., non-ASCII, metacharacters)
#  - not a git repository
#  - unknown base ref
#  - uncommitted changes (tracked changes or untracked files)
#  - git diff itself failed (corrupt object, transient error, ...)
#  - empty diff against the base
#
# Not `set -u`: this file is sourced into the caller's shell, and the caller
# owns its own strictness — imposing one here would flip it for code that
# never opted in.

diff_files() {
    local prefix="$1" base="$2"
    shift 2

    # A literal "--" pathspec separator forwarded by the caller is optional;
    # strip it here so the "--" added below is never duplicated.
    if [ "${1-}" = "--" ]; then
        shift
    fi

    DIFF_FILES=()

    # Charset validation: base must start with alphanumeric, contain only alphanumeric/._/-
    if ! [[ "$base" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
        echo "$prefix: UNMEASURED — invalid base ref '$base'" >&2
        return 2
    fi

    # Reject .. in any position (range syntax, not a single ref)
    if [[ "$base" == *".."* ]]; then
        echo "$prefix: UNMEASURED — invalid base ref '$base'" >&2
        return 2
    fi

    # Check we are in a git repo
    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "$prefix: UNMEASURED — not a git repository" >&2
        return 2
    fi

    # Verify the base ref exists and is a commit
    if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
        echo "$prefix: UNMEASURED — unknown base ref '$base'" >&2
        return 2
    fi

    # Check for uncommitted changes (tracked modifications or untracked files)
    if [ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]; then
        echo "$prefix: UNMEASURED — uncommitted changes are outside the diff" >&2
        return 2
    fi

    # Get changed files (NUL-separated, excluding deletions, with renames as new
    # path, scoped to the given pathspec). Written to a temp file rather than a
    # process substitution so `git diff`'s own exit status is captured instead
    # of hidden by the pipeline.
    local tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/diff-lib.XXXXXX") || {
        echo "$prefix: UNMEASURED — could not create temp file" >&2
        return 2
    }
    if ! git diff -z --name-only --diff-filter=d "$base...HEAD" -- "$@" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        echo "$prefix: UNMEASURED — git diff failed" >&2
        return 2
    fi

    # NUL-delimited read: a `tr '\0' '\n'` + line `read` splits any file name
    # that itself contains a newline into two (missing) paths.
    local top f
    top=$(git rev-parse --show-toplevel)
    while IFS= read -r -d '' f; do
        DIFF_FILES+=("$top/$f")
    done < "$tmp"
    rm -f "$tmp"

    # If the list is empty, the diff is empty
    if [ ${#DIFF_FILES[@]} -eq 0 ]; then
        echo "$prefix: UNMEASURED — empty diff against $base" >&2
        return 2
    fi

    return 0
}

# load_test_file_re <prefix> — the sole loader of tautology-scan.py's
# TEST_FILE regex, shared by every sensor that needs to tell a test file from
# source (classify-diff.sh, security-scan.sh). The extraction used to be
# copy-pasted into each caller; two copies of the same importlib dance drift
# the moment one of them is edited and the other is not — one definition,
# sourced from here, cannot.
#
# Extracted at run time via importlib (bash cannot import a Python module
# directly). A missing or unreadable tautology-scan.py fails closed with
# UNMEASURED, never a raw Python traceback: every failure mode is swallowed
# in the heredoc and reported by the empty-output check below instead.
#
# Sets TEST_FILE_RE in the caller's shell; returns 0 or 2. `${BASH_SOURCE[0]}`
# resolves to this file (diff-lib.sh) regardless of which script called the
# function — bash tracks it per the frame that *defined* the function, not
# the frame that invoked it.
load_test_file_re() {
    local prefix="$1"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEST_FILE_RE="$(python3 -B - "$script_dir/tautology-scan.py" <<'PY'
import importlib.util
import sys

try:
    spec = importlib.util.spec_from_file_location("tautology_scan", sys.argv[1])
    if spec is None or spec.loader is None:
        raise ImportError("no module spec for " + sys.argv[1])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    print(module.TEST_FILE.pattern)
except Exception:
    pass
PY
)"
    if [ -z "$TEST_FILE_RE" ]; then
        echo "$prefix: UNMEASURED — could not load test-file pattern from tautology-scan.py" >&2
        return 2
    fi
    return 0
}
