---
name: multi-agent-coding-pipeline
description: Use when running the full BMAD v6 agile pipeline for a large feature or epic — runs all 9 agents (Analyst, PM, Architect, ScrumMaster, Coder, QA, Reviewer, StressTester, Verdict) from planning through verdict. Trigger phrases — "build", "new feature", "epic", "implement from scratch", "greenfield", "MVP".
---

Run the BMAD v6 agile pipeline. If no task is provided, ask first.

## Contract
- **Input**: a feature/epic description (ask if not provided).
- **Output**: implemented, tested epics with Review/Stress/QA/Verdict scores; a `PROGRESS.md` entry per epic; DevOps artifacts on final PRODUCTION READY.
- **Boundary**: Coder owns tests + implementation test-first; Reviewer/StressTester run only after QA approval or escalation; unmitigated CRITICAL security is automatic NOT READY.
- **Done when**: the Pipeline Summary prints after the final epic's Verdict with Security Gate + Coverage shown.

> **Model assignment** (see CLAUDE.md Model assignment table): dispatch the Coder (core + backend/frontend overlay), Tuner, and DevOps on `opus`; Analyst, PM, Architect, Scrum Master, QA, Reviewer, Stress, Verdict, and the orchestrator on `sonnet`; any read-only Explore/mapping sub-agent on `haiku`. Don't run exploration on opus or author code on haiku.

---

## Phase 1 — Planning (once)

Load and follow `skills/planning.md` (Phase 0 through Phase 4). Phase 2 (grill-me plan stress) and Phase 3 (human validation of unresolved questions) are mandatory before any coding.

- If `product-brief.md` + `PRD.md` already exist (from a prior `/analysis` run): load them and skip Phase 0 (inline analysis).
- If `architecture.md` already exists and was approved: skip Phases 0–2 and proceed directly to Phase 3 (Manifest).
- On changes requested during human validation: update `architecture.md` → re-confirm before continuing.

Complete Phases 0–4 of the planning skill (Phase 5 is informational when invoked from a pipeline). The plan MUST clear the Phase 2 grill-me stress and Phase 3 human validation before any code. Once the **Epic Manifest** is confirmed, continue with Phase 2 below.

---

## Phase 2 — Epic Loop (repeat per epic)

**A. Stories** — `agents/scrum-master.md`
- Input: Epic Manifest rows for current epic + Architecture
- Output: one `story-{slug}.md` per task (scoped architecture sections only; include Security Points)

**B. Parallel Coding (TDD)** — one subagent per story:
- **Stack-aware dispatch**: each subagent gets `agents/coder.md` (core) + ONE tier overlay chosen by the story's Tier — `agents/coder-backend.md` (server/API/domain) or `agents/coder-frontend.md` (UI/SSR/client). Load only the `language-rules-reference.md` section for the story's `Language` — never all.
  - Backend-only story → backend coder. Frontend-only → frontend coder.
  - Full-stack story was already split by the ScrumMaster into BE + FE sub-stories sharing the `api-spec.yaml` contract (BE = producer, FE = consumer). Dispatch each to its tier coder; run BE first so the spec is real before FE consumes it.
  - If the repo/plan has no frontend stack, the frontend coder is never spawned (zero overhead).
  - **Frontend story creating or materially redesigning visual surface** (new page/component/theme/layout — not a pure logic/state change): before dispatching the frontend coder, invoke `/frontend-design` to produce a compact design plan (palette, type pairing, layout concept, signature element), then include that plan in the coder's dispatch prompt. Skip for backend-only stories and for frontend stories that don't touch visual surface (state management, data wiring, a11y-only fixes).
- Each receives: `agents/coder.md` + the tier overlay + `story-{slug}.md` (+ the design plan, when produced)
- The story ACs + Definition of Done are the frozen acceptance contract — Coder satisfies it, never redefines it
- Coder runs Phase 0 Analysis, then Red→Green→Refactor: failing test first, minimum impl, refactor — owns both test and impl files
- Coder emits `CODER DONE` (with TDD evidence: RED → GREEN) when the cycle is complete
- Orchestrator stores compact ref: `"T1.1: {file}.{ext} + tests, {N} lines, implements {Interface}"`

**C. QA audit + gates** — `agents/qa.md`
- Input: ACs from Epic Manifest (including Security ACs) + Amelia's tests + full code
- Quinn audits the tests (intent-encoding, corner cases, no tautologies — see qa.md Test Audit), then runs all quality gates. Quinn authors no tests.

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

After each epic Verdict, append a `PROGRESS.md` entry at the repo root (Done / Failed / Current State / Next — see `references/progress-file.md`) so the next session boots with state.

**Post-verdict (PRODUCTION READY on final epic only)**: load `agents/devops.md` (Ops) — generates Dockerfile, .dockerignore, docker-compose.yml, optional CI/k8s.

> **Context Budget**: Between epics: drop implementation code, test files, and stories for completed epics. Retain: Architecture + Manifest + all scores (Review/Stress/QA/Verdict per epic).
> If running 4+ epics or context >75% full: summarize completed epics to one-line refs:
> `"Epic {N}: {title} — DONE (Review: X/10, Stress: Y/10, QA: Z/10)"` — never drop scores.
> At context >90%: pause, summarize all prior artifacts, confirm with user before continuing.

---

Use `references/output-format.md` headers. Show Pipeline Summary (with Security Gate + Coverage) after each Verdict.
Load agent files on demand — never pre-load all at once.
For example tasks and progressive workflow patterns, see `references/presets.md`.
