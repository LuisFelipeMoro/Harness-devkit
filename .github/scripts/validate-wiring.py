#!/usr/bin/env python3
"""Wiring sensor for the devkit itself.

Every capability here is a file pointing at another file: a marketplace entry at a
plugin dir, a hook entry at a shell script, a skill at a reference, an agent name in
a dispatch instruction. None of those links is executed at authoring time, so a
rename breaks them silently and the failure only shows up mid-delivery. This walks
them all and exits non-zero on the first broken one.

Run: python3 .github/scripts/validate-wiring.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
errors = []
checked = {"manifest": 0, "hook": 0, "link": 0, "agent": 0, "skill": 0, "routing": 0, "desc": 0, "contract": 0}


def err(kind, where, msg):
    errors.append(f"[{kind}] {where}: {msg}")


def rel(p):
    return os.path.relpath(p, ROOT)


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


# ── 1. marketplace ↔ plugin manifests ────────────────────────────────────────
market_path = os.path.join(ROOT, ".claude-plugin", "marketplace.json")
market = json.loads(read(market_path))
declared = {}
for entry in market.get("plugins", []):
    checked["manifest"] += 1
    name, source = entry.get("name"), entry.get("source", "")
    pdir = os.path.normpath(os.path.join(ROOT, source))
    if not os.path.isdir(pdir):
        err("manifest", "marketplace.json", f"plugin '{name}' source '{source}' is not a directory")
        continue
    manifest = os.path.join(pdir, ".claude-plugin", "plugin.json")
    if not os.path.isfile(manifest):
        err("manifest", rel(pdir), "missing .claude-plugin/plugin.json")
        continue
    pj = json.loads(read(manifest))
    if pj.get("name") != name:
        err("manifest", rel(manifest), f"name '{pj.get('name')}' != marketplace name '{name}'")
    declared[name] = pdir

# every plugin dir on disk must be declared — an undeclared one ships to nobody
for d in sorted(os.listdir(os.path.join(ROOT, "plugins"))):
    pdir = os.path.join(ROOT, "plugins", d)
    if os.path.isdir(pdir) and d not in declared:
        err("manifest", f"plugins/{d}", "directory exists but is not listed in marketplace.json")

# ── 2. hooks.json entries point at real scripts ──────────────────────────────
for name, pdir in declared.items():
    pj = json.loads(read(os.path.join(pdir, ".claude-plugin", "plugin.json")))
    hooks_rel = pj.get("hooks")
    if not hooks_rel:
        continue
    hooks_path = os.path.normpath(os.path.join(pdir, hooks_rel))
    if not os.path.isfile(hooks_path):
        err("hook", rel(os.path.join(pdir, ".claude-plugin", "plugin.json")),
            f"hooks '{hooks_rel}' does not exist")
        continue
    blob = read(hooks_path)
    for script in re.findall(r"\$\{CLAUDE_PLUGIN_ROOT\}/([^\"\\\s]+)", blob):
        checked["hook"] += 1
        target = os.path.join(pdir, script)
        if not os.path.isfile(target):
            err("hook", rel(hooks_path), f"references missing script '{script}'")
        elif not os.access(target, os.X_OK):
            err("hook", rel(target), "hook script is not executable (chmod +x)")

# scripts present but wired to nothing are dead weight
for name, pdir in declared.items():
    hdir = os.path.join(pdir, "hooks")
    if not os.path.isdir(hdir):
        continue
    hooks_json = os.path.join(hdir, "hooks.json")
    blob = read(hooks_json) if os.path.isfile(hooks_json) else ""
    # An agent's frontmatter hooks may wire a script for that agent alone.
    adir = os.path.join(pdir, "agents")
    if os.path.isdir(adir):
        blob += "".join(read(os.path.join(adir, a)) for a in os.listdir(adir) if a.endswith(".md"))
    for f in sorted(os.listdir(hdir)):
        if not f.endswith(".sh") or f == "hook-lib.sh":
            continue
        if f not in blob:
            err("hook", rel(os.path.join(hdir, f)), "script is not referenced by hooks.json (orphan)")

# ── 3. in-repo markdown links resolve ────────────────────────────────────────
MD_LINK = re.compile(r"\[[^\]]*\]\((?!https?://|#|mailto:)([^)\s]+)\)")
BACKTICK_PATH = re.compile(r"`((?:\.\./)*(?:references|agents|skills|hooks|scripts|git-hooks|codex)/[A-Za-z0-9._/-]+\.(?:md|sh|json|yml|yaml|toml))`")

for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "plugins")):
    dirnames[:] = [d for d in dirnames if d != ".git"]
    for fn in filenames:
        if not fn.endswith(".md"):
            continue
        path = os.path.join(dirpath, fn)
        text = read(path)
        plugin_dir = next((p for p in declared.values() if path.startswith(p + os.sep)), None)
        for raw in MD_LINK.findall(text):
            checked["link"] += 1
            target = os.path.normpath(os.path.join(dirpath, raw.split("#")[0]))
            if not os.path.exists(target):
                err("link", rel(path), f"broken markdown link -> {raw}")
        if plugin_dir:
            for raw in set(BACKTICK_PATH.findall(text)):
                checked["link"] += 1
                # a plugin-rooted path like `references/x.md`, or one relative to this file
                if os.path.exists(os.path.normpath(os.path.join(plugin_dir, raw))):
                    continue
                if os.path.exists(os.path.normpath(os.path.join(dirpath, raw))):
                    continue
                # a path written relative to the owning skill's root (skills/<name>/)
                parts = path.split(os.sep)
                if "skills" in parts:
                    skill_root = os.sep.join(parts[: parts.index("skills") + 2])
                    if os.path.exists(os.path.normpath(os.path.join(skill_root, raw))):
                        continue
                if "<" in raw or ">" in raw:   # placeholder such as languages/<language>.md
                    continue
                err("link", rel(path), f"path reference does not resolve -> {raw}")

# ── 4. namespaced agent and skill references exist ───────────────────────────
agents = {n: {os.path.splitext(f)[0] for f in os.listdir(os.path.join(p, "agents"))
              if f.endswith(".md")}
          for n, p in declared.items() if os.path.isdir(os.path.join(p, "agents"))}
skills = {n: {d for d in os.listdir(os.path.join(p, "skills"))
              if os.path.isfile(os.path.join(p, "skills", d, "SKILL.md"))}
          for n, p in declared.items() if os.path.isdir(os.path.join(p, "skills"))}

NS = re.compile(r"\b([a-z0-9][a-z0-9_-]*):([a-z0-9][a-z0-9-]*)\b")
for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "plugins")):
    for fn in filenames:
        if not fn.endswith(".md"):
            continue
        path = os.path.join(dirpath, fn)
        for plugin, item in set(NS.findall(read(path))):
            if plugin not in declared:
                continue
            known_agents, known_skills = agents.get(plugin, set()), skills.get(plugin, set())
            if item in known_agents:
                checked["agent"] += 1
            elif item in known_skills:
                checked["skill"] += 1
            else:
                err("ref", rel(path), f"'{plugin}:{item}' matches no agent or skill in that plugin")

# ── 5. CLAUDE.md "Skills (invoke manually)" table resolves, and is complete ──
all_skill_names = set()
for pdir in declared.values():
    sdir = os.path.join(pdir, "skills")
    if os.path.isdir(sdir):
        for d in os.listdir(sdir):
            if os.path.isfile(os.path.join(sdir, d, "SKILL.md")):
                all_skill_names.add(d)

routing_md = os.path.join(ROOT, "plugins", "coding-pipeline", "CLAUDE.md")
if os.path.isfile(routing_md):
    text = read(routing_md)
    # The heading is prose and can be reworded. A miss is an error, not a silent skip,
    # or this check would scan an empty string and pass while verifying nothing.
    m = re.search(r"^## Skills \(invoke manually\)[^\n]*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not m:
        err("routing", rel(routing_md), "'## Skills (invoke manually)' section not found — this check verified nothing")
    table_block = m.group(1) if m else ""
    routed = sorted(set(re.findall(r"`/([a-z0-9][a-z0-9-]*)`", table_block)))
    if m and not routed:
        err("routing", rel(routing_md), "skills table matched but lists no skills — table shape changed")
    for name in routed:
        checked["routing"] += 1
        if name not in all_skill_names:
            err("routing", rel(routing_md), f"listed skill '/{name}' has no matching skills/{name}/SKILL.md")
    if m:
        for name in sorted(all_skill_names - set(routed)):
            err("routing", rel(routing_md), f"skill '{name}' exists but is missing from the Skills table")

# ── 6. every skill: description, manual-only, never calls another skill ─
# A folded/multi-line YAML description is captured too: continuation lines are indented.
DESC_FIELD = re.compile(r"^description:[ \t]*(.*(?:\n[ \t]+\S.*)*)$", re.M)
# A skill must not tell the model to run another skill. Suggesting one ("Next: /validate-code")
# is allowed — only a user starts a skill.
SKILL_CALL = re.compile(r"Skill\(|\b(?:load|invoke|run)(?: and follow)? (?:the )?`/[a-z0-9-]+` skill", re.I)
for name, pdir in declared.items():
    sdir = os.path.join(pdir, "skills")
    if not os.path.isdir(sdir):
        continue
    for d in sorted(os.listdir(sdir)):
        skill_md = os.path.join(sdir, d, "SKILL.md")
        if not os.path.isfile(skill_md):
            continue
        checked["desc"] += 1
        text = read(skill_md)
        fm = re.match(r"\A---\n(.*?)\n---", text, re.S)
        if not fm:
            err("desc", rel(skill_md), "missing frontmatter")
            continue
        dm = DESC_FIELD.search(fm.group(1))
        if not dm or not dm.group(1).strip().strip("'\""):
            err("desc", rel(skill_md), "missing description field")
        if not re.search(r"^disable-model-invocation:[ \t]*true[ \t]*$", fm.group(1), re.M):
            err("desc", rel(skill_md), "frontmatter lacks 'disable-model-invocation: true' (skills are manual)")
        if SKILL_CALL.search(text):
            err("desc", rel(skill_md), "tells the model to invoke another skill — skills never call skills; suggest it instead")

# ── 7. contract: naming conventions and the rules that must not drift ───────
# Data-driven contract: (path, must_contain: list[str], must_not: list[str])
CONTRACT = [
    # agent scope guards: $TMPDIR for probes/scratch, break-run.sh for
    # falsification, never revert/"clean up" a change the agent did not make
    ("plugins/coding-pipeline/agents/coder.md",
     ["$TMPDIR", "break-run.sh", "never revert"], []),
    ("plugins/coding-pipeline/agents/qa.md",
     ["$TMPDIR", "break-run.sh", "never revert"], []),
    ("plugins/coding-pipeline/agents/stress.md",
     ["$TMPDIR", "break-run.sh", "never revert"], []),

    # PROGRESS.md is local memory: git-ignored, never committed state
    ("plugins/coding-pipeline/references/progress-file.md",
     ["git-ignored"], ["committed state"]),
    ("plugins/devtools/skills/handoff/SKILL.md",
     ["git-ignored"], ["committed state"]),

    # README describes what the release ships and never tells the operator to commit PROGRESS.md
    ("README.md",
     ["release-exclude", "/planning", "/validate-code"], ["commit PROGRESS.md"]),

    # standards file: manual skills table, fan-out rules, no roster machinery
    ("plugins/coding-pipeline/CLAUDE.md",
     ["## Skills (invoke manually)", "Skills never run each other",
      "**Read-only fan-out**", "**Never spawn 4+ writers**", "Freeze the shared contract",
      "the gate chain stays in the foreground", "`references/branching.md`",
      "`references/agent-teams.md`", "aliases resolve to the newest model in each family",
      "Load on demand", "scripts/estimate-run.py", "Per-language standards"],
     ["| Roster |", "classify-diff", "Amelia", "Quinn", "/multi-agent"]),

    ("plugins/coding-pipeline/references/thresholds.md",
     ["| Writer subagents per turn | 3 (never 4+)", "| Read-only subagents per turn | 6",
      "every one counts toward the session dispatch budget", "≤ 150 words or one table"],
     ["| Subagents per turn | 3 (never 4+) |"]),

    ("plugins/coding-pipeline/references/branching.md",
     ["feat/{slug}", "fix/{slug}", "Never commit to `main`"], ["worktree add"]),

    ("plugins/coding-pipeline/references/delivery-and-worktree.md",
     ["never dispatch parallel coders into the same tree", "Read-only", "git worktree add", "branching.md"], []),

    ("plugins/coding-pipeline/hooks/dispatch-budget.sh",
     ["caps writers at three per *turn*"], ["caps three per *turn*"]),

    # hooks suggest the manual skills, never instruct the model to act
    ("plugins/coding-pipeline/hooks/pr-review-responder.sh",
     ["/pr-fix"], ["ACTION REQUIRED", "gh pr comment"]),
    ("plugins/coding-pipeline/hooks/delivery-gate.sh",
     ["/validate-code"], ["code-review-gate"]),

    # installers never enable agent teams; no team hooks
    ("install.sh", [], ["AGENT_TEAMS"]),
    ("plugins/coding-pipeline/scripts/install-global.sh", [], ["AGENT_TEAMS"]),
    ("plugins/coding-pipeline/hooks/hooks.json", [], ["TeammateIdle", "TaskCompleted", "TaskCreated"]),

    # Go refresh
    ("plugins/coding-pipeline/references/go-modern-idioms.md",
     ["| Idiom | Min Go |",
      "Apply a row only when the module's `go` directive is at least its Min Go",
      "`wg.Go(f)`", "`errors.AsType[T]`", "JetBrains/go-modern-guidelines"],
     ["json/v2"]),
    ("plugins/coding-pipeline/references/languages/go.md",
     ["[`../go-modern-idioms.md`](../go-modern-idioms.md)",
      "spell it `any`, never `interface{}`",
      "From `go 1.25` start `WaitGroup` goroutines with `wg.Go(f)`",
      "only below `go 1.22`"],
     ["never `interface{}` / `any` in a signature",
      "never at the end of the function; `defer wg.Done()` goes inside the goroutine closure",
      "in leaf tests, with the loop variable captured"]),
    ("plugins/coding-pipeline/references/quality-gate-reference.md",
     ["| Modernize *(advisory)* | `rtk proxy go fix -diff ./...` |",
      "never fails the gate", "`-diff` never rewrites a file"],
     ["(and Stress in parallel)", "go run golang.org/x/tools"]),
    ("plugins/coding-pipeline/references/language-rules-reference.md", [], ["go-modern-idioms"]),

    # latency method and advisory-gate rules
    ("plugins/engineering/skills/performance-profiling/references/optimize-and-benchmark.md",
     ["SetMaxOpenConns", "MaxIdleConnsPerHost", "named invalidation owner",
      "errgroup.WithContext", "off the request path", "Cursor pagination",
      "EXPLAIN ANALYZE", "sync.Pool", "-gcflags=\"-m\""], []),
    ("plugins/engineering/skills/performance-profiling/references/latency-budget.md",
     ["## Trace first", "## Fix by layer", "/observability",
      "sets no millisecond thresholds", "](optimize-and-benchmark.md)"],
     ["20ms", "30ms", "50ms", "15ms", "50 ms", "20 ms"]),
    ("plugins/engineering/skills/performance-profiling/SKILL.md",
     ["`references/latency-budget.md` (trace first, then fix by layer)",
      "references/optimize-and-benchmark.md"], []),
    ("plugins/coding-pipeline/agents/qa.md",
     ["advisory rows never cap the score", "- **Go advisory**: "], []),

    ("CHANGELOG.md",
     ["## [3.0.0]", "## [2.8.0]", "**JetBrains/go-modern-guidelines** (Apache-2.0)",
      "**danicat/skills** (Apache-2.0)", "paraphrased (no text copied)"],
     []),
]

# Frontmatter tools: scoped to the first `---` block, which a substring match cannot do.
# Entries are split on commas outside parentheses so `Agent(a, b)` stays one entry.
def frontmatter_tools(path):
    lines = read(os.path.join(ROOT, path)).split("\n")
    if not lines or lines[0] != "---":
        return None
    for line in lines[1:]:
        if line == "---":
            break
        if line.startswith("tools:"):
            entries, depth, current = [], 0, ""
            for ch in line[len("tools:"):]:
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                if ch == "," and depth == 0:
                    entries.append(current.strip())
                    current = ""
                else:
                    current += ch
            entries.append(current.strip())
            return [e for e in entries if e]
    return None

def tools_check(name, path, required=(), forbidden=()):
    checked["contract"] += 1
    if not os.path.isfile(os.path.join(ROOT, path)):
        err("contract", path, f"FAIL: {name} — file missing")
        return
    tools = frontmatter_tools(path)
    if tools is None:
        errors.append(f"[contract] FAIL: {name} — {path}: no tools: line")
        return
    for t in forbidden:
        if any(e == t or e.startswith(t + "(") for e in tools):
            errors.append(f"[contract] FAIL: {name} — {path}: tools: contains {t}")
    for r in required:
        if not any(e.startswith(r) for e in tools):
            errors.append(f"[contract] FAIL: {name} — {path}: tools: lacks {r}")

# Every pipeline agent declares a tools: allowlist; validators cannot write, so
# implementer != validator is mechanical.
for agent in ["qa", "reviewer", "stress", "verdict", "plan-reviewer",
              "coder", "coder-backend", "coder-frontend", "bug-investigator"]:
    tools_check("contract_agent_tools_allowlist", f"plugins/coding-pipeline/agents/{agent}.md")
for agent in ["qa", "reviewer", "stress", "verdict", "plan-reviewer"]:
    tools_check("contract_validators_cannot_edit",
        f"plugins/coding-pipeline/agents/{agent}.md", forbidden=("Edit", "Write"))

for path, must_contain, must_not in CONTRACT:
    checked["contract"] += 1
    full = os.path.join(ROOT, path)
    if not os.path.isfile(full):
        err("contract", path, "file missing")
        continue
    text = read(full)
    for phrase in must_contain:
        if phrase not in text:
            err("contract", path, f"must contain '{phrase}'")
    for phrase in must_not:
        if phrase in text:
            err("contract", path, f"must not contain '{phrase}'")

# every agent except rote-* declares when it loads references (load-on-demand table)
adir = os.path.join(ROOT, "plugins", "coding-pipeline", "agents")
for fn in sorted(os.listdir(adir)):
    if fn.endswith(".md") and not fn.startswith("rote-"):
        checked["contract"] += 1
        if "load on demand" not in read(os.path.join(adir, fn)).lower():
            err("contract", f"plugins/coding-pipeline/agents/{fn}", "must contain 'load on demand' (references table)")

# handoff's own copy of progress-file.md is optional, but if present must stay "git-ignored".
hp = "plugins/devtools/skills/handoff/references/progress-file.md"
if os.path.isfile(os.path.join(ROOT, hp)):
    checked["contract"] += 1
    ht = read(os.path.join(ROOT, hp))
    if "git-ignored" not in ht or "committed state" in ht:
        err("contract", hp, "must say 'git-ignored' and never 'committed state'")

# ── 8. sweep: no persona names, no pointers to removed skills or machinery ──
PERSONAS = re.compile(r"\b(Amelia|Quinn|Priya|Winston|Tyler)\b")
REMOVED = re.compile(r"(?<![\w.])/(multi-agent|task|analysis|architecture|quality-gate|code-review-gate|pr-review|checkcomments|bug-fix)(?![\w.-])"
                     r"|orchestrator-bash-guard|delivery-state\.sh|`release/\{slug\}")
sweep = [os.path.join(ROOT, "README.md")]
for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "plugins")):
    sweep += [os.path.join(dirpath, f) for f in filenames if f.endswith((".md", ".json", ".sh"))]
for path in sweep:
    if not os.path.isfile(path) or f"{os.sep}scripts{os.sep}" in path:   # scripts/ are frozen, not swept
        continue
    checked["contract"] += 1
    text = read(path)
    for rx, what in ((PERSONAS, "persona name"), (REMOVED, "reference to a removed skill or file")):
        hit = rx.search(text)
        if hit:
            err("sweep", rel(path), f"{what} '{hit.group(0)}'")

print(f"checked: {checked}")
if errors:
    print(f"\n{len(errors)} wiring problem(s):\n")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("wiring OK")
