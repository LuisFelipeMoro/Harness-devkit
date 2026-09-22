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
set -u

review=""; stress=""; qa=""
crit_sec=0; crit_other=0; gate_fail=""; blocked=0

while [ $# -gt 0 ]; do
    case "$1" in
        --review)            review="$2"; shift 2 ;;
        --stress)            stress="$2"; shift 2 ;;
        --qa)                qa="$2"; shift 2 ;;
        --critical-security) crit_sec="$2"; shift 2 ;;
        --critical-other)    crit_other="$2"; shift 2 ;;
        --hard-gate-fail)    gate_fail="$2"; shift 2 ;;
        --reviewer-block)    blocked=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

for v in "$review" "$stress" "$qa"; do
    case "$v" in
        ''|*[!0-9.]*) echo "usage: verdict.sh --review N --stress N --qa N [...]" >&2; exit 2 ;;
    esac
done

python3 - "$review" "$stress" "$qa" "$crit_sec" "$crit_other" "$gate_fail" "$blocked" <<'PY'
import sys

review, stress, qa = (float(x) for x in sys.argv[1:4])
crit_sec, crit_other = int(sys.argv[4]), int(sys.argv[5])
gate_fail = [g for g in sys.argv[6].split(",") if g.strip()]
blocked = sys.argv[7] == "1"

# references/thresholds.md — Scores
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

if reasons:
    verdict = "NOT READY"
elif score >= 8.0 and crit_other == 0:
    verdict = "PRODUCTION READY"
elif score >= 6.5 and crit_other <= 1:
    verdict = "READY WITH CONDITIONS"
    reasons.append(f"overall {score:.2f}" + (f" with {crit_other} non-security CRITICAL" if crit_other else ""))
else:
    verdict = "NOT READY"
    reasons.append(f"{crit_other} non-security CRITICAL issues")

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
PY
