#!/usr/bin/env python3
"""The mechanical half of QA's tautology hunt.

Four of Quinn's tautology patterns are literal shapes in the source, not judgments:
an assertion whose two sides are the same expression, an expectation computed by
calling the function under test, a loop with an empty body, and a spy nobody reads.
Locating those by reading every test file costs a model pass over the suite. Here
they are regexes, and the cost does not grow with the suite or degrade with context.

Python rather than grep because three of the four need a backreference, and
backreferences are not portable across BSD and GNU grep — the first version of
this script hung on macOS for exactly that reason.

`--diff <base> [<path>...]` scopes the scan to one story instead of the whole tree.
A full walk would resurface every pre-existing tautology in every test file the repo
already has — debt this story did not create and the Coder cannot be asked to fix in
passing. Diff mode reads only what `git diff` says changed, so "0 candidates" still
means "scanned the story's tests and found nothing", not "the story added no tests
and nobody checked" — the same fail-closed contract positional mode already keeps,
now scoped to the commits under review. The validation and file-listing logic here
mirrors `diff-lib.sh` exactly (same regex, same UNMEASURED wording, same
`"$base...HEAD"` range) rather than sourcing it, because this script is a separate
interpreter with no bash to source into; `subprocess.run` is called with a list
argv, never `shell=True`, so a crafted base ref can never reach a shell.

What stays with Quinn: over-mocking, snapshot-for-behaviour, intent-encoding,
canonical-only validators, timing-coupled tests. This narrows what she reads; it
does not replace her.

Usage: tautology-scan.py <test-path>... | tautology-scan.py --diff <base> [<path>...]
Exit 0 = clean. Exit 1 = hits, each a MAJOR candidate until Quinn clears it.
Exit 2 = no test file found under the given paths (or in the diff) — unmeasured,
         never a PASS.
"""
import os
import re
import subprocess
import sys
from typing import List, Union

SKIP_DIRS = {"node_modules", "vendor", ".git", "testdata", "__pycache__", "target", "dist"}

# Test-file shape, shared by the positional walk and diff-mode filtering — a
# single source so a future consumer (e.g. classify-diff.sh) names one pattern,
# not a second copy that can drift from this one.
TEST_FILE = re.compile(r"(_test\.|\.test\.|\.spec\.|test_|Test\.|_spec\.)")


def in_skip_dir(path: str) -> bool:
    """True if any path component matches SKIP_DIRS. Diff-mode paths never pass
    through os.walk's `dirs[:] = ...` filtering (they come straight from `git
    diff`), so this re-applies the same exclusion positional mode gets for
    free — otherwise a file under testdata/, vendor/, etc. that changed on the
    story branch would be scanned when the positional walk would have skipped
    the same file untouched."""
    return any(part in SKIP_DIRS for part in path.split(os.sep))

# Base-ref charset, identical to diff-lib.sh: alphanumeric first, then
# alphanumeric/._/- only. ".." is checked separately below — it passes this
# regex (every one of its characters is individually allowed) but is range
# syntax, not a ref, so a second explicit check is required to catch it.
BASE_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")

# Same expression asserted against itself.
SELF_ASSERT = [
    re.compile(r"expect\(\s*([^()]+?)\s*\)\s*\.\s*(?:toBe|toEqual|toStrictEqual)\(\s*\1\s*\)"),
    re.compile(r"assert\.(?:Equal|Same)\(\s*t\s*,\s*([^,]+?)\s*,\s*\1\s*\)"),
    re.compile(r"assert(?:Equals|Same)\(\s*([^,]+?)\s*,\s*\1\s*\)"),
    re.compile(r"assert\s+([^=\n]+?)\s*==\s*\1\s*$"),
]

# Expected value produced by calling the system under test rather than stated as a literal.
EXPECTED_FROM_SUT = re.compile(
    r"\b(?:want|expected|exp)\b\s*:?=\s*[A-Za-z_][A-Za-z0-9_.]*\s*\(",
    re.IGNORECASE,
)
# Builders, fixtures and parsers legitimately compute an expectation.
EXPECTED_ALLOW = re.compile(
    r"fixture|golden|testdata|helper|builder|new[A-Z]|make[A-Z]|parse|load|decode|marshal",
    re.IGNORECASE,
)

LOOP_OPEN = re.compile(r"\b(?:for\s*\(|\.forEach\(|for\s+[\w,\s]+:=\s*range|for\s+\w+\s+in\b)")
EMPTY_BODY = re.compile(r"^\s*(?:\}|\)|\);|//|#|/\*|pass\b|TODO)")

SPY_INSTALL = re.compile(r"jest\.fn\(|vi\.fn\(|sinon\.(?:spy|stub)|mock\.On\(|Mockito\.(?:mock|spy)|unittest\.mock")
SPY_READ = re.compile(
    r"expect\([^)]*(?:mock|spy|stub)|toHaveBeenCalled|assert_(?:called|any_call)|"
    r"AssertExpectations|verify\(|assert\.\w*Called"
)


