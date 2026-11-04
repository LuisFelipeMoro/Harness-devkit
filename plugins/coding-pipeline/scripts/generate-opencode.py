#!/usr/bin/env python3
"""Generate the OpenCode flavour of the devkit's skills, references and agents.

The Claude Code and Codex installs copy the devkit's Markdown as-is, but OpenCode
has its own tool names, its own instruction file (AGENTS.md) and its own paths.
This engine walks the source tree, applies the frozen transform-rule table and the
two-pass dispatch-prose rewrite, and writes the result under a target directory:

  <target>/skills/<name>/SKILL.md        one per plugins/*/skills/*/SKILL.md
  <target>/skills/<name>/references/<rel>.md   one per plugins/*/skills/*/references/**/*.md
  <target>/devkit/references/<rel>.md    one per plugins/*/references/**/*.md
  <target>/agents/<name>.md              one per plugins/coding-pipeline/agents/*.md
                                         (coder.md is merged into its two overlays,
                                         not emitted on its own)
  <target>/devkit/AGENTS.md              CLAUDE.md, transformed, plus the OpenCode Guide
  <target>/devkit/git-hooks/*            copied unchanged
  <target>/devkit/scripts/...            verify/, estimate-run.py, harness-metrics.py, unchanged
  <target>/devkit/commands.json.sample   a static, hand-mergeable snippet — never merged
  <target>/.devkit-opencode-manifest.json  path -> sha256 of every file this engine wrote

Every write goes through WriteGuard. A file already at the target is overwritten only when
the manifest records it as devkit-owned and its bytes still match the recorded hash; otherwise
it is kept and reported. opencode.json is never read or written.

Usage: generate-opencode.py --target DIR --model-cheap P/M --model-standard P/M
           --model-deep P/M [--plugins-root DIR]
Exit 0 — every source file written (kept files are reported, not errors).
Exit 1 — a source file could not be read or parsed, two sources map to one output path,
         or the manifest is unreadable.
Exit 2 — bad arguments.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
from collections.abc import Iterator
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

DEVKIT_DIR = "devkit"
MANIFEST_NAME = ".devkit-opencode-manifest.json"
MANIFEST_VERSION = 1
HEX_SHA256 = re.compile(r"[0-9a-f]{64}")
# Directories and files copied unchanged from plugins/coding-pipeline/ into devkit/.
GIT_HOOKS_SUBDIR = "git-hooks"
SCRIPTS_SUBDIR = "scripts"
SCRIPT_SOURCES = ("verify", "estimate-run.py", "harness-metrics.py")
# Appended to the transformed CLAUDE.md. The S3 finding (harness-adapter.md) showed OpenCode
# auto-invokes skills on trigger phrases regardless of disable-model-invocation, so the
# manual-skill rule is stated here as an imperative the model must follow.
OPENCODE_GUIDE = """## OpenCode Guide

This file is the OpenCode flavour of the standards above. Everything in it applies under
OpenCode except where this section says otherwise.

- **A skill is only ever started by the user.** Never start a skill yourself, and never load one
  because a phrase in the user's message resembles its description. OpenCode can auto-invoke a skill
  on a trigger phrase even when the skill sets `disable-model-invocation: true`, so this rule is a
  convention you must follow, not a setting the tool enforces. If a skill looks relevant, name it
  and wait for the user to start it.
- **Slash commands are not automatic.** Skills are not registered as slash commands. The snippet in
  `devkit/commands.json.sample` is for the operator to merge by hand into their own `opencode.json`;
  nothing in this install writes that file.
