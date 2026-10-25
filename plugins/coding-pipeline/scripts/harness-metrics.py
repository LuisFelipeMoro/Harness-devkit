#!/usr/bin/env python3
"""Count the five Harness health signals of references/harness-metrics.md where they can be counted.

The reference defines five signals — scope creep, question timing, rework, sensor escape,
test honesty — read quarterly by a human from PROGRESS.md, the plans and git history. This
script does the counting half of that reading, from artifacts the devkit already produces:
docs/plans/*/plan.md, docs/plans/*/evidence.md, PROGRESS.md and git history. A signal whose
source is not persisted (a review report that was printed, never written) is printed as
`n/a — needs judgement: <why>`, never as a guessed number.

These are DIAGNOSTICS, NEVER GATES. Every one is trivially gamed by suppressing its own
signal, so nothing may block on this script's output, and its exit status says only whether
it could read the repository.

Usage: harness-metrics.py [--base REF] [--since WHEN]
  --base REF    feature-branch base for the per-branch rework count
                (default: merge-base of HEAD with main, else master)
  --since WHEN  git --since window for history-wide counts (default: 90.days — one quarter)
Exit 0 — table printed. Exit 2 — not a git repository, an unknown --base, or bad usage.
"""
import glob
import os
import re
import subprocess
import sys

AC_LINE = re.compile(r"^[+-]\s*-\s*(AC|SEC|NFR)-?\d")   # an added/removed AC bullet
FIX_SUBJECT = re.compile(r"^fix(\(.+\))?!?:")            # conventional-commit fix
GAP_LINE = re.compile(r"Gap found:\s*(.*)", re.IGNORECASE)
NONE_WORDS = {"", "none", '"none"', "n/a", "-", "—"}
ESCAPE_WORDS = re.compile(r"pre-push|\bCI\b")


def fail(msg):
    print(f"METRICS: UNMEASURED — {msg}")
    sys.exit(2)


