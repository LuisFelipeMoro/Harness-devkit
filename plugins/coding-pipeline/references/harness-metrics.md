# Harness health signals

Moved out of `CLAUDE.md` because it says so itself — *read quarterly, never as a gate*. It was
~1,100 tokens loaded into every session to be consulted four times a year, which fails the
standards' own first rule.

## Is the Harness working? (read quarterly, never as a gate)

A Harness that is never measured drifts into ceremony. These five signals are countable from
artifacts the devkit already produces — no new tooling, no new file:

| Signal | Where it is counted | Healthy |
|---|---|---|
| Scope creep | CD1+CD2+CD3 findings in the Reviewer's `Summary:` line | falling toward zero |
| Question timing | edits to the delivery file's ACs *after* the first Coder dispatch | rare — questions land before code, not after a mistake |
| Rework | files touched by 2+ commits on one delivery branch (`git log --format= --name-only <branch> \| sort \| uniq -c`) | flat; a rise means the spec was too loose |
| Sensor escape | gate failures first caught at pre-push or CI instead of locally | falling — a failure caught late cost a full loop |
| Test honesty | QA MAJORs for tautological or unfalsified tests | zero, *with* coverage steady — zero findings plus climbing coverage is a red flag, not a win |

**These are diagnostics, never targets.** Every one is trivially gamed by suppressing its
signal — ask fewer questions, soften the review, squash the rework away — and an agent told to
optimise them will do exactly that. They are read by a human, from `PROGRESS.md` and the
delivery files, to decide whether the standards are earning their cost.

**What to do with a reading**: scope creep rising means the Guides are not reaching the Coder —
tighten the story, do not tighten the reviewer. A stretch of healthy readings is licence to
*remove* ceremony (demote a lane in Proportionality), which is the only way this file gets
shorter instead of longer.
