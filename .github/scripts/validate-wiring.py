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
checked = {"manifest": 0, "hook": 0, "link": 0, "agent": 0, "skill": 0}


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

print(f"checked: {checked}")
if errors:
    print(f"\n{len(errors)} wiring problem(s):\n")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("wiring OK")