def diff_files(base: str, paths: List[str]) -> Union[List[str], str]:
    """Validated base ref -> NUL-safe list of changed, existing files (repo-root
    absolute), or a str UNMEASURED reason. Mirrors diff-lib.sh's diff_files():
    same charset regex, same checks in the same order, same messages, same
    "$base...HEAD" range. Every git call is a list argv; every git returncode
    that gates a decision is checked explicitly (status is read for content
    only, matching the bash original, which never inspects its exit code)."""
    if paths and paths[0] == "--":
        paths = paths[1:]

    if not BASE_REF_RE.match(base) or ".." in base:
        return f"invalid base ref '{base}'"

    toplevel = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=False,
    )
    if toplevel.returncode != 0:
        return "not a git repository"
    top = toplevel.stdout.strip()

    verify = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}"],
        capture_output=True, text=True, check=False,
    )
    if verify.returncode != 0:
        return f"unknown base ref '{base}'"

    status = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=normal"],
        capture_output=True, text=True, check=False,
    )
    if status.stdout.strip():
        return "uncommitted changes are outside the diff"

    diff = subprocess.run(
        ["git", "diff", "-z", "--name-only", "--diff-filter=d", f"{base}...HEAD", "--", *paths],
        capture_output=True, check=False,
    )
    if diff.returncode != 0:
        return "git diff failed"

    # Decoded with surrogateescape rather than the strict decoding `text=True`
    # would apply: git never refuses to track a path with a non-UTF-8 byte, and
    # `text=True` raising UnicodeDecodeError here turned one bad file name into
    # an unhandled traceback for the whole scan. surrogateescape is how
    # Python's own os layer encodes POSIX paths, so the escaped codepoints
    # re-encode to the exact original bytes when a later open() is attempted.
    stdout = diff.stdout.decode(sys.getfilesystemencoding(), errors="surrogateescape")

    # NUL-delimited split: a file name containing a newline stays one field
    # here. Splitting on "\n" instead would break it into two missing paths.
    files = [f for f in stdout.split("\0") if f]
    if not files:
        return f"empty diff against {base}"

    return [os.path.join(top, f) for f in files]


def walk(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
        for root, dirs, files in os.walk(p):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for f in files:
                if TEST_FILE.search(f):
                    yield os.path.join(root, f)


def scan(path, hits, unmeasured):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except (OSError, ValueError):
        # Not silently skipped: an unreadable selected file is scan coverage
        # that never happened, so it is reported as UNMEASURED rather than
        # counted toward a clean PASS.
        unmeasured.append(path)
        return

    spy_installed = False
    spy_read = False

    for i, line in enumerate(lines, 1):
        for pat in SELF_ASSERT:
            if pat.search(line):
                hits.append(("SELF-ASSERT", path, i, line.strip()[:110]))
                break

        if EXPECTED_FROM_SUT.search(line) and not EXPECTED_ALLOW.search(line):
            hits.append(("EXPECTED-FROM-SUT", path, i, line.strip()[:110]))

        if LOOP_OPEN.search(line) and i < len(lines):
            nxt = lines[i]
            if EMPTY_BODY.match(nxt) or not nxt.strip():
                hits.append(("VACUOUS-LOOP", path, i, line.strip()[:110]))

        if SPY_INSTALL.search(line):
            spy_installed = True
        if SPY_READ.search(line):
            spy_read = True

    if spy_installed and not spy_read:
        hits.append(("SPY-NO-READER", path, 0, "mock/spy installed, no assertion ever reads it"))


def main(argv):
    if not argv:
        print("usage: tautology-scan.py <test-path>... | --diff <base> [<path>...]", file=sys.stderr)
        return 2

    if argv[0] == "--diff":
        if len(argv) < 2:
            print("usage: tautology-scan.py --diff <base> [<path>...]", file=sys.stderr)
            return 2
        base, paths = argv[1], argv[2:]
        result = diff_files(base, paths)
        if isinstance(result, str):
            print(f"TAUTOLOGY-SCAN: UNMEASURED — {result}", file=sys.stderr)
            return 2
        seen = [
            f for f in result
            if TEST_FILE.search(os.path.basename(f)) and not in_skip_dir(f)
        ]
        if not seen:
            print("TAUTOLOGY-SCAN: UNMEASURED — no test file in diff", file=sys.stderr)
            return 2
    else:
        seen = []
        dedup = set()
        for f in walk(argv):
            if f in dedup:
                continue
            dedup.add(f)
            seen.append(f)
        if not seen:
            print("TAUTOLOGY-SCAN: UNMEASURED — 0 test files under " + " ".join(argv) +
                  "; nothing was scanned, so nothing is cleared")
            return 2

    hits = []
    unmeasured = []
    for f in seen:
        if os.path.islink(f):
            # Never followed: a symlink among the selected paths can point
            # anywhere, including outside the repo. Reported as a hit — not
            # opened, not silently skipped — so an escape is always visible.
            try:
                target = os.readlink(f)
            except OSError:
                target = "?"
            hits.append(("SYMLINK", f, 0, target))
            continue
        if not os.path.isfile(f):
            unmeasured.append(f)
            continue
        scan(f, hits, unmeasured)

    for label, path, line, text in hits:
        if label == "SYMLINK":
            print(f"[SYMLINK] {path} -> {text}")
            continue
        loc = f"{path}:{line}" if line else path
        print(f"[{label}] {loc} — {text}")

    if unmeasured:
        print(f"\nTAUTOLOGY-SCAN: UNMEASURED — could not read: {', '.join(unmeasured)}",
              file=sys.stderr)
        return 2

    if hits:
        print(f"\nTAUTOLOGY-SCAN: FAIL — {len(hits)} mechanical tautology candidate(s); "
              "each is a MAJOR until Quinn clears it")
        return 1

    print(f"TAUTOLOGY-SCAN: PASS — {len(seen)} test file(s), no mechanical tautology pattern")
    print("NOTE: over-mocking, snapshot-for-behaviour, intent-encoding, canonical-only "
          "validators and timing-coupled tests are NOT covered here — Quinn still audits those.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
