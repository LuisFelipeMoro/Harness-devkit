# PROGRESS

## [2c9fee] Diff-Scoped Story Loop — all 10 merged into the release branch; release PR next

**Resume here.** Delivery-Key `2c9fee` · worktree `.worktrees/dlv-2c9fee` · branch
`release/diff-scoped-story-loop-2c9fee` · delivery file
`docs/deliveries/delivery-diff-scoped-story-loop-2c9fee.md` · manifest
`docs/deliveries/2c9fee/task-manifest.md` (both gitignored, local only). Plan APPROVED (2 rounds).
**Next: push the release branch, open the PR to main, `/pr-review` on it (human merges).** — spec already carries 4 pre-empted rows (symlink
named like a style file, source deletion, newline name, security-scan exit 2 propagation).
Start the next session from the worktree (`cd .worktrees/dlv-2c9fee`) so this file is the one bootstrapped.

| ST | Roster | Result | Tokens |
|---|---|---|---|
| ST1 bug-fix named agents + validate-wiring §7 host | light | merged `b713c88`, Review 6→9 | Coder 59k + fix 80k · Review 66k · confirm 40k (haiku) ≈245k |
| ST2 diff-lib + security-scan --diff | full | merged `faa69bc`, 8.35 (R9 S8 Q8) after Stress 3 CRITICAL | ≈968k (haiku Coder rounds 207k wasted, sonnet 336k) |
| ST3 tautology-scan --diff | full | merged `80fbe00`, 8.65 (R9 S8 Q9) after R6/S7 | ≈738k |
| ST4 classify-diff.sh | full | merged `9b9d972`, 8.65 (R9 S8 Q9) after Stress 2 CRITICAL (code in .css/.md or a disguised rename classified cosmetic, no scan) → D3 amendment; QA then caught rename+content shadowing | Coder 215k + 2 stalls + 228k + 92k (sonnet) · QA 168k (4 rounds) · Review 122k + 57k haiku · Stress 85k + 66k haiku · ≈1.03M |
| Batch A: ST5 verdict roster · ST9 bench · ST10 --manifest | standard | merged `9c1f39b`, 8.0 (R8 Q8) after R6 (unrecognized roster silently dropped) | first Coder died mid-falsification (left stress.md out; restored) · COST-test decouple 88k · fix 98k (reverted thresholds.md — restored) · QA 131k · Review 116k + 64k haiku ≈ 0.65M |
| Batch B: all docs (ST6 ST7 ST8 ST10) — last, per operator | light | merged `5f2846a`, Review 9 | one oversized Coder stalled; split into 3 parallel (163k+155k+163k) + contract rows 106k + review 142k + tuner 58k ≈ 0.8M |
| — | — | `29a5225` removed a probe file a Stress agent committed into ST2 | — |

Planning 440k (map 77k haiku · architect 184k opus · plan-review 179k sonnet). **Measured result** (bench-context.py vs v2.6.0): dispatches per 5-story delivery 40 → 20 (mixed 18); guide tokens 244,170 → 209,394 (−14.2%). Delivery cost ≈4.9M tokens (legacy loop est. 6–7M+). Earlier estimate lines follow. Spent ≈2.39M after ST3;
remaining estimate ≈1.9M (ST4 ~550k · ST5/9/10 ~280k · ST6–8 ~170k); delivery ≈4.3M vs ~6M+ legacy.

Parallel since ST4 (operator: "can't we do batch changes"): batch A (ST5+ST9+ST10 code) in `.worktrees/dlv-2c9fee-scripts`; batch B (all docs) runs LAST (operator: docs must see the final state).
Checkpoint M checks the exact changed-file set (a fix Coder silently reverted thresholds.md; extras-only check missed it).

