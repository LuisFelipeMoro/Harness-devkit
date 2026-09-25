#!/usr/bin/env bash
# break-run.sh — mutate exactly one literal occurrence in a file, run a test
# command against the mutation, and prove the row failed for itself — then
# always restore the file, however the run ends.
#
# WHY: two failure classes this tool exists to close. (F4) a hand-edited break
# whose pattern occurs more than once (or not at all) can silently land on the
# wrong line — the command still runs, still exits non-zero for some unrelated
# reason, and "proves" nothing about the row it claims to falsify. (F3) an
# agent that dies mid-break — killed, crashed, context cut — can leave the
# mutation sitting in the tree with no marker explaining why. Refusing an
# ambiguous pattern up front, and restoring from a pristine copy on every exit
# path (normal, interrupted, or a restore that itself fails loudly instead of
# silently), makes a falsification pass unable to leave the working tree worse
# than it found it.
#
# Usage: break-run.sh --file <f> --old <literal> --new <literal> --row "<name>" -- <test cmd...>
# Exit 0 — the run's combined output contains the literal `FAIL: <row>` (the
#          row failed for itself: real falsification evidence).
# Exit 1 — the run passed despite the mutation, or failed without ever naming
#          the row — neither is evidence the row's check was exercised.
# Exit 2 — misuse (bad args, <file> missing, --old not present exactly once)
#          or the post-run restore did not reproduce the pristine copy.
set -u

usage() {
    echo 'usage: break-run.sh --file <f> --old <literal> --new <literal> --row "<name>" -- <test cmd...>' >&2
    exit 2
}

file=""
old=""
new=""
row=""
cmd=()
while [ $# -gt 0 ]; do
    case "$1" in
        --file)
            [ $# -ge 2 ] || usage
            file="$2"
            shift 2
            ;;
        --old)
            [ $# -ge 2 ] || usage
            old="$2"
            shift 2
            ;;
        --new)
            [ $# -ge 2 ] || usage
            new="$2"
            shift 2
            ;;
        --row)
            [ $# -ge 2 ] || usage
            row="$2"
            shift 2
            ;;
        --)
            shift
            cmd=("$@")
            break
            ;;
        *)
            usage
            ;;
    esac
done

