#!/usr/bin/env python3
"""The Tasks-table parser shared by estimate-run.py and the tasks.json row-state tool.

parse() reads the plan's Tasks table and returns one dict per row (id, files, tests, deps).
A table it cannot read raises TableError — the caller decides how to report it (estimate-run
prints `ESTIMATE: UNMEASURED — {msg}` and exits 2). Stdlib only.

CLI (row state in <plan dir>/tasks.json, written only here):
  tasks_state.py init   <plan.md>                          create or extend tasks.json from the Tasks table
  tasks_state.py set    <plan.md> <ID> <status> [--evidence TEXT]   one allowed transition
  tasks_state.py status <plan.md>                          one status line
  tasks_state.py verify <plan.md>                          TASKS: PASS / FAIL / UNMEASURED
"""
import dataclasses
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time

class TableError(Exception):
    """The plan's Tasks table cannot be read; the message names what is wrong."""


REQUIRED = ["id", "task", "files", "test rows", "language", "tier", "depends on"]
NONE_TOKENS = {"", "-", "—", "–", "none", "n/a"}


def cells(line):
    s = line.strip()
    if not (s.startswith("|") and s.endswith("|")):
        return None
    return [c.strip() for c in s[1:-1].split("|")]


def split_list(cell):
    # A `code span` is taken verbatim (a glob's `*` is part of the path); outside one, `*` is
    # markdown emphasis and dropped.
    items = [(m.group(1) if (m := re.search(r"`([^`]*)`", x)) else re.sub(r"[`*]", "", x)).strip()
             for x in re.split(r"[,;]| and ", cell)]
    return [x for x in items if x.lower() not in NONE_TOKENS]


def parse(path):
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError as e:
        raise TableError(f"cannot read plan: {e}")
    # The Tasks table is the one whose header carries every required column.
    start = None
    for i, line in enumerate(lines):
        c = cells(line)
        if c and {x.lower() for x in c} >= set(REQUIRED):
            start, header = i, [x.lower() for x in c]
            break
    if start is None:
        raise TableError("no Tasks table (| ID | Task | Files | Test rows | Language | Tier | Depends on |)")
    idx = {name: header.index(name) for name in REQUIRED}
    rows = []
    for line in lines[start + 1:]:
        c = cells(line)
        if c is None:
            break
        if all(re.fullmatch(r":?-+:?", x) for x in c if x):
            continue
        if len(c) != len(header):
            raise TableError(f"malformed Tasks row ({len(c)} cells, header has {len(header)}): {line.strip()}")
        rid = re.sub(r"[`*]", "", c[idx["id"]]).strip()
        if not rid:
            raise TableError(f"Tasks row without an ID: {line.strip()}")
        rows.append({
            "id": rid,
            "files": split_list(c[idx["files"]]),
            "tests": split_list(c[idx["test rows"]]),
            "deps": split_list(c[idx["depends on"]]),
        })
    if not rows:
        raise TableError("Tasks table has no rows")
    ids = [r["id"] for r in rows]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        raise TableError(f"duplicate Task ID(s): {', '.join(dup)}")
    for r in rows:
        for d in r["deps"]:
            if d not in ids:
                raise TableError(f"{r['id']} depends on unknown task '{d}'")
        if not r["files"]:
            raise TableError(f"{r['id']} lists no Files — the checkpoint needs them as --expect")
    return rows


# ── tasks.json row state ────────────────────────────────────────────────────

SCHEMA = 1
STATUSES = ("todo", "in_progress", "done", "failed")
ROW_KEYS = {"id", "status", "evidence", "head", "updated"}
ID_RE = re.compile(r"[A-Za-z][A-Za-z0-9._-]{0,15}")
LOCK_TIMEOUT_DEFAULT = 5.0
USAGE = "usage: tasks_state.py {init|status|verify} <plan.md> | set <plan.md> <ID> <status> [--evidence TEXT]"
EVIDENCE_MAX = 300
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f-\x9f]")
# (from, to) → the rule the transition must meet (AC2). Any pair not listed is an illegal transition.
TRANSITIONS = {
    ("todo", "in_progress"): "deps",
    ("failed", "in_progress"): "deps",
    ("in_progress", "done"): "pass",
    ("in_progress", "failed"): "evidence",
    ("in_progress", "todo"): "evidence",
    ("done", "todo"): "evidence",
}