### Loop rules in force (operator-approved 2026-09-23; ST6 writes them into loop.md)
- Roster per manifest row (cosmetic · light · standard · full); mechanical gates run on every roster.
- **Checkpoint M after every Coder return**: run ALL mechanical checks and return every failure at
  once — spec rows by exact name, falsification re-breaks by the orchestrator (each FAIL line must
  name its row), all suites, shellcheck, dup-gate, `git diff --name-only main...HEAD` holds only
  expected files. Any FAIL/UNMEASURED → back to Coder, no agent dispatched. 3 round trips → ask.
- QA rejection → Coder → M → QA; Reviewer ∥ Stress only after QA approval; one fix round for both.
- Re-checks after D are narrow: QA only if tests changed (resume the same QA agent, ~25k);
  Reviewer/Stress confirm only their own findings on haiku (~50k each).
- Coder model: sonnet for `full` (haiku misreported coverage twice on ST2); fix rounds = a fresh
  Coder with a narrow prompt, not a resumed large context (184k for a 3-line fix).
- Every dispatch prompt: "Gate outputs were run by the orchestrator. Do not re-run …".
- Execution-options checkpoint (ST10) after plan approval, before code.

## Lessons (session 3 — 2026-09-23)
- **An agent's report is a claim, not evidence.** A haiku Coder reported 20/20 rows with 7 present
  and quoted falsification for tests that did not exist; a sonnet Coder reported a break that
  "failed" but printed nothing. Only the orchestrator's by-name row check and its own re-breaks
  caught them.
- **A failing assertion must name its row.** `case … fail=1` failed the suite silently; the
  orchestrator's grep for `FAIL: <row>` read it as unfalsified. Every assertion prints its name.
- **Fixtures can pass for the wrong reason.** A deletion test removed a file absent from the
  branch (`git rm … || true`) and passed on an empty diff; an "unchanged debt ignored" test never
  had the file on disk. Falsify by breaking the code path, not by trusting the green run.
- **Agents that died mid-falsification leave the code broken.** Twice (rate limit, stall) a file
  was left mutated (`"HEAD~1"`). Keep a pre-break copy and verify it after every agent exit.
- **Agents commit where they probe.** A Stress agent told to use `$TMPDIR` committed its
  `evil\nline.js` fixture onto the story branch; it merged. Check M must diff the commit history,
  not only the working tree.
- **Stress is the lens that finds the escapes.** Both `full` stories' worst defects (newline false
  clean scan; symlink followed / directory-symlink fail-open PASS) came only from Stress. Carry
  each story's Stress findings into the next story's spec before code.
- **Resuming beats re-dispatching for small re-checks** (QA resume ~25k vs ~80k fresh), but
  resuming a large Coder context for a small fix is the most expensive option measured.
- **Oversized agent prompts stall.** Four stream-watchdog stalls, all on prompts spanning many files; splitting the docs batch into three disjoint parallel agents finished each in ~17 min.
- **Fix Coders revert files they were told not to edit.** A fix round "reverted thresholds.md per task spec"; checkpoint M now compares the exact expected file set, not just "no extras".
- **Tests coupled to production data break when the data gets real.** The COST "assumed" test depended on the live table having qa n=0; recording a measurement broke it — tests supply fixtures.
- **A classifier that trusts a name is a bypass.** Symlink-by-name (ST2/ST3) then extension-by-name (ST4): `evil.css` and `git mv x.ts x.css` classified cosmetic. Content must be scanned before any roster is lowered.
- **Estimates must model rework.** The execution-options estimate counts first passes; full-roster stories here added 40–60% in fix rounds.
- **TEST_FILE misses the devkit's own `test-*.sh`** — classify-diff will over-escalate devkit stories touching tests. Follow-up.
- **Plan-review agents cost like implementers** (165–184k). The reviewer floor applies to them too.

## Done — 2026-09-22 (session 2) · review fixes, dup-gate, autonomous context

Branch `release/token-dispatch-reduction`: `2880471` = pass 1 as reviewed; second commit = everything
below. Not pushed. All 6 suites green (hooks 62 · git-hooks 32 · dup-attribution 11 · install 21 ·
verify 12 · wiring), every new test falsified by reverting its fix.

