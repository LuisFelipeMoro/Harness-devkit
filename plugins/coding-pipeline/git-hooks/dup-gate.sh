#!/bin/bash
# Duplication gate — the one place the jscpd flags and the baseline rule live.
#
# pre-push runs it on the commits being pushed. /quality-gate runs it with
# --worktree, which measures the uncommitted tree too, so the verdict an agent sees
# before committing is the verdict pre-push will give — not a hand-rolled jscpd
# call with different flags that disagrees with it (which is how a repo-wide 5.5%
# once got reported as a FAIL on a change that introduced 0.5%).
#
# Usage: dup-gate.sh [--worktree]
# Exit 0 = pass · 1 = introduced duplication over the limit, an unreadable report,
#      or a snapshot that could not be built/replayed/committed
#      2 = UNENFORCED (jscpd or dup-attribution.py missing) — never rendered as a pass
DUP_MAX="${DEVKIT_DUP_MAX:-3}"

dup_attr="$(cd "$(dirname "$0")" && pwd)/dup-attribution.py"
[ -f "$dup_attr" ] || dup_attr="$HOME/.claude/git-hooks/dup-attribution.py"

# The baseline this delivery is measured against. Without it every clone in the
# repository is charged to the current push, which on any codebase with history
# fails on day one — and a gate that fails on day one gets disabled, taking the
# real finding with it.
dup_base() {
    local ref base
    for ref in origin/main origin/master main master; do
        git rev-parse --verify -q "$ref" >/dev/null 2>&1 || continue
        base="$(git merge-base HEAD "$ref" 2>/dev/null)" || continue
        # On the mainline itself there is nothing ahead of the base, so nothing
        # would ever be attributed. Fall back to the last commit so a direct
        # push to main is still measured against something.
        if [ "$base" = "$(git rev-parse HEAD)" ]; then
            git rev-parse --verify -q HEAD~1 2>/dev/null && return 0
            return 1
        fi
        printf '%s' "$base"
        return 0
    done
    return 1
}

# Every path below — jscpd's report, the diff, the untracked list — is taken as
# repo-root-relative. Run from a subdirectory, ls-files answers relative to it and
# the snapshot would put new files in the wrong place.
if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    cd "$top" || exit 1
elif [ "${1:-}" = "--worktree" ]; then
    echo "WARN: not a git repository — --worktree has nothing to snapshot; measuring the directory as-is"
fi

echo "→ Duplication ≤${DUP_MAX}% (introduced by this delivery)"
if command -v jscpd &>/dev/null; then
    jscpd_bin="jscpd"
elif [ -x node_modules/.bin/jscpd ]; then
    jscpd_bin="$PWD/node_modules/.bin/jscpd"
else
    echo "WARN: jscpd not found — duplication UNENFORCED. Install: npm i -g jscpd"
    exit 2
fi
if [ ! -f "$dup_attr" ]; then
    echo "WARN: dup-attribution.py not found beside the hook — duplication UNENFORCED. Re-run: bash ~/.claude/git-hooks/install.sh"
    exit 2
fi

# --worktree: attribution reads `git diff base...HEAD`, which cannot see work that
# is not committed. So the uncommitted tree is committed — in a throwaway detached
# worktree, never in the caller's repo, index or branch — and measured there.
# Per-run report dir: a fixed path let two concurrent runs (two deliveries' gates)
# delete or overwrite each other's report mid-read.
dup_out="$(mktemp -d "${TMPDIR:-/tmp}/devkit-jscpd.XXXXXX")"
snapshot=""
cleanup() {
    rm -rf "$dup_out"
    [ -n "$snapshot" ] || return 0
    git -C "$top" worktree remove --force "$snapshot" >/dev/null 2>&1
    rm -rf "$snapshot"
    git -C "$top" worktree prune >/dev/null 2>&1
}
trap cleanup EXIT
if [ "${1:-}" = "--worktree" ] && [ -n "$(git status --porcelain --untracked-files=all 2>/dev/null)" ]; then
    snapshot="$(mktemp -d "${TMPDIR:-/tmp}/devkit-dup-snap.XXXXXX")"
    if ! git worktree add -q --detach "$snapshot" HEAD >/dev/null 2>&1; then
        echo "FAIL: could not snapshot the working tree — refusing to pass an unmeasured gate"
        exit 1
    fi
    if [ -n "$(git diff HEAD)" ]; then
        git diff --binary HEAD | git -C "$snapshot" apply --binary || {
            echo "FAIL: could not replay uncommitted changes into the snapshot"; exit 1; }
    fi
    git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
        mkdir -p "$snapshot/$(dirname "$f")"
        cp -p "$f" "$snapshot/$f"
    done
    git -C "$snapshot" add -A
    git -C "$snapshot" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
        -c user.name=dup-gate -c user.email=dup-gate@localhost \
        commit -qm "chore: dup-gate snapshot" || {
        echo "FAIL: could not commit the snapshot"; exit 1; }
    cd "$snapshot" || exit 1
fi

# --threshold 100 so jscpd never gates: attribution owns the comparison, and a
# repo-wide percentage answers the wrong question. Markdown is excluded because
# the gate targets code — deliberately repeated prose (a per-language reference
# that must stay self-sufficient on a single-file load) is a token-efficiency
# decision, not a defect. Per-repo tuning (extra ignores, per-language limits)
# belongs in a committed .jscpd.json, which jscpd reads without this hook knowing.
"$jscpd_bin" . --threshold 100 --min-lines 8 --min-tokens 50 \
    --ignore "**/.git/**,**/node_modules/**,**/vendor/**,**/dist/**,**/build/**,**/target/**,**/.worktrees/**,**/testdata/**,**/*.lock,**/*.min.*,**/*.md" \
    --reporters json --output "$dup_out" >/dev/null 2>&1 || true

if base="$(dup_base)"; then
    python3 "$dup_attr" --report "$dup_out/jscpd-report.json" --base "$base" --threshold "$DUP_MAX"
else
    # No baseline: every clone is gated as if this push wrote it. Loud, and
    # deliberately not a silent skip — an unattributable gate is still a gate.
    python3 "$dup_attr" --report "$dup_out/jscpd-report.json" --threshold "$DUP_MAX"
fi
