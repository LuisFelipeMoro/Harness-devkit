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

**A. Story** — `agents/scrum-master.md`
Input: Task Manifest row + the delivery file → Output: `docs/deliveries/{key}/story-{slug}.md`

**B. Code (Spec→Implement→Test→Falsify)** — sub-agent with `agents/coder.md` (core) + ONE tier overlay + `story-{slug}.md`

> Runs **inside the delivery worktree** (`.worktrees/dlv-{key}/`) and **one sub-task at a time** —
> sub-tasks share that single worktree, so two concurrent Coders would overwrite each other.
> **Cut `feat/{key}-{story-slug}` from the release branch before coding** — that branch is the unit
> of review, and its own PR into `release/*` is where `/pr-review` runs with this sub-task's ACs,
> Test Case table, Reuse Map and Blast Radius in context. Merge back with `--no-ff` once the Verdict
> passes and the story PR is green. Only a genuinely trivial sub-task (manifest projected under ~50
> lines) commits straight to the release branch, and taking that exception is stated, not silent.
> Never commit or merge to `main`. Branch table: `../../references/delivery-and-worktree.md`.
- **Stack-aware dispatch**: pick the overlay by the sub-task's Tier — `agents/coder-backend.md` (server/API/domain) or `agents/coder-frontend.md` (UI/SSR/client). Load only `references/languages/<language>.md` for the sub-task's `Language` — never the index. Full-stack sub-tasks were split BE/FE around the `api-spec.yaml` contract (BE producer first, then FE consumer). No frontend stack → frontend coder never spawned.
  - **Frontend sub-task creating or materially redesigning visual surface** (new page/component/theme/layout — not a pure logic/state change): before dispatching the frontend coder, invoke `/frontend-design` for a compact design plan (palette, type pairing, layout concept, signature element) and include it in the coder's dispatch prompt. Skip for backend-only sub-tasks and frontend sub-tasks that don't touch visual surface.
- The story ACs + Definition of Done are the frozen acceptance contract — Coder satisfies it, never redefines it
- Coder runs Phase 0 Analysis, then Phase 1 implement to the frozen Test Case table → Phase 2 write exactly the specified tests → Phase 3 falsify each one (apply the row's break, confirm the assertion fails, restore) — owns both test and impl files
- Coder emits `CODER DONE` with spec coverage ({n}/{N} rows) and one falsification evidence line per test
- Orchestrator stores compact ref: `"ST1: {file}.{ext} + tests, {N} lines, implements {Interface}"`

**C. QA audit + gates** — `agents/qa.md`
Input: ACs from Task Manifest (including Security ACs) + Amelia's tests + full code
Quinn audits the tests (spec-row completeness, falsification evidence + spot-checks, intent-encoding, corner cases, no tautologies — see qa.md Test Audit), then runs all quality gates. Quinn authors no tests. Route on Quinn's output signal:

- `QA→REVIEWER APPROVAL` → proceed to D (Review + Stress in parallel)
- `QA→CODER BUG REPORT`, `QA→CODER TEST GAP`, or `QA→CODER COVERAGE REQUEST` → Bug-Fix Loop
- `QA ESCALATION` (after 3 iterations) → proceed to D with FAIL status

See `references/quality-gate-reference.md` **Bug-Fix Loop Protocol** (and **Loop Integrity** — no goalpost-moving, stop on an identical repeat failure, compact only at story boundaries) for exact procedure, iteration counting, and coverage failure sub-path.

**D. Review + Stress** *(triggered by QA signal — never before QA approval or escalation)*:
- `agents/reviewer.md` → full code, language-specific checks, **plus the acceptance contract**: the story (ACs + Test Case table), the delivery file's Reuse Map, and `codebase-map.md`. Without them the Reviewer's own escape clause fires and CD1/CD3/CD7 — every intent and scope check — is skipped silently, which is how a diff that builds the wrong thing scores 8/10.
- `agents/stress.md` → full code + tests, Security Under Stress

If Reviewer or StressTester emits `TUNER REQUEST` → load `agents/tuner.md` (Tyler):
- Tyler applies MINOR/NIT fixes; emits `TUNER COMPLETE`
- Reviewer re-scores only changed files; use higher score for Verdict
- Maximum 2 iterations; on `TUNER LIMIT REACHED` → proceed to E

**E. Verdict** — `agents/verdict.md`
Input: Review score + Stress score + QA summary + AC checklist + Gate Report
Unmitigated CRITICAL security = automatic NOT READY.

**F. Checkpoint**

| Score | Security | Gates | Action |
|-------|----------|-------|--------|
| ≥ 8.0 | No CRITICAL | All green | Next sub-task or final summary |
| ≥ 8.0 | CRITICAL | Any | NOT READY — fix security first |
| < 8.0 | Any | Any | Show issues; ask: *"Fix and re-run / skip / stop?"* |

On re-run: pass only delta (CRITICAL/MAJOR issues + failing ACs + failed gates).

After each sub-task Verdict, append a `PROGRESS.md` entry at the repo root (Done / Failed / Current State / Next — see `references/progress-file.md`) so the next session boots with state.

**Post-verdict (PRODUCTION READY)**: load `agents/devops.md` (Ops) — generates Dockerfile, .dockerignore, docker-compose.yml, optional CI/k8s.

> **Context Budget — 80% is a hard ceiling, not a warning.** Model reliability degrades before the
> window is full: recall of mid-context detail drops and confident invention rises, and a pipeline is
> exactly where that is most expensive — a hallucinated interface signature or a mis-remembered AC
> propagates through every stage after it.
> - **Between sub-tasks**: drop implementation code, test files, and completed sub-task stories. Retain the
>   delivery file, the Manifest, and every score.
> - **At 4+ sub-tasks, or 60%**: compact completed sub-tasks to one-line refs —
>   `"ST{N}: {slug} — DONE (Review: X/10, Stress: Y/10, QA: Z/10)"` — never dropping a score.
> - **At 80%: stop and hand off.** Run `/handoff`, write the `[{key}]` `PROGRESS.md` entries, push
>   the current story branch, and start a fresh session that resumes from the delivery file's Status
>   plus those entries. Do not "push a bit further" — the next thing produced past this line is the
>   thing least likely to be right, and hardest to spot as wrong.
> - **Handoff state lives in `PROGRESS.md` and the handoff doc — never in the code.** No `TODO`,
>   no `FIXME`, no commented-out stub, no placeholder marking where the session stopped. A source
>   file must not record that an agent ran out of context; that is what the Memory leg is for, and a
>   marker left behind is a finding (CD6) in the next review.

Use `references/output-format.md` headers. Show Pipeline Summary after each Verdict. Load agent files on demand — never pre-load all at once.
