# Epic Loop — dispatch detail

Steps A–F of `SKILL.md` Phase 2, repeated per epic. All work happens inside the delivery
worktree (`.worktrees/dlv-{key}/`) on `release/{slug}-{key}` — see
[../../../references/delivery-and-worktree.md](../../../references/delivery-and-worktree.md).

**A. Stories** — `agents/scrum-master.md`, dispatched only when the Epic Manifest for this epic has **≥ 2 manifest rows**; a single-row epic has the orchestrator fill the story template directly, no dispatch
- Input: Epic Manifest rows for current epic + the delivery file
- Output: one `story-{slug}.md` per task (scoped architecture sections only; include Security Points and the row's declared Roster)

**B. Coding (Spec→Implement→Test→Falsify)** — one subagent per story, **dispatched one at a time**:

> Stories share the delivery's single worktree, so they run **sequentially** — story N clears checkpoint M and Verdict before story N+1 is dispatched. Never run two Coder subagents against the same worktree; they would overwrite each other. Read-only Explore/mapping subagents may still run in parallel.
> **Each story gets its own branch** — `feat/{key}-{story-slug}`, cut from the release branch. In `pr` mode (no remote/`gh` unavailable = `local` mode, decided once per delivery — D1): commit → push → `gh pr create --draft --base release/{slug}-{key}`; the Reviewer posts inline via `gh pr review` and `gh pr ready` gates the merge. In `local` mode: commit to the branch only, and the Reviewer writes its findings to `docs/deliveries/{key}/review-{story-slug}.md` for the human to read later. Merge with `--no-ff` either way so the story stays legible as a unit in the release history. Branch table and commands: `../../references/delivery-and-worktree.md`.
- **Stack-aware dispatch**: each subagent gets `agents/coder.md` (core) + ONE tier overlay chosen by the story's Tier — `agents/coder-backend.md` (server/API/domain) or `agents/coder-frontend.md` (UI/SSR/client). Load only `references/languages/<language>.md` for the story's `Language` — never the index.
  - Backend-only story → backend coder. Frontend-only → frontend coder.
  - Full-stack story was already split by the ScrumMaster into BE + FE sub-stories sharing the `api-spec.yaml` contract (BE = producer, FE = consumer). Dispatch each to its tier coder; run BE first so the spec is real before FE consumes it.
  - If the repo/plan has no frontend stack, the frontend coder is never spawned (zero overhead).
  - **Frontend story creating or materially redesigning visual surface** (new page/component/theme/layout — not a pure logic/state change): before dispatching the frontend coder, invoke `/frontend-design` to produce a compact design plan (palette, type pairing, layout concept, signature element), then include that plan in the coder's dispatch prompt. Skip for backend-only stories and for frontend stories that don't touch visual surface (state management, data wiring, a11y-only fixes).
- **Model**: haiku, except **sonnet for roster `full`** — haiku misreported coverage twice on a `full` story (PROGRESS.md). A fix round is always a **fresh, narrowly-scoped Coder dispatch**, never a resumed context: resuming a large Coder transcript for a small fix was the single most expensive path measured.
- **Split a dispatch that spans many files.** A prompt naming a large file set stalls rather than finishing — `dispatch-budget.sh` warns once past its threshold, but the fix is narrowing the dispatch, not reading past the warning; break it into per-file or per-component dispatches instead.
- Each receives: `agents/coder.md` + the tier overlay + `story-{slug}.md` (+ the design plan, when produced) + the dispatch prompt contract: `Gate outputs below were run by the orchestrator. Do not re-run tests, linters, coverage, dup-gate, security-scan or tautology-scan; read the attached output.`
- The story ACs + Definition of Done are the frozen acceptance contract — Coder satisfies it, never redefines it
- Coder runs Phase 0 Analysis, then Phase 1 implement to the frozen Test Case table → Phase 2 write exactly the specified tests → Phase 3 falsify each one (apply the row's break, confirm the assertion fails, restore) — owns both test and impl files
- Coder emits `CODER DONE` with spec coverage ({n}/{N} rows) and one falsification evidence line per test
- Orchestrator stores compact ref: `"T1.1: {file}.{ext} + tests, {N} lines, implements {Interface}"`

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
- Input: ACs from Epic Manifest (including Security ACs) + Amelia's tests + the diff — `git diff --name-only release/{slug}-{key}...HEAD`
- Quinn audits the tests (spec-row completeness, falsification evidence + spot-checks, intent-encoding, corner cases, no tautologies via `tautology-scan.py --diff` — see qa.md Test Audit), then runs the repo-wide gates she owns (coverage, race). Quinn authors no tests.

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

See `references/quality-gate-reference.md` **Bug-Fix Loop Protocol** (and **Loop Integrity** — no goalpost-moving, stop on an identical repeat failure, compact only at story boundaries) for exact loop procedure, iteration counting, escalation format, and coverage failure sub-path.

**D. Reviewer ∥ Stress** *(triggered by QA signal for `standard`/`full`, or directly after checkpoint M for `light` — never before QA approval or escalation when QA ran)*:
- `agents/reviewer.md` → the diff (`git diff --name-only release/{slug}-{key}...HEAD`) + the attached sensor output; apply language-specific checks; **pass the acceptance contract with it** — the story (ACs + Test Case table), the delivery file's Reuse Map, and `codebase-map.md`. Without them the Reviewer's own escape clause fires and CD1/CD3/CD7 — every intent and scope check — is skipped silently, which is how a diff that builds the wrong thing scores 8/10.
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

**E. Verdict** — `scripts/verify/verdict.sh --roster {roster} --classify-exit {n}` computes the gate, score and threshold; `agents/verdict.md` is read once per delivery and its Security Gate, narrative and Verdict Self-Check are applied **inline by the orchestrator** — no Verdict agent is dispatched per story
- Input: Review score + Stress score (dispatched or folded) + QA summary (when QA ran) + AC checklist
- Security Gate section required; unmitigated CRITICAL security = automatic NOT READY
- `--classify-exit` non-zero (the declared roster was under-scoped) is itself a NOT READY reason, independent of score

**F. Checkpoint**

| Score | Security | Action |
|-------|----------|--------|
| ≥ 8.0 | No CRITICAL | `pr` mode: `gh pr ready` → `git merge --no-ff` into the release branch, push. `local` mode: `git merge --no-ff` only. Proceed to next epic or show final summary |
| ≥ 8.0 | CRITICAL security | NOT READY — security fix required; re-run pipeline after fix |
| < 8.0 | Any | Show issues; ask: *"Fix and re-run / skip / stop?"* |

The Reviewer's pass on the story's own diff is the story-level review — there is no separate review dispatch at story level. The release branch keeps its own pull-request review, unchanged, for cross-story duplication and plan drift.

On re-run: pass only the delta (CRITICAL/MAJOR issues + failing ACs).

After each epic Verdict, append a `[{key}]`-prefixed `PROGRESS.md` entry at the repo root (Done / Failed / Current State / Next — see `references/progress-file.md`) so the next session boots with state.

**Post-verdict (PRODUCTION READY on final epic only)**: load `agents/devops.md` (Ops) — generates Dockerfile, .dockerignore, docker-compose.yml, optional CI/k8s.
