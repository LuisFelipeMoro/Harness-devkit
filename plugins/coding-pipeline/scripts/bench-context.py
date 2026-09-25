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

Dispatch counts follow the roster model (references/thresholds.md — Roster):
each story declares a roster (cosmetic/light/standard/full) that fixes which
agents are dispatched — a decision recorded once in the delivery's own
architecture file, not restated here.

Usage:
  bench-context.py [--root DIR] [--stories N] [--json] [--baseline FILE] [--mix MIX]
  bench-context.py --manifest <task-manifest.md|epic-manifest.md> [--json]

  --baseline FILE   compare against a previously saved --json run and print the delta
  --mix MIX         "roster=count,roster=count,..." for the mixed profile
                     (default: cosmetic=1,light=1,standard=2,full=1)
  --manifest PATH   read the manifest's Roster column and print the execution-options
                     checkpoint (as planned / all standard / legacy full loop) instead
                     of the guide-token report
"""
import argparse
import json
import os
import sys

CHARS_PER_TOKEN = 3.6  # markdown with tables/code, cl100k-ish

# --- the roster model (D7) -----------------------------------------------------
# Which agents a story's declared roster dispatches. Cosmetic/light/standard/full
# only ever escalate (classify-diff.sh); this table is the dispatch side of that.

ROSTER = {
    "cosmetic": ["coder"],
    "light": ["coder", "reviewer"],
    "standard": ["coder", "qa", "reviewer"],
    "full": ["coder", "qa", "reviewer", "stress"],
}

DEFAULT_MIX = {"cosmetic": 1, "light": 1, "standard": 2, "full": 1}

# The legacy graph: every row dispatched all seven regardless of roster.
LEGACY_PER_ROW = ["scrum-master", "coder", "qa", "reviewer", "stress", "verdict", "pr-review"]

PLANNING_AGENTS = ["map", "architect", "plan-reviewer"]
DELIVERY_AGENTS = ["pr-review", "devops"]

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
    # per story, roster-driven (see ROSTER)
    "story: coder (core + overlay + language)": [
        "agents/coder.md",
        "agents/coder-backend.md",
        "references/languages/go.md",
        "references/spec-driven-reference.md",
    ],
    "story: qa": ["agents/qa.md", "references/quality-gate-reference.md"],
    "story: reviewer": [
        "agents/reviewer.md",
        "agents/stress.md",
        "references/change-discipline.md",
        "references/languages/go.md",
    ],
    "story: stress": ["agents/stress.md"],
    # once per delivery
    "delivery: pr-review (release PR)": [
        "../pr-workflow/skills/pr-review/SKILL.md",
        "../pr-workflow/skills/pr-review/references/review-checklist.md",
    ],
    "delivery: devops": ["agents/devops.md"],
}

# Maps a ROSTER agent short name to the DISPATCH label it loads. Labels with no
# entry here (planning/delivery) are dispatched once per delivery, not per story.
ROSTER_PATH = {
    "coder": "story: coder (core + overlay + language)",
    "qa": "story: qa",
    "reviewer": "story: reviewer",
    "stress": "story: stress",
}

PLANNING_LABELS = [
    "planning: codebase map (Explore)",
    "planning: architect",
    "planning: plan-reviewer",
]
DELIVERY_LABELS = ["delivery: pr-review (release PR)", "delivery: devops"]

# Read once by the orchestrator, applied inline per story (D8) — no dispatch.
INLINE = {"orchestrator: verdict.md (read once)": ["agents/verdict.md"]}

# --- per-dispatch token cost (execution-options checkpoint) -------------
# {agent: (tokens, n_samples)}. n_samples == 0 means "assumed" — not yet
# measured; otherwise "measured (n=...)". Seeded from a delivery's own
# dispatches (PROGRESS.md — Loop rules in force): planning map 77k (haiku,
# n=1), architect 184k (opus, n=1), plan-reviewer 165k (sonnet, n=1);
# first-pass dispatches: reviewer 66-161k (n=9, mean 106k), coder 59-215k
# (n=9, mean 137k), qa 82-116k (n=3, mean 99k), stress 72-99k (n=3, mean
# 85k). Fix rounds are NOT in these means: they added ~40-60% per
# full-roster story on top of first pass.
COST = {
    "map": (77000, 1),
    "architect": (184000, 1),
    "plan-reviewer": (165000, 1),
    "reviewer": (106000, 9),
    "coder": (137000, 9),
    "qa": (99000, 3),
    "stress": (85000, 3),
    "scrum-master": (40000, 0),
    "verdict": (20000, 0),
    "pr-review": (90000, 0),
    "devops": (60000, 0),
}

# --- rework overhead -------------------------------------------------
# {roster: (factor, n_samples)}, labelled like COST: n_samples == 0 means
# "assumed", otherwise "measured (n=...)". A first-pass token total undercounts
# what a story actually costs — fix rounds from QA/Reviewer findings reopen the
# Coder dispatch. Seeded from a delivery's own PROGRESS.md (Loop rules in
# force), stated plainly: full-roster ran n=3 stories, 1.3-1.7x
# first-pass across their fix rounds; standard n=1; light n=2. These are seeds,
# not a claim about every project — a project should replace them with its own
# measured samples as fix rounds accumulate. cosmetic carries no rework because
# its roster (Coder only, gates only) has no QA/Reviewer fix-round loop to
# reopen.
REWORK = {
    "full": (1.5, 3),
    "standard": (1.3, 1),
    "light": (1.2, 2),
    "cosmetic": (1.0, 0),
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


def expand_mix(mix):
    rosters = []
    for name, n in mix.items():
        rosters.extend([name] * n)
    return rosters


def parse_mix(s):
    """argparse type for --mix: "roster=count,roster=count,...". """
    result = {}
    for part in s.split(","):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            raise argparse.ArgumentTypeError(f"invalid --mix entry: {part!r}")
        name, _, count = part.partition("=")
        name = name.strip()
        if name not in ROSTER:
            raise argparse.ArgumentTypeError(f"unknown roster in --mix: {name!r}")
        try:
            n = int(count)
        except ValueError as exc:
            raise argparse.ArgumentTypeError(f"invalid --mix count for {name!r}: {count!r}") from exc
        if n < 0:
            raise argparse.ArgumentTypeError(f"negative --mix count for {name!r}: {n}")
        result[name] = n
    if not result:
        raise argparse.ArgumentTypeError("empty --mix")
    return result


def build_paths(root, roster_list):
    """Per-path guide-token cost for one profile's roster mix."""
    story_counts = dict.fromkeys(ROSTER_PATH.values(), 0)
    for roster in roster_list:
        for agent in ROSTER[roster]:
            story_counts[ROSTER_PATH[agent]] += 1

    paths, missing = {}, []
    for label, files in DISPATCH.items():
        per_load, miss = measure(root, files)
        missing += miss
        count = 1 if label in PLANNING_LABELS or label in DELIVERY_LABELS else story_counts.get(label, 0)
        paths[label] = {"per_load": per_load, "dispatches": count, "total": per_load * count}
    return paths, missing