class StateError(Exception):
    """A refused or unmeasurable operation; rc is the CLI exit code (1 refused, 2 unmeasured)."""

    def __init__(self, rc, msg):
        super().__init__(msg)
        self.rc = rc
        self.msg = msg


@dataclasses.dataclass
class TaskFile:
    schema: int
    plan: str
    slug: str
    rows: list


def tasks_path(plan):
    return os.path.join(os.path.dirname(plan), "tasks.json")


def canonical_sum(rows):
    text = json.dumps(rows, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _refuse_symlink(path):
    if os.path.islink(path):
        raise StateError(2, f"TASKS: UNMEASURED — {os.path.basename(path)} is a symlink; refusing")


def _read_json(path):
    _refuse_symlink(path)
    if not os.path.lexists(path):
        raise StateError(2, "TASKS: UNMEASURED — no tasks.json (run tasks_state.py init)")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        raise StateError(2, "TASKS: UNMEASURED — tasks.json is unreadable JSON")
    if not isinstance(data, dict) or type(data.get("schema")) is not int or data["schema"] != SCHEMA:
        raise StateError(2, "TASKS: UNMEASURED — tasks.json has an unknown schema")
    return data


def _row_problem(i, row):
    """Return why a stored row is not a state the tools write, or None."""
    if not isinstance(row, dict):
        return f"row {i} is not an object"
    if set(row) != ROW_KEYS:
        return f"row {i} does not have exactly the keys id, status, evidence, head, updated"
    rid = row["id"]
    if not isinstance(rid, str) or not ID_RE.fullmatch(rid):
        return f"row {i} has an invalid ID {str(rid)[:40]!r}"
    if row["status"] not in STATUSES:
        return f"row {rid!r} has status {str(row['status'])[:20]!r}; not one of {', '.join(STATUSES)}"
    for key in ("evidence", "head", "updated"):
        if not isinstance(row[key], str):
            return f"row {rid!r} field {key} is not a string"
    return None


def load(plan):
    """Strict read for status and init: any row the tools would not write is an unmeasurable file."""
    data = _read_json(tasks_path(plan))
    rows = data.get("rows")
    if not isinstance(rows, list):
        raise StateError(2, "TASKS: UNMEASURED — tasks.json has no rows list")
    for i, row in enumerate(rows, 1):
        problem = _row_problem(i, row)
        if problem:
            raise StateError(2, f"TASKS: UNMEASURED — {problem}")
    ids = [r["id"] for r in rows]
    if len(set(ids)) != len(ids):
        raise StateError(2, "TASKS: UNMEASURED — tasks.json has a duplicate row ID")
    if not isinstance(data.get("plan"), str) or not isinstance(data.get("slug"), str):
        raise StateError(2, "TASKS: UNMEASURED — tasks.json has no plan or slug")
    return TaskFile(SCHEMA, data["plan"], data["slug"], rows)


def _plan_rows(plan):
    try:
        return parse(plan)
    except TableError as e:
        raise StateError(2, f"TASKS: UNMEASURED — {e}")


def _check_plan_ids(plan_rows):
    for r in plan_rows:
        if not ID_RE.fullmatch(r["id"]):
            raise StateError(1, f"TASKS: FAIL — Tasks ID {r['id']!r} is not a valid ID (letters, digits, . _ -; 1–16 chars)")


def _lock_timeout():
    raw = os.environ.get("DEVKIT_TASKS_LOCK_TIMEOUT", str(LOCK_TIMEOUT_DEFAULT))
    try:
        value = float(raw)
    except ValueError:
        raise StateError(2, "TASKS: UNMEASURED — DEVKIT_TASKS_LOCK_TIMEOUT is not a number")
    if not value >= 0:
        raise StateError(2, "TASKS: UNMEASURED — DEVKIT_TASKS_LOCK_TIMEOUT must be zero or more")
    return value


def _lock(plan):
    """Exclusive flock on <plan dir>/tasks.json.lock; returns the fd. The caller closes it."""
    lock = tasks_path(plan) + ".lock"
    _refuse_symlink(lock)
    timeout = _lock_timeout()
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o644)
    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BlockingIOError:
            if time.monotonic() >= deadline:
                os.close(fd)
                raise StateError(2, "TASKS: locked")
            time.sleep(0.05)