"""
COMMANDS_SAMPLE = """{
  "command": {
    "devkit-help": {
      "template": "Run the devkit-help skill with: $ARGUMENTS",
      "description": "Show what the devkit has, or one skill's usage"
    },
    "retro": {
      "template": "Run the retro skill with: $ARGUMENTS",
      "description": "Retrospective on a session; propose environment improvements"
    }
  }
}
"""
WRITE, KEPT_MODIFIED, KEPT_NOT_DEVKIT = "write", "kept-modified", "kept-not-devkit"

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


def decide_write(prior: dict[str, str], rel: str, on_disk: str | None) -> str:
    """Pure guard: may the generator overwrite `rel`, given the previous manifest and the file's hash on disk.

    No file at the path -> write. A path the manifest does not own -> keep (not the devkit's).
    An owned path whose bytes no longer match the recorded hash -> keep (hand-edited since install).
    Only an owned path whose bytes still match is overwritten.
    """
    if on_disk is None:
        return WRITE
    if rel not in prior:
        return KEPT_NOT_DEVKIT
    return WRITE if on_disk == prior[rel] else KEPT_MODIFIED


def _sha256_if_file(path: Path) -> str | None:
    if not path.is_file():
        return None
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _default_mode() -> int:
    current = os.umask(0)
    os.umask(current)
    return 0o666 & ~current


def _atomic_write(dest: Path, data: bytes, mode: int | None) -> None:
    """Write to a temp file beside dest, then rename it into place (AC11).

    A kill mid-write leaves the old file intact or the temp file behind; a reader never sees a
    truncated or partial destination. os.replace is atomic on POSIX.
    """
    fd, tmp_name = tempfile.mkstemp(dir=dest.parent, prefix=f".{dest.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp_name, mode if mode is not None else _default_mode())
        os.replace(tmp_name, dest)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp_name)
        raise


@contextlib.contextmanager
def _target_lock(target: Path) -> Iterator[None]:
    """Hold an exclusive lock on the target for the whole generate + manifest-write sequence (SEC-5).

    Without it, two concurrent runs each read the manifest before the other finished, and the
    last process to write the manifest erases the other's bookkeeping. The lock is taken on the
    target directory's own handle, so no lockfile is created inside the target: every file there
    stays one the manifest accounts for.
    """
    fd = os.open(target, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


class WriteGuard:
    """The one place the generator writes a file. Every engine calls write(), so the collision guard covers all of them."""

    def __init__(self, target: Path, prior: dict[str, str]) -> None:
        self.target = target
        self.prior = dict(prior)
        self.written: dict[str, str] = {}
        self.kept: list[str] = []

    def write(
        self, rel: str, data: bytes, mode: int | None = None, *, trusted_owner: bool = False
    ) -> ManifestEntry | None:
        """trusted_owner is set only for the manifest itself: its ownership is already established
        by read_manifest, and it is never listed among the entries it records."""
        dest = self.target / rel
        # Checked before anything follows the path: a symlink at a devkit-owned path is never written through (SEC-6).
        if dest.is_symlink():
            self._keep_not_devkit(rel)
            return None
        # SEC-7: every directory between the target root and dest.parent is checked, so a symlinked
        # agents/, devkit/ or skills/<name>/ is never created through or written into.
        symlinked = _first_symlink_component(self.target, Path(rel).parent.as_posix())
        if symlinked is not None:
            self._keep_not_devkit(symlinked)
            return None
        action = WRITE if trusted_owner else decide_write(self.prior, rel, _sha256_if_file(dest))
        if action == KEPT_MODIFIED:
            self.kept.append(f"kept (modified since install): {rel}")
            return None
        if action == KEPT_NOT_DEVKIT:
            self._keep_not_devkit(rel)
            return None
        dest.parent.mkdir(parents=True, exist_ok=True)
        _atomic_write(dest, data, mode)
        sha = hashlib.sha256(data).hexdigest()
        if not trusted_owner:
            self.written[rel] = sha
        return ManifestEntry(path=rel, sha256=sha)

    def _keep_not_devkit(self, rel: str) -> None:
        # One line per offending path: a symlinked directory skips every file under it, and each would repeat it.
        line = f"kept (not the devkit's): {rel}"
        if line not in self.kept:
            self.kept.append(line)

    def manifest_entries(self) -> list[ManifestEntry]:
        # Prior entries carry over: a kept-modified file stays devkit-owned under its old hash,
        # and a file the devkit no longer generates keeps its ownership (no pruning is performed).
        merged = {**self.prior, **self.written}
        return [ManifestEntry(path=p, sha256=merged[p]) for p in sorted(merged)]


def read_manifest(target: Path) -> dict[str, str]:
    path = target / MANIFEST_NAME
    # A symlink is never read through (SEC-6): it is not a manifest this devkit owns.
    if path.is_symlink() or not path.is_file():
        return {}
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{path}: manifest unreadable ({exc}); fix or delete it") from exc
    version = doc.get("version") if isinstance(doc, dict) else None
    if not isinstance(version, int) or isinstance(version, bool) or version != MANIFEST_VERSION:
        raise ValueError(f"{path}: not a version {MANIFEST_VERSION} manifest; fix or delete it")
    raw = doc.get("entries")
    if not isinstance(raw, list):
        raise ValueError(f"{path}: manifest has no entries list")
    prior: dict[str, str] = {}
    for item in raw:
        if (
            not isinstance(item, dict)
            or not isinstance(item.get("path"), str)
            or not isinstance(item.get("sha256"), str)
            or not HEX_SHA256.fullmatch(item["sha256"])
        ):
            raise ValueError(f"{path}: malformed manifest entry {item!r}")
        prior[item["path"]] = item["sha256"]
    return prior


def write_manifest(guard: WriteGuard) -> None:
    entries = guard.manifest_entries()
    doc = {
        "version": MANIFEST_VERSION,
        "entries": [{"path": e.path, "sha256": e.sha256} for e in sorted(entries, key=lambda e: e.path)],
    }
    data = (json.dumps(doc, indent=2, sort_keys=True) + "\n").encode("utf-8")
    guard.write(MANIFEST_NAME, data, trusted_owner=True)


def _emit(guard: WriteGuard, entries: list[ManifestEntry], rel: str, text: str) -> None:
    entry = guard.write(rel, text.encode("utf-8"))
    if entry is not None:
        entries.append(entry)


def _first_symlink_component(root: Path, rel_dir: str) -> str | None:
    """Return the first directory under root/rel_dir that is a symlink, broken or valid, else None (SEC-7).

    is_dir()/exists() disagree for a broken link, so only is_symlink() is trusted here. Every
    component is checked, so a symlink at any level of the chain is seen, not just the last.
    The returned path is relative to root, so the kept line names the link itself (e.g. `agents`).
    """
    current = root
    for part in Path(rel_dir).parts:
        current = current / part
        if current.is_symlink():
            return current.relative_to(root).as_posix()
    return None


def _first_symlink_ancestor(target: Path) -> Path | None:
    """Return the first symlinked directory above target on the path as given, else None (SEC-9).

    Every prefix from the anchor down to target's parent is lstat-ed. Nothing is resolved:
    resolve() would follow a symlink and hide it. The leaf is excluded because SEC-8 owns it.
    A relative target is anchored at the physical cwd, so a symlink inside the relative part is still seen.
    """
    as_given = target if target.is_absolute() else Path.cwd() / target
    current = Path(as_given.anchor)
    for part in as_given.parts[1:-1]:
        current = current / part
        if current.is_symlink():
            return current
    return None


def generate_skills(
    plugins_root: Path, guard: WriteGuard, overrides: dict[str, Path]
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

            skill_refs_dir = source.parent / "references"
            ref_sources = sorted(skill_refs_dir.rglob("*.md")) if skill_refs_dir.is_dir() else []
            ref_rels: list[str] = []
            for ref in ref_sources:
                ref_rel = f"skills/{name}/references/" + ref.relative_to(skill_refs_dir).as_posix()
                if ref_rel in seen:
                    raise ValueError(f"skill reference collision: {ref_rel} from {seen[ref_rel]} and {ref}")
                seen[ref_rel] = ref
                ref_rels.append(ref_rel)

            if name in overrides:
                text = overrides[name].read_text(encoding="utf-8")
            else:
                text = apply_transforms(source.read_text(encoding="utf-8"))
            _emit(guard, entries, rel, text)

            for ref, ref_rel in zip(ref_sources, ref_rels):
                _emit(guard, entries, ref_rel, apply_transforms(ref.read_text(encoding="utf-8")))

    for plugin in iter_plugin_dirs(plugins_root):
        refs_dir = plugin / "references"
        for source in sorted(refs_dir.rglob("*.md")):
            rel = "devkit/references/" + source.relative_to(refs_dir).as_posix()
            if rel in seen:
                raise ValueError(f"reference output collision: {rel} from {seen[rel]} and {source}")
            seen[rel] = source
            _emit(guard, entries, rel, apply_transforms(source.read_text(encoding="utf-8")))

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


def generate_agents(agents_dir: Path, guard: WriteGuard, model_map: dict[str, str]) -> list[ManifestEntry]:
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
        _emit(guard, entries, rel, front + "\n" + apply_transforms(body))
    return entries


def _copy_source(guard: WriteGuard, entries: list[ManifestEntry], src: Path, rel: str) -> None:
    if not src.is_file():
        raise ValueError(f"devkit source file missing: {src}")
    entry = guard.write(rel, src.read_bytes(), mode=src.stat().st_mode & 0o777)
    if entry is not None:
        entries.append(entry)


def generate_devkit(plugins_root: Path, guard: WriteGuard) -> list[ManifestEntry]:
    """devkit/AGENTS.md, the copied git-hooks and scripts, and the static commands sample. Never opencode.json."""
    core = plugins_root / "coding-pipeline"
    entries: list[ManifestEntry] = []

    claude_md = core / "CLAUDE.md"
    if not claude_md.is_file():
        raise ValueError(f"standards file {claude_md} not found")
    agents_md = apply_transforms(claude_md.read_text(encoding="utf-8")).rstrip("\n") + "\n\n" + OPENCODE_GUIDE
    _emit(guard, entries, f"{DEVKIT_DIR}/AGENTS.md", agents_md)

    hooks_dir = core / GIT_HOOKS_SUBDIR
    if not hooks_dir.is_dir():
        raise ValueError(f"git-hooks directory {hooks_dir} not found")
    for src in sorted(p for p in hooks_dir.iterdir() if p.is_file()):
        _copy_source(guard, entries, src, f"{DEVKIT_DIR}/{GIT_HOOKS_SUBDIR}/{src.name}")

    scripts_dir = core / SCRIPTS_SUBDIR
    for name in SCRIPT_SOURCES:
        src = scripts_dir / name
        if src.is_dir():
            for file in sorted(p for p in src.rglob("*") if p.is_file()):
                rel = f"{DEVKIT_DIR}/{SCRIPTS_SUBDIR}/{name}/{file.relative_to(src).as_posix()}"
                _copy_source(guard, entries, file, rel)
        else:
            _copy_source(guard, entries, src, f"{DEVKIT_DIR}/{SCRIPTS_SUBDIR}/{name}")

    _emit(guard, entries, f"{DEVKIT_DIR}/commands.json.sample", COMMANDS_SAMPLE)
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
    except SystemExit as exc:
        # argparse exits 0 for -h/--help and 2 for a bad argument; keep whichever it chose.
        return 0 if exc.code is None else exc.code

    # SEC-8: the whole destination being a symlink leaves no partial install to report, so refuse outright.
    # This runs before mkdir, the lock and any read, because mkdir follows the link and would write through it.
    if args.target.is_symlink():
        print(
            f"generate-opencode: --target is a symlink: {args.target} — refusing to install through it",
            file=sys.stderr,
        )
        return 1

    # SEC-9: a symlink anywhere above the target means mkdir would write through it. Checked here, once,
    # for --target, --project and the default path alike, because all three arrive as this one argument.
    try:
        ancestor = _first_symlink_ancestor(args.target)
    except OSError as exc:
        print(f"generate-opencode: could not check the ancestors of --target {args.target}: {exc}", file=sys.stderr)
        return 1
    if ancestor is not None:
        print(
            f"generate-opencode: --target ancestor is a symlink: {ancestor} — refusing to install through it",
            file=sys.stderr,
        )
        return 1

    model_map = {"cheap": args.model_cheap, "standard": args.model_standard, "deep": args.model_deep}
    try:
        args.target.mkdir(parents=True, exist_ok=True)
        # The lock is taken before the manifest is read, so a concurrent run's manifest is never stale (SEC-5).
        with _target_lock(args.target):
            guard = WriteGuard(args.target, read_manifest(args.target))
            entries: list[ManifestEntry] = []
            try:
                entries += generate_skills(args.plugins_root, guard, discover_overrides(args.plugins_root))
                entries += generate_agents(args.plugins_root / AGENTS_SUBDIR, guard, model_map)
                entries += generate_devkit(args.plugins_root, guard)
            finally:
                # Record every file actually written, even on a failed run, so the next run still owns them.
                write_manifest(guard)
    except (OSError, ValueError) as exc:
        print(f"generate-opencode: {exc}", file=sys.stderr)
        return 1

    for line in guard.kept:
        print(line)
    print(f"generate-opencode: wrote {len(entries)} files under {args.target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
