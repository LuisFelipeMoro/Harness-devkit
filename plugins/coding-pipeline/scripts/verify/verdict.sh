#!/usr/bin/env bash
# The arithmetic half of the Verdict agent.
#
# Hard-gate check, weighted score and threshold lookup are a table and three
# multiplications. Spending a sonnet dispatch on them buys nothing and costs a
# chance to get the arithmetic wrong — which is the one failure mode a verdict
# cannot afford, because nobody downstream re-checks it.
#
# What this does NOT do is the Verdict Self-Check: whether each PASS is backed by
# a named artifact, whether every AC is accounted for, whether findings came from
# an agent other than the author. That is judgment and stays with the agent, which
# now reads this output instead of re-deriving it.
#
# Thresholds come from references/thresholds.md — change them there, not here.
#
# Usage:
#   verdict.sh --review 8.5 --stress 7.0 --qa 9.0 \
#              [--critical-security N] [--critical-other N] \
#              [--hard-gate-fail "name,name"] [--reviewer-block]
#
#   verdict.sh --roster {cosmetic|light|standard|full} --classify-exit N \
#              [--review N] [--stress N] [--qa N] [...]
#     Per-roster lens rules (references/thresholds.md — Roster):
#       cosmetic  no score flags — gates only
#       light     --review --stress; --qa forbidden; weight renormalised
#       standard  --review --stress --qa; Stress is the Reviewer's folded lens
#       full      --review --stress --qa; Stress is a dispatched agent
#     --classify-exit is mandatory with --roster; non-zero is always NOT READY.
set -u

review=""; stress=""; qa=""
crit_sec=0; crit_other=0; gate_fail=""; blocked=0
roster=""; classify_exit=""

while [ $# -gt 0 ]; do
    case "$1" in
        --review)            review="$2"; shift 2 ;;
        --stress)            stress="$2"; shift 2 ;;
        --qa)                qa="$2"; shift 2 ;;
        --critical-security) crit_sec="$2"; shift 2 ;;
        --critical-other)    crit_other="$2"; shift 2 ;;
        --hard-gate-fail)    gate_fail="$2"; shift 2 ;;
        --reviewer-block)    blocked=1; shift ;;
        --roster)            roster="$2"; shift 2 ;;
        --classify-exit)     classify_exit="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

usage() {
    echo "usage: verdict.sh --review N --stress N --qa N [...]" >&2
    echo "       verdict.sh --roster {cosmetic|light|standard|full} --classify-exit N [--review N --stress N [--qa N]] [...]" >&2
    exit 2
}

valid_score() {
    case "$1" in
        ''|*[!0-9.]*|*.*.*|.) return 1 ;;
        *) return 0 ;;
    esac
}

if [ -n "$roster" ]; then
    case "$roster" in
        cosmetic|light|standard|full) ;;
        *) usage ;;
    esac
    case "$classify_exit" in
        ''|*[!0-9]*) usage ;;
    esac
    case "$roster" in
        cosmetic)
            if [ -n "$review" ] || [ -n "$stress" ] || [ -n "$qa" ]; then usage; fi
            ;;
        light)
            if [ -z "$review" ] || [ -z "$stress" ]; then usage; fi
            if [ -n "$qa" ]; then usage; fi
            valid_score "$review" || usage
            valid_score "$stress" || usage
            ;;
        standard|full)
            if [ -z "$review" ] || [ -z "$stress" ] || [ -z "$qa" ]; then usage; fi
            valid_score "$review" || usage
            valid_score "$stress" || usage
            valid_score "$qa" || usage
            ;;
    esac
else
    # legacy path — byte-identical to pre-roster behaviour
    for v in "$review" "$stress" "$qa"; do
        case "$v" in
            ''|*[!0-9.]*|*.*.*|.) echo "usage: verdict.sh --review N --stress N --qa N [...]" >&2; exit 2 ;;
        esac
    done
fi

python3 - "$review" "$stress" "$qa" "$crit_sec" "$crit_other" "$gate_fail" "$blocked" "$roster" "$classify_exit" <<'PY'
import sys


def classify_verdict(score, crit_other, reasons):
    """Shared by the legacy and roster paths — thresholds.md — Scores."""
    if reasons:
        return "NOT READY"
    if score >= 8.0 and crit_other == 0:
        return "PRODUCTION READY"
    if score >= 6.5 and crit_other <= 1:
        reasons.append(f"overall {score:.2f}" + (f" with {crit_other} non-security CRITICAL" if crit_other else ""))
        return "READY WITH CONDITIONS"
    reasons.append(f"{crit_other} non-security CRITICAL issues")
    return "NOT READY"


review_s, stress_s, qa_s = sys.argv[1:4]
crit_sec, crit_other = int(sys.argv[4]), int(sys.argv[5])
gate_fail = [g for g in sys.argv[6].split(",") if g.strip()]
blocked = sys.argv[7] == "1"
roster = sys.argv[8]
classify_exit_s = sys.argv[9]

