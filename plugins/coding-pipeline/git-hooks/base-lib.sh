#!/usr/bin/env bash
# base-lib.sh — shared base-commit resolution.
#
# dup-gate.sh and pre-push both needed "the commit this push/delivery should
# be measured against" and had grown two separately-typed copies of the same
# mainline-then-HEAD~1 search, free to drift apart (pre-push's copy already
# had diverged: it `continue`d past a degenerate ref instead of stopping like
# dup-gate.sh's did). One function, sourced by both, so there is exactly one
# place this logic can be wrong.
#
# Not executable on its own — meant to be sourced:
#   base_lib="$(dirname "$0")/base-lib.sh"
#   [ -f "$base_lib" ] || base_lib="$HOME/.claude/git-hooks/base-lib.sh"
#   [ -f "$base_lib" ] && . "$base_lib"

# resolve_base — prints the base commit sha to diff HEAD against, in
# mainline-ref-then-HEAD~1 order. Returns 1 (nothing printed) when there is
# no mainline ref reachable and no parent commit to fall back to.
resolve_base() {
    local ref base
    for ref in origin/main origin/master main master; do
        git rev-parse --verify -q "$ref" >/dev/null 2>&1 || continue
        base="$(git merge-base HEAD "$ref" 2>/dev/null)" || continue
        # On the mainline itself there is nothing ahead of the base, so
        # nothing would ever be attributed. Fall back to the last commit so
        # a direct push to main is still measured against something.
        if [ "$base" = "$(git rev-parse HEAD)" ]; then
            git rev-parse --verify -q HEAD~1 2>/dev/null && return 0
            return 1
        fi
        printf '%s' "$base"
        return 0
    done
    return 1
}
