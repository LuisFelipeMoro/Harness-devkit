#!/usr/bin/env python3
"""Generate the OpenCode flavour of the devkit's skills, references and agents.

The Claude Code and Codex installs copy the devkit's Markdown as-is, but OpenCode
has its own tool names, its own instruction file (AGENTS.md) and its own paths.
This engine walks the source tree, applies the frozen transform-rule table and the
two-pass dispatch-prose rewrite, and writes the result under a target directory:

  <target>/skills/<name>/SKILL.md        one per plugins/*/skills/*/SKILL.md
  <target>/devkit/references/<rel>.md    one per plugins/*/references/**/*.md
  <target>/agents/<name>.md              one per plugins/coding-pipeline/agents/*.md
                                         (coder.md is merged into its two overlays,
                                         not emitted on its own)

Usage: generate-opencode.py --target DIR --model-cheap P/M --model-standard P/M
           --model-deep P/M [--plugins-root DIR]
Exit 0 — every source file written.
Exit 1 — a source file could not be read or parsed, or two sources map to one output path.
Exit 2 — bad arguments.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PLUGINS_ROOT = Path(__file__).resolve().parents[2]
OVERRIDES_SUBDIR = Path("coding-pipeline") / "opencode" / "overrides"
AGENTS_SUBDIR = Path("coding-pipeline") / "agents"
CORE_AGENT = "coder"
OVERLAY_AGENTS = ("coder-backend", "coder-frontend")
TIERS = ("cheap", "standard", "deep")
# Source `model:` alias -> the operator-supplied tier whose provider/model string is written.
MODEL_TIER_FOR_SOURCE = {"haiku": "cheap", "sonnet": "standard", "opus": "deep"}
READ_WRITE_TOOLS = ("Edit", "Write", "Patch")
DISPATCH_ALIASES = {"Explore": "explore", "general-purpose": "general"}

# Frozen transform-rule table (Pass 1), applied in table order as plain substitutions.
# The dispatch rows are deliberately absent: Pass 2 (rewrite_dispatch) handles them.
# The `~/.claude/projects/...` row is deliberately absent: it is an override, not a transform.
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

# Pass 2: a `subagent_type:` clause, its `|`-joined alternatives, and an adjacent
# `model:` clause or comma. Not line-anchored. `[\s`]` crosses a markdown code-span
# backtick that closes the value, as in `subagent_type: "reviewer"`, `model: "sonnet"`.
DISPATCH_RE = re.compile(
    r'subagent_type:\s*((?:"[^"]+"\s*\|\s*)*"[^"]+")([\s`]*,)?([\s`]*model:\s*"[^"]+")?([\s`]*,)?'
)
# A same-line `# comment` directly after a dispatch clause (the bugfix conditional-dispatch shape).
TRAILING_COMMENT_RE = re.compile(r"[ \t]*#[ \t]*([^\n]*)")


@dataclass(frozen=True)
class ManifestEntry:
    path: str  # POSIX path relative to the target directory
    sha256: str  # 64 hex chars of the bytes written


def _alias(name: str) -> str:
    return DISPATCH_ALIASES.get(name, name)


def _dispatch_prose(values: list[str], comment: str | None) -> str:
    if len(values) == 1:
        return f'"dispatch the `{values[0]}` agent"'
    quoted = [f"`{v}`" for v in values]
    listing = ", ".join(quoted[:-1]) + f", or {quoted[-1]}"
    if comment:
        return f'"dispatch whichever of the {listing} agents fits — {comment}"'
    return f'"dispatch whichever of the {listing} agents best fits the task"'


def rewrite_dispatch(text: str) -> str:
    out: list[str] = []
    pos = 0
    for match in DISPATCH_RE.finditer(text):
        end = match.end()
        comment = None
        tail = TRAILING_COMMENT_RE.match(text, end)
        if tail:
            comment = tail.group(1).strip() or None
            end = tail.end()
        values = [_alias(v.strip().strip('"').strip()) for v in match.group(1).split("|")]
        comma = match.group(2) or match.group(4)
        out.append(text[pos : match.start()])
        out.append(_dispatch_prose(values, comment) + ("," if comma else ""))
        pos = end
    out.append(text[pos:])
    return "".join(out)


def apply_transforms(text: str) -> str:
    for old, new in TRANSFORMS:
        text = text.replace(old, new)
    return rewrite_dispatch(text)


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


def split_frontmatter(text: str, source: Path) -> tuple[dict[str, str], str]:
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        raise ValueError(f"{source}: missing frontmatter")
    try:
        close = lines.index("---", 1)
    except ValueError as exc:
        raise ValueError(f"{source}: unterminated frontmatter") from exc
    fields: dict[str, str] = {}
    for line in lines[1:close]:
        if not line.strip():
            continue
        key, sep, value = line.partition(":")
        if not sep:
            raise ValueError(f"{source}: frontmatter line without a key: {line!r}")
        fields[key.strip()] = value.strip()
    body = "\n".join(lines[close + 1 :]).lstrip("\n")
    return fields, body


def build_agent_frontmatter(source: dict[str, str], model_map: dict[str, str]) -> dict:
    name = source.get("name", "")
    if not name:
        raise ValueError("agent frontmatter has no name")
    if not source.get("description"):
        raise ValueError(f"agent {name}: frontmatter has no description")
    src_model = source.get("model", "")
    tier = MODEL_TIER_FOR_SOURCE.get(src_model)
    if tier is None:
        raise ValueError(f"agent {name}: unmapped source model {src_model!r}")
    tools = [t.strip() for t in source.get("tools", "").split(",") if t.strip()]
    # Fail closed: an agent with no Edit/Write/Patch tool, or no tools field at all, is read-only.
    read_only = not any(t in READ_WRITE_TOOLS for t in tools)
    writable = not read_only
    return {
        "name": name,
        "description": apply_transforms(source["description"]),
        "mode": "subagent",
        "model": model_map[tier],
        "permission": {"edit": "allow" if writable else "deny"},
        "tools": {"edit": writable, "write": writable, "patch": writable},
    }


def _yaml_scalar(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return json.dumps(str(value), ensure_ascii=False)


def render_frontmatter(fields: dict) -> str:
    lines = ["---"]
    for key, value in fields.items():
        if isinstance(value, dict):
            lines.append(f"{key}:")
            lines.extend(f"  {k}: {_yaml_scalar(v)}" for k, v in value.items())
        else:
            lines.append(f"{key}: {_yaml_scalar(value)}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def generate_agents(agents_dir: Path, target: Path, model_map: dict[str, str]) -> list[ManifestEntry]:
    for tier in TIERS:
        if not model_map.get(tier):
            raise ValueError(f"model tier {tier!r} is not set")
    core_path = agents_dir / f"{CORE_AGENT}.md"
    if not core_path.is_file():
        raise ValueError(f"core agent {core_path} not found")
    _, core_body = split_frontmatter(core_path.read_text(encoding="utf-8"), core_path)

    entries: list[ManifestEntry] = []
    for source in sorted(agents_dir.glob("*.md")):
        if source.stem == CORE_AGENT:
            continue
        fields, body = split_frontmatter(source.read_text(encoding="utf-8"), source)
        if source.stem in OVERLAY_AGENTS:
            body = core_body.rstrip("\n") + "\n\n" + body
        front = render_frontmatter(build_agent_frontmatter(fields, model_map))
        rel = f"agents/{source.stem}.md"
        entries.append(_write(target, rel, front + "\n" + apply_transforms(body)))
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
    parser.add_argument("--model-cheap", required=True)
    parser.add_argument("--model-standard", required=True)
    parser.add_argument("--model-deep", required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2

    model_map = {"cheap": args.model_cheap, "standard": args.model_standard, "deep": args.model_deep}
    try:
        args.target.mkdir(parents=True, exist_ok=True)
        entries = generate_skills(args.plugins_root, args.target, discover_overrides(args.plugins_root))
        entries += generate_agents(args.plugins_root / AGENTS_SUBDIR, args.target, model_map)
    except (OSError, ValueError) as exc:
        print(f"generate-opencode: {exc}", file=sys.stderr)
        return 1

    print(f"generate-opencode: wrote {len(entries)} files under {args.target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
