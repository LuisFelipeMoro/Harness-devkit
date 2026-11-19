#!/usr/bin/env bash
# go-test-name.sh — a Go test file is named after the source file it tests.
#
# Go groups a package by directory, so a `*_test.go` whose `<stem>.go` is not in
# the same directory is a test filed under the wrong name: it is found by the
# next agent only by accident, and it invites a second test file for a source
# that already has one. The rule is go.md:119; this script is its one
# implementation, shared by checkpoint-m.sh, the pre-commit hook and the
# PreToolUse Write guard so the three gates never drift apart.
#
# Pairing: the stem is the file name minus `_test.go`, minus a trailing
# `_integration` or `_e2e`. A stem is paired when `<dir>/<stem>.go` exists, or
# when `<dir>/<stem>_*.go` exists (a platform split with no bare source). `main`,
# `export` and `example` stems are exempt, as are a directory holding no
# non-test `.go` file (test-only) and any path under `testdata/` or `vendor/`.
#
# Usage: go-test-name.sh <path>...
# Exit 0 — every path is paired, exempt, or not a `*_test.go`.
# Exit 1 — one or more paths are unpaired. One line per breach on stdout:
#          `go-test-name: <path> — no <stem>.go in <dir>; rename it after the
#          source it tests or add the tests to <candidates>`
#          where <candidates> lists the other `*_test.go` files in that
#          directory, or `its source's _test.go` when there are none.
# Exit 2 — misuse (no path given). Never read as a pass.
set -u

usage() {
    echo "usage: go-test-name.sh <path>..." >&2
    exit 2
}

# check_path <path> — prints one breach line and returns 1 when unpaired.
check_path() {
    local path="$1" dir stem bn cands where c
    case "$path" in
        *_test.go) ;;
        *) return 0 ;;
    esac
    case "/$path" in
        */testdata/*|*/vendor/*) return 0 ;;
    esac
    [ -f "$path" ] || return 0
    dir=$(dirname "$path")
    stem=$(basename "$path" _test.go)
    case "$stem" in
        main|export|example) return 0 ;;
    esac
    stem="${stem%_integration}"
    stem="${stem%_e2e}"
    [ -f "$dir/$stem.go" ] && return 0
    # A platform-split package has foo_linux.go and foo_windows.go but no foo.go.
    # The stem comes from a file name, so it is quoted: a glob character in it
    # matches only itself and cannot fake a pairing (SEC-6).
    for c in "$dir"/*.go; do
        [ -f "$c" ] || continue
        case "$c" in
            *_test.go) ;;
            "$dir"/"$stem"_*.go) return 0 ;;
        esac
    done
    # A test-only directory has no source file to pair with.
    find "$dir" -maxdepth 1 -name '*.go' ! -name '*_test.go' | grep -q . || return 0
    bn=$(basename "$path")
    cands=$(find "$dir" -maxdepth 1 -name '*_test.go' | sed 's|.*/||' \
        | grep -Fvx -- "$bn" | sort | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')
    if [ -n "$cands" ]; then
        where="$cands"
    else
        where="its source's _test.go"
    fi
    echo "go-test-name: $path — no $stem.go in $dir; rename it after the source it tests or add the tests to $where"
    return 1
}

[ $# -gt 0 ] || usage

breaches=0
for p in "$@"; do
    check_path "$p" || breaches=$((breaches + 1))
done

[ "$breaches" -eq 0 ] && exit 0
exit 1