def _atomic_write(path, text):
    """Temp file in the same directory, then os.replace — a reader sees the old or the new file, never half."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=os.path.basename(path) + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _write_state(tf, path):
    doc = {"schema": tf.schema, "plan": tf.plan, "slug": tf.slug, "rows": tf.rows}
    _atomic_write(path, json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    _atomic_write(path + ".sum", canonical_sum(tf.rows) + "\n")


def _sum_matches(path, rows):
    """True when <path>.sum holds the canonical hash of rows; a missing or unreadable sum is a mismatch."""
    try:
        with open(path + ".sum", encoding="utf-8") as f:
            recorded = f.read().strip()
    except OSError:
        recorded = ""
    return recorded == canonical_sum(rows)


def _git(cwd, *args):
    """stdout of a git command run in cwd, or "" when git is absent or the command fails."""
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


def _repo_root(cwd):
    return _git(cwd, "rev-parse", "--show-toplevel")


def _head(cwd):
    return _git(cwd, "rev-parse", "--short", "HEAD")


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _ids(xs):
    return ", ".join(xs) or "—"


def status_line(tf, plan_rows):
    deps = {r["id"]: r["deps"] for r in plan_rows}
    state = {r["id"]: r["status"] for r in tf.rows}
    done = sum(1 for r in tf.rows if r["status"] == "done")
    in_progress = [r["id"] for r in tf.rows if r["status"] == "in_progress"]
    failed = [r["id"] for r in tf.rows if r["status"] == "failed"]
    nxt = next((r["id"] for r in tf.rows
                if r["status"] == "todo" and all(state.get(d) == "done" for d in deps.get(r["id"], []))), None)
    return (f"[{tf.slug}] {done}/{len(tf.rows)} done · in_progress: {_ids(in_progress)} · "
            f"failed: {_ids(failed)} · next: {nxt or '—'}")


def init(plan):
    """Create tasks.json, or extend an existing one with plan rows it does not hold. Nothing is written on refusal."""
    plan_rows = _plan_rows(plan)
    _check_plan_ids(plan_rows)
    path = tasks_path(plan)
    for p in (path, path + ".sum"):
        _refuse_symlink(p)
    plan_ids = [r["id"] for r in plan_rows]
    slug = os.path.basename(os.path.dirname(os.path.abspath(plan)))
    root = _repo_root(os.path.dirname(os.path.abspath(plan)))
    plan_field = os.path.relpath(os.path.abspath(plan), root) if root else plan
    fd = _lock(plan)
    try:
        if os.path.lexists(path):
            stored = load(plan)
            if not _sum_matches(path, stored.rows):
                raise StateError(1, "TASKS: FAIL — tasks.json changed outside tasks_state.py; run tasks_state.py verify")
            stored_ids = [r["id"] for r in stored.rows]
            for sid in stored_ids:
                if sid not in plan_ids:
                    raise StateError(1, f"TASKS: FAIL — stored row {sid!r} is no longer in the plan; nothing written")
            if stored_ids != plan_ids[:len(stored_ids)]:
                raise StateError(1, "TASKS: FAIL — stored row order differs from the plan; nothing written")
            new_rows = [{"id": r["id"], "status": "todo", "evidence": "", "head": "", "updated": ""}
                        for r in plan_rows if r["id"] not in stored_ids]
            merged_ids = stored_ids + [r["id"] for r in new_rows]
            if merged_ids != plan_ids[:len(merged_ids)]:
                raise StateError(1, "TASKS: FAIL — a new plan row sits before a stored row; order cannot change; nothing written")
            tf = TaskFile(SCHEMA, plan_field, slug, stored.rows + new_rows)
        else:
            rows = [{"id": i, "status": "todo", "evidence": "", "head": "", "updated": ""} for i in plan_ids]
            tf = TaskFile(SCHEMA, plan_field, slug, rows)
        _write_state(tf, path)
    finally:
        os.close(fd)
    return tf


def _check_deps(row_id, plan_rows, rows):
    """Every row the plan lists in `Depends on` for row_id must be stored as done."""
    plan_deps = {r["id"]: r["deps"] for r in plan_rows}
    if row_id not in plan_deps:
        raise StateError(1, f"TASKS: FAIL — {row_id} is no longer in the plan")
    state = {r["id"]: r["status"] for r in rows}
    for dep in plan_deps[row_id]:
        if state.get(dep) != "done":
            raise StateError(1, f"TASKS: FAIL — {row_id} depends on {dep} ({state.get(dep, 'missing')})")


def set_status(plan, row_id, status_to, evidence):
    """Apply one allowed transition under the lock; rewrite tasks.json, then tasks.json.sum. Returns the TaskFile."""
    if status_to not in STATUSES:
        raise StateError(2, f"TASKS: UNMEASURED — unknown status {status_to[:20]!r}; use {', '.join(STATUSES)}")
    if len(evidence) > EVIDENCE_MAX:
        raise StateError(2, f"TASKS: UNMEASURED — evidence is {len(evidence)} chars; the limit is {EVIDENCE_MAX}")
    text = CONTROL_RE.sub("", evidence)
    plan_rows = _plan_rows(plan)
    path = tasks_path(plan)
    for p in (path, path + ".sum"):
        _refuse_symlink(p)
    fd = _lock(plan)
    try:
        tf = load(plan)
        if not _sum_matches(path, tf.rows):
            raise StateError(1, "TASKS: FAIL — tasks.json changed outside tasks_state.py; run tasks_state.py verify")
        row = next((r for r in tf.rows if r["id"] == row_id), None)
        if row is None:
            raise StateError(2, f"TASKS: UNMEASURED — unknown task {row_id!r}; not in tasks.json (run tasks_state.py init)")
        current = row["status"]
        rule = TRANSITIONS.get((current, status_to))
        if rule is None:
            raise StateError(1, f"TASKS: FAIL — illegal transition {current} → {status_to}")
        if rule == "deps":
            _check_deps(row_id, plan_rows, tf.rows)
        elif rule == "pass" and not text.startswith("M: PASS"):
            raise StateError(1, 'TASKS: FAIL — done needs evidence starting "M: PASS"')
        elif rule == "evidence" and not text.strip():
            raise StateError(1, f"TASKS: FAIL — {current} → {status_to} needs non-empty --evidence")
        row.update(status=status_to, evidence=text,
                   head=_head(os.path.dirname(os.path.abspath(plan))), updated=_now())
        _write_state(tf, path)
    finally:
        os.close(fd)
    return tf


def status(plan):
    tf = load(plan)
    return status_line(tf, _plan_rows(plan))


def verify(plan):
    """Return (exit code, message). 0 PASS · 1 FAIL (a rule broken) · 2 UNMEASURED (no reading possible)."""
    try:
        plan_rows = _plan_rows(plan)
        data = _read_json(tasks_path(plan))
        rows = data.get("rows")
        if not isinstance(rows, list):
            return 1, "TASKS: FAIL — tasks.json has no rows list"
        for i, row in enumerate(rows, 1):
            problem = _row_problem(i, row)
            if problem:
                return 1, f"TASKS: FAIL — {problem}"
        stored_ids = [r["id"] for r in rows]
        plan_ids = [r["id"] for r in plan_rows]
        if stored_ids != plan_ids[:len(stored_ids)]:
            gone = [s for s in stored_ids if s not in plan_ids]
            if gone:
                return 1, f"TASKS: FAIL — stored row {gone[0]!r} is no longer in the plan"
            return 1, "TASKS: FAIL — stored row order differs from the plan"
        _refuse_symlink(tasks_path(plan) + ".sum")
        if not _sum_matches(tasks_path(plan), rows):
            return 1, "TASKS: FAIL — tasks.json changed outside tasks_state.py"
        return 0, "TASKS: PASS"
    except StateError as e:
        return e.rc, e.msg


def _cmd_set(argv):
    pos, evidence, i = [], "", 0
    while i < len(argv):
        if argv[i] == "--evidence" and i + 1 < len(argv):
            evidence, i = argv[i + 1], i + 2
        else:
            pos.append(argv[i])
            i += 1
    if len(pos) != 3:
        print("usage: tasks_state.py set <plan.md> <ID> <status> [--evidence TEXT]", file=sys.stderr)
        return 2
    plan, row_id, status_to = pos
    print(status_line(set_status(plan, row_id, status_to, evidence), _plan_rows(plan)))
    return 0


def main(argv):
    try:
        if argv[:1] == ["set"]:
            return _cmd_set(argv[1:])
        if len(argv) != 2 or argv[0] not in ("init", "status", "verify"):
            print(USAGE, file=sys.stderr)
            return 2
        cmd, plan = argv
        if cmd == "verify":
            rc, msg = verify(plan)
            print(msg)
            return rc
        if cmd == "init":
            print(status_line(init(plan), _plan_rows(plan)))
        else:
            print(status(plan))
        return 0
    except StateError as e:
        print(e.msg)
        return e.rc
    except OSError as e:
        print(f"TASKS: UNMEASURED — {e.strerror or e.__class__.__name__}")
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
