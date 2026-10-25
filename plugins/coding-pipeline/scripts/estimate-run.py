#!/usr/bin/env python3
"""Estimate the run options for /code from a plan's Tasks table, and measure the guides.

/code asks the user how to execute a plan — inline, one coder, one coder per row, or
parallel coders in worktrees. The choice is a cost/risk trade the user should make with
numbers in front of them, not a default the skill picks silently. This script reads the
plan's Tasks table and prints, per mode, the dispatch count and a token range, plus which
rows are safe to run in parallel and why the others are not.

Every constant below is a Const(value, n): n == 0 means ASSUMED (a derivation, stated),
n >= 1 means MEASURED on n real dispatches (provenance stated). A mode's range is labelled
`measured` only when every constant it uses is measured, `assumed` when none is, and
`partly measured` otherwise — so a label never claims more than its weakest input.

--guides counts what the guides themselves cost (CLAUDE.md per session, each dispatch's
agent + reference files, each skill's SKILL.md), by reading the files — the devkit's first
rule is that an addition earns its tokens, and this is the check. Token counts are
estimated at CHARS_PER_TOKEN, not tokenized: compare runs against each other (before vs
after a change), where a constant bias cancels; treat absolute figures as ±10%.

Usage: estimate-run.py --plan <docs/plans/{slug}/plan.md>
       estimate-run.py --guides [--root DIR] [--json] [--baseline FILE]
Exit 0 — table printed.
Exit 2 — plan missing, no Tasks table, a malformed row, a duplicate ID or an unknown
         dependency; for --guides, a guide file in the dispatch graph that cannot be read.
         "Could not estimate" is never printed as an estimate.
"""
import json
import os
import re
import sys
from collections import namedtuple

Const = namedtuple("Const", "value n")  # n == 0 → assumed; n >= 1 → measured (n samples)

# ── Measured costs (tokens per first-pass dispatch) ──────────────────────────────────
# Provenance: one 2.x delivery's own dispatches (PROGRESS.md — Loop rules in force),
# carried over from the 2.x COST table. Fix rounds are NOT in these
# means (see REWORK). Measured before agents gained a `tools:` allowlist, so each still
# carries the ~26k of inherited tool definitions that SUBAGENT_BASELINE describes — an
# overestimate by up to that much until a post-change delivery re-measures them.
# coder 59–215k, mean 137k (n=9).
CODER_DISPATCH = Const(137_000, 9)
CODER_SPREAD = Const((59_000 / 137_000, 215_000 / 137_000), 9)  # the measured min/max
# qa 82–116k, mean 99k (n=3) · stress 72–99k, mean 85k (n=3) · reviewer 66–161k, mean 106k (n=9).
QA_DISPATCH = Const(99_000, 3)
STRESS_DISPATCH = Const(85_000, 3)
REVIEWER_DISPATCH = Const(106_000, 9)
# Subagent baseline, measured on delivery 4e6020: a subagent starts at ~45k tokens, ~26k of
# them inherited tool definitions (n=1). A probe with the pipeline allowlist measured 14.9k
# (n=1); 45k is kept because it is the baseline the coder figure above was measured with.
SUBAGENT_BASELINE = Const(45_000, 1)
# Not used here, kept as provenance for /planning's own cost: map 77k (haiku, n=1),
# plan-reviewer 165k (sonnet, n=1); the 2.x main session ran 45 calls × 170k average context
# per story (opus, n=1) — an orchestrator shape /code's main session no longer has.

# Rework: a first-pass total undercounts what a change costs — fix rounds reopen the coder.
# {depth: factor}, measured on the same delivery's stories across their fix rounds:
# full 1.3–1.7x (n=3), standard n=1, light n=2. cosmetic is assumed: no qa/stress loop to reopen.
REWORK = {
    "light": Const(1.2, 2),
    "standard": Const(1.3, 1),
    "full": Const(1.5, 3),
    "cosmetic": Const(1.0, 0),
}