def git(*args, check=True):
    r = subprocess.run(["git", *args], capture_output=True, text=True, errors="replace")
    if check and r.returncode != 0:
        fail(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def lines(text):
    return [x for x in text.splitlines() if x.strip()]


def default_base():
    for main in ("main", "master"):
        r = subprocess.run(["git", "merge-base", "HEAD", main], capture_output=True, text=True)
        if r.returncode == 0:
            return r.stdout.strip()
    return None


def rework(base, since):
    """references/harness-metrics.md — Rework: files touched by 2+ commits on one feature
    branch; plus the history-wide forms of the same signal, reverts and fix commits that
    touch a merged feature's files after the merge."""
    parts = []
    if base is None or git("rev-parse", base).strip() == git("rev-parse", "HEAD").strip():
        parts.append("branch: n/a — no commits past the base (on the mainline? pass --base)")
    else:
        counts = {}
        for f in lines(git("log", "--no-merges", "--format=", "--name-only", f"{base}..HEAD")):
            counts[f] = counts.get(f, 0) + 1
        hot = sorted((f for f, n in counts.items() if n >= 2), key=lambda f: -counts[f])
        top = ", ".join(f"{f} ×{counts[f]}" for f in hot[:3])
        parts.append(f"{len(hot)} file(s) touched by 2+ commits since {base[:7]}" + (f" ({top})" if top else ""))
    reverts = [s for s in lines(git("log", f"--since={since}", "--format=%s")) if s.startswith('Revert "')]
    merges = lines(git("log", f"--since={since}", "--merges", "--format=%H"))
    if not merges:
        parts.append("fix-after-merge: n/a — needs judgement: no merge commits in the window (squash merges leave none)")
    else:
        fixes = set()
        for m in merges:
            merged = set(lines(git("diff", "--name-only", f"{m}^1", m)))
            # One log pass per merge range: each commit is a \x01-led header (sha \x00 subject)
            # followed by the files it touched — not one `git show` per commit.
            for chunk in git("log", "--no-merges", "--name-only", "--format=%x01%H%x00%s", f"{m}..HEAD").split("\x01")[1:]:
                header, _, body = chunk.partition("\n")
                sha, _, subject = header.partition("\x00")
                if FIX_SUBJECT.match(subject) and merged & set(lines(body)):
                    fixes.add(sha)
        parts.append(f"{len(fixes)} fix commit(s) after a feature merge")
    parts.append(f"{len(reverts)} revert(s)")
    return " · ".join(parts)


def question_timing(plans, since):
    """references/harness-metrics.md — Question timing: edits to the plan's ACs after the
    first Coder dispatch. The dispatch itself leaves no trace in git, so its proxy is the
    first commit after the plan was added that touches a file outside docs/plans/. A
    `Gap found` the coder reported is the same signal seen from the code side."""
    if not plans:
        return "n/a — needs judgement: no docs/plans/*/plan.md"
    edits = 0
    for plan in plans:
        added = lines(git("log", "--diff-filter=A", "--format=%H", "--", plan))
        if not added:
            continue  # plan never committed: nothing to time
        first_code = lines(git("log", "--reverse", "--topo-order", "--no-merges", "--format=%H",
                               f"{added[-1]}..HEAD", "--", ".", ":(exclude)docs/plans"))
        if not first_code:
            continue
        for sha in lines(git("log", "--no-merges", f"--since={since}", "--format=%H",
                             f"{first_code[0]}..HEAD", "--", plan)):
            diff = git("show", "-U0", "--format=", sha, "--", plan)
            if any(AC_LINE.match(x) for x in diff.splitlines()):
                edits += 1
    gaps = 0
    for path in sorted(glob.glob("docs/plans/*/evidence.md")) + plans:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for x in fh:
                m = GAP_LINE.search(x)
                if m and m.group(1).strip().strip("`*").strip().lower() not in NONE_WORDS:
                    gaps += 1
    return f"{edits} AC edit(s) after code started ({len(plans)} plan(s)) · {gaps} Gap found line(s)"


def sensor_escape():
    """references/harness-metrics.md — Sensor escape: gate failures first caught at pre-push
    or CI. Countable only where they were recorded: PROGRESS.md's Failed section."""
    if not os.path.isfile("PROGRESS.md"):
        return "n/a — needs judgement: no PROGRESS.md; CI failure history lives in the CI provider"
    failed, section = [], None
    with open("PROGRESS.md", encoding="utf-8", errors="replace") as fh:
        for x in fh:
            if x.startswith("## "):
                section = x[3:].strip().lower()
            elif section == "failed" and x.lstrip().startswith("- "):
                failed.append(x)
    escaped = sum(1 for x in failed if ESCAPE_WORDS.search(x))
    return f"{escaped} of {len(failed)} Failed entries in PROGRESS.md were caught at pre-push or CI"


def test_honesty(plans):
    """references/harness-metrics.md — Test honesty: QA MAJORs for tautological or
    unfalsified tests. qa's reports are printed, not persisted; the unfalsified half is
    countable by running the falsification sensor over each plan's evidence.md."""
    sensor = os.path.join(os.path.dirname(os.path.abspath(__file__)), "verify", "falsification.sh")
    rows = missing = no_evidence = 0
    for plan in plans:
        evidence = os.path.join(os.path.dirname(plan), "evidence.md")
        if not os.path.isfile(evidence):
            no_evidence += 1
            continue
        r = subprocess.run(["bash", sensor, evidence, plan], capture_output=True, text=True)
        if r.returncode == 2:
            return f"n/a — needs judgement: falsification.sh could not run ({r.stderr.strip()})"
        m = re.search(r"(\d+)/(\d+) tests have valid evidence", r.stdout)
        if m:
            rows += int(m.group(2))
            missing += int(m.group(2)) - int(m.group(1))
    if not rows:
        return "n/a — needs judgement: no plan with both a Test Case table and evidence.md"
    note = f"; {no_evidence} plan(s) without evidence.md" if no_evidence else ""
    return (f"{missing} of {rows} Test Case rows lack valid falsification evidence{note} · "
            "tautology MAJORs: n/a — needs judgement: qa reports are not persisted")


def main(argv):
    base, since = None, "90.days"
    it = iter(argv)
    for a in it:
        val = next(it, None) if a in ("--base", "--since") else None
        if a == "--base" and val:
            base = val
        elif a == "--since" and val:
            since = val
        else:
            print("usage: harness-metrics.py [--base REF] [--since WHEN]", file=sys.stderr)
            return 2
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if r.returncode != 0:
        fail("not a git repository")
    os.chdir(r.stdout.strip())
    if base is not None:
        if subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}"],
                          capture_output=True).returncode != 0:
            fail(f"unknown base '{base}'")
    else:
        base = default_base()
    plans = sorted(glob.glob("docs/plans/*/plan.md"))

    rows = [
        ("Scope creep", "n/a — needs judgement: CD1+CD2+CD3 findings live in the reviewer's report, "
                        "which /review-code prints or posts but never writes to the repo", "falling toward zero"),
        ("Question timing", question_timing(plans, since), "rare — questions land before code"),
        ("Rework", rework(base, since), "flat; a rise means the spec was too loose"),
        ("Sensor escape", sensor_escape(), "falling — a failure caught late cost a full loop"),
        ("Test honesty", test_honesty(plans), "zero, with coverage steady"),
    ]
    print(f"# Harness health signals — window {since} (references/harness-metrics.md)")
    print()
    print("| Signal | Reading | Healthy |")
    print("|---|---|---|")
    for name, reading, healthy in rows:
        print(f"| {name} | {reading} | {healthy} |")
    print()
    print("These are diagnostics, never gates: read by a human, never optimised or blocked on.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
