#!/usr/bin/env python3
"""Run every fixture x arm x repetition as fresh headless sessions, one per skill stage.

Usage: bench/run.py --arms B-haiku[,B-sonnet] [--reps N] [--fixtures all|a,b] [--out DIR] --yes

Without --yes the runner prints the run count and a cost estimate, then exits 2 before any
directory is created or any stage starts: an eval burns the usage limit (LLM10). Stages go
through plugins/coding-pipeline/scripts/headless.py, so classification, the limit stop and the
per-stage budget cap are the ones the driver uses. Results go to bench/results/ (release-excluded).
Each run record carries the validate verdict; each stage record carries result_tail, the last 500
characters of its result text (diagnosis only; run-state.json never holds result text, SEC-5).

A run passes when every stage ended `ok` and the measured gate result equals the fixture's
expected.json `gates_green`. The gate is scored per stack, offline, with no install:
- Go seed (`go.mod`): `go test ./...`.
- TypeScript seed (`package.json`): `node --experimental-strip-types --test` over every
  `*.test.ts` under the run repo (built-in `node:test`, Node >= 22.6). No test file, or a Node
  older than 22.6 or missing, is UNMEASURED.
- Doc-only seed (no `go.mod`, no `package.json`): green iff every path changed against `main`
  (the seed commit) ends `.md`. Any other changed path is UNMEASURED.
A seed matching none of these, or a gate that cannot run, is UNMEASURED and fails closed
(pass = false, stop_reason says so).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
from functools import partial
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "plugins" / "coding-pipeline" / "scripts"))
import headless  # noqa: E402 — stdlib-only runner library, imported from the repo root

BENCH = ROOT / "bench"
ARMS_FILE = BENCH / "arms.json"
FIXTURES = BENCH / "fixtures"
RESULTS = BENCH / "results"
FALSIFICATION = ROOT / "plugins" / "coding-pipeline" / "scripts" / "verify" / "falsification.sh"
STAGES = ("code", "validate", "review")
STAGE_BUDGET_USD = 3.0  # LLM10: per-stage cap
STAGE_TIMEOUT_S = headless.DEFAULT_TIMEOUT_S
ALLOWED_TOOLS = "Bash,Agent,Glob,Grep,Skill,Read(~/.claude/**)"  # G1
GATE_TIMEOUT_S = 600
NODE_PROBE_TIMEOUT_S = 30
NODE_MIN = (22, 6)  # --experimental-strip-types first shipped in Node 22.6
FALSIFICATION_TIMEOUT_S = 300
EXPECTED_TYPES = {"gates_green": bool, "plan_gap": bool, "depth": str}
GIT = ["git", "-c", "user.email=bench@localhost", "-c", "user.name=bench", "-c", "commit.gpgsign=false"]
NI = (
    "\n\nNon-interactive benchmark run: AskUserQuestion is unavailable, so the answers are given "
    "in the Answers line. If any other decision needs the user, do not guess: print one line "
    "`NEEDS_USER: <question>` as your last line and stop."
)
VERDICT_RE = re.compile(
    r"^VERDICT_LINE: (.+?) ([0-9]+(?:\.[0-9]+)?)(?:/10)?$"
)
RESULT_TAIL_CHARS = 500  # per stage, in the bench summary only (SEC-5: never in run-state)
Runner = Callable[[list[str], str], tuple[int, str, str]]


class BenchError(Exception):
    """A refusal before any stage runs; the message names what to fix."""


def stage_prompt(stage: str, slug: str, branch: str) -> str:
    plan = f"docs/plans/{slug}/plan.md"
    if stage == "code":
        return (
            f"/code {plan}" + NI
            + " Answers: plan_not_approved=proceed; uncommitted=continue; run_mode=single; "
            "fix_rounds_exhausted=stop. Do not commit, push or open a PR. Write your CODER DONE "
            f"block verbatim to docs/plans/{slug}/evidence.md."
        )
    if stage == "validate":
        return (
            f"/validate-code {plan}" + NI
            + " Answers: validate_low_score=stop. Report only. End with one line "
            "`VERDICT_LINE: <verdict> <score>`."
        )
    return (
        f"/review-code {branch} --spec {plan}" + NI
        + " Answers: review_post=no; review_language=English; review_style=short; "
        "review_low_score=stop. There is no PR: do not post; keep the review in $TMPDIR. "
        "End with one line `REVIEW_SCORE: <score> <pass|block>`."
    )


def _verdict_match(sentinel: str | None) -> re.Match[str] | None:
    return VERDICT_RE.match(sentinel or "")


def verdict_name(sentinel: str | None) -> str | None:
    match = _verdict_match(sentinel)
    return match.group(1) if match else None


def verdict_score(sentinel: str | None) -> float | None:
    match = _verdict_match(sentinel)
    return float(match.group(2)) if match else None


def load_arms(names: list[str]) -> tuple[str, dict[str, dict[str, Any]]]:
    data = json.loads(ARMS_FILE.read_text(encoding="utf-8"))
    table = data.get("arms", {})
    arms: dict[str, dict[str, Any]] = {}
    for name in names:
        if name not in table:
            raise BenchError(f"unknown arm '{name}' (bench/arms.json holds {', '.join(sorted(table))})")
        arm = table[name]
        if arm.get("topology") != "fresh":
            raise BenchError(f"arm '{name}': topology must be 'fresh' (resume is not wired into run_stage)")
        models = arm.get("models")
        if not isinstance(models, dict) or set(models) != set(STAGES) or not all(
            isinstance(m, str) and m for m in models.values()
        ):
            raise BenchError(f"arm '{name}': models must name one model for each of {', '.join(STAGES)}")
        est = arm.get("est_usd_per_run")
        if isinstance(est, bool) or not isinstance(est, (int, float)) or est < 0:
            raise BenchError(f"arm '{name}': est_usd_per_run must be a non-negative number")
        arms[name] = arm
    return str(data.get("basis", "")), arms


def validate_fixture(path: Path) -> dict[str, Any]:
    if not (path / "seed").is_dir():
        raise BenchError(f"fixture '{path.name}' has no seed/ directory")
    plan = path / "plan.md"
    if not plan.is_file() or not re.search(r"^Status: approved\b", plan.read_text(encoding="utf-8"), re.M):
        raise BenchError(f"fixture '{path.name}': plan.md must carry 'Status: approved'")
    expected_file = path / "expected.json"
    if not expected_file.is_file():
        raise BenchError(f"fixture '{path.name}' has no expected.json")
    expected = json.loads(expected_file.read_text(encoding="utf-8"))
    if not isinstance(expected, dict) or set(expected) != set(EXPECTED_TYPES):
        raise BenchError(f"fixture '{path.name}': expected.json must hold exactly {sorted(EXPECTED_TYPES)}")
    for key, kind in EXPECTED_TYPES.items():
        if not isinstance(expected[key], kind) or (kind is not bool and isinstance(expected[key], bool)):
            raise BenchError(f"fixture '{path.name}': expected.json '{key}' must be {kind.__name__}")
    return expected


def load_fixtures(selection: str) -> list[tuple[str, Path, dict[str, Any]]]:
    found = sorted(p for p in FIXTURES.iterdir() if p.is_dir()) if FIXTURES.is_dir() else []
    if selection != "all":
        wanted = [n for n in selection.split(",") if n]
        names = {p.name for p in found}
        missing = [n for n in wanted if n not in names]
        if missing:
            raise BenchError(f"no fixture named {', '.join(missing)} under bench/fixtures/")
        found = [p for p in found if p.name in wanted]
    if not found:
        raise BenchError("no fixtures found under bench/fixtures/")
    return [(p.name, p, validate_fixture(p)) for p in found]


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        GIT + list(args), cwd=repo, capture_output=True, text=True, stdin=subprocess.DEVNULL, check=False
    )


def init_repo(repo: Path, branch: str) -> None:
    for args in (["init", "-q", "-b", "main"], ["add", "-A"], ["commit", "-q", "-m", "bench: fixture seed"],
                 ["checkout", "-q", "-b", branch]):
        if git(repo, *args).returncode != 0:
            raise RuntimeError(f"bench: git {args[0]} failed in {repo}")


def commit_code_stage(repo: Path) -> bool:
    """Commit the code stage's output on the feature branch. False when it changed nothing."""
    git(repo, "add", "-A")
    if not git(repo, "status", "--porcelain").stdout.strip():
        return False
    if git(repo, "commit", "-q", "-m", "bench: code stage output").returncode != 0:
        raise RuntimeError(f"bench: committing the code stage failed in {repo}")
    return True


