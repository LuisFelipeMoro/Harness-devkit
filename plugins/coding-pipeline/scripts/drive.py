#!/usr/bin/env python3
"""Drive /code, /validate-code and /review-code for one approved plan, one fresh session each.

The manual flow asks a human to start every skill and to read every verdict. The driver does
the same three steps as separate `claude -p` sessions (ADR-2: validators never inherit the
coder's transcript, so implementer != validator holds), and stops on every rule a human would
stop on. Its state lives in docs/plans/{slug}/run-state.json, written after every stage, so a
stopped run can be resumed from a named stage without redoing committed work.

Refusals happen before any stage is dispatched: plan Status is not `approved`; the slug (the
plan's parent directory name) does not match ^[a-z0-9-]+$; HEAD is detached; the branch is main
or master; `git status` lists a path outside docs/ (tracked or untracked), because those would be
committed as the code stage; --resume-from names no schema-valid run-state.json. A refusal never
reaches the runner, so no `claude` call is made and no state is written.

Stages advance only on green: after code, a non-empty change outside docs/ that commits on the
feature branch (only paths outside docs/ are staged, ADR-5 / G5); after validate, the last
VERDICT_LINE reads `PRODUCTION READY`; after review, the last REVIEW_SCORE ends in `pass`. Any
other outcome stops the run with `stop_reason` recorded. A usage limit stops it and is never
retried (SEC-4). The driver never pushes and never opens a PR; it stops after review.

Usage: drive.py --plan <docs/plans/{slug}/plan.md> [--model sonnet] [--mode sequential]
                [--budget-usd 3] [--resume-from code|validate|review]
Exit 0 — all three stages advanced.
Exit 1 — stopped by a rule (the reason is printed and recorded in run-state.json).
Exit 2 — refused before any stage ran: a precondition failed, or the arguments were malformed.
"""
from __future__ import annotations

import fnmatch
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from functools import partial

from headless import (
    DEFAULT_TIMEOUT_S,
    Runner,
    RunState,
    StageResult,
    _stage_env,  # the default stage environment (TMPDIR, Go tools on PATH): defined once, in headless
    _subprocess_runner,  # the default runner: defined once, in headless
    last_sentinel,
    load_runs,
    result_text,
    run_stage,
    write_state,
)

SLUG_RE = re.compile(r"[a-z0-9-]+")  # fullmatch of this is ^[a-z0-9-]+$ with no trailing newline
MODEL_RE = re.compile(r"[a-z0-9][a-z0-9.-]{0,39}")
MODES = ("inline", "single", "sequential", "parallel")
STAGES = ("code", "validate", "review")
MAINLINES = ("main", "master")
FLAGS = ("--plan", "--model", "--mode", "--budget-usd", "--resume-from")
DEFAULT_MODEL = "sonnet"
DEFAULT_MODE = "sequential"
DEFAULT_BUDGET_USD = 3.0
USAGE = (
    "usage: drive.py --plan <docs/plans/{slug}/plan.md> [--model sonnet] [--mode sequential] "
    "[--budget-usd 3] [--resume-from code|validate|review]"
)
# G1: the only tools a stage is granted. No WebFetch, no WebSearch; destructive-guard.sh stays active.
ALLOWED_TOOLS = "Bash,Agent,Glob,Grep,Skill,Read(~/.claude/**)"
STAGE_COMMAND = {"code": "/code", "validate": "/validate-code", "review": "/review-code"}
# C4 answers keys, in table order. run_mode is the only key the driver varies.
ANSWERS_TEMPLATE = (
    "plan_not_approved=stop; uncommitted=stop; run_mode={mode}; fix_rounds_exhausted=stop; "
    "validate_low_score=stop; review_post=no; review_language=English; review_style=short; "
    "review_low_score=stop"
)
NEEDS_USER_RULE = (
    "A question with no key in Answers: print NEEDS_USER: <question> as the plain last line and stop. Never guess."
)
VERDICT_RE = re.compile(r"VERDICT_LINE: (PRODUCTION READY|READY WITH CONDITIONS|NOT READY) (\d+(?:\.\d+)?)(?:/10)?")
STOP_REASON_MAX = 300  # ≤ 300 chars, per AC11
COMMIT_TAIL_MAX = 240  # hook output kept in a rejected-commit stop reason, tail only
# Basenames the code stage never commits (AC11b, SEC-5): a credential written through Bash bypasses
# secret-write-guard, which sees only Write and Edit, so the commit is the last place to stop it.
DENY_LIST = (".env", ".env.*", ".envrc", "*.pem", "*.key", "id_rsa*", "*.p12")

# git(args, cwd) -> (returncode, stdout, stderr). Tests inject a fake; the default runs real git.
GitFn = Callable[[list[str], str], tuple[int, str, str]]


