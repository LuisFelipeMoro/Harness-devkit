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

What stays with Quinn: over-mocking, snapshot-for-behaviour, intent-encoding,
canonical-only validators, timing-coupled tests. This narrows what she reads; it
does not replace her.

Usage: tautology-scan.py <test-path>...
Exit 0 = clean. Exit 1 = hits, each a MAJOR candidate until Quinn clears it.
"""
import os
import re
import sys

SKIP_DIRS = {"node_modules", "vendor", ".git", "testdata", "__pycache__", "target", "dist"}

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


def walk(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
        for root, dirs, files in os.walk(p):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for f in files:
                if re.search(r"(_test\.|\.test\.|\.spec\.|test_|Test\.|_spec\.)", f):
                    yield os.path.join(root, f)


def scan(path, hits):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
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
        print("usage: tautology-scan.py <test-path>...", file=sys.stderr)
        return 2

    hits = []
    seen = set()
    for f in walk(argv):
        if f in seen:
            continue
        seen.add(f)
        scan(f, hits)

    for label, path, line, text in hits:
        loc = f"{path}:{line}" if line else path
        print(f"[{label}] {loc} — {text}")

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
