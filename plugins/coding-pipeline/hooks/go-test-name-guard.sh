#!/usr/bin/env bash
# PreToolUse(Write) — block creating a Go test file that is not named after its source.
#
# A new `*_test.go` must pair with a source file in its directory (`foo.go` ->
# `foo_test.go`). The rule lives in git-hooks/go-test-name.sh, shared with
# checkpoint-m and pre-commit so the three gates cannot drift. That script judges
# paths that exist, so the guard asks it about a throwaway mirror of the target
# directory: file names only, nothing written into the tree. Existing files are
# never judged, because renaming them is the coder's call.
# Exit 2 blocks the call and prints the shared script's message on stderr, and
# only when the shared script exits 1 (its naming verdict). Every other outcome
# exits 0 silently: shared script not found, scratch mirror not made, shared
# script exiting anything but 0 or 1. A guard fault must never block every
# test-file Write (fail open, A05).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

# block <message> — the agent learns the naming rule at the moment it writes.
block() {
    echo "BLOCKED $1" >&2
    exit 2
}

# fail_open — any internal fault allows the Write. Every internal error path
# routes here so the fail-open choice is stated once.
fail_open() { exit 0; }

devkit_hook_enabled "pre:write:go-test-name" || exit 0

input=$(cat)
target="$(devkit_field "$input" file_path)"
case "$target" in
    *_test.go) ;;
    *) exit 0 ;;
esac

cwd="$(devkit_field "$input" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
case "$target" in
    /*) abs="$target" ;;
    *) abs="$cwd/$target" ;;
esac
# Lexical normalisation of both paths: `..` must not let the mirror below escape
# its scratch dir, and a doubled slash must not hide the cwd prefix.
abs="$(python3 -c 'import os, sys; print(os.path.normpath(sys.argv[1]))' "$abs" 2>/dev/null)"
[ -n "$abs" ] || fail_open
cwd="$(python3 -c 'import os, sys; print(os.path.normpath(sys.argv[1]))' "$cwd" 2>/dev/null)"
[ -n "$cwd" ] || cwd="/"

# Only creation is judged: an existing file is rewritten or renamed by the coder's choice.
[ -e "$abs" ] && exit 0

shared=""
for cand in "$SCRIPT_DIR/../git-hooks/go-test-name.sh" "${HOME:-}/.claude/git-hooks/go-test-name.sh"; do
    if [ -n "${HOME:-}" ] || [ "$cand" != "/.claude/git-hooks/go-test-name.sh" ]; then
        if [ -f "$cand" ]; then
            shared="$cand"
            break
        fi
    fi
done
[ -n "$shared" ] || exit 0

case "$abs" in
    "$cwd"/*) rel="${abs#"$cwd"/}" ;;
    *) rel="${abs#/}" ;;
esac

# Mirror the target directory by name only, so the shared script sees the same
# siblings and the same relative path it would see in the tree.
tmp=""
trap '[ -n "$tmp" ] && rm -rf "$tmp"' EXIT
tmp="$(mktemp -d "${TMPDIR:-/tmp}/go-test-name.XXXXXX")" || fail_open
reldir="$(dirname "$rel")"
mkdir -p "$tmp/$reldir" || fail_open
realdir="$(dirname "$abs")"
for f in "$realdir"/*.go; do
    [ -f "$f" ] && : > "$tmp/$reldir/$(basename "$f")"
done
: > "$tmp/$rel" || fail_open

out="$(cd "$tmp" && bash "$shared" "$rel" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then exit 0; fi
if [ "$rc" -eq 1 ]; then block "$out"; fi
fail_open