# ── Assumed constants — recalibrate from a measured run ──────────────────────────────
# Inline mode only (no inline run has been measured): each file a row touches is read,
# edited and re-read while testing — ~6k per file (a 200-300 line file read twice + edits).
PER_FILE = Const(6_000, 0)
# Each Test Case row is written, run, broken with break-run.sh and run again: ~4k per row.
PER_TEST_ROW = Const(4_000, 0)
# The main session reads each CODER DONE block (≤ 40 lines), appends evidence, runs the
# re-break and checkpoint M: ~5k per row in the main thread.
MAIN_PER_ROW = Const(5_000, 0)
# Inline: the main session's context already holds the conversation, so every later call
# re-reads a longer context — a carry factor on the row's work.
INLINE_CARRY = Const(1.3, 0)
# Single coder: one dispatch, then every later row re-reads the growing transcript.
SINGLE_CARRY_PER_ROW = Const(0.15, 0)
# Parallel: worktree setup + merge back + gates after each merge, per row.
PARALLEL_MERGE_PER_ROW = Const(6_000, 0)
# Range spread for a mode with no measured spread.
SPREAD = Const((0.7, 1.4), 0)
MAX_WRITERS = 3          # CLAUDE.md Sub-agent Discipline: never 4+ writers in a turn
SINGLE_CODER_WARN_ROWS = 4

REQUIRED = ["id", "task", "files", "test rows", "language", "tier", "depends on"]
NONE_TOKENS = {"", "-", "—", "–", "none", "n/a"}


def fail(msg):
    print(f"ESTIMATE: UNMEASURED — {msg}")
    sys.exit(2)


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
        fail(f"cannot read plan: {e}")
    # The Tasks table is the one whose header carries every required column.
    start = None
    for i, line in enumerate(lines):
        c = cells(line)
        if c and {x.lower() for x in c} >= set(REQUIRED):
            start, header = i, [x.lower() for x in c]
            break
    if start is None:
        fail("no Tasks table (| ID | Task | Files | Test rows | Language | Tier | Depends on |)")
    idx = {name: header.index(name) for name in REQUIRED}
    rows = []
    for line in lines[start + 1:]:
        c = cells(line)
        if c is None:
            break
        if all(re.fullmatch(r":?-+:?", x) for x in c if x):
            continue
        if len(c) != len(header):
            fail(f"malformed Tasks row ({len(c)} cells, header has {len(header)}): {line.strip()}")
        rid = re.sub(r"[`*]", "", c[idx["id"]]).strip()
        if not rid:
            fail(f"Tasks row without an ID: {line.strip()}")
        rows.append({
            "id": rid,
            "files": split_list(c[idx["files"]]),
            "tests": split_list(c[idx["test rows"]]),
            "deps": split_list(c[idx["depends on"]]),
        })
    if not rows:
        fail("Tasks table has no rows")
    ids = [r["id"] for r in rows]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        fail(f"duplicate Task ID(s): {', '.join(dup)}")
    for r in rows:
        for d in r["deps"]:
            if d not in ids:
                fail(f"{r['id']} depends on unknown task '{d}'")
        if not r["files"]:
            fail(f"{r['id']} lists no Files — the checkpoint needs them as --expect")
    return rows


def basis(consts):
    """measured only if every constant is measured; assumed if none is."""
    measured = [c.n > 0 for c in consts]
    if all(measured):
        return "measured"
    if any(measured):
        return "partly measured"
    return "assumed"


def claim(path):
    """The repo path a Files entry claims: `./` and trailing `/` dropped; a glob claims its directory."""
    p = path.strip().replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    if any(ch in p for ch in "*?["):
        head = re.split(r"[*?\[]", p, maxsplit=1)[0]
        p = head.rsplit("/", 1)[0] if "/" in head else ""
    return re.sub(r"/+", "/", p).strip("/")


def overlaps(a, b):
    """Same path, or one contains the other (a directory and a file inside it); "" is the repo root."""
    return a == b or a == "" or b == "" or a.startswith(b + "/") or b.startswith(a + "/")


