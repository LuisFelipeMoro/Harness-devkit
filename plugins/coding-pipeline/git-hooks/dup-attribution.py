#!/usr/bin/env python3
"""Attribute jscpd's clones to this delivery or to pre-existing debt.

A repo-wide duplication percentage answers the wrong question. On any codebase
with history it is dominated by debt the current change did not cause, so the
gate either fails every push on day one (and gets disabled) or is set so loose it
never fires. Neither state catches the thing worth catching: a helper this
delivery reimplemented instead of reusing.

So the clones are split by *who wrote them*. Attribution is line-level, not
file-level: a duplicated line counts against the delivery only when it lies in a
range the diff actually added. Touching one function in a 900-line legacy file
does not make its other clones yours.

  introduced   → blocks. This delivery added it.
  pre-existing → reported as debt, never blocks. Route it to a follow-up.

Exit 0 = no introduced duplication above the threshold. Exit 1 = blocked, or the
report could not be read — an unreadable gate must never render as a pass.
"""
import argparse
import json
import subprocess
import sys


def added_ranges(base):
    """{path: [(start, end), ...]} — the line ranges this delivery added.

    --unified=0 so each hunk's `+` span is exactly the added lines, with no
    context bleeding the range into code the change never touched.
    """
    out = subprocess.run(
        ["git", "diff", "--unified=0", "--no-color", f"{base}...HEAD"],
        capture_output=True, text=True, check=True).stdout
    ranges, path = {}, None
    for line in out.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("@@") and path:
            # @@ -a,b +c,d @@ — d defaults to 1 when omitted; d == 0 is a pure deletion
            plus = line.split("+", 1)[1].split(" ", 1)[0]
            start, _, count = plus.partition(",")
            start, count = int(start), int(count or 1)
            if count:
                ranges.setdefault(path, []).append((start, start + count - 1))
    return ranges


def lines_of(entry):
    start = int(entry.get("start") or 0)
    end = int(entry.get("end") or 0)
    return start, max(start, end)


def touches(path, start, end, ranges):
    for lo, hi in ranges.get(path.lstrip("./"), ()):
        if start <= hi and lo <= end:
            return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", required=True, help="jscpd JSON report")
    ap.add_argument("--base", help="merge-base ref; omit for whole-repo mode")
    ap.add_argument("--threshold", type=float, default=3.0)
    args = ap.parse_args()

    try:
        with open(args.report, encoding="utf-8") as f:
            data = json.load(f)
        duplicates = data["duplicates"]
        total_lines = int(data["statistics"]["total"]["lines"])
    except Exception as exc:                       # noqa: BLE001 — any failure here is the same failure
        print(f"FAIL: duplication report unreadable ({exc}) — refusing to pass an unmeasured gate")
        return 1

    if total_lines <= 0:
        print("FAIL: duplication report counted 0 lines — refusing to pass an unmeasured gate")
        return 1

    ranges = {}
    attributed = args.base is not None
    if attributed:
        try:
            ranges = added_ranges(args.base)
        except subprocess.CalledProcessError:
            attributed = False

    introduced, preexisting = [], []
    intro_lines, debt_lines = set(), set()
    for dup in duplicates:
        first, second = dup.get("firstFile", {}), dup.get("secondFile", {})
        fp, sp = first.get("name", "?"), second.get("name", "?")
        fs, fe = lines_of(first)
        ss, se = lines_of(second)
        is_new = attributed and (touches(fp, fs, fe, ranges) or touches(sp, ss, se, ranges))
        pair = f"{fp}:{fs}-{fe}  ↔  {sp}:{ss}-{se}  ({dup.get('lines', fe - fs + 1)} lines)"
        sink, lines = (introduced, intro_lines) if is_new else (preexisting, debt_lines)
        sink.append(pair)
        lines.update((fp, n) for n in range(fs, fe + 1))
        lines.update((sp, n) for n in range(ss, se + 1))

    intro_pct = len(intro_lines) * 100.0 / total_lines
    debt_pct = len(debt_lines) * 100.0 / total_lines

    if attributed:
        print(f"Duplication: introduced {intro_pct:.1f}% (limit {args.threshold:g}%) "
              f"· pre-existing debt {debt_pct:.1f}%")
    else:
        print(f"Duplication: {intro_pct + debt_pct:.1f}% total (limit {args.threshold:g}%) "
              f"— ATTRIBUTION UNAVAILABLE (no merge-base), so every clone is gated as if this "
              f"delivery wrote it")

    if preexisting:
        print(f"Pre-existing debt — not blocking, route to a follow-up ({len(preexisting)} pair(s)):")
        for pair in preexisting[:10]:
            print(f"  {pair}")
        if len(preexisting) > 10:
            print(f"  … {len(preexisting) - 10} more")

    if introduced:
        print(f"Introduced by this delivery ({len(introduced)} pair(s)):")
        for pair in introduced:
            print(f"  {pair}")

    gated = intro_pct if attributed else intro_pct + debt_pct
    if gated > args.threshold:
        label = "introduced" if attributed else "total"
        print(f"FAIL: {label} duplication {gated:.1f}% exceeds {args.threshold:g}% — "
              f"reuse the existing symbol rather than extracting a new abstraction to absorb the copies")
        return 1
    print("Duplication gate: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
