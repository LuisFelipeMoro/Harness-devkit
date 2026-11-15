#!/usr/bin/env bash
# SessionStart hook — Harness "Memory & Progress" component.
# Reconstructs cross-session context: prints PROGRESS.md so a new session boots
# with what was done, what failed, and the current state — instead of starting blind.
# This hook only injects context; it never blocks. Exit code is always 0.
# Claude Code cuts SessionStart output at 10,000 characters, so the whole
# injection is held to 9,500: PROGRESS.md gives way first, oldest entries first.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

input=""
[ -t 0 ] || input="$(cat 2>/dev/null)"
source_kind="$(devkit_field "$input" source)"

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
progress="$root/PROGRESS.md"

# After auto-compaction the session continues on its own — no human opens a new
# one — so the deterministic snapshot precompact-snapshot.sh wrote goes back in,
# and the context-budget latches re-arm: the window just emptied, and the next
# climb to 80% must be announced again.
snap=""
resume=""
state=""
if [ "$source_kind" = "compact" ] && state="$(devkit_state_dir "$input")"; then
    # Same session id only. Guessing by directory would hand one session another
    # concurrent session's branch and dirty files as authoritative resume state.
    snap="$state/precompact.md"
    [ -f "$snap" ] || snap=""
    resume="Resumed after compaction. Continue the task from PROGRESS.md and the snapshot above;
if the snapshot flags PROGRESS.md as stale, update it first. Do not ask the human to restart."
fi

progress_arg=""
if [ -f "$progress" ]; then
    progress_arg="$progress"
fi

# Sizing and printing happen in one pass so the cap is checked against the exact
# text written. Stdlib python only; the script writes nothing unless it fits.
if python3 -I - "$progress_arg" "$snap" "$resume" <<'PY'
import sys

LIMIT = 9500
OPEN = "=== PROGRESS.md (resume context — written by pipelines/handoff last session) ==="
END = "=== end PROGRESS.md ==="
CUT = "(PROGRESS.md cut to the size budget — read PROGRESS.md for the rest)"
TRUNC = "(snapshot truncated — see git status)"
FRESH = "No PROGRESS.md at repo root — fresh start. Pipelines and /handoff will create it (see references/progress-file.md)."


def read(path):
    with open(path, encoding="utf-8", errors="replace", newline="") as fh:
        text = fh.read()
    if text and not text.endswith("\n"):
        text += "\n"
    return text


def entries_of(body):
    # Segment 0 may be the header before the first entry; it is the oldest segment.
    segs, cur = [], []
    for line in body.splitlines(True):
        if line.startswith("## [") and cur:
            segs.append("".join(cur))
            cur = []
        cur.append(line)
    if cur:
        segs.append("".join(cur))
    return segs


def omission(n):
    return "(%d older PROGRESS.md entries omitted — read PROGRESS.md for them)" % n


def progress_block(body, budget):
    verbatim = OPEN + "\n" + body + END + "\n"
    if len(verbatim) <= budget:
        return verbatim
    segs = entries_of(body)
    if any(seg.startswith("## [") for seg in segs):
        for dropped in range(1, len(segs) + 1):
            kept = "".join(segs[dropped:])
            block = OPEN + "\n" + omission(dropped) + "\n" + kept + END + "\n"
            if len(block) <= budget:
                return block
        # Nothing but the omission line fits; the snapshot cut decides what follows.
        return OPEN + "\n" + omission(len(segs)) + "\n" + END + "\n"
    # Free-form text with no entry markers: cut at a character boundary.
    room = budget - (len(OPEN) + len(CUT) + len(END) + 4)
    cut = body[:max(0, room)]
    if cut and not cut.endswith("\n"):
        cut += "\n"
    return OPEN + "\n" + cut + CUT + "\n" + END + "\n"


progress_path, snap_path, resume = sys.argv[1], sys.argv[2], sys.argv[3]
snap = read(snap_path) if snap_path else ""
tail_resume = resume + "\n" if resume else ""

body_budget = LIMIT - len(snap) - len(tail_resume)
if not progress_path:
    head = FRESH + "\n"
else:
    head = progress_block(read(progress_path), body_budget)

# Last resort: even with PROGRESS.md gone, the snapshot does not fit. Keep its
# first whole lines and mark the cut; the resume lines still close the output.
if len(head) + len(snap) + len(tail_resume) > LIMIT and snap:
    room = LIMIT - len(head) - len(tail_resume) - len(TRUNC) - 2
    keep = snap[:max(0, room)]
    if len(keep) < len(snap) and "\n" in keep:
        keep = keep[: keep.rfind("\n") + 1]
    if keep and not keep.endswith("\n"):
        keep += "\n"
    snap = keep + TRUNC + "\n"

out = head + snap + tail_resume
if len(out) > LIMIT:
    sys.exit(2)
sys.stdout.buffer.write(out.encode("utf-8"))
PY
then
    [ -n "$snap" ] && rm -f "$snap"
else
    echo "PROGRESS.md could not be sized for SessionStart — read PROGRESS.md directly."
    [ -n "$resume" ] && echo "$resume"
fi

if [ -n "$resume" ]; then
    rm -f "$state/ctx-warn" "$state/ctx-ceiling"
fi

# Prune session-tracker scratch dirs older than a day so /tmp does not accumulate.
find "${TMPDIR:-/tmp}/claude-devkit" -mindepth 1 -maxdepth 1 -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true

exit 0
