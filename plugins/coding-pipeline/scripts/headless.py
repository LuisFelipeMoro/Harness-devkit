#!/usr/bin/env python3
"""Run one skill stage as a headless `claude -p` session and classify how it ended.

The answers contract (references/headless-runs.md) lets a skill finish without a human, but
three outcomes must be decided mechanically, never by a model reading prose: whether the
session hit the usage limit (retrying into it burns the next window), whether it stopped on a
question (a stalled question must stop the run), and whether it ran out of budget. bench/run.py,
drive.py, estimate-run.py and harness-metrics.py all read and write the same run-state record,
so the argv, the classification and the schema check live here once, not in four readers.

Library module, stdlib only, no CLI. Imported from this directory, and from
~/.claude/devkit/scripts/ in a flat install.

classify() — first match wins (AC7):
  1. a result line opens with "hit your ... limit"      -> limit, whatever the exit code
  2. subtype == "error_max_budget_usd"                  -> budget
  3. a NEEDS_USER: line in the result                   -> needs_user
  4. exit != 0, timeout, or claude not found            -> error
  5. otherwise                                          -> ok

Sentinels are read only from the stage's final result text, and only the last occurrence of a
name counts: a line quoted earlier in the session must not decide the outcome (LLM01).
Run-state records hold counts and identifiers only, never prompt, result or tool text (SEC-5).
Output that does not parse as a JSON object is never ok: nothing was measured, so nothing passes.
"""
from __future__ import annotations

import contextlib
import glob
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, fields
from datetime import datetime, timezone
from functools import partial
from typing import Any, Callable

SCHEMA = 2
SCHEMAS_READ = (1, 2)  # 1 predates StageResult.reason: its stages are read with reason ""
STAGE_NAMES = ("code", "validate", "review")
STAGE_STATUSES = ("ok", "limit", "needs_user", "budget", "error")
RUN_STATUSES = ("running", "done", "stopped", "refused")
DEFAULT_TIMEOUT_S = 3600  # per stage; the driver and bench read this one value (ADR-7)
DEFAULT_BUDGET_USD = 8.0  # per stage: room for three fix rounds (ADR-7, grill G6)
SENTINEL_NAMES = ("VERDICT_LINE", "REVIEW_SCORE", "NEEDS_USER")
# The limit message must open a line: ordinary text that only mentions it is not a usage-limit stop.
LIMIT_RE = re.compile(r"^\W*(?:you've |you have )?hit your [^\n]*limit", re.IGNORECASE | re.MULTILINE)
# Markdown wrapping a sentinel line may carry: code ticks, bold stars, a blockquote mark, whitespace.
WRAP_CHARS = " \t\r\n`*>"

# runner(argv, cwd) -> (exit_code, stdout, stderr). Tests inject a fake; the default one
# is bound to the stage's timeout and environment by run_stage.
Runner = Callable[[list[str], str], tuple[int, str, str]]


@dataclass
class StageResult:
    stage: str  # code | validate | review
    status: str  # ok | limit | needs_user | budget | error
    exit_code: int  # -1 when claude never ran to an exit
    subtype: str  # JSON payload subtype only; "" when the stage did not run to an exit
    reason: str  # why the stage did not run to an exit ("" otherwise)
    model: str  # --model passed
    cost_usd: float
    input_tokens: int
    output_tokens: int
    cache_read: int
    cache_creation: int
    turns: int
    session_id: str  # audit only
    sentinel: str | None  # last VERDICT_LINE / REVIEW_SCORE / NEEDS_USER line
    wall_s: int
    finished_at: str  # ISO-8601 UTC


@dataclass
class RunState:
    plan: str
    slug: str
    branch: str
    base: str
    mode: str
    stages: list[StageResult]
    status: str  # running | done | stopped | refused
    stop_reason: str | None
    schema: int = SCHEMA


def build_argv(
    prompt: str,
    model: str,
    budget_usd: float,
    tmp_dir: str,
    allowed_tools: str,
    resume: str | None,
) -> list[str]:
    """The claude argv for one stage. The prompt sits right after -p, before any variadic flag."""
    flags = [
        "--output-format", "json",
        "--model", model,
        "--max-budget-usd", f"{budget_usd:.2f}",
        "--permission-mode", "acceptEdits",
    ]
    if resume is not None:
        flags += ["--resume", resume]
    flags += ["--add-dir", tmp_dir, "--allowedTools", allowed_tools]
    return ["claude", "-p", prompt] + flags


def _bare(line: str) -> str:
    """The line without the surrounding whitespace, ticks, stars and blockquote marks (AC8c)."""
    return line.strip(WRAP_CHARS)


def last_sentinel(result: str, name: str) -> str | None:
    """The bare text of the last line that starts with `<name>:` once wrapping is stripped, or None."""
    prefix = f"{name}:"
    found: str | None = None
    for line in result.splitlines():
        bare = _bare(line)
        if bare.startswith(prefix):
            found = bare
    return found


