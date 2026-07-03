# Task pipeline — sub-task loop detail

## Phase 1 — Planning (once)

> **Backend-Driven Architecture check (mandatory):** Verify tier placement for every component: **Frontend** = render only; **BFF** = orchestrate + shape for UI; **Core** = domain logic. Flag and push back on any AC asking the wrong tier to own logic.

Load and follow `skills/planning.md` starting from **Phase 1 (Architecture)**.

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
Input: Task Manifest row + Architecture → Output: `story-{slug}.md`

**B. Code (TDD)** — sub-agent with `agents/coder.md` (core) + ONE tier overlay + `story-{slug}.md`
- **Stack-aware dispatch**: pick the overlay by the sub-task's Tier — `agents/coder-backend.md` (server/API/domain) or `agents/coder-frontend.md` (UI/SSR/client). Load only the `language-rules-reference.md` section for the sub-task's `Language` — never all. Full-stack sub-tasks were split BE/FE around the `api-spec.yaml` contract (BE producer first, then FE consumer). No frontend stack → frontend coder never spawned.
  - **Frontend sub-task creating or materially redesigning visual surface** (new page/component/theme/layout — not a pure logic/state change): before dispatching the frontend coder, invoke `/frontend-design` for a compact design plan (palette, type pairing, layout concept, signature element) and include it in the coder's dispatch prompt. Skip for backend-only sub-tasks and frontend sub-tasks that don't touch visual surface.
- The story ACs + Definition of Done are the frozen acceptance contract — Coder satisfies it, never redefines it
- Coder runs Phase 0 Analysis, then the Red→Green→Refactor cycle: failing test first, minimum impl, refactor — owns both test and impl files
- Coder emits `CODER DONE` (with TDD evidence: RED → GREEN) when the cycle is complete
- Orchestrator stores compact ref: `"ST1: {file}.{ext} + tests, {N} lines, implements {Interface}"`

**C. QA audit + gates** — `agents/qa.md`
Input: ACs from Task Manifest (including Security ACs) + Amelia's tests + full code
Quinn audits the tests (intent-encoding, corner cases, no tautologies — see qa.md Test Audit), then runs all quality gates. Quinn authors no tests. Route on Quinn's output signal:

- `QA→REVIEWER APPROVAL` → proceed to D (Review + Stress in parallel)
- `QA→CODER BUG REPORT`, `QA→CODER TEST GAP`, or `QA→CODER COVERAGE REQUEST` → Bug-Fix Loop
- `QA ESCALATION` (after 3 iterations) → proceed to D with FAIL status

See `references/quality-gate-reference.md` **Bug-Fix Loop Protocol** for exact procedure, iteration counting, and coverage failure sub-path.

**D. Review + Stress** *(triggered by QA signal — never before QA approval or escalation)*:
- `agents/reviewer.md` → full code, language-specific checks
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

> **Context Budget**: After each sub-task: drop code + story. Retain: Architecture + Manifest + all scores.
> If running 4+ sub-tasks or context >75% full: summarize completed sub-tasks to one-line refs:
> `"ST{N}: {slug} — DONE (Review: X/10, Stress: Y/10, QA: Z/10)"` — never drop scores.

Use `references/output-format.md` headers. Show Pipeline Summary after each Verdict. Load agent files on demand — never pre-load all at once.
