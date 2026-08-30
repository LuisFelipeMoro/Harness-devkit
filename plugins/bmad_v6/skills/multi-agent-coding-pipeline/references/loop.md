# Epic Loop — dispatch detail

Steps A–F of `SKILL.md` Phase 2, repeated per epic. All work happens inside the delivery
worktree (`.worktrees/dlv-{key}/`) on `release/{slug}-{key}` — see
[../../../references/delivery-and-worktree.md](../../../references/delivery-and-worktree.md).

**A. Stories** — `agents/scrum-master.md`
- Input: Epic Manifest rows for current epic + the delivery file
- Output: one `story-{slug}.md` per task (scoped architecture sections only; include Security Points)

**B. Coding (Spec→Implement→Test→Falsify)** — one subagent per story, **dispatched one at a time**:

> Stories share the delivery's single worktree, so they run **sequentially** — story N's gates are green and its work merged before story N+1 is dispatched. Never run two Coder subagents against the same worktree; they would overwrite each other. Read-only Explore/mapping subagents may still run in parallel.
- **Stack-aware dispatch**: each subagent gets `agents/coder.md` (core) + ONE tier overlay chosen by the story's Tier — `agents/coder-backend.md` (server/API/domain) or `agents/coder-frontend.md` (UI/SSR/client). Load only the `language-rules-reference.md` section for the story's `Language` — never all.
  - Backend-only story → backend coder. Frontend-only → frontend coder.
  - Full-stack story was already split by the ScrumMaster into BE + FE sub-stories sharing the `api-spec.yaml` contract (BE = producer, FE = consumer). Dispatch each to its tier coder; run BE first so the spec is real before FE consumes it.
  - If the repo/plan has no frontend stack, the frontend coder is never spawned (zero overhead).
  - **Frontend story creating or materially redesigning visual surface** (new page/component/theme/layout — not a pure logic/state change): before dispatching the frontend coder, invoke `/frontend-design` to produce a compact design plan (palette, type pairing, layout concept, signature element), then include that plan in the coder's dispatch prompt. Skip for backend-only stories and for frontend stories that don't touch visual surface (state management, data wiring, a11y-only fixes).
- Each receives: `agents/coder.md` + the tier overlay + `story-{slug}.md` (+ the design plan, when produced)
- The story ACs + Definition of Done are the frozen acceptance contract — Coder satisfies it, never redefines it
- Coder runs Phase 0 Analysis, then Phase 1 implement to the frozen Test Case table → Phase 2 write exactly the specified tests → Phase 3 falsify each one (apply the row's break, confirm the assertion fails, restore) — owns both test and impl files
- Coder emits `CODER DONE` with spec coverage ({n}/{N} rows) and one falsification evidence line per test
- Orchestrator stores compact ref: `"T1.1: {file}.{ext} + tests, {N} lines, implements {Interface}"`

**C. QA audit + gates** — `agents/qa.md`
- Input: ACs from Epic Manifest (including Security ACs) + Amelia's tests + full code
- Quinn audits the tests (spec-row completeness, falsification evidence + spot-checks, intent-encoding, corner cases, no tautologies — see qa.md Test Audit), then runs all quality gates. Quinn authors no tests.

Route on Quinn's output signal:

- `QA→REVIEWER APPROVAL` → proceed to D (Review + Stress in parallel)
- `QA→CODER BUG REPORT`, `QA→CODER TEST GAP`, or `QA→CODER COVERAGE REQUEST` → Bug-Fix Loop
- `QA ESCALATION` (after 3 iterations) → proceed to D with FAIL status

See `references/quality-gate-reference.md` **Bug-Fix Loop Protocol** for exact loop procedure, iteration counting, escalation format, and coverage failure sub-path.

**D. Review + Stress** *(triggered by QA signal — never before QA approval or escalation)*:
- `agents/reviewer.md` → full code; apply language-specific checks
- `agents/stress.md` → full code + tests; include Security Under Stress

Never dispatch Reviewer before receiving `QA→REVIEWER APPROVAL` or `QA ESCALATION`.

If Reviewer or StressTester emits `TUNER REQUEST` → load `agents/tuner.md` (Tyler):
- Tyler applies MINOR/NIT fixes; emits `TUNER COMPLETE`
- Reviewer re-scores only the changed files; use higher score for Verdict
- Maximum 2 iterations; on `TUNER LIMIT REACHED` → proceed to E

**E. Verdict** — `agents/verdict.md`
- Input: Review score + Stress score + QA summary + AC checklist
- Security Gate section required; unmitigated CRITICAL security = automatic NOT READY

**F. Checkpoint**

| Score | Security | Action |
|-------|----------|--------|
| ≥ 8.0 | No CRITICAL | Proceed to next epic or show final summary |
| ≥ 8.0 | CRITICAL security | NOT READY — security fix required; re-run pipeline after fix |
| < 8.0 | Any | Show issues; ask: *"Fix and re-run / skip / stop?"* |

On re-run: pass only the delta (CRITICAL/MAJOR issues + failing ACs).

After each epic Verdict, append a `[{key}]`-prefixed `PROGRESS.md` entry at the repo root (Done / Failed / Current State / Next — see `references/progress-file.md`) so the next session boots with state.

**Post-verdict (PRODUCTION READY on final epic only)**: load `agents/devops.md` (Ops) — generates Dockerfile, .dockerignore, docker-compose.yml, optional CI/k8s.