def _last_any_sentinel(result: str) -> str | None:
    found: str | None = None
    for line in result.splitlines():
        bare = _bare(line)
        if any(bare.startswith(f"{name}:") for name in SENTINEL_NAMES):
            found = bare
    return found


def classify(exit_code: int, payload: dict[str, Any]) -> str:
    """ok | limit | needs_user | budget | error — the rule order is AC7's, first match wins."""
    result = _result_text(payload)
    if LIMIT_RE.search(result):
        return "limit"
    if payload.get("subtype") == "error_max_budget_usd":
        return "budget"
    if last_sentinel(result, "NEEDS_USER") is not None:
        return "needs_user"
    if exit_code != 0:
        return "error"
    return "ok"


def _go_bin_dir() -> str | None:
    """`$(go env GOPATH)/bin` when `go` is on PATH and that directory exists, else None.

    Installed Go tools (golangci-lint, govulncheck) live there; a headless stage
    whose PATH omits it reports them missing. Only GOPATH is read from go's output.
    """
    if shutil.which("go") is None:
        return None
    try:
        proc = subprocess.run(
            ["go", "env", "GOPATH"], capture_output=True, text=True, timeout=30, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    gopath = proc.stdout.strip().split(os.pathsep)[0] if proc.returncode == 0 else ""
    bindir = os.path.join(gopath, "bin") if gopath else ""
    return bindir if bindir and os.path.isdir(bindir) else None


def _stage_env(tmp_dir: str) -> dict[str, str]:
    """Environment for a default-runner stage: scratch stays in tmp_dir; Go tools stay reachable."""
    env = {**os.environ, "TMPDIR": tmp_dir}
    gobin = _go_bin_dir()
    if gobin is not None:
        env["PATH"] = gobin + os.pathsep + env.get("PATH", "")
    return env


def _subprocess_runner(
    argv: list[str], cwd: str, *, timeout_s: int, env: dict[str, str]
) -> tuple[int, str, str]:
    proc = subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,  # a stage never reads the terminal
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout_s,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


def run_stage(
    stage: str,
    prompt: str,
    model: str,
    cwd: str,
    *,
    budget_usd: float,
    tmp_dir: str,
    allowed_tools: str,
    timeout_s: int = DEFAULT_TIMEOUT_S,
    runner: Runner | None = None,
    on_stdout: Callable[[str], None] | None = None,
) -> StageResult:
    """Run one stage and return its typed record. Timeout and a missing binary are `error`.

    `on_stdout` receives the raw stdout once, when the runner returned; a stage that never
    returned (timeout, missing binary) reports nothing.
    """
    argv = build_argv(prompt, model, budget_usd, tmp_dir, allowed_tools, None)
    if runner is None:
        env = _stage_env(tmp_dir)  # per-stage scratch stays inside tmp_dir
        runner = partial(_subprocess_runner, timeout_s=timeout_s, env=env)
    started = time.monotonic()
    try:
        exit_code, stdout, _stderr = runner(argv, cwd)
        if on_stdout is not None:
            on_stdout(stdout)
    except subprocess.TimeoutExpired:
        return _unrun(stage, model, f"timeout after {timeout_s}s", started)
    except FileNotFoundError:
        return _unrun(stage, model, "claude not found", started)
    except OSError as exc:
        return _unrun(stage, model, f"claude could not start: {type(exc).__name__}", started)

    payload = _parse_payload(stdout)
    body: dict[str, Any] = payload if payload is not None else {"result": stdout}
    status = classify(exit_code, body)
    if payload is None and status == "ok":
        status = "error"  # exit 0 with no parsable result: nothing was measured
    usage = body.get("usage") if isinstance(body.get("usage"), dict) else {}
    return StageResult(
        stage=stage,
        status=status,
        exit_code=exit_code,
        subtype="unparsable output" if payload is None else str(body.get("subtype") or ""),
        reason="",
        model=model,
        cost_usd=_num(body.get("total_cost_usd")),
        input_tokens=int(_num(usage.get("input_tokens"))),
        output_tokens=int(_num(usage.get("output_tokens"))),
        cache_read=int(_num(usage.get("cache_read_input_tokens"))),
        cache_creation=int(_num(usage.get("cache_creation_input_tokens"))),
        turns=int(_num(body.get("num_turns"))),
        session_id=str(body.get("session_id") or ""),
        sentinel=_last_any_sentinel(_result_text(body)),
        wall_s=round(time.monotonic() - started),
        finished_at=_now(),
    )


def write_state(path: str, state: RunState) -> None:
    """Write the record atomically: a temp file in the same directory, then os.replace."""
    tmp = f"{path}.{os.getpid()}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump({**asdict(state), "schema": SCHEMA}, fh, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise


def load_runs(root: str) -> list[RunState]:
    """Every readable docs/plans/*/run-state.json under root. A bad record is skipped, loudly."""
    runs: list[RunState] = []
    pattern = os.path.join(root, "docs", "plans", "*", "run-state.json")
    for path in sorted(glob.glob(pattern)):
        try:
            runs.append(_read_state(path))
        except (OSError, ValueError) as exc:
            print(f"UNMEASURED — {path}: {exc}; record skipped", file=sys.stderr)
    return runs


# field -> (accepted types, label for the error, allowed values or None). A run-state file is
# untrusted input (SEC-4): every field is type-checked before any reader uses it.
FieldSpec = tuple[tuple[type, ...], str, tuple[str, ...] | None]
_RUN_FIELDS: dict[str, FieldSpec] = {
    "plan": ((str,), "str", None),
    "slug": ((str,), "str", None),
    "branch": ((str,), "str", None),
    "base": ((str,), "str", None),
    "mode": ((str,), "str", None),
    "status": ((str,), "str", RUN_STATUSES),
    "stop_reason": ((str, type(None)), "str|None", None),
}
_STAGE_FIELDS: dict[str, FieldSpec] = {
    "stage": ((str,), "str", STAGE_NAMES),
    "status": ((str,), "str", STAGE_STATUSES),
    "exit_code": ((int,), "int", None),
    "subtype": ((str,), "str", None),
    "reason": ((str,), "str", None),
    "model": ((str,), "str", None),
    "cost_usd": ((int, float), "int|float", None),
    "input_tokens": ((int,), "int", None),
    "output_tokens": ((int,), "int", None),
    "cache_read": ((int,), "int", None),
    "cache_creation": ((int,), "int", None),
    "turns": ((int,), "int", None),
    "session_id": ((str,), "str", None),
    "sentinel": ((str, type(None)), "str|None", None),
    "wall_s": ((int,), "int", None),
    "finished_at": ((str,), "str", None),
}


def _read_state(path: str) -> RunState:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError("not a JSON object")
    schema = data.get("schema")
    if type(schema) is not int or schema not in SCHEMAS_READ:
        raise ValueError(f"schema {schema!r} is not one of {SCHEMAS_READ}")
    if set(data) != _names(RunState):
        raise ValueError(f"fields {sorted(set(data) ^ _names(RunState))} differ from the record")
    _check_fields(data, _RUN_FIELDS)
    stages = data["stages"]
    if not isinstance(stages, list):
        raise ValueError(f"stages is {type(stages).__name__}, expected list")
    return RunState(**{**data, "stages": [_stage_from(item, schema) for item in stages]})


def _check_fields(record: dict[str, Any], spec: dict[str, FieldSpec]) -> None:
    """Raise ValueError naming the first field whose type or value no reader may use (SEC-4)."""
    for name, (types, label, allowed) in spec.items():
        value = record[name]
        if isinstance(value, bool) or not isinstance(value, types):  # JSON true is not a count
            raise ValueError(f"{name} is {type(value).__name__}, expected {label}")
        if allowed is not None and value not in allowed:
            raise ValueError(f"{name} is {value!r}, expected one of {', '.join(allowed)}")


def _stage_from(item: Any, schema: int) -> StageResult:
    """One stage record. Schema 1 predates `reason`, so its stages read with reason ""."""
    expected = _names(StageResult) - ({"reason"} if schema == 1 else set())
    if not isinstance(item, dict) or set(item) != expected:
        raise ValueError("a stage record does not match the declared fields")
    record = {"reason": "", **item}
    _check_fields(record, _STAGE_FIELDS)
    return StageResult(**record)


def _names(cls: type) -> set[str]:
    return {f.name for f in fields(cls)}


def _parse_payload(stdout: str) -> dict[str, Any] | None:
    lines = [line for line in stdout.splitlines() if line.strip()]
    if not lines:
        return None
    try:
        payload = json.loads(lines[-1])
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def result_text(stdout: str) -> str:
    """The stage's result text exactly as run_stage reads it: the payload's result, else the raw stdout."""
    payload = _parse_payload(stdout)
    body: dict[str, Any] = payload if payload is not None else {"result": stdout}
    return _result_text(body)


def _result_text(payload: dict[str, Any]) -> str:
    result = payload.get("result")
    return result if isinstance(result, str) else ""


def _num(value: Any) -> float:
    """A number from a claude payload, or 0.0 when it is absent, typed wrong, or not finite.

    json parses `1e999` and `NaN` to inf/nan, and a 400-digit integer has no float at all:
    each maps to 0.0 so a garbled count never aborts run_stage or reaches run-state.json.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0.0
    try:
        return float(value) if math.isfinite(value) else 0.0
    except OverflowError:
        return 0.0


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _unrun(stage: str, model: str, reason: str, started: float) -> StageResult:
    return StageResult(
        stage=stage,
        status="error",
        exit_code=-1,
        subtype="",
        reason=reason,
        model=model,
        cost_usd=0.0,
        input_tokens=0,
        output_tokens=0,
        cache_read=0,
        cache_creation=0,
        turns=0,
        session_id="",
        sentinel=None,
        wall_s=round(time.monotonic() - started),
        finished_at=_now(),
    )
