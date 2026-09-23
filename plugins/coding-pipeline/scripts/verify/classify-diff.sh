#!/usr/bin/env bash
# classify-diff.sh — verifies a story's declared agent roster against its real diff.
#
# WHY: a declared roster (cosmetic/light/standard/full — the Architect's plan-time
# judgment call in the manifest) is a claim about how much a diff touches. Claims
# drift from reality: a "light" story grows a third file, a "cosmetic" edit turns
# out to touch a handler. This is the sensor that checks the claim against the
# real diff and only ever escalates it — never talks a declared roster down
# (SEC-4, D3/D7 in the delivery). Composed from two existing sensors rather than
# a second copy of their patterns: diff-lib.sh (ref validation, file listing) and
# security-scan.sh --diff (the STRESS-TRIGGER line already computed there).
#
# Classification order (D3, exactly, first match wins):
#   1. every changed file is doc/style                              -> cosmetic
#   2. else no non-test source file changed (tests/docs only)       -> light
#      (security-scan is not run)
#   3. else security-scan.sh --diff reports STRESS-TRIGGER: yes     -> full
#   4. else a dependency manifest changed, or >2 non-test source
#      files changed                                                -> standard
#   5. else                                                         -> light
#
# A symlink is never classified by its name (Stress ST2/ST3 class: a name-only
# rule lets a symlink disguise anything as anything) — it always counts as a
# non-test source file, whatever it is named. Deletions are excluded from
# diff-lib's own listing (--diff-filter=d — nothing left to scan) but must still
# be seen here: removing a source file is a behaviour change, so this script
# lists deletions itself (--diff-filter=D, NUL-safe) and folds them into
# classification; a deletion-only diff is therefore not the same as an empty one.
#
# Usage: classify-diff.sh --diff <base> --declared cosmetic|light|standard|full
# Exit 0 — required <= declared roster (declared is kept, never de-escalated).
# Exit 1 — required > declared; prints ROSTER: ESCALATE <declared> -> <required>.
# Exit 2 — usage error, unknown roster, invalid/unknown base, dirty tree, truly
#          empty diff, or security-scan itself came back UNMEASURED while source
#          was present in the diff (propagated, never swallowed into "no trigger").
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/diff-lib.sh"

usage() {
    echo "usage: classify-diff.sh --diff <base> --declared cosmetic|light|standard|full" >&2
    exit 2
}

rank() {
    case "$1" in
        cosmetic) echo 0 ;;
        light)    echo 1 ;;
        standard) echo 2 ;;
        full)     echo 3 ;;
        *)        echo -1 ;;
    esac
}