# --new may legitimately be the empty string (the break deletes the matched
# literal outright) — only --file, --old, --row and a non-empty test command
# are mandatory.
[ -n "$file" ] || usage
[ -n "$old" ] || usage
[ -n "$row" ] || usage
[ ${#cmd[@]} -gt 0 ] || usage

# A symlinked --file is refused outright, before any read, copy or mutation:
# following it would let a killed run corrupt whatever the link points to,
# including a target outside the repository entirely. -L is checked ahead of
# -f so a broken symlink (target missing) still reports "is a symlink"
# rather than the generic "no such file".
if [ -L "$file" ]; then
    echo "break-run: refused — '$file' is a symlink, symlink targets are never followed" >&2
    exit 2
fi
[ -f "$file" ] || { echo "break-run: usage — no such file '$file'" >&2; exit 2; }

# A falsification tool must only ever touch the code under test — refuse a
# --file whose real (symlink-resolved) path falls outside the git toplevel,
# or outside the current directory when this isn't a git repo at all.
file_real=$(python3 -c '
import os, sys
print(os.path.realpath(sys.argv[1]))
' "$file") || { echo "break-run: could not resolve path of '$file'" >&2; exit 2; }
if base_dir=$(git rev-parse --show-toplevel 2>/dev/null); then
    :
else
    base_dir=$(pwd)
fi
base_real=$(python3 -c '
import os, sys
print(os.path.realpath(sys.argv[1]))
' "$base_dir") || { echo "break-run: could not resolve containment base" >&2; exit 2; }
case "$file_real" in
    "$base_real"|"$base_real"/*) ;;
    *)
        echo "break-run: refused — '$file' resolves outside $base_real" >&2
        exit 2
        ;;
esac

# Exact literal occurrence count, never a regex count: --old is ordinary
# source text and may hold `.`, `*`, `(`, `[` — characters a regex engine
# would reinterpret. python3's str.count is a byte-for-byte literal count.
# newline="" on every open: the default text-mode universal-newline
# translation would read a CRLF line ending as "\n" and, on write, drop the
# "\r" for good — silently rewriting every line ending in the file instead
# of the one matched literal. newline="" passes line endings through as
# ordinary bytes, so only --old's own bytes ever change.
count=$(OLD="$old" python3 -c '
import os, sys
with open(sys.argv[1], "r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
    data = fh.read()
print(data.count(os.environ["OLD"]))
' "$file") || { echo "break-run: could not read '$file' to count occurrences" >&2; exit 2; }

if [ "$count" -ne 1 ]; then
    echo "break-run: refused — '--old' occurs $count time(s) in $file (want exactly 1)" >&2
    exit 2
fi

cmd_pid=""  # set once the test command is backgrounded — see on_interrupt below
out_tmp=""  # set once the test command's output file is created — see cleanup below
marker="$file.devkit-break"
# Atomic O_EXCL create: a plain `cp -p` over an existing marker let a second
# concurrent run silently overwrite the first run's pristine copy — the one
# thing standing between an interrupted run and a permanently mutated file.
# O_EXCL refuses outright (exit 3) when the marker already exists; copystat
# still carries $file's own permissions onto the marker, so the restore path
# below is unchanged: it still `cp -p`s the marker back over $file.
python3 -c '
import os, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
except FileExistsError:
    sys.exit(3)
with os.fdopen(fd, "wb") as out, open(src, "rb") as inp:
    shutil.copyfileobj(inp, out)
shutil.copystat(src, dst)
' "$file" "$marker"
marker_rc=$?
if [ "$marker_rc" -eq 3 ]; then
    echo "break-run: refused — '$marker' held by another run" >&2
    exit 2
elif [ "$marker_rc" -ne 0 ]; then
    echo "break-run: could not create pristine copy $marker" >&2
    exit 2
fi

# Single restore path for every way this script can end: falls through
# normally, `exit`s explicitly below, or is interrupted mid-run. A restore
# that fails is reported loudly and forces exit 2 — a marker left behind on a
# failed restore is the one outcome this script must never produce silently.
cleanup() {
    local rc=$?
    if [ -n "$out_tmp" ] && [ -f "$out_tmp" ]; then
        rm -f "$out_tmp"
    fi
    if [ -f "$marker" ]; then
        # The marker is the only pristine copy left. A restore that fails —
        # cp cannot write $file, or the post-copy cmp does not match — must
        # never delete it: that copy is the one thing standing between this
        # run and a permanently mutated file. Keep it and fail loudly instead.
        if ! cp -p "$marker" "$file" 2>/dev/null; then
            echo "break-run: RESTORE FAILED — pristine copy kept at $marker" >&2
            exit 2
        fi
        if ! cmp -s "$marker" "$file"; then
            echo "break-run: RESTORE FAILED — pristine copy kept at $marker" >&2
            exit 2
        fi
        rm -f "$marker"
    fi
    exit "$rc"
}
trap cleanup EXIT
# INT/TERM: kill the still-running test command first — a long-running
# command (e.g. `sleep 30`) must not outlive an interrupted break-run.sh —
# then translate the signal into a plain `exit 2` so cleanup's own EXIT trap
# performs the one restore path above, instead of duplicating it here.
on_interrupt() {
    [ -n "$cmd_pid" ] && kill -TERM "$cmd_pid" 2>/dev/null
    exit 2
}
trap on_interrupt INT TERM

OLD="$old" NEW="$new" python3 -c '
import os, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
    data = fh.read()
with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
    fh.write(data.replace(os.environ["OLD"], os.environ["NEW"], 1))
' "$file" || {
    echo "break-run: mutation failed applying to $file" >&2
    exit 2
}

# Backgrounded and waited on explicitly (never a synchronous command
# substitution) so on_interrupt has a real pid to kill: a foreground `$(...)`
# leaves the test command running until it exits on its own even after
# break-run.sh itself has been signalled.
out_tmp=$(mktemp "${TMPDIR:-/tmp}/break-run.out.XXXXXX") || {
    echo "break-run: could not create temp output file" >&2
    exit 2
}
"${cmd[@]}" >"$out_tmp" 2>&1 &
cmd_pid=$!
wait "$cmd_pid"
run_rc=$?
run_out=$(cat "$out_tmp")
rm -f "$out_tmp"
printf '%s\n' "$run_out"

needle="FAIL: $row"
if printf '%s\n' "$run_out" | grep -qF -- "$needle"; then
    echo "break-run: row '$row' failed for itself (falsification proven)"
    exit 0
fi

if [ "$run_rc" -eq 0 ]; then
    echo "break-run: FAIL — test command passed despite the mutation (row '$row' not falsified)" >&2
else
    echo "break-run: FAIL — test command failed but never printed '$needle' (row '$row' not falsified)" >&2
fi
exit 1