def go_green(repo: Path) -> bool | None:
    """True/False from `go test ./...`; None when the toolchain is missing or the run times out."""
    try:
        proc = subprocess.run(
            ["go", "test", "./..."], cwd=repo, capture_output=True, text=True,
            stdin=subprocess.DEVNULL, timeout=GATE_TIMEOUT_S, check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    return proc.returncode == 0


def node_supports_strip_types() -> bool:
    """True when `node` exists and is at least NODE_MIN (type stripping shipped in 22.6)."""
    try:
        proc = subprocess.run(
            ["node", "--version"], capture_output=True, text=True,
            stdin=subprocess.DEVNULL, timeout=NODE_PROBE_TIMEOUT_S, check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False
    match = re.match(r"v(\d+)\.(\d+)", proc.stdout)
    return proc.returncode == 0 and match is not None and (int(match.group(1)), int(match.group(2))) >= NODE_MIN


def ts_green(repo: Path) -> bool | None:
    """True/False from node's built-in test runner over the repo's *.test.ts files."""
    if not node_supports_strip_types():
        return None
    tests = sorted(
        p.relative_to(repo).as_posix() for p in repo.rglob("*.test.ts")
        if not {"node_modules", ".git"} & set(p.relative_to(repo).parts)
    )
    if not tests:
        return None
    try:
        proc = subprocess.run(
            ["node", "--experimental-strip-types", "--test", *(f"./{t}" for t in tests)],
            cwd=repo, capture_output=True, text=True,
            stdin=subprocess.DEVNULL, timeout=GATE_TIMEOUT_S, check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    return proc.returncode == 0


def changed_paths(repo: Path) -> list[str] | None:
    """Every path that differs from `main` (the seed commit), committed or not. None if git fails."""
    tracked = git(repo, "diff", "--name-only", "--no-renames", "-z", "main")
    untracked = git(repo, "ls-files", "--others", "--exclude-standard", "-z")
    if tracked.returncode != 0 or untracked.returncode != 0:
        return None
    return [p for p in (tracked.stdout + untracked.stdout).split("\0") if p]


def doc_only_green(repo: Path) -> bool | None:
    """True when every changed path is Markdown; None when any other path changed or git fails."""
    changed = changed_paths(repo)
    if changed is None or not all(p.endswith(".md") for p in changed):
        return None
    return True


def gate_green(repo: Path) -> bool | None:
    """Score the seed's gate by stack: Go, then TypeScript, then doc-only. None means UNMEASURED."""
    if (repo / "go.mod").is_file():
        return go_green(repo)
    if (repo / "package.json").is_file():
        return ts_green(repo)
    return doc_only_green(repo)


def falsification_exit(repo: Path, slug: str) -> int | None:
    evidence = repo / "docs" / "plans" / slug / "evidence.md"
    if not evidence.is_file():
        return None
    proc = subprocess.run(
        ["bash", str(FALSIFICATION), str(evidence), str(repo / "docs" / "plans" / slug / "plan.md")],
        cwd=repo, capture_output=True, text=True, stdin=subprocess.DEVNULL,
        timeout=FALSIFICATION_TIMEOUT_S, check=False,
    )
    return proc.returncode


def _recording(inner: Runner, seen: list[str]) -> Runner:
    """Pass the runner through, keeping each stdout so the result tail can be read after the stage."""
    def run(argv: list[str], cwd: str) -> tuple[int, str, str]:
        code, stdout, stderr = inner(argv, cwd)
        seen.append(stdout)
        return code, stdout, stderr
    return run


def run_one(
    name: str, fixture: Path, expected: dict[str, Any], arm_name: str, arm: dict[str, Any],
    rep: int, out: Path, runner: Runner | None,
) -> dict[str, Any]:
    cell = out / "work" / arm_name / f"{name}-r{rep}"
    repo, tmp = cell / "repo", cell / "tmp"
    shutil.copytree(fixture / "seed", repo)
    tmp.mkdir(parents=True)
    plan_dir = repo / "docs" / "plans" / name
    plan_dir.mkdir(parents=True)
    shutil.copy2(fixture / "plan.md", plan_dir / "plan.md")
    branch = f"feat/{name}"
    init_repo(repo, branch)

    # The default runner is run_stage's own: same timeout, and TMPDIR kept inside the cell's tmp.
    inner: Runner = runner or partial(
        headless._subprocess_runner, timeout_s=STAGE_TIMEOUT_S, env={**os.environ, "TMPDIR": str(tmp)})
    stages: list[headless.StageResult] = []
    tails: list[str] = []
    stop: str | None = None
    for stage in STAGES:
        seen: list[str] = []
        result = headless.run_stage(
            stage, stage_prompt(stage, name, branch), arm["models"][stage], str(repo),
            budget_usd=STAGE_BUDGET_USD, tmp_dir=str(tmp), allowed_tools=ALLOWED_TOOLS,
            timeout_s=STAGE_TIMEOUT_S, runner=_recording(inner, seen),
        )
        stages.append(result)
        tails.append(headless.result_text(seen[-1])[-RESULT_TAIL_CHARS:] if seen else "")
        if result.status != "ok":
            stop = f"{stage} {result.status}"
            break
        if stage == "code" and not commit_code_stage(repo):
            stop = "code stage changed nothing"
            break

    gates = gate_green(repo) if stages and stages[0].status == "ok" else None
    validate = next((s for s in stages if s.stage == "validate" and s.status == "ok"), None)
    passed = stop is None and gates is not None and gates == expected["gates_green"]
    return {
        "fixture": name,
        "rep": rep,
        "pass": passed,
        "gates_green": gates,
        "verdict": verdict_name(validate.sentinel) if validate else None,
        "score": verdict_score(validate.sentinel) if validate else None,
        "falsification_exit": falsification_exit(repo, name),
        "cost_usd": round(sum(s.cost_usd for s in stages), 4),
        "stop_reason": stop or (None if gates is not None else "gates unmeasured"),
        "stages": [
            {"stage": s.stage, "status": s.status, "exit_code": s.exit_code, "subtype": s.subtype,
             "cost_usd": s.cost_usd, "wall_s": s.wall_s, "result_tail": tail}
            for s, tail in zip(stages, tails)
        ],
    }


def spread(values: list[float]) -> dict[str, float | None]:
    if not values:
        return {"median": None, "min": None, "max": None}
    return {"median": round(statistics.median(values), 4), "min": round(min(values), 4),
            "max": round(max(values), 4)}


def summarise(arm_name: str, arm: dict[str, Any], names: list[str], reps: int,
              runs: list[dict[str, Any]]) -> dict[str, Any]:
    flipped = sorted(
        name for name in names
        if len({r["pass"] for r in runs if r["fixture"] == name}) > 1
    )
    return {
        "schema": 1,
        "arm": arm_name,
        "models": arm["models"],
        "reps": reps,
        "fixtures": names,
        "runs": runs,
        "aggregates": {
            "runs": len(runs),
            "pass_rate": round(sum(r["pass"] for r in runs) / len(runs), 4),
            "score": spread([r["score"] for r in runs if r["score"] is not None]),
            "cost_usd": spread([r["cost_usd"] for r in runs]),
            "flipped": flipped,
        },
    }


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="bench/run.py", description=__doc__.split("\n")[0])
    parser.add_argument("--arms", required=True, help="comma-separated arm names from bench/arms.json")
    parser.add_argument("--reps", type=int, default=1, help="repetitions per fixture and arm")
    parser.add_argument("--fixtures", default="all", help="'all' or comma-separated fixture names")
    parser.add_argument("--out", default=None, help="results directory (default bench/results/<UTC stamp>)")
    parser.add_argument("--yes", action="store_true", help="start the runs after the count and cost print")
    return parser.parse_args(argv)


def main(
    argv: list[str] | None = None,
    *,
    runner: Runner | None = None,
    stdout: Any = None,
    stderr: Any = None,
) -> int:
    out_stream = stdout or sys.stdout
    err_stream = stderr or sys.stderr
    try:
        args = parse_args(argv)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else 2

    try:
        arm_names = [a for a in args.arms.split(",") if a]
        if not arm_names:
            raise BenchError("--arms names no arm")
        if args.reps < 1:
            raise BenchError("--reps must be at least 1")
        basis, arms = load_arms(arm_names)
        fixtures = load_fixtures(args.fixtures)
        out_dir = Path(args.out) if args.out else RESULTS / dt.datetime.now(dt.timezone.utc).strftime(
            "%Y%m%dT%H%M%SZ")
        if out_dir.exists():
            raise BenchError(f"results directory {out_dir} already exists")
    except BenchError as exc:
        print(f"bench: refused — {exc}", file=err_stream)
        return 2

    names = [name for name, _, _ in fixtures]
    runs = len(fixtures) * len(arms) * args.reps
    usd = sum(arm["est_usd_per_run"] for arm in arms.values()) * len(fixtures) * args.reps
    print(f"bench: runs={runs} (fixtures {len(fixtures)} x arms {len(arms)} x reps {args.reps})",
          file=out_stream)
    print(f"bench: estimated cost: USD {usd:.2f} — {basis}", file=out_stream)
    if not args.yes:
        print("bench: refused — rerun with --yes to start the runs counted above", file=err_stream)
        return 2

    out_dir.mkdir(parents=True, exist_ok=False)
    for arm_name, arm in arms.items():
        arm_runs = [
            run_one(name, path, expected, arm_name, arm, rep, out_dir, runner)
            for name, path, expected in fixtures
            for rep in range(1, args.reps + 1)
        ]
        summary = summarise(arm_name, arm, names, args.reps, arm_runs)
        target = out_dir / f"{arm_name}.summary.json"
        target.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"bench: {arm_name} pass_rate={summary['aggregates']['pass_rate']:.2f} wrote {target}",
              file=out_stream)
    return 0


if __name__ == "__main__":
    sys.exit(main())
