#!/usr/bin/env bash
# Release content guard (G7) — session memory, handoff snapshots and generated
# test output must never enter a commit or a push. "Do not let PROGRESS.md and
# other progress files or tests that are not static go to the release."
#
# Checks PATHS only, never content: a path matching a pattern is rejected
# regardless of what it contains, and a static test source under tests/ is
# never matched by these patterns even though its own path contains "test" —
# the patterns name generated artifacts and session files, not test sources.
#
# Patterns come from the repo's own committed .devkit/release-exclude (one
# glob per line, # comments and blank lines ignored) so a repo can extend the
# set without editing this script. A repo with no such file has nothing to
# check — the guard never hard-codes a default list of its own.
#
# Usage: release-content-guard.sh --staged              (pre-commit: staged files)
#        release-content-guard.sh --range <a>..<b>       (pre-push: existing branch — the exact remote..local sha range being pushed)
#        release-content-guard.sh --commits <sha> [<sha> ...]
#                                                         (pre-push: new branch — no remote sha to range against, so each
#                                                          commit `git rev-list <lsha> --not --remotes` found is checked on its own)
# Exit 0 = clean · 1 = one or more offending paths, each named · 2 = misuse,
#          or a git command failed and the content could not be verified —
#          never read as clean; the caller (pre-commit / pre-push) blocks on
#          any non-zero exit, 1 or 2 alike.
set -u

usage() {
    echo "usage: release-content-guard.sh --staged | --range <a>..<b> | --commits <sha> [<sha> ...]" >&2
    exit 2
}

[ $# -ge 1 ] || usage
mode="$1"

top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "WARN: not a git repository — release content guard skipped"
    exit 0
}
cd "$top" || exit 1

exclude_file=".devkit/release-exclude"
patterns=()
if [ -f "$exclude_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        # trim leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -n "$line" ] && patterns+=("$line")
    done < "$exclude_file"
fi

# path_matches <path> <pattern> — glob match on the full relative path. A
# "**/" prefix also matches the pattern with no leading directory at all
# (repo-root files), matching the conventional "any depth including zero"
# reading of "**/" elsewhere (gitignore, rsync) that a plain shell pattern
# does not give for free.
path_matches() {
    local path="$1" pattern="$2"
    # shellcheck disable=SC2254  # pattern is a glob, not meant to be quoted
    case "$path" in
        $pattern) return 0 ;;
    esac
    case "$pattern" in
        '**/'*)
            local stripped="${pattern#\*\*/}"
            # shellcheck disable=SC2254
            case "$path" in
                $stripped) return 0 ;;
            esac
            ;;
    esac
    return 1
}

offending=()

# already_offending <path> — linear scan; bash 3.2 (macOS's /bin/bash) has no
# associative arrays to dedupe with in O(1), and the offending list is short
# (a guard hit is already unusual). Needed because a merge commit's `-m` diff
# reports the same path once per parent it changed relative to.
already_offending() {
    local path="$1" o
    [ "${#offending[@]}" -gt 0 ] || return 1
    for o in "${offending[@]}"; do
        [ "$o" = "$path" ] && return 0
    done
    return 1
}

check_paths() {   # reads NUL-delimited paths on stdin
    local path p
    while IFS= read -r -d '' path; do
        [ -n "$path" ] || continue
        # bash 3.2 (macOS's /bin/bash) treats "${arr[@]}" on a zero-length
        # array as an unbound-variable error under `set -u` — guard the
        # expansion with a length check rather than relying on the array
        # itself being "declared".
        [ "${#patterns[@]}" -gt 0 ] || continue
        already_offending "$path" && continue
        for p in "${patterns[@]}"; do
            if path_matches "$path" "$p"; then
                offending+=("$path")
                break
            fi
        done
    done
}

# run_git_diff <outfile> <errmsg> -- <git-args...> — writes the NUL-delimited
# name list to <outfile> and checks git's own exit status. A `< <(...)`
# process substitution (the previous shape) discards that status entirely —
# `git diff-tree` failing on a corrupt object, or any other transient git
# error, read as an empty path list, which is indistinguishable from "nothing
# offending" (ST12 Review MAJOR: a failed inspection must never look clean).
# Prints "release-content-guard: UNMEASURED — <errmsg>" and returns 2 on
# failure; the caller passes it straight through as this script's own exit 2.
run_git_diff() {
    local outfile="$1" errmsg="$2"
    shift 2
    [ "${1-}" = "--" ] && shift
    if ! git "$@" > "$outfile" 2>/dev/null; then
        echo "release-content-guard: UNMEASURED — $errmsg" >&2
        return 2
    fi
    return 0
}

case "$mode" in
    --staged)
        tmp="$(mktemp "${TMPDIR:-/tmp}/release-guard.staged.XXXXXX")" || {
            echo "release-content-guard: UNMEASURED — could not create temp file" >&2
            exit 2
        }
        if ! run_git_diff "$tmp" "git diff --cached failed" -- diff --cached --name-only -z --diff-filter=ACMR; then
            rm -f "$tmp"
            exit 2
        fi
        check_paths < "$tmp"
        rm -f "$tmp"
        ;;
    --range)
        range="${2:-}"
        case "$range" in
            *..*) ;;
            *) usage ;;
        esac
        tmp="$(mktemp "${TMPDIR:-/tmp}/release-guard.range.XXXXXX")" || {
            echo "release-content-guard: UNMEASURED — could not create temp file" >&2
            exit 2
        }
        if ! run_git_diff "$tmp" "git diff failed for $range" -- diff --name-only -z --diff-filter=ACMR "$range"; then
            rm -f "$tmp"
            exit 2
        fi
        check_paths < "$tmp"
        rm -f "$tmp"
        ;;
    --commits)
        shift
        [ $# -ge 1 ] || usage
        # A new branch has no remote sha to range against. Each commit is
        # checked on its own via diff-tree (--root handles the very first
        # commit of a repo, which diff-tree shows nothing for otherwise) so
        # every commit being published is guarded, not just the net diff.
        for sha in "$@"; do
            tmp="$(mktemp "${TMPDIR:-/tmp}/release-guard.commit.XXXXXX")" || {
                echo "release-content-guard: UNMEASURED — could not create temp file" >&2
                exit 2
            }
            # -m: without it, diff-tree prints nothing for a merge commit —
            # the commonest integration flow (resolve a conflict, commit the
            # merge) would otherwise let its content ride a new-branch push
            # straight through. With -m each parent is diffed separately, so
            # a changed path can appear once per parent; already_offending
            # dedupes it above.
            if ! run_git_diff "$tmp" "git diff-tree failed for $sha" -- diff-tree -m --no-commit-id --name-only -r -z --root --diff-filter=ACMR "$sha"; then
                rm -f "$tmp"
                exit 2
            fi
            check_paths < "$tmp"
            rm -f "$tmp"
        done
        ;;
    *)
        usage
        ;;
esac

if [ "${#offending[@]}" -gt 0 ]; then
    echo "release-content-guard: FAIL — these paths must never enter the release (see .devkit/release-exclude):"
    for f in "${offending[@]}"; do
        echo "  $f"
    done
    exit 1
fi

exit 0
