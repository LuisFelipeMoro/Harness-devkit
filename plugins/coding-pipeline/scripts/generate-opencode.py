#!/usr/bin/env python3
"""Generate the OpenCode flavour of the devkit's skills and references.

The Claude Code and Codex installs copy the devkit's Markdown as-is, but OpenCode
has its own tool names, its own instruction file (AGENTS.md) and its own paths.
This engine walks the source tree, rewrites the non-dispatch terms in the frozen
transform-rule table, and writes the result under a target directory:

  <target>/skills/<name>/SKILL.md        one per plugins/*/skills/*/SKILL.md
  <target>/devkit/references/<rel>.md    one per plugins/*/references/**/*.md

Dispatch clauses (`subagent_type:`) are NOT rewritten here; that two-pass rewrite
belongs to the agents engine, so skill and reference text that still carries one
passes through unchanged for now.

Usage: generate-opencode.py --target DIR [--plugins-root DIR]
Exit 0 — every source file written.
Exit 1 — a source file could not be read, or two sources map to one output path.
Exit 2 — bad arguments.
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PLUGINS_ROOT = Path(__file__).resolve().parents[2]
OVERRIDES_SUBDIR = Path("coding-pipeline") / "opencode" / "overrides"

# Frozen transform-rule table, applied in table order as plain substitutions.
# The dispatch rows and the `~/.claude/projects/...` row are deliberately absent:
# the first belong to the agents engine, the second is an override, not a transform.
TRANSFORMS: tuple[tuple[str, str], ...] = (
    ("~/.claude/", "<devkit>/"),
    ("plugins/coding-pipeline/", "<devkit>/"),
    ("coding-pipeline/", "<devkit>/"),
    ("CLAUDE.md", "AGENTS.md"),
    ("Claude Code", "OpenCode"),
    ("Claude", "OpenCode"),
    ("${CLAUDE_PLUGIN_ROOT}", "<devkit>"),
    ("coding-pipeline:", ""),
    ("AskUserQuestion", "question"),
    ("TaskCreate", "todowrite"),
    ("TaskUpdate", "todowrite"),
)


@dataclass(frozen=True)
class ManifestEntry:
    path: str  # POSIX path relative to the target directory
    sha256: str  # 64 hex chars of the bytes written


def apply_transforms(text: str) -> str:
    for old, new in TRANSFORMS:
        text = text.replace(old, new)
    return text


def iter_plugin_dirs(plugins_root: Path) -> list[Path]:
    return sorted(p for p in plugins_root.iterdir() if p.is_dir())


def _write(target: Path, rel: str, text: str) -> ManifestEntry:
    data = text.encode("utf-8")
    dest = target / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return ManifestEntry(path=rel, sha256=hashlib.sha256(data).hexdigest())


def generate_skills(
    plugins_root: Path, target: Path, overrides: dict[str, Path]
) -> list[ManifestEntry]:
    entries: list[ManifestEntry] = []
    seen: dict[str, Path] = {}

    for plugin in iter_plugin_dirs(plugins_root):
        for source in sorted((plugin / "skills").glob("*/SKILL.md")):
            name = source.parent.name
            rel = f"skills/{name}/SKILL.md"
            if rel in seen:
                raise ValueError(f"skill output collision: {rel} from {seen[rel]} and {source}")
            seen[rel] = source
            if name in overrides:
                text = overrides[name].read_text(encoding="utf-8")
            else:
                text = apply_transforms(source.read_text(encoding="utf-8"))
            entries.append(_write(target, rel, text))

    for plugin in iter_plugin_dirs(plugins_root):
        refs_dir = plugin / "references"
        for source in sorted(refs_dir.rglob("*.md")):
            rel = "devkit/references/" + source.relative_to(refs_dir).as_posix()
            if rel in seen:
                raise ValueError(f"reference output collision: {rel} from {seen[rel]} and {source}")
            seen[rel] = source
            entries.append(_write(target, rel, apply_transforms(source.read_text(encoding="utf-8"))))

    return entries


def discover_overrides(plugins_root: Path) -> dict[str, Path]:
    overrides_dir = plugins_root / OVERRIDES_SUBDIR
    if not overrides_dir.is_dir():
        return {}
    return {p.stem: p for p in sorted(overrides_dir.glob("*.md"))}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="generate-opencode.py", description=__doc__.split("\n")[0])
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--plugins-root", type=Path, default=DEFAULT_PLUGINS_ROOT)
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2

    try:
        args.target.mkdir(parents=True, exist_ok=True)
        entries = generate_skills(args.plugins_root, args.target, discover_overrides(args.plugins_root))
    except (OSError, ValueError) as exc:
        print(f"generate-opencode: {exc}", file=sys.stderr)
        return 1

    print(f"generate-opencode: wrote {len(entries)} files under {args.target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