class Refused(Exception):
    """A precondition failed. Reported as `drive: REFUSED — <reason>`, exit 2, nothing dispatched."""


class UsageError(Exception):
    """The arguments do not parse. Reported with the usage line, exit 2."""


@dataclass(frozen=True)
class Options:
    plan: str  # absolute path to plan.md
    model: str
    mode: str
    budget_usd: float
    resume_from: str | None


@dataclass(frozen=True)
class Context:
    root: str  # git work-tree top level
    branch: str
    base: str  # HEAD commit the run starts from
    slug: str
    plan_dir: str


def parse_args(argv: list[str]) -> Options:
    """Hand-parsed argv, as estimate-run.py does: every value is checked before use."""
    values: dict[str, str] = {}
    it = iter(argv)
    for arg in it:
        if arg not in FLAGS:
            raise UsageError(f"unknown argument {arg!r}")
        value = next(it, None)
        if value is None:
            raise UsageError(f"{arg} needs a value")
        values[arg] = value
    if "--plan" not in values:
        raise UsageError("--plan is required")
    model = values.get("--model", DEFAULT_MODEL)
    if MODEL_RE.fullmatch(model) is None:
        raise UsageError(f"--model {model!r} is not a model alias")
    mode = values.get("--mode", DEFAULT_MODE)
    if mode not in MODES:
        raise UsageError(f"--mode must be one of {', '.join(MODES)}")
    budget = _budget(values.get("--budget-usd"))
    resume = values.get("--resume-from")
    if resume is not None and resume not in STAGES:
        raise UsageError(f"--resume-from must be one of {', '.join(STAGES)}")
    return Options(
        plan=os.path.abspath(values["--plan"]),
        model=model,
        mode=mode,
        budget_usd=budget,
        resume_from=resume,
    )


def _budget(raw: str | None) -> float:
    if raw is None:
        return DEFAULT_BUDGET_USD
    try:
        value = float(raw)
    except ValueError:
        raise UsageError(f"--budget-usd {raw!r} is not a number") from None
    if not math.isfinite(value) or value <= 0:
        raise UsageError("--budget-usd must be a positive number")
    return value


