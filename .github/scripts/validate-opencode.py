#!/usr/bin/env python3
"""OpenCode sensor: manifest integrity, model-tier rejection, secret/network and timing.

generate-opencode.py is the only producer of the OpenCode tree, and the manifest it writes is
the only record of which files the devkit owns. A manifest that lists a missing file, a stale
hash, or the wrong shape silently breaks the next re-install's collision guard, so this checks
the manifest against the bytes on disk. The generator must also refuse a missing model tier,
never read a stray .env/.envrc, never need the network, and finish a full run in under 5 s.

Each test_* function is one Test Case row of the OpenCode plan (T8). Failure lines start with
"FAIL: <test name>" so that break-run.sh can prove a falsifying mutation failed each row for
its own assertion.

Run: python3 .github/scripts/validate-opencode.py
Exit 0 — every check ran and passed (an unmeasured check is printed as NOTE, never as a pass).
Exit 1 — at least one check failed.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(ROOT, "plugins", "coding-pipeline", "scripts", "generate-opencode.py")
INSTALLER = os.path.join(ROOT, "plugins", "coding-pipeline", "scripts", "install-opencode.sh")
MANIFEST_NAME = ".devkit-opencode-manifest.json"
# Real-shaped provider/model strings: the generator writes them verbatim, and the installer
# validates their shape, so these exercise the same path an operator's values would take.
TIERS = [
    "--model-cheap", "anthropic/claude-haiku-4-5",
    "--model-standard", "anthropic/claude-sonnet-4-5",
    "--model-deep", "anthropic/claude-opus-4-5",
]
TIER_FLAGS = ["--model-cheap", "--model-standard", "--model-deep"]
SENTINEL = "SENTINEL-FAKE-SECRET-7f3a9c2e"
SECRET_FILES = (".env", ".envrc")
TIMING_BUDGET_S = 5.0
# A full run writes 24 skills + 12 agents at minimum; fewer means the timing run measured nothing.
MIN_GENERATED_FILES = 36
NETWORK_MODULES = re.compile(
    r"^\s*(?:import|from)\s+(urllib|socket|http|requests|ssl|ftplib|smtplib|xmlrpc)\b", re.M)

errors = []
notes = []
checked = {"manifest_entries": 0, "tier_flags": 0, "secret_files": 0, "timed_runs": 0, "static_modules": 0}
UNSHARE = []  # filled once by probe_unshare(): [True] when `unshare -n` works here


def fail(name, where, msg):
    errors.append(f"FAIL: {name} — {where}: {msg}")


def run_gen(target, cwd=None, wrapper=(), tiers=TIERS):
    cmd = [*wrapper, sys.executable, "-I", GEN, "--target", target, *tiers]
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=120)


def probe_unshare():
    if shutil.which("unshare") is None:
        UNSHARE.append(False)
        return
    probe = subprocess.run(["unshare", "-n", "true"], capture_output=True, text=True)
    UNSHARE.append(probe.returncode == 0)


def all_files(root):
    found = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            found.append(os.path.relpath(full, root))
    return sorted(found)


def sha256_of(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


# ── manifest integrity (static half of AC5/AC6 bookkeeping) ─────────────────
def check_manifest(work):
    name = "manifest_integrity"
    target = os.path.join(work, "manifest-target")
    r = run_gen(target)
    if r.returncode != 0:
        fail(name, "generator", f"exit {r.returncode}: {r.stderr.strip()}")
        return
    mpath = os.path.join(target, MANIFEST_NAME)
    if not os.path.isfile(mpath):
        fail(name, MANIFEST_NAME, "not written")
        return
    try:
        with open(mpath, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        fail(name, MANIFEST_NAME, f"not valid JSON: {exc}")
        return
    if not isinstance(doc, dict) or set(doc) != {"version", "entries"}:
        fail(name, MANIFEST_NAME, f"top-level keys must be exactly version+entries, got {sorted(doc) if isinstance(doc, dict) else type(doc).__name__}")
        return
    if type(doc["version"]) is not int:
        fail(name, MANIFEST_NAME, f"version must be an int, got {doc['version']!r}")
    if not isinstance(doc["entries"], list) or not doc["entries"]:
        fail(name, MANIFEST_NAME, "entries must be a non-empty list")
        return

    listed = set()
    for i, entry in enumerate(doc["entries"]):
        where = f"{MANIFEST_NAME}[{i}]"
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256"}:
            fail(name, where, f"entry must have exactly path+sha256, got {entry!r}")
            continue
        path, digest = entry["path"], entry["sha256"]
        if not isinstance(path, str) or not isinstance(digest, str):
            fail(name, where, "path and sha256 must both be strings")
            continue
        if os.path.isabs(path) or re.search(r"(^|/)\.\.(/|$)", path) or path in listed:
            fail(name, where, f"path must be unique, relative and inside the target: {path!r}")
            continue
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            fail(name, where, f"sha256 is not 64 lowercase hex chars: {digest!r}")
            continue
        listed.add(path)
        full = os.path.join(target, path)
        checked["manifest_entries"] += 1
        if not os.path.isfile(full):
            fail(name, path, "listed in manifest but missing on disk")
        elif sha256_of(full) != digest:
            fail(name, path, "on-disk sha256 differs from the manifest entry")

    on_disk = {p for p in all_files(target) if p != MANIFEST_NAME}
    for orphan in sorted(on_disk - listed):
        fail(name, orphan, "written by the generator but not recorded in the manifest")


# ── model-tier rejection (static re-confirmation of AC4) ────────────────────
def check_model_mapping(work):
    name = "model_mapping"
    for flag in TIER_FLAGS:
        checked["tier_flags"] += 1
        target = os.path.join(work, f"missing-{flag.strip('-')}")
        tiers = []
        skip = False
        for tok in TIERS:
            if tok == flag:
                skip = True
                continue
            if skip:
                skip = False
                continue
            tiers.append(tok)
        r = run_gen(target, tiers=tiers)
        if r.returncode == 0:
            fail(name, flag, "generator accepted a run with this model tier missing")
        elif flag not in r.stderr:
            fail(name, flag, f"rejected but stderr does not name {flag}: {r.stderr.strip()[-200:]}")
        if os.path.exists(os.path.join(target, MANIFEST_NAME)):
            fail(name, flag, "rejected run still wrote a manifest")

    # A malformed value (no provider/model slash) is the installer's job: install-opencode.sh
    # validates shape before any write, and the generator takes the string verbatim.
    checked["tier_flags"] += 1
    tgt = os.path.join(work, "malformed-install")
    os.makedirs(tgt)
    r = subprocess.run(
        ["bash", INSTALLER, "--target", tgt, "--model-cheap", "haiku",
         "--model-standard", "anthropic/claude-sonnet-4-5", "--model-deep", "anthropic/claude-opus-4-5",
         "--no-git-hooks", "--yes"],
        capture_output=True, text=True, timeout=120)
    if r.returncode == 0:
        fail(name, "install-opencode.sh", "accepted bare alias 'haiku' for --model-cheap")
    elif "cheap" not in r.stderr:
        fail(name, "install-opencode.sh", f"rejected but stderr does not name the cheap tier: {r.stderr.strip()[-200:]}")
    if all_files(tgt):
        fail(name, "install-opencode.sh", "rejected malformed tier but wrote files")


# ── test_never_reads_env_or_envrc_or_calls_network ──────────────────────────
def static_network_scan():
    with open(GEN, encoding="utf-8") as f:
        src = f.read()
    checked["static_modules"] += 1
    for hit in NETWORK_MODULES.finditer(src):
        fail("test_never_reads_env_or_envrc_or_calls_network", "generate-opencode.py",
             f"imports network-capable module '{hit.group(1)}'")


def test_never_reads_env_or_envrc_or_calls_network(work):
    name = "test_never_reads_env_or_envrc_or_calls_network"
    cwd = os.path.join(work, "secret-cwd")
    target = os.path.join(work, "secret-target")
    os.makedirs(cwd)
    os.makedirs(target)
    for d in (cwd, target):
        for fn in SECRET_FILES:
            with open(os.path.join(d, fn), "w", encoding="utf-8") as f:
                f.write(f"API_TOKEN={SENTINEL}\n")

    wrapper = ()
    if UNSHARE and UNSHARE[0]:
        wrapper = ("unshare", "-n")
    else:
        notes.append("NOTE: network block UNMEASURED for test_never_reads_env_or_envrc_or_calls_network — "
                     "`unshare -n` is unavailable in this environment; the static import scan stands in for it")
    static_network_scan()

    r = run_gen(target, cwd=cwd, wrapper=wrapper)
    if r.returncode != 0:
        fail(name, "generator", f"exit {r.returncode} with sentinel secrets present: {r.stderr.strip()[-200:]}")
        return
    for rel in all_files(target):
        if rel in SECRET_FILES:   # the sentinels this test planted, not generator output
            continue
        checked["secret_files"] += 1
        with open(os.path.join(target, rel), "rb") as f:
            if SENTINEL.encode() in f.read():
                fail(name, rel, "generated file contains the .env/.envrc sentinel secret")


# ── test_generation_completes_under_5s ──────────────────────────────────────
def test_generation_completes_under_5s(work):
    name = "test_generation_completes_under_5s"
    target = os.path.join(work, "timing-target")
    started = time.perf_counter()
    r = run_gen(target)
    elapsed = time.perf_counter() - started
    checked["timed_runs"] += 1
    if r.returncode != 0:
        fail(name, "generator", f"exit {r.returncode}: {r.stderr.strip()[-200:]}")
        return
    generated = len(all_files(target))
    if generated < MIN_GENERATED_FILES:
        fail(name, "generator", f"only {generated} files generated; a full run writes at least {MIN_GENERATED_FILES}")
    if elapsed >= TIMING_BUDGET_S:
        fail(name, "generator", f"full run took {elapsed:.2f}s, budget is < {TIMING_BUDGET_S:.0f}s")
    else:
        print(f"timing: full generation run {elapsed:.2f}s ({generated} files) — budget < {TIMING_BUDGET_S:.0f}s")


def main():
    probe_unshare()
    work = tempfile.mkdtemp(prefix="validate-opencode-")
    try:
        check_manifest(work)
        check_model_mapping(work)
        test_never_reads_env_or_envrc_or_calls_network(work)
        test_generation_completes_under_5s(work)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print(f"checked: {checked}")
    for n in notes:
        print(n)
    if errors:
        print(f"\n{len(errors)} opencode problem(s):\n")
        for e in errors:
            print("  " + e)
        sys.exit(1)
    print("opencode validation OK")


if __name__ == "__main__":
    main()
