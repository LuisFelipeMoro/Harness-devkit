#!/usr/bin/env python3
"""Measure what the devkit's guides cost in tokens, per session and per delivery.

The devkit's own first rule is that an addition must earn its tokens. That was a
claim nobody could check, because nothing counted them. This counts them.

Two numbers matter and they multiply:
  - **per-load cost** — the guide bytes a given dispatch drags into a context
  - **dispatch count** — how many times a delivery pays that cost

So the report is per-path (what one dispatch loads) and per-delivery (that cost
times the dispatch graph in skills/*/references/loop.md).

Token counts are estimated at CHARS_PER_TOKEN, not tokenized — no tokenizer ships
with the devkit and adding a dependency to a measuring tool is the wrong trade.
The estimator is only ever compared against itself (before vs after a change), so
a constant bias cancels; treat absolute figures as ±10%.

Usage:
  bench-context.py [--root DIR] [--stories N] [--json] [--baseline FILE]

  --baseline FILE   compare against a previously saved --json run and print the delta
"""
import argparse
import json
import os
import sys

CHARS_PER_TOKEN = 3.6  # markdown with tables/code, cl100k-ish

# --- the dispatch graph -------------------------------------------------------
# Each entry: what one dispatch of that path loads into a fresh context.
# Paths are relative to the plugin root. Sourced from the skills' own loop.md
# files; when a loop changes, this table changes with it or the bench lies.

ALWAYS_ON = {
    "CLAUDE.md (global, every session)": ["CLAUDE.md"],
}

DISPATCH = {
    # planning, once per delivery
    "planning: codebase map (Explore)": ["skills/planning/references/phases.md"],
    "planning: architect": [
        "agents/architect.md",
        "skills/architecture/references/sections.md",
    ],
    "planning: plan-reviewer": ["agents/plan-reviewer.md"],
    # per story, steps A-F
    "story: scrum-master": ["agents/scrum-master.md"],
    "story: coder (core + overlay + language)": [
        "agents/coder.md",
        "agents/coder-backend.md",
        "references/languages/go.md",
        "references/spec-driven-reference.md",
    ],
    "story: qa": ["agents/qa.md", "references/quality-gate-reference.md"],
    "story: reviewer": [
        "agents/reviewer.md",
        "references/change-discipline.md",
        "references/languages/go.md",
    ],
    "story: stress": ["agents/stress.md"],
    "story: verdict": ["agents/verdict.md"],
    "story: pr-review": [
        "../pr-workflow/skills/pr-review/SKILL.md",
        "../pr-workflow/skills/pr-review/references/review-checklist.md",
        "../pr-workflow/skills/pr-review/references/output-format.md",
    ],
    # once per delivery
    "delivery: pr-review (release PR)": [
        "../pr-workflow/skills/pr-review/SKILL.md",
        "../pr-workflow/skills/pr-review/references/review-checklist.md",
    ],
    "delivery: devops": ["agents/devops.md"],
}

# How many times each path is dispatched in one delivery of N stories.
# `None` means "once per story".
PER_DELIVERY = {
    "planning: codebase map (Explore)": 1,
    "planning: architect": 1,
    "planning: plan-reviewer": 1,
    "story: scrum-master": None,
    "story: coder (core + overlay + language)": None,
    "story: qa": None,
    "story: reviewer": None,
    "story: stress": None,
    "story: verdict": None,
    "story: pr-review": None,
    "delivery: pr-review (release PR)": 1,
    "delivery: devops": 1,
}


def tokens(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return int(len(fh.read()) / CHARS_PER_TOKEN)
    except OSError:
        return 0


def measure(root, files):
    total, missing = 0, []
    for rel in files:
        p = os.path.normpath(os.path.join(root, rel))
        t = tokens(p)
        if t == 0:
            missing.append(rel)
        total += t
    return total, missing


def collect(root, stories):
    report = {"stories": stories, "always_on": {}, "paths": {}, "missing": []}

    for label, files in ALWAYS_ON.items():
        t, miss = measure(root, files)
        report["always_on"][label] = t
        report["missing"] += miss

    for label, files in DISPATCH.items():
        t, miss = measure(root, files)
        count = PER_DELIVERY[label]
        n = stories if count is None else count
        report["paths"][label] = {"per_load": t, "dispatches": n, "total": t * n}
        report["missing"] += miss

    report["session_always_on"] = sum(report["always_on"].values())
    report["delivery_dispatches"] = sum(p["dispatches"] for p in report["paths"].values())
    report["delivery_guide_tokens"] = sum(p["total"] for p in report["paths"].values())
    return report


def fmt(n):
    return f"{n:,}"


def render(r, baseline=None):
    out = []
    out.append(f"# devkit context benchmark — {r['stories']}-story delivery")
    out.append("")
    out.append(f"Always-on (per session): {fmt(r['session_always_on'])} tok")
    out.append("")
    out.append("| Dispatch path | per load | × | total |")
    out.append("|---|---:|---:|---:|")
    for label, p in sorted(r["paths"].items(), key=lambda kv: -kv[1]["total"]):
        out.append(f"| {label} | {fmt(p['per_load'])} | {p['dispatches']} | {fmt(p['total'])} |")
    out.append("|  |  |  |  |")
    out.append(
        f"| **delivery total** |  | **{r['delivery_dispatches']}** "
        f"| **{fmt(r['delivery_guide_tokens'])}** |"
    )
    out.append("")

    if baseline:
        d_tok = r["delivery_guide_tokens"] - baseline["delivery_guide_tokens"]
        d_disp = r["delivery_dispatches"] - baseline["delivery_dispatches"]
        d_always = r["session_always_on"] - baseline["session_always_on"]
        pct = 100.0 * d_tok / baseline["delivery_guide_tokens"] if baseline["delivery_guide_tokens"] else 0
        out.append("## vs baseline")
        out.append("")
        out.append("| Metric | baseline | now | delta |")
        out.append("|---|---:|---:|---:|")
        out.append(
            f"| always-on / session | {fmt(baseline['session_always_on'])} "
            f"| {fmt(r['session_always_on'])} | {d_always:+,} |"
        )
        out.append(
            f"| dispatches / delivery | {baseline['delivery_dispatches']} "
            f"| {r['delivery_dispatches']} | {d_disp:+} |"
        )
        out.append(
            f"| guide tokens / delivery | {fmt(baseline['delivery_guide_tokens'])} "
            f"| {fmt(r['delivery_guide_tokens'])} | {d_tok:+,} ({pct:+.1f}%) |"
        )
        out.append("")

    if r["missing"]:
        out.append(f"Unreadable/renamed paths (counted as 0): {sorted(set(r['missing']))}")
    return "\n".join(out)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(here))
    ap.add_argument("--stories", type=int, default=5)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--baseline")
    a = ap.parse_args()

    r = collect(a.root, a.stories)
    if a.json:
        print(json.dumps(r, indent=2))
        return 0

    base = None
    if a.baseline:
        with open(a.baseline, encoding="utf-8") as fh:
            base = json.load(fh)
    print(render(r, base))
    return 0


if __name__ == "__main__":
    sys.exit(main())