# True if $1 is one of the paths diff-lib actually listed as changed (added,
# modified or renamed-to) — i.e. it exists on disk and can be handed to
# security-scan, as opposed to a path this script only knows about via the
# separate deletion listing below.
in_diff_files() {
    local target="$1" d
    if [ ${#DIFF_FILES[@]} -gt 0 ]; then
        for d in "${DIFF_FILES[@]}"; do
            [ "$d" = "$target" ] && return 0
        done
    fi
    return 1
}

# run_capturing_stderr <outvar> <errvar> -- <cmd...>
# Runs <cmd...> with stdout and stderr each captured to a variable, without
# ever wrapping the call itself in a `$(...)` subshell — `diff_files` (below)
# sets the DIFF_FILES array as a side effect, and a subshell would drop that
# on the floor the moment it exited. Every diff-lib / security-scan call in
# this script needs exactly this shape (mktemp, run, capture, clean up); it
# existed three times as a copy-pasted block before this replaced it. Pass ""
# for <outvar> when the caller only needs the exit status and stderr text.
run_capturing_stderr() {
    local __outvar="$1" __errvar="$2" __otmp __etmp __rc
    shift 2
    [ "${1-}" = "--" ] && shift
    __otmp="$(mktemp "${TMPDIR:-/tmp}/classify-diff.out.XXXXXX")" || {
        echo "CLASSIFY: UNMEASURED — could not create temp file" >&2
        exit 2
    }
    __etmp="$(mktemp "${TMPDIR:-/tmp}/classify-diff.err.XXXXXX")" || {
        rm -f "$__otmp"
        echo "CLASSIFY: UNMEASURED — could not create temp file" >&2
        exit 2
    }
    "$@" >"$__otmp" 2>"$__etmp"
    __rc=$?
    if [ -n "$__outvar" ]; then
        printf -v "$__outvar" '%s' "$(cat "$__otmp")"
    fi
    printf -v "$__errvar" '%s' "$(cat "$__etmp")"
    rm -f "$__otmp" "$__etmp"
    return "$__rc"
}

base=""
declared=""
while [ $# -gt 0 ]; do
    case "$1" in
        --diff)
            [ $# -ge 2 ] || usage
            base="$2"
            shift 2
            ;;
        --declared)
            [ $# -ge 2 ] || usage
            declared="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done
[ -n "$base" ] || usage
[ -n "$declared" ] || usage

decl_rank="$(rank "$declared")"
if [ "$decl_rank" -lt 0 ]; then
    echo "classify-diff: usage — unknown declared roster '$declared' (want cosmetic|light|standard|full)" >&2
    exit 2
fi

# Reused, not re-typed: the test-file shape lives once, in tautology-scan.py's
# TEST_FILE constant. Extracted at run time via importlib (bash cannot import a
# Python module) so this script and that one can never drift on what a test
# file looks like.
TEST_FILE_RE="$(python3 -B - "$SCRIPT_DIR/tautology-scan.py" <<'PY'
import importlib.util
import sys

# A missing or unreadable tautology-scan.py must fail closed with UNMEASURED,
# never a raw Python traceback: every failure mode here is swallowed and
# reported by the empty-output check below instead.
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
    echo "CLASSIFY: UNMEASURED — could not load test-file pattern from tautology-scan.py" >&2
    exit 2
fi

DOC_STYLE_EXT_RE='\.(css|scss|sass|less|styl|md|txt)$'
DOC_STYLE_LOCALE_RE='(^|/)(locales|i18n|tokens)/.*\.(json|ya?ml|po|properties)$'
# D3 amendment (2026-09-23): exactly the dependency-manifest list the amendment
# names — no more, no less, so an unlisted manifest format is a plan-time
# question for the Architect, never a silently escalated or silently missed one.
DEP_MANIFEST_RE='(^|/)(package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|go\.(mod|sum)|Cargo\.(toml|lock)|requirements[A-Za-z0-9_.-]*\.txt|Pipfile(\.lock)?|pyproject\.toml|poetry\.lock|Gemfile(\.lock)?|pom\.xml|build\.gradle(\.kts)?|composer\.(json|lock)|pubspec\.(yaml|lock)|[A-Za-z0-9_.-]+\.csproj|packages\.config|Directory\.Packages\.props)$'

# diff-lib validates the base (charset, repo, ref existence, dirty tree) before
# it ever looks at file names — that validation runs exactly once here, so its
# failure text is captured rather than re-derived. Its own "empty diff" failure
# is the one case this script overrides: a deletion-only diff is empty to
# diff-lib (nothing left to scan after --diff-filter=d) but is not an empty
# story (D3, D4) — a deleted source file really did change.
errmsg=""
run_capturing_stderr "" errmsg -- diff_files "CLASSIFY" "$base"
rc=$?

if [ "$rc" -ne 0 ]; then
    case "$errmsg" in
        *"empty diff against"*)
            # Might still not be empty once deletions are counted — checked below.
            ;;
        *)
            echo "$errmsg" >&2
            exit 2
            ;;
    esac
fi

# Deletions are invisible to diff-lib by design (--diff-filter=d); list them
# separately, NUL-safe, so removing a source file can never pass as "nothing
# changed". The base was already validated above, so no re-validation here.
delfile="$(mktemp "${TMPDIR:-/tmp}/classify-diff.del.XXXXXX")" || {
    echo "CLASSIFY: UNMEASURED — could not create temp file" >&2
    exit 2
}
if ! git diff -z --name-only --diff-filter=D "$base...HEAD" > "$delfile" 2>/dev/null; then
    rm -f "$delfile"
    echo "CLASSIFY: UNMEASURED — git diff failed" >&2
    exit 2
fi
top="$(git rev-parse --show-toplevel)"
deleted=()
while IFS= read -r -d '' f; do
    deleted+=("$top/$f")
done < "$delfile"
rm -f "$delfile"

if [ "$rc" -ne 0 ] && [ ${#deleted[@]} -eq 0 ]; then
    # diff-lib's own emptiness call stands: nothing added/modified, nothing deleted.
    echo "$errmsg" >&2
    exit 2
fi

all_files=()
if [ ${#DIFF_FILES[@]} -gt 0 ]; then
    all_files+=("${DIFF_FILES[@]}")
fi
if [ ${#deleted[@]} -gt 0 ]; then
    all_files+=("${deleted[@]}")
fi

all_docstyle=1
source_files=()
existing_source_files=()
docstyle_existing_files=()
deps_changed=0

for f in "${all_files[@]}"; do
    # Category is exactly one of: docstyle, test, source. A file is only
    # "doc/style" when it actually matches the doc/style shape — a test file
    # is neither doc/style nor source, and must not silently satisfy step 1.
    is_docstyle=0
    is_source=0
    if [ -L "$f" ]; then
        # Never trusted by name: a symlink counts as source however it is named.
        is_source=1
    elif [[ "$f" =~ $DOC_STYLE_EXT_RE ]] || [[ "$f" =~ $DOC_STYLE_LOCALE_RE ]]; then
        is_docstyle=1
    elif [[ "$(basename "$f")" =~ $TEST_FILE_RE ]]; then
        : # test file: neither docstyle nor source
    else
        is_source=1
    fi

    if [ "$is_docstyle" -eq 0 ]; then
        all_docstyle=0
    elif in_diff_files "$f"; then
        # Only files that still exist on disk can be handed to security-scan
        # for the (c) content check below — a deleted doc/style file has
        # nothing left to read.
        docstyle_existing_files+=("$f")
    fi

    if [ "$is_source" -eq 1 ]; then
        source_files+=("$f")
        if in_diff_files "$f"; then
            existing_source_files+=("$f")
        fi
    fi

    if [[ "$f" =~ $DEP_MANIFEST_RE ]]; then
        deps_changed=1
    fi
done

required=""
reason=""

if [ "$all_docstyle" -eq 1 ]; then
    # D3 amendment: extension/location alone (checked above, step 1) is only
    # part (a) of cosmetic. (b): a rename or copy must not disguise a
    # non-doc/style origin as one — diff-lib's own listing (`--name-only`)
    # shows only the new path, so the origin is invisible there; `--name-status
    # -M -C` carries both. Parsed NUL-safe for the same reason diff-lib reads
    # its own list that way (a `\n`-split name silently becomes two paths).
    disguised_rename=0
    renstat_tmp="$(mktemp "${TMPDIR:-/tmp}/classify-diff.ren.XXXXXX")" || {
        echo "CLASSIFY: UNMEASURED — could not create temp file" >&2
        exit 2
    }
    git diff -z -M -C --name-status "$base...HEAD" > "$renstat_tmp" 2>/dev/null
    ren_state="status"
    old_path=""
    while IFS= read -r -d '' ren_tok; do
        case "$ren_state" in
            status)
                case "$ren_tok" in
                    R*|C*) ren_state="old" ;;
                    *)     ren_state="skip" ;;
                esac
                ;;
            skip)
                ren_state="status"
                ;;
            old)
                old_path="$ren_tok"
                ren_state="new"
                ;;
            new)
                if ! [[ "$old_path" =~ $DOC_STYLE_EXT_RE ]] && ! [[ "$old_path" =~ $DOC_STYLE_LOCALE_RE ]]; then
                    disguised_rename=1
                fi
                ren_state="status"
                ;;
        esac
    done < "$renstat_tmp"
    rm -f "$renstat_tmp"

    # (c): a doc/style-shaped file can still hold real code — security-scan's
    # default filters exclude `.md` for the Reviewer's own noise reduction, so
    # `--include-docs` is required to actually look inside these files. This
    # check runs on the doc/style files that still exist, renamed ones
    # included, regardless of (b)'s rename verdict below: a security-scan
    # candidate always wins over a bare rename's own light classification.
    content_clean=1
    if [ ${#docstyle_existing_files[@]} -gt 0 ]; then
        docsec_out="" docsec_err=""
        run_capturing_stderr docsec_out docsec_err -- bash "$SCRIPT_DIR/security-scan.sh" --include-docs "${docstyle_existing_files[@]}"
        docsec_rc=$?
        if [ "$docsec_rc" -ne 0 ]; then
            echo "CLASSIFY: UNMEASURED — security-scan: $docsec_err" >&2
            exit 2
        fi
        case "$docsec_out" in
            *"0 candidates"*) content_clean=1 ;;
            *)                content_clean=0 ;;
        esac
    fi

    if [ "$content_clean" -eq 0 ]; then
        required="full"
        reason="a doc/style file contained a security-scan candidate (D3 amendment)"
    elif [ "$disguised_rename" -eq 1 ]; then
        required="light"
        reason="a renamed or copied file's origin path was not doc/style (D3 amendment)"
    else
        required="cosmetic"
        reason="every changed file is doc/style"
    fi
elif [ ${#source_files[@]} -eq 0 ]; then
    required="light"
    reason="no non-test source file changed (tests/docs only)"
else
    trigger=no
    if [ ${#existing_source_files[@]} -gt 0 ]; then
        sec_out="" sec_err=""
        run_capturing_stderr sec_out sec_err -- bash "$SCRIPT_DIR/security-scan.sh" --diff "$base"
        sec_rc=$?
        if [ "$sec_rc" -ne 0 ]; then
            # Propagated verbatim, never swallowed into "no trigger": a real
            # UNMEASURED from security-scan is not the same claim as a clean scan.
            echo "CLASSIFY: UNMEASURED — security-scan: $sec_err" >&2
            exit 2
        fi
        case "$sec_out" in
            *"STRESS-TRIGGER: yes"*) trigger=yes ;;
        esac
    fi

    if [ "$trigger" = yes ]; then
        required="full"
        reason="security-scan reported a Stress trigger in the diff"
    elif [ "$deps_changed" -eq 1 ] || [ ${#source_files[@]} -gt 2 ]; then
        required="standard"
        if [ "$deps_changed" -eq 1 ]; then
            reason="a dependency manifest changed"
        else
            reason="${#source_files[@]} non-test source files changed (> 2)"
        fi
    else
        required="light"
        reason="${#source_files[@]} non-test source file(s), no dependency change, no trigger"
    fi
fi

req_rank="$(rank "$required")"

echo "CLASSIFY: required=$required declared=$declared"
if [ "$req_rank" -gt "$decl_rank" ]; then
    echo "REASON: $reason"
    echo "ROSTER: ESCALATE $declared → $required"
    exit 1
elif [ "$decl_rank" -gt "$req_rank" ]; then
    echo "REASON: declared roster kept"
    exit 0
else
    echo "REASON: $reason"
    exit 0
fi