def build_inline(root):
    inline, missing = {}, []
    for label, files in INLINE.items():
        per_load, miss = measure(root, files)
        missing += miss
        inline[label] = {"per_load": per_load, "dispatches": 0, "total": per_load}
    return inline, missing


def profile_totals(paths, inline):
    dispatches = sum(p["dispatches"] for p in paths.values())
    guide_tokens = sum(p["total"] for p in paths.values()) + sum(i["total"] for i in inline.values())
    return dispatches, guide_tokens


def collect(root, stories, mix):
    report = {"stories": stories, "always_on": {}, "missing": []}

    for label, files in ALWAYS_ON.items():
        t, miss = measure(root, files)
        report["always_on"][label] = t
        report["missing"] += miss
    report["session_always_on"] = sum(report["always_on"].values())

    uniform_rosters = ["standard"] * stories
    mixed_rosters = expand_mix(mix if mix is not None else DEFAULT_MIX)

    profiles = {}
    for name, rosters in (("uniform", uniform_rosters), ("mixed", mixed_rosters)):
        paths, miss1 = build_paths(root, rosters)
        inline, miss2 = build_inline(root)
        dispatches, guide_tokens = profile_totals(paths, inline)
        report["missing"] += miss1 + miss2
        profiles[name] = {"dispatches": dispatches, "guide_tokens": guide_tokens}
        if name == "uniform":
            # Top-level keys keep their pre-roster meaning: the uniform profile.
            report["paths"] = paths
            report["inline"] = inline
            report["delivery_dispatches"] = dispatches
            report["delivery_guide_tokens"] = guide_tokens

    report["profiles"] = profiles
    report["missing"] = sorted(set(report["missing"]))
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

    out.append("## Profiles")
    out.append("")
    out.append("| Profile | Dispatches | Guide tokens |")
    out.append("|---|---:|---:|")
    for name, p in r["profiles"].items():
        out.append(f"| {name} | {p['dispatches']} | {fmt(p['guide_tokens'])} |")
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


# --- execution-options checkpoint (--manifest) --------------------------