def parallel_plan(rows):
    """First wave: rows with no dependency whose Files are disjoint from every earlier pick.

    Disjoint means no path overlap, not just unequal strings: `src/` and `src/a.go` are
    the same file to two coders, and so are `lib/*.go` (its directory) and `lib/b.go`."""
    safe, reasons, taken = [], {}, []
    for r in rows:
        if r["deps"]:
            reasons[r["id"]] = "depends on " + ", ".join(r["deps"])
            continue
        clash = [(f, owner) for f in r["files"] for c, owner in taken if overlaps(claim(f), c)]
        if clash:
            f, other = clash[0]
            reasons[r["id"]] = f"shares {f} with {other}"
            continue
        safe.append(r["id"])
        taken.extend((claim(f), r["id"]) for f in r["files"])
    return safe, reasons


def fmt(n):
    return f"{n / 1000:.0f}k"


def rng(n, spread):
    low, high = spread.value
    return f"{fmt(n * low)}–{fmt(n * high)}"


def estimate(argv):
    rows = parse(argv[1])
    n = len(rows)
    files = len({f for r in rows for f in r["files"]})
    tests = sum(len(r["tests"]) for r in rows)
    main_rows = MAIN_PER_ROW.value * n

    inline_work = sum(PER_FILE.value * len(r["files"]) + PER_TEST_ROW.value * len(r["tests"]) for r in rows)
    inline = int(inline_work * INLINE_CARRY.value + main_rows)
    inline_k = [PER_FILE, PER_TEST_ROW, INLINE_CARRY, MAIN_PER_ROW, SPREAD]
    # One dispatch pays the subagent baseline once; every row then pays the measured
    # per-row work (coder dispatch minus that baseline), carried by the growing transcript.
    row_work = CODER_DISPATCH.value - SUBAGENT_BASELINE.value
    single = int(SUBAGENT_BASELINE.value + row_work * n * (1 + SINGLE_CARRY_PER_ROW.value * (n - 1)) + main_rows)
    single_k = [SUBAGENT_BASELINE, CODER_DISPATCH, SINGLE_CARRY_PER_ROW, MAIN_PER_ROW, CODER_SPREAD]
    sequential = CODER_DISPATCH.value * n + main_rows
    sequential_k = [CODER_DISPATCH, MAIN_PER_ROW, CODER_SPREAD]
    safe, reasons = parallel_plan(rows)
    waves = -(-len(safe) // MAX_WRITERS) if safe else 0
    parallel = sequential + PARALLEL_MERGE_PER_ROW.value * len(safe)
    parallel_k = sequential_k + [PARALLEL_MERGE_PER_ROW]

    if n <= 2 and files <= 4:
        rec = "Inline"
    elif len(safe) >= 2:
        rec = "Parallel coders"
    else:
        rec = "Sequential coders"

    single_note = "tightly coupled rows / shared files"
    if n > SINGLE_CODER_WARN_ROWS:
        single_note += f"; WARN {n} rows > {SINGLE_CODER_WARN_ROWS}: coder context ceiling"
    par_note = (f"{len(safe)} row(s) parallel-safe in {waves} wave(s) of ≤ {MAX_WRITERS}, worktree each; rest sequential"
                if len(safe) >= 2 else "no benefit: fewer than 2 parallel-safe rows")
    options = [
        ("Inline", 0, inline, SPREAD, inline_k, "main session implements every row; best for 1–2 small rows"),
        ("Single coder", 1, single, CODER_SPREAD, single_k, single_note),
        ("Sequential coders", n, sequential, CODER_SPREAD, sequential_k, "one coder per row in dependency order (default)"),
        ("Parallel coders", n, parallel, CODER_SPREAD, parallel_k, par_note),
    ]
    options.sort(key=lambda o: o[0] != rec)

    print(f"Plan: {argv[1]} · {n} rows · {files} files · {tests} test rows")
    print()
    print("| Mode | Coder dispatches | Tokens | Basis | Notes |")
    print("|---|---|---|---|---|")
    for name, d, t, spread, used, note in options:
        mark = " (recommended)" if name == rec else ""
        print(f"| {name}{mark} | {d} | {rng(t, spread)} | {basis(used)} | {note} |")
    print()
    print("Parallel-safe: " + (", ".join(safe) if safe else "none"))
    for rid, why in reasons.items():
        print(f"  not parallel-safe: {rid} — {why}")
    print("Fix rounds are not in these ranges — multiply first pass by: " + " · ".join(
        f"{depth} ×{c.value} {basis([c])}" + (f" (n={c.n})" if c.n else "")
        for depth, c in REWORK.items()) + ".")
    qa_stress = QA_DISPATCH.value + STRESS_DISPATCH.value
    print(f"Then: /validate-code — light: qa {fmt(QA_DISPATCH.value)} · standard/full: qa + stress {fmt(qa_stress)} "
          f"({basis([QA_DISPATCH, STRESS_DISPATCH])}, n={QA_DISPATCH.n}/{STRESS_DISPATCH.n}); cosmetic: no dispatch · "
          f"/review-code — reviewer {fmt(REVIEWER_DISPATCH.value)} ({basis([REVIEWER_DISPATCH])}, n={REVIEWER_DISPATCH.n}).")
    print("Gates and falsification evidence (break-run.sh, evidence.md) run in every mode.")
    return 0


# ── --guides: what the guides cost, measured from the files ─────────────────────────
CHARS_PER_TOKEN = 3.6  # markdown with tables/code, cl100k-ish

# Paths are (plugin, path-inside-plugin). Each dispatch loads its agent file plus what the
# agent loads up front — one language file for coder and reviewer (Go stands in for any);
# every other reference is load-on-demand and is not counted. When an agent or skill
# changes what it loads up front, this table changes with it or the figure lies.
ALWAYS_ON = {"CLAUDE.md (every session)": [("coding-pipeline", "CLAUDE.md")]}
DISPATCH = {
    "map (Explore)": [("coding-pipeline", "skills/map/references/map-procedure.md")],
    "plan-reviewer": [("coding-pipeline", "agents/plan-reviewer.md")],
    "coder (core + backend overlay + one language file)": [
        ("coding-pipeline", "agents/coder.md"),
        ("coding-pipeline", "agents/coder-backend.md"),
        ("coding-pipeline", "references/languages/go.md"),
    ],
    "qa": [("coding-pipeline", "agents/qa.md")],
    "stress": [("coding-pipeline", "agents/stress.md")],
    "reviewer (+ one language file)": [
        ("coding-pipeline", "agents/reviewer.md"),
        ("coding-pipeline", "references/languages/go.md"),
    ],
    "bug-investigator": [("coding-pipeline", "agents/bug-investigator.md")],
}
# Skill → (its SKILL.md, the dispatches of its target shape — CLAUDE.md Sub-agent Discipline).
SKILLS = {
    "/planning (one review round)": (("coding-pipeline", "skills/planning/SKILL.md"), ["map (Explore)", "plan-reviewer"]),
    "/code (per Tasks row)": (("coding-pipeline", "skills/code/SKILL.md"), ["coder (core + backend overlay + one language file)"]),
    "/validate-code (full depth)": (("coding-pipeline", "skills/validate-code/SKILL.md"), ["qa", "stress"]),
    "/review-code": (("pr-workflow", "skills/review-code/SKILL.md"), ["reviewer (+ one language file)"]),
    "/bugfix": (("coding-pipeline", "skills/bugfix/SKILL.md"), ["bug-investigator", "coder (core + backend overlay + one language file)"]),
}


def resolve(root, plugin, rel):
    """Plugin layout: root is plugins/coding-pipeline, siblings are other plugins.
    Flat install: root is ~/.claude/devkit (CLAUDE.md); agents/, references/ and
    skills/ sit one level up, in ~/.claude/ (CLAUDE.md — Path resolution)."""
    first = os.path.join(root, rel) if plugin == "coding-pipeline" else os.path.join(root, "..", plugin, rel)
    for p in (first, os.path.join(root, "..", rel)):
        if os.path.isfile(p):
            return os.path.normpath(p)
    return None


def guide_tokens(root, paths, missing):
    total = 0
    for plugin, rel in paths:
        p = resolve(root, plugin, rel)
        try:
            with open(p, encoding="utf-8") as fh:
                total += int(len(fh.read()) / CHARS_PER_TOKEN)
        except (OSError, TypeError):
            missing.append(f"{plugin}/{rel}")
    return total


def measure_guides(root):
    missing = []
    always_on = {label: guide_tokens(root, paths, missing) for label, paths in ALWAYS_ON.items()}
    dispatch = {label: guide_tokens(root, paths, missing) for label, paths in DISPATCH.items()}
    skills = {}
    for name, (skill_md, agents) in SKILLS.items():
        own = guide_tokens(root, [skill_md], missing)
        dispatched = sum(dispatch[a] for a in agents)
        skills[name] = {"skill_md": own, "dispatches": len(agents), "dispatched": dispatched, "total": own + dispatched}
    if missing:
        print("GUIDES: UNMEASURED — cannot read: " + ", ".join(sorted(set(missing))))
        sys.exit(2)
    return {"always_on": sum(always_on.values()), "always_on_paths": always_on,
            "dispatch": dispatch, "skills": skills}


def guides(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    as_json, baseline = False, None
    it = iter(argv[1:])
    for a in it:
        if a == "--root":
            root = next(it, None)
        elif a == "--json":
            as_json = True
        elif a == "--baseline":
            baseline = next(it, None)
        else:
            root = None
        if root is None or (a == "--baseline" and baseline is None):
            print("usage: estimate-run.py --guides [--root DIR] [--json] [--baseline FILE]", file=sys.stderr)
            sys.exit(2)
    r = measure_guides(root)
    if as_json:
        print(json.dumps(r, indent=2))
        return 0
    n = "{:,}".format
    print(f"# Guide tokens — {root} (≈ chars / {CHARS_PER_TOKEN}, ±10%; compare runs, not absolutes)")
    print()
    print("| Loaded | Tokens per load |")
    print("|---|---:|")
    for label, t in r["always_on_paths"].items():
        print(f"| {label} | {n(t)} |")
    for label, t in r["dispatch"].items():
        print(f"| {label} | {n(t)} |")
    print()
    print("| Skill | SKILL.md | Dispatches | Dispatched guides | Total |")
    print("|---|---:|---:|---:|---:|")
    for name, s in r["skills"].items():
        print(f"| {name} | {n(s['skill_md'])} | {s['dispatches']} | {n(s['dispatched'])} | {n(s['total'])} |")
    if baseline:
        try:
            with open(baseline, encoding="utf-8") as fh:
                b = json.load(fh)
            rows = [("always-on / session", b["always_on"], r["always_on"])]
            rows += [(name, b["skills"][name]["total"], s["total"]) for name, s in r["skills"].items() if name in b["skills"]]
        except (OSError, ValueError, KeyError, TypeError) as e:
            print(f"GUIDES: UNMEASURED — unreadable baseline {baseline}: {e}")
            sys.exit(2)
        print()
        print("| vs baseline | baseline | now | delta |")
        print("|---|---:|---:|---:|")
        for label, was, now in rows:
            print(f"| {label} | {n(was)} | {n(now)} | {now - was:+,} |")
    return 0


def main(argv):
    if argv and argv[0] == "--guides":
        return guides(argv)
    if len(argv) != 2 or argv[0] != "--plan":
        print("usage: estimate-run.py --plan <plan.md> | --guides [--root DIR] [--json] [--baseline FILE]", file=sys.stderr)
        sys.exit(2)
    return estimate(argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
