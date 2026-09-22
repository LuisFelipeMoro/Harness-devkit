# PROGRESS

## Done — 2026-09-22 · devkit token & dispatch reduction (pass 1)

Working tree only, nothing committed, all 5 CI suites green
(`validate-wiring` · hooks 51 · git-hooks 27 · dup-attribution 11 · install 20).

**Sensors added** — both were Guides with no Sensor, the same defect `delivery-gate.sh` fixed once:
- `hooks/context-budget.sh` — reads real context fill from the session transcript
  (`input + cache_read + cache_creation` of the last assistant turn). Warns 60%, ceiling 80%.
  Wired PostToolUse. The 80% rule was stated in three files and enforced in none.
- `hooks/dispatch-budget.sh` — counts subagent dispatches, warns once past `DEVKIT_DISPATCH_BUDGET`
  (12 — derived: 3 per story + 3 planning + 2 delivery). Wired PreToolUse(Agent|Task). Never blocks.

**Reasoning → mechanical**, `plugins/coding-pipeline/scripts/verify/`, each falsified against a fixture:
`spec-coverage.sh` · `falsification.sh` · `tautology-scan.py` · `security-scan.sh` · `verdict.sh`.
Each prints what it does *not* cover so the judgment half stays with the agent.

**Single-sourced**: `references/thresholds.md` (coverage was restated in 18 files, duplication in 9;
`verdict.md` had already dropped React/Flutter/Kotlin). Also extracted `context-budget.md`,
`security-checklist.md`, `test-audit-reference.md`, `harness-metrics.md`.

**Benchmark**: `scripts/bench-context.py` — 253,056 → 243,406 guide tokens per 5-story delivery
(−3.8%), dispatches unchanged at 40.

## Failed / wrong first time

- `tautology-scan.sh` hung on macOS — backreferences are not portable in `grep -E` (BSD vs GNU).
  Rewritten as `tautology-scan.py`.
- `security-scan.sh` missed SQL injection built on one line and executed on another — a call-site
  grep only catches the concat when it sits inside the `Query(...)` call. Added `INJECTION-SQL-BUILD`.
- `context-budget.sh` downgraded CEILING to a *warning* on the second call: the ceiling branch was
  latched, so control fell through to the un-latched warn branch. Caught by the new hook test.

## Current State

Handoff doc (rich narrative): `/tmp/handoff-2026-09-22-154451.md`.
No delivery in flight — no Delivery-Key, no worktree, no release branch. Working-tree work on `main`.

20 files changed, uncommitted, on `main`. **Not yet run: `/code-review-gate` on the diff** — the
session hit 95% context, which is what the new ceiling sensor exists to catch.

## Next — pass 2: diff-scoped validation at draft-PR time

The measured economy of the mechanical scans is **31×** (security-scan vs reading changed source)
and **137×** (tautology-scan vs reading a test suite). None of it lands yet, because `loop.md`
still hands the Reviewer "full code" and the scans default to the whole tree. Pass 2 changes the
loop to the shape an agile team actually uses:

```
B  code → commit → push feat/{key}-{story-slug} → open DRAFT PR
C  QA        scope = git diff --name-only release/{slug}-{key}...HEAD
             diff-scoped: spec-coverage, falsification, tautology-scan
             repo-wide  : coverage, jscpd, vuln, race   ← must stay repo-wide
D  Reviewer  same diff scope; security-scan on it; posts inline on the draft PR
E  verdict.sh
F  gh pr ready → merge --no-ff
```

One reviewer, one diff, one PR. Ordered:

1. Rewrite `skills/multi-agent/references/loop.md` + `skills/task/references/loop.md` steps B–F to
   the block above; add the diff-scope command as the first line of C and D.
2. Add `--diff <base>` to `security-scan.sh` and `tautology-scan.py` so scope is a flag, not a
   convention that erodes.
3. **Delete the story-level `/pr-review` dispatch.** The Reviewer *is* the PR reviewer. The
   release-PR review stays — it is the only pass that sees cross-story duplication and plan drift.
4. Fold `agents/stress.md` into the Reviewer as a conditional section, dispatched separately only
   when the story's Blast Radius touches shared mutable state, external I/O, or an auth surface.
5. Drop the ScrumMaster dispatch for single-row manifests (template fill, orchestrator inline).
6. Re-run `scripts/bench-context.py --baseline` and record the real delta.

Target: 40 → ~20 dispatches for a 5-story delivery, 3 per story.

**Also unfixed**: `skills/bug-fix/references/dispatch.md` dispatches `subagent_type: "claude"`
instead of the named `bug-investigator` / `coder` agents, so Sam and Amelia lose their
`sonnet` / `haiku` model assignment.

## Lessons

- **A guide restated in N files has already drifted in one of them.** The coverage floor appeared
  in 18 files; `verdict.md` was missing three languages. Found by grep, not by reading.
- **Measure the thing you are actually changing.** The guide-token benchmark showed −3.8% and was
  technically correct and nearly useless: the saving from mechanical checks is read-avoidance, which
  only appears once the scans are diff-scoped. A benchmark aimed at the wrong quantity reports a
  true number about the wrong thing.
- **Write the test for a new sensor before trusting it.** The context-budget latch bug was invisible
  by reading and obvious to a two-line test case.
- **`grep -E` backreferences are not portable** (BSD vs GNU). Anything needing one goes in Python.
- **zsh does not word-split unquoted variables.** A `$FILES` holding several paths reaches `cat` as
  one filename; use an array or `${=VAR}`.