if not roster:
    # references/thresholds.md — Scores. Legacy path: byte-identical output.
    review, stress, qa = float(review_s), float(stress_s), float(qa_s)
    score = review * 0.35 + stress * 0.35 + qa * 0.30
    if blocked:
        score = min(score, 5.0)

    reasons = []
    if gate_fail:
        reasons.append("hard gate FAIL: " + ", ".join(g.strip() for g in gate_fail))
    if crit_sec > 0:
        reasons.append(f"{crit_sec} unmitigated CRITICAL security issue(s)")
    if score < 6.5:
        reasons.append(f"overall {score:.2f} < 6.5")
    if review < 7:
        reasons.append(f"Reviewer {review} below story floor 7")
    if stress < 7:
        reasons.append(f"Stress {stress} below story floor 7")

    verdict = classify_verdict(score, crit_other, reasons)

    print(f"VERDICT: {verdict}")
    if verdict != "NOT READY" or not gate_fail:
        print(f"Overall Score: {score:.2f}/10  (Review {review} x35% · Stress {stress} x35% · QA {qa} x30%)")
    if blocked:
        print("NOTE: Reviewer BLOCK — score capped at 5.0")
    if abs(review - stress) > 3:
        print(f"WARNING: Review/Stress gap {abs(review - stress):.1f} > 3 — manual inspection recommended before shipping")
    for r in reasons:
        print(f"  - {r}")
    print()
    print("Computed from thresholds.md. The agent still owes the Verdict Self-Check:")
    print("  Evidence · Traceability · Independence · Residual risk · Actionability (1-5 each).")
    sys.exit(0 if verdict == "PRODUCTION READY" else 1)

# ── roster path — references/thresholds.md — Roster ───────────────────────
classify_exit = int(classify_exit_s)
reasons = []
if classify_exit != 0:
    reasons.append(f"roster not verified (classify-diff exit {classify_exit})")
if gate_fail:
    reasons.append("hard gate FAIL: " + ", ".join(g.strip() for g in gate_fail))
if crit_sec > 0:
    reasons.append(f"{crit_sec} unmitigated CRITICAL security issue(s)")

if roster == "cosmetic":
    # No lens exists to average — a gate failure or an unverified roster is
    # the only way a cosmetic story is anything but PRODUCTION READY.
    verdict = "NOT READY" if reasons else "PRODUCTION READY"
    print(f"VERDICT: {verdict}")
    print("Overall Score: n/a (cosmetic — gates only)")
    for r in reasons:
        print(f"  - {r}")
    sys.exit(0 if verdict == "PRODUCTION READY" else 1)

review = float(review_s)
stress = float(stress_s)
qa = float(qa_s) if qa_s else None

# Story floor. The average can hide one failing lens — checked before the
# roster-specific formula so it applies identically to light/standard/full.
if review < 7:
    reasons.append(f"Reviewer {review} below story floor 7")
if stress < 7:
    reasons.append(f"Stress {stress} below story floor 7")

if roster == "light":
    # QA is mechanical sensors only for this roster; renormalise the two
    # remaining lenses instead of averaging in a QA score that never happened.
    score = (review * 0.35 + stress * 0.35) / 0.70
else:
    score = review * 0.35 + stress * 0.35 + qa * 0.30

if blocked:
    score = min(score, 5.0)

if score < 6.5:
    reasons.append(f"overall {score:.2f} < 6.5")

verdict = classify_verdict(score, crit_other, reasons)

stress_source = {"standard": "[folded]", "full": "[dispatched]"}.get(roster, "")

print(f"VERDICT: {verdict}")
# When NOT READY due to hard-gate failure, skip the overall score line (same as legacy path)
if verdict != "NOT READY" or not gate_fail:
    if roster == "light":
        print(f"Overall Score: {score:.2f}/10  (Review {review} x35% · Stress {stress} x35% / 0.70 renormalised)")
        print("QA: mechanical sensors only — weight renormalised")
    else:
        print(f"Overall Score: {score:.2f}/10  (Review {review} x35% · Stress {stress} x35% {stress_source} · QA {qa} x30%)")
if blocked:
    print("NOTE: Reviewer BLOCK — score capped at 5.0")
if roster in ("light", "standard"):
    # Same agent produced both lenses — a gap warning would be noise.
    print("NOTE: Review and Stress from one agent")
elif abs(review - stress) > 3:
    print(f"WARNING: Review/Stress gap {abs(review - stress):.1f} > 3 — manual inspection recommended before shipping")
for r in reasons:
    print(f"  - {r}")
print()
print("Computed from thresholds.md. The agent still owes the Verdict Self-Check:")
print("  Evidence · Traceability · Independence · Residual risk · Actionability (1-5 each).")
sys.exit(0 if verdict == "PRODUCTION READY" else 1)
PY
