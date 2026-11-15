# Headless runs — the answers contract

Loaded only by a run where `AskUserQuestion` is unavailable (a non-interactive `claude -p` stage).
An interactive run never reads this file; its questions go to the user as they always have.

## Answers line

The prompt carries one line, built by the caller from the closed key list below:

`Answers: run_mode=sequential; review_post=no; review_language=English; …`

- Format: `Answers:` then `key=value` pairs separated by `; `. One value per key, no spaces inside a key.
- A key the skill asks and the line does not carry → the skill prints `NEEDS_USER: <question>` and stops.
- A value outside the key's listed values → the same: `NEEDS_USER: <question>` and stop.
- Never guess a default, never pick the first option, never answer from memory of an earlier run.

## Keys

| Key | Values | Skill step it answers |
|---|---|---|
| `plan_not_approved` | `stop` · `proceed` | code/SKILL.md step 1 (plan `Status` is not `approved`) |
| `uncommitted` | `stop` · `continue` | code/SKILL.md step 2 (uncommitted changes outside `docs/`) |
| `run_mode` | `inline` · `single` · `sequential` · `parallel` | code/SKILL.md step 4 (mode choice) |
| `fix_rounds_exhausted` | `stop` | code/SKILL.md step 6; validation-loop.md (fix round limit) |
| `validate_low_score` | `stop` · `accept` | validate-code validation-loop.md outcome table (score < 8.0) |
| `review_post` | `no` · `inline` · `summary` | review-code SKILL.md step 6 (post to PR) |
| `review_language` | `English` · `Português (BR)` | review-code SKILL.md step 6 (language) |
| `review_style` | `short` · `suggestions` | review-code SKILL.md step 6 (style) |
| `review_low_score` | `stop` | review-code diff-verdict-and-rules.md (review score < 8.0 or CRITICAL) |

A key with value `stop` means the skill ends the run at that step and reports why. It is never
a reason to continue with a guess.

## Questions with no key

Asks that are not in the table — several plans to choose from, a mini-plan to approve, a missing
Design section, a spec path to supply — have no key. Print `NEEDS_USER: <question>` as the last
line and stop. The caller treats that line as a human decision.

## Sentinels

A headless skill prints exactly one sentinel as its **last line**. The caller reads only the last
occurrence in the stage's final result.

| Skill | Last line | Values |
|---|---|---|
| `/validate-code` | `VERDICT_LINE: <verdict> <score>` | `<verdict>` is one of `PRODUCTION READY` · `READY WITH CONDITIONS` · `NOT READY` (the exact strings `scripts/verify/verdict.sh` emits); `<score>` is the verdict's score |
| `/review-code` | `REVIEW_SCORE: <score> <pass\|block>` | `pass` exactly when the verdict table in `diff-verdict-and-rules.md` passes (score ≥ 8.0 and no CRITICAL); `block` otherwise |

`NEEDS_USER: <question>` (above) is the third sentinel. Any skill may print it at any step.

A skill that reaches its final step without a sentinel line has failed the contract: the caller
stops the run on the missing line. Do not print a sentinel to mark a stop that is not a verdict.

The sentinel is the plain last line: no markdown, bold, backticks or blockquote around it.

## Driver

`scripts/drive.py` runs `/code` → `/validate-code` → `/review-code` as three fresh `claude -p`
sessions for one approved plan. It is opt-in: the manual skill flow is unchanged.

    python3 scripts/drive.py --plan docs/plans/{slug}/plan.md [--model sonnet] [--mode sequential] \
        [--budget-usd 3] [--resume-from code|validate|review]

- `--model` defaults to `sonnet`; `--mode` is one of `inline`, `single`, `sequential`, `parallel`.
- `--resume-from <stage>` reruns from that stage and keeps the earlier recorded results. It needs a
  schema-valid `docs/plans/{slug}/run-state.json`.

Exit codes: `0` all three stages advanced · `1` stopped by a rule (reason printed and recorded in
run-state.json) · `2` refused before any stage ran, or malformed arguments.

Preconditions, all checked before any session starts (refusal prints `drive: REFUSED — <reason>`):
the plan `Status` is `approved`; the slug (the plan's directory name) matches `^[a-z0-9-]+$`; the
branch is not `main` or `master`; `git status` lists nothing outside `docs/`, tracked or untracked;
a `--resume-from` run has a valid run-state.json.

The driver never pushes and never opens a PR. It stops after review, and a usage-limit stop halts
without a retry.
