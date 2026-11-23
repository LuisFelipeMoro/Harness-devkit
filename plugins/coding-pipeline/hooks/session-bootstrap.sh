#!/usr/bin/env bash
# SessionStart hook — Harness "Memory & Progress" component.
# Reconstructs cross-session context: prints PROGRESS.md so a new session boots
# with what was done, what failed, and the current state — instead of starting blind.
# It also prints the row status of unfinished plans from their tasks.json, validated
# here because tasks.json text lands in the model's context. This hook only injects
# context; it never blocks. Exit code is always 0.
# Claude Code cuts SessionStart output at 10,000 characters, so the whole
# injection is held to 9,500: the row-status block is counted first, then
# PROGRESS.md gives way, oldest entries first.
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

# The five newest plan tasks.json files, newest mtime first. Symlinks are skipped
# (file or plan dir) so a planted link cannot point the hook at another file.
# Paths go to python as argv, never into a shell string.
candidates=()
for f in "$root"/docs/plans/*/tasks.json; do
    [ -f "$f" ] && [ ! -L "$f" ] && [ ! -L "$(dirname "$f")" ] && candidates+=("$f")
done
tasks_args=()
if [ ${#candidates[@]} -gt 0 ]; then
    # ls -t is the one mtime sort that runs on both BSD and GNU userlands. A name with a
    # newline would split into two paths that fail the python validator: unreadable, not trusted.
    # shellcheck disable=SC2012

    while IFS= read -r f; do tasks_args+=("$f"); done < <(ls -t -- "${candidates[@]}" 2>/dev/null | head -n 5)
fi

# Sizing and printing happen in one pass so the cap is checked against the exact
# text written. Stdlib python only; the script writes nothing unless it fits.
if python3 -I - "$progress_arg" "$snap" "$resume" "${tasks_args[@]+"${tasks_args[@]}"}" <<'PY'
import hashlib
import json
import os
import re
import sys

LIMIT = 9500
ROWS_CAP = 3000          # the row-status block's own bound; PROGRESS gives way to it
TASKS_CAP = 64 * 1024    # SEC-5: a larger tasks.json is skipped, never parsed
PLAN_CAP = 256 * 1024    # plan.md is read only for the Depends-on column
LESSONS_MAX = 15
LESSONS_CHARS = 1500
LESSON = "- Lessons:"
CARRY = "(Lessons carried from omitted entries, newest first:)"
OPEN = "=== PROGRESS.md (resume context — written by pipelines/handoff last session) ==="
END = "=== end PROGRESS.md ==="
CUT = "(PROGRESS.md cut to the size budget — read PROGRESS.md for the rest)"
TRUNC = "(snapshot truncated — see git status)"
FRESH = "No PROGRESS.md at repo root — fresh start. Pipelines and /handoff will create it (see references/progress-file.md)."
IN_PROGRESS = ("Row(s) in_progress at session start — run the /code resume protocol "
               "(skills/code/references/loop.md § Resume) before new work.")
STATUS_OMITTED = "(+%d more tasks.json lines omitted — run tasks_state.py status)"

# Literals copied byte-identical from plugins/coding-pipeline/scripts/tasks_state.py.
ID_RE = re.compile(r"[A-Za-z][A-Za-z0-9._-]{0,15}")
STATUSES = ("todo", "in_progress", "done", "failed")
ROW_KEYS = {"id", "status", "evidence", "head", "updated"}
NONE_TOKENS = {"", "-", "—", "–", "none", "n/a"}
# The slug is the plan dir name; SEC-1 slug regex.
SLUG_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")


def read(path):
    with open(path, encoding="utf-8", errors="replace", newline="") as fh:
        text = fh.read()
    if text and not text.endswith("\n"):
        text += "\n"
    return text


def read_capped(path, cap):
    # O_NOFOLLOW: a symlink raises OSError. Reads at most cap+1 bytes; over = longer than cap.
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(fd, "rb") as fh:
        data = fh.read(cap + 1)
    return data[:cap], len(data) > cap


def unreadable(slug):
    return f"[{slug}] tasks.json unreadable — run tasks_state.py verify"


def row_ok(row):
    if not isinstance(row, dict) or set(row) != ROW_KEYS:
        return False
    if not isinstance(row["id"], str) or not ID_RE.fullmatch(row["id"]):
        return False
    if row["status"] not in STATUSES:
        return False
    return all(isinstance(row[k], str) for k in ("evidence", "head", "updated"))


def canonical_sum(rows):
    text = json.dumps(rows, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def cells(line):
    s = line.strip()
    if not (s.startswith("|") and s.endswith("|")):
        return None
    return [c.strip() for c in s[1:-1].split("|")]


def split_list(cell):
    items = [(m.group(1) if (m := re.search(r"`([^`]*)`", x)) else re.sub(r"[`*]", "", x)).strip()
             for x in re.split(r"[,;]| and ", cell)]
    return [x for x in items if x.lower() not in NONE_TOKENS]


def plan_deps(path):
    # Depends-on IDs from the plan's Tasks table. Unreadable plan -> {}, and every row
    # then counts as dependency-free, the same default tasks_state.py applies.
    try:
        raw, over = read_capped(path, PLAN_CAP)
    except OSError:
        return {}
    if over:
        return {}
    deps, want = {}, None
    for line in raw.decode("utf-8", "replace").splitlines():
        c = cells(line)
        if c is None:
            if want is not None:
                break
            continue
        lower = [x.lower() for x in c]
        if want is None:
            if "id" in lower and "depends on" in lower:
                want = (lower.index("id"), lower.index("depends on"), len(c))
            continue
        if all(re.fullmatch(r":?-+:?", x) for x in c if x):
            continue
        if len(c) != want[2]:
            continue
        rid = re.sub(r"[`*]", "", c[want[0]]).strip()
        if rid:
            deps[rid] = split_list(c[want[1]])
    return deps


def _ids(xs):
    return ", ".join(xs) or "—"


def status_text(slug, rows, deps):
    state = {r["id"]: r["status"] for r in rows}
    done = sum(1 for r in rows if r["status"] == "done")
    in_progress = [r["id"] for r in rows if r["status"] == "in_progress"]
    failed = [r["id"] for r in rows if r["status"] == "failed"]
    nxt = next((r["id"] for r in rows
                if r["status"] == "todo" and all(state.get(d) == "done" for d in deps.get(r["id"], []))), None)
    return (f"[{slug}] {done}/{len(rows)} done · in_progress: {_ids(in_progress)} · "
            f"failed: {_ids(failed)} · next: {nxt or '—'}")


def tasks_lines(path):
    # The printed lines for one tasks.json, and whether it printed an in_progress row.
    slug = os.path.basename(os.path.dirname(path))
    if not SLUG_RE.fullmatch(slug):
        return [unreadable("?")], False
    try:
        raw, over = read_capped(path, TASKS_CAP)
    except OSError:
        return [unreadable(slug)], False
    if over:
        return [f"[{slug}] tasks.json skipped (over 64 KiB)"], False
    try:
        doc = json.loads(raw.decode("utf-8"))
    except (ValueError, RecursionError):
        return [unreadable(slug)], False
    rows = doc.get("rows") if isinstance(doc, dict) else None
    if not isinstance(rows, list) or not all(row_ok(r) for r in rows):
        return [unreadable(slug)], False
    ids = [r["id"] for r in rows]
    if len(set(ids)) != len(ids):
        return [unreadable(slug)], False
    # The stamp is checked before the all-done filter: a forged all-done plan is
    # the exact state a session must not trust, so it cannot be silent.
    if doc.get("sum") != canonical_sum(rows):
        return [f"[{slug}] tasks.json changed outside tasks_state.py — run tasks_state.py verify"], False
    if all(r["status"] == "done" for r in rows):
        return [], False
    deps = plan_deps(os.path.join(os.path.dirname(path), "plan.md"))
    in_progress = any(r["status"] == "in_progress" for r in rows)
    return [status_text(slug, rows, deps)], in_progress


def rows_block(paths):
    lines, resume_needed = [], False
    for p in paths:
        out, in_progress = tasks_lines(p)
        lines += out
        resume_needed = resume_needed or in_progress
    tail = [IN_PROGRESS] if resume_needed else []
    keep, dropped = list(lines), 0
    while True:
        extra = [STATUS_OMITTED % dropped] if dropped else []
        text = "".join(line + "\n" for line in keep + extra + tail)
        if len(text) <= ROWS_CAP or not keep:
            return text
        keep.pop()
        dropped += 1


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


def lessons_of(segs):
    # Lessons of dropped entries, newest first, deduplicated, capped at 15 lines and 1,500 chars.
    # Stops at the first line over a cap: the cap keeps the newest rules, not a scattered sample.
    out, seen, size = [], set(), 0
    for seg in reversed(segs):
        for line in seg.splitlines():
            if not line.startswith(LESSON) or line in seen:
                continue
            if len(out) == LESSONS_MAX or size + len(line) + 1 > LESSONS_CHARS:
                return out
            seen.add(line)
            out.append(line)
            size += len(line) + 1
    return out


def carry_block(segs):
    lessons = lessons_of(segs)
    if not lessons:
        return ""
    return CARRY + "\n" + "".join(line + "\n" for line in lessons)


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
            block = (OPEN + "\n" + omission(dropped) + "\n" + carry_block(segs[:dropped])
                     + kept + END + "\n")
            if len(block) <= budget:
                return block
        # Nothing but the omission line fits; the snapshot cut decides what follows.
        return OPEN + "\n" + omission(len(segs)) + "\n" + carry_block(segs) + END + "\n"
    # Free-form text with no entry markers: cut at a character boundary.
    room = budget - (len(OPEN) + len(CUT) + len(END) + 4)
    cut = body[:max(0, room)]
    if cut and not cut.endswith("\n"):
        cut += "\n"
    return OPEN + "\n" + cut + CUT + "\n" + END + "\n"


progress_path, snap_path, resume = sys.argv[1], sys.argv[2], sys.argv[3]
rows = rows_block(sys.argv[4:])
snap = read(snap_path) if snap_path else ""
tail_resume = resume + "\n" if resume else ""

body_budget = LIMIT - len(rows) - len(snap) - len(tail_resume)
if not progress_path:
    head = FRESH + "\n"
else:
    head = progress_block(read(progress_path), body_budget)

# Last resort: even with PROGRESS.md gone, the snapshot does not fit. Keep its
# first whole lines and mark the cut; the resume lines still close the output.
if len(rows) + len(head) + len(snap) + len(tail_resume) > LIMIT and snap:
    room = LIMIT - len(rows) - len(head) - len(tail_resume) - len(TRUNC) - 2
    keep = snap[:max(0, room)]
    if len(keep) < len(snap) and "\n" in keep:
        keep = keep[: keep.rfind("\n") + 1]
    if keep and not keep.endswith("\n"):
        keep += "\n"
    snap = keep + TRUNC + "\n"

out = rows + head + snap + tail_resume
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
