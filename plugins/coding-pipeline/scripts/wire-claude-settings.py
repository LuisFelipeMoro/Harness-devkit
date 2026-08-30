#!/usr/bin/env python3
"""Merge the devkit's hooks into ~/.claude/settings.json.

A flat install copies the hook scripts into ~/.claude/hooks/, but Claude Code only
runs them if settings.json points at them. That wiring used to be printed for the
operator to paste by hand, which meant a machine could have every guard installed
and none of them active.

The hook graph is read from the plugin's own hooks.json rather than restated here,
so the two can't drift: ${CLAUDE_PLUGIN_ROOT} is rewritten to the install target.

Ownership: an entry is "ours" when its command references a script under
~/.claude/hooks/ that either ships with this devkit or no longer exists on disk.
That second clause is what heals a rename — the stale entry is dropped instead of
accumulating beside its replacement. Anything else in settings.json is left alone.

Usage: wire-claude-settings.py <plugin-dir> [--home DIR] [--dry-run]
"""
import json
import os
import re
import sys


def load_hook_graph(plugin_dir, hooks_home):
    """Read hooks.json and rebind ${CLAUDE_PLUGIN_ROOT} to the flat install path."""
    with open(os.path.join(plugin_dir, "hooks", "hooks.json"), encoding="utf-8") as f:
        raw = f.read()
    raw = raw.replace("${CLAUDE_PLUGIN_ROOT}/hooks", hooks_home)
    return json.loads(raw).get("hooks", {})


def shipped_scripts(plugin_dir):
    hooks_dir = os.path.join(plugin_dir, "hooks")
    return {f for f in os.listdir(hooks_dir) if f.endswith(".sh")}


def command_of(hook):
    return hook.get("command", "") if isinstance(hook, dict) else ""


def is_ours(entry, hooks_home, shipped):
    """True when this settings.json entry is a devkit hook — current or stale."""
    for hook in entry.get("hooks", []):
        cmd = command_of(hook)
        m = re.search(re.escape(hooks_home) + r"/([A-Za-z0-9._-]+\.sh)", cmd)
        if not m:
            continue
        name = m.group(1)
        if name in shipped:
            return True
        # points into our hooks dir at something we no longer ship — stale, drop it
        if not os.path.exists(os.path.join(hooks_home, name)):
            return True
    return False


def merge(settings, graph, hooks_home, shipped):
    existing = settings.get("hooks")
    if not isinstance(existing, dict):
        existing = {}
    merged = dict(existing)
    for event, entries in graph.items():
        kept = [e for e in merged.get(event, []) if not is_ours(e, hooks_home, shipped)]
        merged[event] = kept + entries
    # events we no longer ship must lose their stale devkit entries too
    for event in list(merged):
        if event in graph:
            continue
        kept = [e for e in merged[event] if not is_ours(e, hooks_home, shipped)]
        if kept:
            merged[event] = kept
        else:
            del merged[event]
    settings["hooks"] = merged
    return settings


def main():
    args = [a for a in sys.argv[1:]]
    dry_run = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    home = os.path.expanduser("~")
    if "--home" in args:
        i = args.index("--home")
        home = args[i + 1]
        del args[i:i + 2]
    if not args:
        print("usage: wire-claude-settings.py <plugin-dir> [--home DIR] [--dry-run]",
              file=sys.stderr)
        return 2
    plugin_dir = args[0]

    claude_dir = os.path.join(home, ".claude")
    hooks_home = os.path.join(claude_dir, "hooks")
    settings_path = os.path.join(claude_dir, "settings.json")

    try:
        graph = load_hook_graph(plugin_dir, hooks_home)
        shipped = shipped_scripts(plugin_dir)
    except OSError as exc:
        print(f"cannot read the plugin's hook graph: {exc}", file=sys.stderr)
        return 1

    settings = {}
    if os.path.exists(settings_path):
        try:
            with open(settings_path, encoding="utf-8") as f:
                settings = json.load(f)
        except (json.JSONDecodeError, OSError) as exc:
            # Refuse rather than overwrite: this file holds the operator's
            # permissions and model config, and a rewrite would destroy it.
            print(f"settings.json is not valid JSON ({exc}) — refusing to rewrite it.",
                  file=sys.stderr)
            print("Fix or move the file, then re-run the installer.", file=sys.stderr)
            return 1
        if not isinstance(settings, dict):
            print("settings.json is not a JSON object — refusing to rewrite it.",
                  file=sys.stderr)
            return 1

    merge(settings, graph, hooks_home, shipped)
    count = sum(len(v) for v in settings["hooks"].values())

    if dry_run:
        print(f"would wire {count} hook entr{'y' if count == 1 else 'ies'} into {settings_path}")
        return 0

    os.makedirs(claude_dir, exist_ok=True)
    tmp = settings_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.replace(tmp, settings_path)
    print(f"✓ settings.json — {count} hook entries wired")
    return 0


if __name__ == "__main__":
    sys.exit(main())
