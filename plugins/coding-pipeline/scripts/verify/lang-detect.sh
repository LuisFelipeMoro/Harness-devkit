#!/usr/bin/env bash
# lang-detect.sh — names the languages a diff touches, so the reviewer is handed
# the rules that apply and its language claims have something to check against.
#
# WHY: a reviewer asked "is this good Go" first has to know the diff is Go.
# Inferring that from file names is unverifiable, and a proof line with nothing
# to check against is worth no more than the guess (ADR-9). Extensions name most
# languages; content decides the two ambiguous cases — htmx against plain HTML
# (an `hx-` in the file) and a `.tmpl` text template (an HTML tag makes it
# html-css, and a template with no tag gets no HTML rules at all, a user
# decision). It does not reuse diff-lib.sh: diff-lib refuses a dirty tree and an
# empty diff, both normal here (uncommitted work, Score Loop rounds), so it
# lists the changed files itself, NUL-safe (AC20).
#
# Usage: lang-detect.sh --diff <base>
# Output: one line per language, sorted by name —
#   LANGUAGE: <name> references/languages/<name>.md <file count>
#   then LANGUAGES: <names>, or LANGUAGES: none when no language rules apply.
# Exit 0 — the diff was read; LANGUAGES: none means nothing matched, not that
#          nothing could be read.
# Exit 2 — usage error, a base that is not a commit or looks like a git option,
#          a git listing that failed, or a file that could not be read.
set -u

usage() {
    echo "usage: lang-detect.sh --diff <base>" >&2
    exit 2
}

die() {
    echo "lang-detect: $*" >&2
    exit 2
}

[ $# -eq 2 ] && [ "$1" = "--diff" ] || usage
base="$2"

# A base beginning with "-" would be read by git as an option (SEC-7), so it is
# refused before any git call that takes it.
case "$base" in
    -*) die "invalid base $base" ;;
esac

toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 || die "invalid base $base"

# Enter the top level before any listing: git ls-files prints paths relative to
# the working directory, so from a subdirectory it would miss untracked files
# elsewhere and name the ones it found folder-relative. The next.config probe
# resolves against the same directory.
cd "$toplevel" || die "cannot enter $toplevel"

list=""
tally=""
cleanup() { rm -f "$list" "$tally"; }
trap cleanup EXIT
list=$(mktemp "${TMPDIR:-/tmp}/lang-detect.XXXXXX") || die "cannot create a temp file"
tally=$(mktemp "${TMPDIR:-/tmp}/lang-detect.XXXXXX") || die "cannot create a temp file"

# Changed files (base vs the working tree, so committed and uncommitted work
# count) plus untracked files. Deletions are dropped: nothing is left to read.
git diff --name-only -z --diff-filter=d "$base" -- >> "$list" || die "git diff failed against $base"
git ls-files -z --others --exclude-standard >> "$list" || die "git ls-files failed"

has_next_config() {
    local c
    for c in next.config.js next.config.mjs next.config.ts; do
        [ -f "$c" ] && return 0
    done
    return 1
}

# Content probes are fixed patterns on the file as named. A symlink is classified
# by its name and never followed for the read (SEC-7), so it reads as no match.
# grep exits 2 when it cannot read the file: that is passed up, never taken as "no match".
has_hx() {
    [ -L "$1" ] && return 1
    grep -Fq -- 'hx-' "$1"
}

has_html_tag() {
    [ -L "$1" ] && return 1
    grep -Eiq -- '<(!doctype|/?(html|head|body|div|span|p|a|ul|ol|li|table|tr|td|form|input|button|section|main|nav|header|footer|script|style|meta|link|img|h[1-6]))[ >/]' "$1"
}

# probe <check> <path> — 0 match, 1 no match; an unreadable file is fatal.
probe() {
    "$1" "$2"
    local rc=$?
    [ "$rc" -le 1 ] || die "cannot read $2"
    return "$rc"
}

# classify <path> — sets $lang to the language name, or "" when no rules apply.
classify() {
    local p="$1"
    lang=""
    case "$p" in
        *.go) lang=go ;;
        *.java) lang=java ;;
        *.kt|*.kts) lang=kotlin ;;
        *.rs) lang=rust ;;
        *.php) lang=php ;;
        *.dart) lang=flutter ;;
        *.ts|*.mts|*.cts|*.js|*.mjs|*.cjs) lang=typescript ;;
        *.tsx|*.jsx)
            if has_next_config; then lang=nextjs; else lang=react; fi ;;
        *.html|*.templ|*.gohtml)
            if probe has_hx "$p"; then lang=htmx; else lang=html-css; fi ;;
        *.tmpl)
            if probe has_hx "$p"; then lang=htmx
            elif probe has_html_tag "$p"; then lang=html-css
            fi ;;
        *.css|*.scss) lang=html-css ;;
    esac
}

# Read NUL-separated: a name with a space or a newline maps to its own language (SEC-7).
while IFS= read -r -d '' f; do
    classify "$f"
    [ -n "$lang" ] && printf '%s\n' "$lang" >> "$tally"
done < "$list"

# Fixed, sorted order (LC_ALL=C): the output is stable and each name maps to one file.
ALL="flutter go html-css htmx java kotlin nextjs php react rust typescript"
summary=""
for name in $ALL; do
    count=$(grep -cxF -- "$name" "$tally")
    if [ "$count" -gt 0 ]; then
        printf 'LANGUAGE: %s references/languages/%s.md %s\n' "$name" "$name" "$count"
        summary="$summary $name"
    fi
done
if [ -n "$summary" ]; then
    echo "LANGUAGES:$summary"
else
    echo "LANGUAGES: none"
fi
exit 0
