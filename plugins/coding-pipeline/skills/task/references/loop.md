# Task pipeline — sub-task loop detail

## Phase 1 — Planning (once)

> **Backend-Driven Architecture check (mandatory):** Verify tier placement for every component: **Frontend** = render only; **BFF** = orchestrate + shape for UI; **Core** = domain logic. Flag and push back on any AC asking the wrong tier to own logic.

Load and follow `skills/planning/SKILL.md` starting from **Phase 1 (Architecture)**.

- Skip Phase 0 — task description is the input; Brief + PRD not required.
- Derive tech stack from existing codebase if present.
- Phase 2 (grill-me plan stress) and Phase 3 (human validation of unresolved questions) are mandatory before any coding.
- Produce **Task Manifest** (Phase 4 single-task path). Confirm before continuing.

**Sub-task sizing rules:**
- Max ~200 lines of production code per sub-task
- Each sub-task has a clear interface boundary (function, class, module, endpoint)
- Sub-tasks must be independently testable — split if not

## Phase 2 — Sub-Task Loop (repeat per sub-task)

**A. Story** — `agents/scrum-master.md`, dispatched only when the Task Manifest has **≥ 2 manifest rows**; a single-row manifest has the orchestrator fill the story template directly, no dispatch
Input: Task Manifest row + the delivery file → Output: `docs/deliveries/{key}/story-{slug}.md` (include the row's declared Roster)

**B. Code (Spec→Implement→Test→Falsify)** — sub-agent with `agents/coder.md` (core) + ONE tier overlay + `story-{slug}.md`

> Runs **inside the delivery worktree** (`.worktrees/dlv-{key}/`) and **one sub-task at a time** —
> sub-tasks share that single worktree, so two concurrent Coders would overwrite each other.
> **Cut `feat/{key}-{story-slug}` from the release branch before coding.** In `pr` mode (no
> remote/`gh` unavailable = `local` mode, decided once per delivery — D1): commit → push →
> `gh pr create --draft --base release/{slug}-{key}`; the Reviewer posts inline via `gh pr review`
> and `gh pr ready` gates the merge. In `local` mode: commit to the branch only, and the Reviewer
> writes its findings to `docs/deliveries/{key}/review-{story-slug}.md` for the human to read
> later. Merge back with `--no-ff` once the Verdict passes. Only a genuinely trivial sub-task
> (manifest projected under ~50 lines) commits straight to the release branch, and taking that
> exception is stated, not silent. Never commit or merge to `main`. Branch table:
> `../../references/delivery-and-worktree.md`.
- **Stack-aware dispatch**: pick the overlay by the sub-task's Tier — `agents/coder-backend.md` (server/API/domain) or `agents/coder-frontend.md` (UI/SSR/client). Load only `references/languages/<language>.md` for the sub-task's `Language` — never the index. Full-stack sub-tasks were split BE/FE around the `api-spec.yaml` contract (BE producer first, then FE consumer). No frontend stack → frontend coder never spawned.
  - **Frontend sub-task creating or materially redesigning visual surface** (new page/component/theme/layout — not a pure logic/state change): before dispatching the frontend coder, invoke `/frontend-design` for a compact design plan (palette, type pairing, layout concept, signature element) and include it in the coder's dispatch prompt. Skip for backend-only sub-tasks and frontend sub-tasks that don't touch visual surface.
- **Model**: haiku, except **sonnet for roster `full`** — haiku misreported coverage twice on a `full` sub-task (PROGRESS.md). A fix round is always a **fresh, narrowly-scoped Coder dispatch**, never a resumed context.
- **Split a dispatch that spans many files.** A prompt naming a large file set stalls rather than finishing — `dispatch-budget.sh` warns once past its threshold, but the fix is narrowing the dispatch, not reading past the warning; break it into per-file or per-component dispatches instead.
- Dispatch prompt carries the contract: `Gate outputs below were run by the orchestrator. Do not re-run tests, linters, coverage, dup-gate, security-scan or tautology-scan; read the attached output.`
- The story ACs + Definition of Done are the frozen acceptance contract — Coder satisfies it, never redefines it
- Coder runs Phase 0 Analysis, then Phase 1 implement to the frozen Test Case table → Phase 2 write exactly the specified tests → Phase 3 falsify each one (apply the row's break, confirm the assertion fails, restore) — owns both test and impl files
- Coder emits `CODER DONE` with spec coverage ({n}/{N} rows) and one falsification evidence line per test
- Orchestrator stores compact ref: `"ST1: {file}.{ext} + tests, {N} lines, implements {Interface}"`

**Checkpoint M** *(after every Coder return, including every fix round, and after ANY agent exit
— done, stalled, rate-limited, or killed — before anything else runs)*: one command, not a
hand-run list —
```
scripts/verify/checkpoint-m.sh --base release/{slug}-{key} --spec story-{slug}.md \
  --tests <path>... --expect <file>... [--declared {roster}] [--gates "<cmd>"]
```
**Fail fast** — it composes what used to be a hand-run list into one command, so the orchestrator
does not have to run every mechanical check itself, and returns all failures at once, never a
bail-out on the first red one: every Test Case row implemented by exact name (spec-coverage.sh),
the changed-file set exactly matching `--expect` (a rename counts as touching both paths, a
deletion counts as touching the deleted path — missing or extra either one is a FAIL), no commit
on HEAD beyond `--base`, no leftover `*.devkit-break` marker anywhere in the tree, the duplication
gate (`git-hooks/dup-gate.sh`, the same sensor `dup-gate.sh --worktree` runs elsewhere to also
cover uncommitted work), and the roster read (internally `classify-diff.sh --diff` against
`--base`, surfaced here as `--declared {roster}`) — into one `M: PASS` / `M: FAIL (n)` line.
Exit 2 is unmeasured, not a pass — route it exactly like a FAIL, never read it as a silent skip.
- The orchestrator still re-breaks a sample of the falsification evidence by hand with
  `break-run.sh` — an agent's claimed break is a claim, not proof; `checkpoint-m.sh` proves the
  marker is gone, not that the break itself was real.
- `classify-diff.sh`'s escalation is binding: `ROSTER: ESCALATE` means dispatch the agents the
  heavier roster requires, never override the sensor's read of the diff. Re-measure only after
  fixing whatever made the diff look heavier (an unrelated file touched, scope that crept) — never
  by arguing with the exit code.

Any FAIL or exit 2 → back to the Coder with the output; no QA, Reviewer or Stress dispatch. Every Coder fix — whether it came from M, QA, Reviewer or Stress — goes back to M before any agent sees the code again. 3 round trips at one checkpoint → ask the operator: fix differently / relax scope / stop.

**C. QA audit + gates** — `agents/qa.md`, dispatched for roster `standard` and `full` (`cosmetic` has no spec table to audit; `light` is audited by the Reviewer instead — see the Roster table in `CLAUDE.md`)
Input: ACs from Task Manifest (including Security ACs) + Amelia's tests + the diff — `git diff --name-only release/{slug}-{key}...HEAD`
Quinn audits the tests (spec-row completeness, falsification evidence + spot-checks, intent-encoding, corner cases, no tautologies via `tautology-scan.py --diff` — see qa.md Test Audit), then runs the repo-wide gates she owns (coverage, race). Quinn authors no tests.

> **Run the sensors before Quinn reasons.** `scripts/verify/spec-coverage.sh`,
> `scripts/verify/falsification.sh` and `scripts/verify/tautology-scan.py --diff` decide spec-row
> completeness, evidence validity and the mechanical tautology shapes by exit code — already run at
> checkpoint M. Quinn reads their output and spends her pass on what they cannot decide: whether
> each break matches the behaviour, the spot-check re-breaks, over-mocking, intent-encoding and
> corner cases.

Route on Quinn's output signal:

- `QA→REVIEWER APPROVAL` → proceed to D (Reviewer ∥ Stress)
- `QA→CODER BUG REPORT`, `QA→CODER TEST GAP`, or `QA→CODER COVERAGE REQUEST` → Coder → back to M → QA — never straight to D
- `QA ESCALATION` (after 3 iterations) → proceed to D with FAIL status

See `references/quality-gate-reference.md` **Bug-Fix Loop Protocol** (and **Loop Integrity** — no goalpost-moving, stop on an identical repeat failure, compact only at story boundaries) for exact procedure, iteration counting, and coverage failure sub-path.

**D. Reviewer ∥ Stress** *(triggered by QA signal for `standard`/`full`, or directly after checkpoint M for `light` — never before QA approval or escalation when QA ran)*:
- `agents/reviewer.md` → the diff (`git diff --name-only release/{slug}-{key}...HEAD`) + the attached sensor output, language-specific checks, **plus the acceptance contract**: the story (ACs + Test Case table), the delivery file's Reuse Map, and `codebase-map.md`. Without them the Reviewer's own escape clause fires and CD1/CD3/CD7 — every intent and scope check — is skipped silently, which is how a diff that builds the wrong thing scores 8/10.
- Reviewer runs `security-scan.sh --diff` on the changed paths first and adjudicates the
  `file:line` candidates, rather than reading every file hunting for the patterns.
- For roster `light`/`standard` the Reviewer also folds the Stress lens: reads `agents/stress.md`, applies its categories to the diff, and emits its own Stress Score + Hard Gates lines.
- **StressTester is dispatched separately only for roster `full`, or when `STRESS-TRIGGER: yes` from `security-scan.sh --diff` is not explained by test-fixture strings** → `agents/stress.md` → full code + tests, Security Under Stress.
- Both dispatch prompts carry the dispatch prompt contract line from B.
- One fix round covers both Reviewer and Stress findings together, then re-check.

If Reviewer or StressTester emits `TUNER REQUEST` → load `agents/tuner.md` (Tyler):
- Tyler applies MINOR/NIT fixes; emits `TUNER COMPLETE`
- Re-checks after a fix round are **narrow, never a full re-review**: QA re-audits only if tests changed, resuming the same QA agent rather than a fresh dispatch; Reviewer and Stress each run a confirmation pass on only their own prior findings, on haiku.
- Any code fix — Tuner's included — goes back to M first.
- Maximum 2 iterations; on `TUNER LIMIT REACHED` → proceed to E

**E. Verdict** — `scripts/verify/verdict.sh --roster {roster} --classify-exit {n}` computes the gate, score and threshold; `agents/verdict.md` is read once per delivery and its Security Gate, narrative and Verdict Self-Check are applied **inline by the orchestrator** — no Verdict agent is dispatched per sub-task
Input: Review score + Stress score (dispatched or folded) + QA summary (when QA ran) + AC checklist + Gate Report
Unmitigated CRITICAL security = automatic NOT READY. `--classify-exit` non-zero (the declared roster was under-scoped) is itself a NOT READY reason, independent of score.

**F. Checkpoint**

| Score | Security | Gates | Action |
|-------|----------|-------|--------|
| ≥ 8.0 | No CRITICAL | All green | `pr` mode: `gh pr ready` → `git merge --no-ff` into the release branch, push. `local` mode: `git merge --no-ff` only. Next sub-task or final summary |
| ≥ 8.0 | CRITICAL | Any | NOT READY — fix security first |
| < 8.0 | Any | Any | Show issues; ask: *"Fix and re-run / skip / stop?"* |

The Reviewer's pass on the sub-task's own diff is the sub-task-level review — there is no separate review dispatch at that level. The release branch keeps its own pull-request review, unchanged, for cross-story duplication and plan drift.

On re-run: pass only delta (CRITICAL/MAJOR issues + failing ACs + failed gates).

After each sub-task Verdict, append a `PROGRESS.md` entry at the repo root (Done / Failed / Current State / Next — see `references/progress-file.md`) so the next session boots with state.

**Post-verdict (PRODUCTION READY)**: load `agents/devops.md` (Ops) — generates Dockerfile, .dockerignore, docker-compose.yml, optional CI/k8s.

> **Context Budget — 80% is a hard ceiling.** Measured by `hooks/context-budget.sh`; full rule in
> [`references/context-budget.md`](../../../references/context-budget.md). Compact at 60%, `/handoff` at 80%,
> and never record session state in a source file.
Use `references/output-format.md` headers. Show Pipeline Summary after each Verdict. Load agent files on demand — never pre-load all at once.