def parse_manifest_rosters(path):
    """Read a Phase-4 manifest table and return its Roster column values, in
    row order, or None when the table carries no Roster column at all.
    Exits with error if an unrecognized roster value is found."""
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    header_idx, cols = None, []
    for i, line in enumerate(lines):
        s = line.strip()
        if not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if "Roster" in cells:
            header_idx, cols = i, cells
            break
    if header_idx is None:
        return None

    roster_i = cols.index("Roster")
    rosters = []
    row_num = header_idx + 1
    for line in lines[header_idx + 1:]:
        s = line.strip()
        if not s.startswith("|"):
            break
        cells = [c.strip() for c in s.strip("|").split("|")]
        if all(c == "" or set(c) <= set("-: ") for c in cells):
            continue  # markdown separator row
        if len(cells) <= roster_i:
            row_num += 1
            continue
        val = cells[roster_i]
        if val in ROSTER:
            rosters.append(val)
        elif val:  # non-empty value that's not in ROSTER
            print(f"bench-context: unrecognized roster '{val}' in manifest row {row_num}", file=sys.stderr)
            sys.exit(2)
        row_num += 1
    return rosters


def option_agents(name, rosters):
    n = len(rosters)
    if name == "as planned":
        agents = [a for r in rosters for a in ROSTER[r]]
    elif name == "all standard":
        agents = list(ROSTER["standard"]) * n
    else:  # legacy full loop
        agents = list(LEGACY_PER_ROW) * n
    return agents + PLANNING_AGENTS + DELIVERY_AGENTS


def rework_avg_factor(rosters, rework):
    """Weighted average rework factor across the manifest's own declared rosters.
    Rework is a property of how much back-and-forth a real story of that roster
    needs — it applies to every option's first-pass total the same way, not
    just the hypothetical agent set a given option prices."""
    if not rosters:
        return 1.0
    return sum(rework[r][0] for r in rosters) / len(rosters)


def compute_options(rosters, cost=None, rework=None):
    if cost is None:
        cost = COST
    if rework is None:
        rework = REWORK
    avg_factor = rework_avg_factor(rosters, rework)
    options = {}
    for name in ("as planned", "all standard", "legacy full loop"):
        agents = option_agents(name, rosters)
        total = sum(cost[a][0] for a in agents)
        low, high = int(total * 0.8), int(total * 1.2)
        options[name] = {
            "dispatches": len(agents),
            "tokens_low": low,
            "tokens_high": high,
            "rework_low": int(low * avg_factor),
            "rework_high": int(high * avg_factor),
        }
    return options


def render_manifest(rosters, options, cost=None, rework=None):
    if cost is None:
        cost = COST
    if rework is None:
        rework = REWORK
    out = [f"# Execution options — {len(rosters)} manifest rows", ""]
    out.append("| Agent | Cost (tokens) | Basis |")
    out.append("|---|---:|---|")
    for agent in sorted(cost):
        tok, n = cost[agent]
        basis = "assumed" if n == 0 else f"measured (n={n})"
        out.append(f"| {agent} | {fmt(tok)} | {basis} |")
    out.append("")
    out.append("| Roster | Rework factor | Basis |")
    out.append("|---|---:|---|")
    for roster in sorted(rework):
        factor, n = rework[roster]
        basis = "assumed" if n == 0 else f"measured (n={n})"
        out.append(f"| {roster} | {factor}x | {basis} |")
    out.append("")
    out.append("| Option | Dispatches | First pass | With rework |")
    out.append("|---|---:|---:|---:|")
    for name in ("as planned", "all standard", "legacy full loop"):
        o = options[name]
        out.append(
            f"| {name} | {o['dispatches']} | {fmt(o['tokens_low'])}–{fmt(o['tokens_high'])} tok "
            f"| {fmt(o['rework_low'])}–{fmt(o['rework_high'])} tok (with rework) |"
        )
    return "\n".join(out)


def run_manifest(path, as_json, cost=None, rework=None):
    if cost is None:
        cost = COST
    if rework is None:
        rework = REWORK
    rosters = parse_manifest_rosters(path)
    if rosters is None:
        print("bench-context: no Roster column in manifest", file=sys.stderr)
        return 2

    options = compute_options(rosters, cost=cost, rework=rework)
    if as_json:
        cost_json = {a: {"tokens": t, "n_samples": n} for a, (t, n) in cost.items()}
        rework_json = {r: {"factor": f, "n_samples": n} for r, (f, n) in rework.items()}
        print(json.dumps(
            {"rows": len(rosters), "options": options, "cost": cost_json, "rework": rework_json},
            indent=2,
        ))
    else:
        print(render_manifest(rosters, options, cost=cost, rework=rework))
    return 0


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(here))
    ap.add_argument("--stories", type=int, default=5)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--baseline")
    ap.add_argument("--mix", type=parse_mix, default=None)
    ap.add_argument("--manifest")
    a = ap.parse_args()

    if a.manifest:
        return run_manifest(a.manifest, a.json)

    r = collect(a.root, a.stories, a.mix)
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