- **Pass-1 review (5/10 → fixed)**: spec-coverage/falsification substring match (a PASS with a
  specified test never written) → whole-name; dispatch budget 12/25 drift → 14 everywhere (the
  formula 3×3+3+2 was mis-added); security-scan UNMEASURED exit 2 on unreadable paths, skips `*.md`
  and itself; tautology-scan exit 2 on 0 files; verdict.sh enforces the story floor; context-budget
  counts `output_tokens`, skips sidechain turns, one interpreter per call; QA security table has a
  mechanical load trigger and an auditable skip line.
- **`git-hooks/dup-gate.sh`**: single owner of jscpd flags + attribution; pre-push calls it;
  `--worktree` measures uncommitted work in a throwaway worktree. Seven guides told agents to run raw
  repo-wide jscpd (markdown + old debt included) — repointed. Per-run report dir; runs from any subdir.
- **Installer**: stray gitignored dir in `git-hooks/` (`__pycache__`) aborted `install-global.sh`
  under `set -e`; now copies files only (RED test first).
- **`test-verify.sh`** (new, in CI): the five verify scripts had no test at all.
- **Autonomous context** (no human step): 80% message = checkpoint + continue;
  `precompact-snapshot.sh` (PreCompact, never blocks, 5s timeout) records branch/dirty/commits/
  PROGRESS staleness; `session-bootstrap.sh` re-injects it on `source=compact` (same session id only)
  and re-arms the 60/80 latches; window inferred (usage >200k ⇒ 1M) unless `DEVKIT_CONTEXT_WINDOW`.
- Review rounds: 5/10 → 6/10 → 9/10 (dup-gate) · 6/10 (autonomy) → 9/10 APPROVE.

## Benchmark — 2026-09-22 (measured; tokens = bytes/3.6)

| Check | model would read | script prints | saving |
|---|---:|---:|---:|
| duplication (raw jscpd → dup-gate) | 6,784 | 91 | 75× |
| security (changed files → scan) | 66,568 | 365 | 182× |
| tautology (38 Go test files) | 52,257 | 65 | 797× |
| verdict (agent guide → verdict.sh) | 1,633 | 74 | 22× |

Reviewer dispatches this session: 161k (100 KB diff) · 128k (37 KB delta) · 104k (narrow, but re-ran
suites) · 94k (20 KB, 3 tool calls). **Floor of a reviewer dispatch ≈ 90k regardless of payload** —
the agent's own guides dominate. Guide tokens/delivery 253,056 → 244,170 (−3.5%); dispatches 40 → 40.

## Lessons (session 2)

- **The guide and the sensor disagreed, and the agent followed the guide.** `/quality-gate` said
  repo-wide jscpd; pre-push ran attribution. Eight tool calls produced a wrong FAIL. Fix the guide by
  pointing it at the sensor, never by restating the sensor's flags.
- **A reviewer re-running gates the orchestrator already ran is the largest avoidable cost.** Say
  "do not run tests" in the dispatch; it cut a round from 128k to 94k.
- **Fixed temp paths are races.** Found three (`devkit-jscpd`, `devkit-githook-tests`, and the
  reviewer's own concurrent run colliding with mine). Per-run `mktemp -d`.
- **An apostrophe in a comment inside `python3 -c '…'` breaks the hook.** Existing tests caught it.
- **Falsify on the path the test actually reaches.** One mutation sat behind a `$PWD` fallback and
  proved nothing; re-falsified on the exit path.

## Next (pass 2 — unchanged, plus)

- Install: `bash install.sh` — none of the new hooks run in `~/.claude` until then.
- Pass 2 as below; add to it: dispatch prompts forbid re-running gates; measure the reviewer floor
  (~90k) and whether a `haiku` confirmation round is enough for fix-verification.
- Follow-up: git lock contention when two `dup-gate --worktree` runs share a repo (false
  "could not snapshot", never a false pass).

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