def _git(args: list[str], cwd: str) -> tuple[int, str, str]:
    """Run git in cwd. A git that cannot start is returncode -1, which every caller refuses on."""
    try:
        proc = subprocess.run(
            ["git", *args],
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdin=subprocess.DEVNULL,
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return -1, "", ""
    return proc.returncode, proc.stdout, proc.stderr


def _plan_status(text: str) -> str | None:
    """The first `Status:` value in the plan header, or None when the plan has none."""
    match = re.search(r"^Status:[ \t]*(\S+)", text, re.MULTILINE)
    return match.group(1) if match else None


def _foreign_paths(porcelain_z: str) -> list[str]:
    """Paths `git status --porcelain -z` lists that are not under docs/.

    With -z, a rename or copy entry is followed by its source path as a separate field; both
    sides are checked, so a file moved out of docs/ still counts as a foreign change.
    """
    fields = porcelain_z.split("\0")
    paths: list[str] = []
    i = 0
    while i < len(fields):
        entry = fields[i]
        i += 1
        if len(entry) < 4:
            continue
        code, path = entry[:2], entry[3:]
        paths.append(path)
        if ("R" in code or "C" in code) and i < len(fields):
            paths.append(fields[i])
            i += 1
    return [p for p in paths if not p.startswith("docs/")]


def check_preconditions(opts: Options, git: GitFn) -> Context:
    """Every AC10 refusal, in order. Returns the context when all of them pass."""
    try:
        with open(opts.plan, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        raise Refused(f"cannot read plan {opts.plan}: {type(exc).__name__}") from None

    status = _plan_status(text)
    if status != "approved":
        raise Refused(f"plan Status is {status!r}, not 'approved'")

    plan_dir = os.path.dirname(opts.plan)
    slug = os.path.basename(plan_dir)
    if not SLUG_RE.fullmatch(slug):
        raise Refused(f"plan slug {slug!r} does not match ^[a-z0-9-]+$")

    rc, root, _err = git(["rev-parse", "--show-toplevel"], plan_dir)
    if rc != 0 or not root.strip():
        raise Refused("cannot read git state: the plan is not inside a git work tree")
    root = root.strip()

    rc, branch, _err = git(["rev-parse", "--abbrev-ref", "HEAD"], plan_dir)
    if rc != 0 or not branch.strip():
        raise Refused("cannot read the current branch")
    branch = branch.strip()
    if branch == "HEAD":
        raise Refused("HEAD is detached; check out a feature branch first, the code stage commits on it")
    if branch in MAINLINES:
        raise Refused(f"branch {branch!r} is a mainline; drive runs on a feature branch")

    rc, base, _err = git(["rev-parse", "HEAD"], plan_dir)
    if rc != 0 or not base.strip():
        raise Refused("cannot read the HEAD commit")

    rc, porcelain, _err = git(["status", "--porcelain", "-z", "--untracked-files=all"], root)
    if rc != 0:
        raise Refused("cannot read git status")
    foreign = _foreign_paths(porcelain)
    if foreign:
        shown = ", ".join(foreign[:3]) + (" …" if len(foreign) > 3 else "")
        raise Refused(f"uncommitted paths outside docs/: {shown}")

    return Context(root=root, branch=branch, base=base.strip(), slug=slug, plan_dir=plan_dir)


def load_prior(opts: Options, ctx: Context, git: GitFn) -> RunState | None:
    """The recorded run for this slug, read through headless.load_runs (the one run-state parser).

    A missing or schema-invalid file yields None; load_runs reports an invalid one on stderr.
    A resume past the code stage is refused unless the code stage ran and committed (AC12b):
    validating an empty diff must not reach /pr.
    """
    state_path = os.path.join(ctx.plan_dir, "run-state.json")
    prior = next((run for run in load_runs(ctx.root) if run.slug == ctx.slug), None)
    if opts.resume_from is not None and prior is None:
        if not os.path.exists(state_path):
            raise Refused(f"--resume-from {opts.resume_from}: no run-state.json at {state_path}; nothing to resume from")
        raise Refused(f"--resume-from {opts.resume_from}: run-state.json at {state_path} is not a schema-valid record")
    if opts.resume_from in ("validate", "review") and prior is not None:
        _check_resume_record(opts.resume_from, prior, ctx, git)
    return prior


def _check_resume_record(stage: str, prior: RunState, ctx: Context, git: GitFn) -> None:
    """Refuse a resume whose recorded run shows the code stage did not run and commit, or no validate."""
    recorded = {run.stage for run in prior.stages}
    if "code" not in recorded:
        raise Refused(f"--resume-from {stage}: the recorded run has no code stage record; the code stage never ran")
    rc, head, _err = git(["rev-parse", "HEAD"], ctx.root)
    if rc != 0 or not head.strip():
        raise Refused("cannot read the HEAD commit")
    if head.strip() == prior.base:
        raise Refused(f"--resume-from {stage}: HEAD is still the recorded base; the code stage committed nothing")
    if stage == "review" and "validate" not in recorded:
        raise Refused("--resume-from review: the recorded run has no validate stage record; review would skip validation")


def build_prompt(stage: str, opts: Options, ctx: Context) -> str:
    """The stage's skill command, the Answers line (C4 keys) and the NEEDS_USER rule."""
    if stage == "review":
        command = f"{STAGE_COMMAND[stage]} {ctx.branch} --spec {opts.plan}"
    else:
        command = f"{STAGE_COMMAND[stage]} {opts.plan}"
    answers = ANSWERS_TEMPLATE.format(mode=opts.mode)
    return f"{command}\nAnswers: {answers}\n{NEEDS_USER_RULE}"


def _tail(text: str) -> str:
    """One line, the last COMMIT_TAIL_MAX characters: hook output for a stop reason."""
    return " ".join(text.split())[-COMMIT_TAIL_MAX:]


def _after(sentinel: str, name: str) -> str:
    """The text after `<name>:` in a bare sentinel line."""
    return sentinel[len(name) + 1 :].strip()


def _denied(path: str) -> bool:
    """True when the path's basename matches DENY_LIST."""
    name = os.path.basename(path)
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in DENY_LIST)


def _code_stage(ctx: Context, git: GitFn) -> str | None:
    """Commit the code stage's change outside docs/. None when committed; else the stop reason."""
    rc, porcelain, _err = git(["status", "--porcelain", "-z", "--untracked-files=all"], ctx.root)
    if rc != 0:
        return "cannot read git status after the code stage"
    if not _foreign_paths(porcelain):
        return "code stage changed nothing"
    rc, _out, err = git(["add", "-A", "--", ".", ":(exclude)docs/**"], ctx.root)
    if rc != 0:
        return f"git add failed: {_tail(err)}"
    rc, staged, err = git(["diff", "--cached", "--name-only", "-z"], ctx.root)
    if rc != 0:
        return f"cannot list staged paths: {_tail(err)}"
    for path in filter(None, staged.split("\0")):
        if _denied(path):
            rc, _out, err = git(["reset", "-q"], ctx.root)
            if rc != 0:
                return f"staged file matches deny list: {path}; git reset failed: {_tail(err)}"
            return f"staged file matches deny list: {path}"
    rc, out, err = git(["commit", "-m", f"feat({ctx.slug}): /code stage (drive.py)"], ctx.root)
    if rc != 0:
        return "commit rejected: " + _tail(out + err)
    return None


def _validate_verdict(text: str) -> str | None:
    """None when the last VERDICT_LINE reads PRODUCTION READY; else the stop reason."""
    line = last_sentinel(text, "VERDICT_LINE")
    if line is None:
        return "no VERDICT_LINE"
    match = VERDICT_RE.fullmatch(line)
    if match is None:
        return "unreadable VERDICT_LINE"
    verdict, score = match.group(1), match.group(2)
    if verdict != "PRODUCTION READY":
        return f"validate verdict {verdict} {score}"
    return None


def _review_score(text: str) -> str | None:
    """None when the last REVIEW_SCORE ends in pass; else the stop reason."""
    line = last_sentinel(text, "REVIEW_SCORE")
    if line is None:
        return "no REVIEW_SCORE"
    fields = line.split()
    verdict = fields[-1] if fields else ""
    if verdict == "pass":
        return None
    if verdict == "block":
        return f"review block: {line}"
    return "unreadable REVIEW_SCORE"


def _advance(stage: str, result: StageResult, text: str, ctx: Context, git: GitFn) -> str | None:
    """None when the stage advanced; else the rule that stopped the run."""
    if result.status == "limit":
        return "usage limit: stopped, not retried"
    if result.status == "needs_user":
        question = last_sentinel(text, "NEEDS_USER")
        return f"needs user: {_after(question, 'NEEDS_USER') if question else 'question unreadable'}"
    if result.status == "budget":
        return f"per-stage budget exhausted (--budget-usd): {stage}"
    if result.status == "error":
        return f"stage error: {result.subtype or f'exit {result.exit_code}'}"
    if stage == "code":
        return _code_stage(ctx, git)
    if stage == "validate":
        return _validate_verdict(text)
    return _review_score(text)


def _stop(state: RunState, state_path: str, reason: str) -> int:
    """Record the stop (≤ 300 chars) in run-state.json, print it, and return exit 1."""
    state.status = "stopped"
    state.stop_reason = reason[:STOP_REASON_MAX]
    write_state(state_path, state)
    print(f"drive: STOPPED — {state.stop_reason}", file=sys.stderr)
    return 1


def run_stages(
    opts: Options, ctx: Context, prior: RunState | None, runner: Runner | None, git: GitFn
) -> int:
    """The stage loop: code -> validate -> review, each a fresh session, stopping on any rule.

    --resume-from keeps the recorded results of the stages before the named one and reruns from it.
    run-state.json is written after every stage. Nothing is pushed and no PR is opened.
    """
    start = STAGES.index(opts.resume_from) if opts.resume_from else 0
    kept = [s for s in prior.stages if s.stage in STAGES[:start]] if prior is not None else []
    base = prior.base if (prior is not None and start > 0) else ctx.base
    state = RunState(
        plan=opts.plan,
        slug=ctx.slug,
        branch=ctx.branch,
        base=base,
        mode=opts.mode,
        stages=kept,
        status="running",
        stop_reason=None,
    )
    state_path = os.path.join(ctx.plan_dir, "run-state.json")
    tmp_dir = tempfile.mkdtemp(prefix=f"drive-{ctx.slug}-")
    try:
        inner: Runner = runner or partial(
            _subprocess_runner, timeout_s=DEFAULT_TIMEOUT_S, env=_stage_env(tmp_dir)
        )
        seen: dict[str, str] = {}

        def capture(argv: list[str], cwd: str) -> tuple[int, str, str]:
            code, out, err = inner(argv, cwd)
            seen["out"] = out
            return code, out, err

        for stage in STAGES[start:]:
            seen.clear()
            result = run_stage(
                stage,
                build_prompt(stage, opts, ctx),
                opts.model,
                ctx.root,
                budget_usd=opts.budget_usd,
                tmp_dir=tmp_dir,
                allowed_tools=ALLOWED_TOOLS,
                timeout_s=DEFAULT_TIMEOUT_S,
                runner=capture,
            )
            state.stages.append(result)
            write_state(state_path, state)
            reason = _advance(stage, result, result_text(seen.get("out", "")), ctx, git)
            if reason is not None:
                return _stop(state, state_path, reason)
        state.status = "done"
        state.stop_reason = None
        write_state(state_path, state)
        print("drive: done — code, validate and review advanced; nothing pushed, no PR opened")
        return 0
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def main(argv: list[str], *, git: GitFn | None = None, runner: Runner | None = None) -> int:
    try:
        opts = parse_args(argv)
    except UsageError as exc:
        print(f"drive: {exc}", file=sys.stderr)
        print(USAGE, file=sys.stderr)
        return 2
    git_fn = git or _git
    try:
        ctx = check_preconditions(opts, git_fn)
        prior = load_prior(opts, ctx, git_fn)
    except Refused as exc:
        print(f"drive: REFUSED — {exc}", file=sys.stderr)
        return 2
    return run_stages(opts, ctx, prior, runner, git_fn)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
