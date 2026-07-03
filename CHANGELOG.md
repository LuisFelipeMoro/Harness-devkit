# Changelog

## [1.2.0] — 2026-07-03

### Added

- **Database selection reference for the Architect.** `references/db-selection-reference.md` —
  a PACELC-classified comparison of 15 databases (Cassandra, MongoDB, DynamoDB, CockroachDB,
  Spanner, PostgreSQL, Redis, etcd, Riak, Neo4j, Elasticsearch, FoundationDB, ScyllaDB,
  Couchbase, YugabyteDB) with use cases and refactor-risk notes. `architect.md` loads it only
  when a feature introduces a new datastore or an existing one takes on a materially different
  use case — not part of every Architecture Document.
- **Frontend design-quality checklist (anti-AI-slop).** `references/frontend-design-reference.md`,
  condensed from [Impeccable](https://github.com/pbakaus/impeccable) (Apache 2.0): absolute
  bans (gradient text, glassmorphism-as-default, side-stripe borders, identical card grids,
  eyebrow-on-every-section, etc.) plus color/typography/layout/motion rules. `coder-frontend.md`
  carries the hard-ban shortlist inline and loads the full reference only for stories that
  create or materially redesign visual surface. Quinn's frontend audit lens (`qa.md`)
  spot-checks the same bans as a MINOR/aesthetic finding, never a gate blocker.
- **`/frontend-design` dispatch wired into the task and epic pipelines.** Before dispatching
  the frontend coder on a story that creates/redesigns visual surface,
  `multi-agent-coding-pipeline` and `task-coding-pipeline` now invoke Anthropic's
  `frontend-design` skill for a design plan (palette, type pairing, layout concept, signature
  element) and pass it into the coder's dispatch prompt. Skipped for backend-only and
  non-visual frontend work — zero overhead otherwise. Doesn't change the TDD cycle: tests
  still come first, the plan only governs visual direction.

## [1.1.2] — 2026-07-02

### Fixed

- **Agent model tier pinned in frontmatter.** Pipeline agents (`analyst`, `pm`, `architect`,
  `scrum-master`, `bug-investigator`, `qa`, `reviewer`, `stress`, `verdict`, `coder` +
  overlays, `tuner`, `devops`, `rote-adapter`) had no `model:` field, so the Agent tool fell
  back to inheriting the parent session's model on every spawn regardless of the CLAUDE.md
  model-assignment table. Now pinned (`sonnet` for reasoning/validation, `opus` for
  code-writing). Also fixes `DevOps` being listed `opus` in CLAUDE.md but `sonnet` in both
  pipeline `SKILL.md` files — standardized on `opus` (it writes IaC files).
- **`bug-fix`'s Phase 3 only ran the test command** — no lint, typecheck, or build — so a fix
  could reach Reviewer with a broken build. Now runs the full gate set (same as the other
  pipelines), with reloop-to-fix on any failure via the existing Bug-Fix Loop Protocol.
- **Missing build gate for React SPA.** Only Next.js had a `next build` gate; `tsc --noEmit`
  doesn't catch bundler-only failures (unresolved imports, case-sensitive path mismatches).
  Added to `quality-gate-reference.md`, Quinn's gate list, and the `pre-push` git hook.
- **`env-guard.sh` only fired on the `Read` tool.** `cat .env`, `grep SECRET .env`, and nested
  `bash -c "cat .env"` all bypassed the "never read `.env`" rule entirely. Now covers
  `Read|Bash|Grep|Glob`; regex hardened to catch `.env` anywhere in a command string, not
  just as a suffix.
- **Indirect prompt-injection surface in `pr-review-responder.sh`.** Untrusted GitHub PR
  comment bodies were piped straight into Claude's context with no delimiter, immediately
  followed by an "ACTION REQUIRED" directive Claude is instructed to obey — exploitable by
  anyone who can comment on the PR. Now wrapped in explicit untrusted-content markers.
- **`engineering/quality-gate` depended on a `bmad_v6`-only reference file**
  (`quality-gate-reference.md`), the same class of bug fixed for the Reviewer agent ref in
  1.1.1 but missed here — breaks when `engineering` is installed standalone. Gave it its own
  trimmed local copy instead of a hard cross-plugin dependency.
- **`security-review` did its full-codebase scan inline** instead of dispatching a read-only
  Explore/haiku sub-agent like `improve-codebase-architecture` does for identical-shaped
  work — burning main-thread context on pure grunt work. Now dispatches the same way.
- **Missing Contract blocks.** `multi-agent-coding-pipeline` and `security-review` had no
  explicit Input/Output/Boundary/Done-when block, unlike their sibling skills — a SkillSpec
  HIGH finding (agent follow-through risk). Added, matching the existing pattern.

## [1.1.1] — 2026-07-01

### Fixed

- **Cross-plugin agent references now resolve under the plugin install.** Two skills pointed
  at `agents/<name>.md` for an agent that lives in a *different* plugin, so the relative path
  dangled once installed via the plugin manager (all 18 agents ship in `bmad_v6`):
  - `engineering/code-review-gate` → the **Reviewer** (its Phase 2 gate). Now dispatches the
    `bmad_v6:reviewer` subagent (falls back to `reviewer` in a flat `~/.claude/agents` install)
    instead of reading `agents/reviewer.md`. This was the quality-gate wiring bug — the gate
    could skip its independent Reviewer under the plugin install.
  - `devtools/rote-adapter` → the `bmad_v6:rote-adapter` subagent, same treatment.

  In-plugin references (all `bmad_v6` pipeline skills) were already correct and are unchanged.
  Git and Claude Code hooks invoke no agents by design (exit-code sensors + shell), so they were
  not affected.

## [1.1.0] — 2026-07-01

### SkillSpec validation pass — all 23 skills

Ran every `SKILL.md` through [SkillSpec](https://github.com/modiqo/skillspec) `doctor`, which
scores **agent follow-through risk** (the chance an agent skips, reorders, improvises, or
finishes without proof given a skill's shape), and acted on the findings:

- **Leaner activation bodies** — heavy tables, templates, and examples moved out of the
  always-loaded `SKILL.md` into on-demand `references/*` (net −1236/+278 lines across the 23
  skills). Lower per-session context cost, same coverage.
- **Sharper discovery** — descriptions rewritten use-case-first; trigger phrases preserved.
- **Tidier structure** — labeled code fences, critical rules lifted toward the top.

Only the files Claude actually reads (`SKILL.md` + linked `references/`) are committed. The
SkillSpec contract scaffolding (`skill.spec.yml`, `deps.toml`, `source/`, `imports/`,
`resources/`, `.skillspec/`) is tool-only — Claude never loads it — and is `.gitignore`d.

### `write-a-skill` now self-validates

The `/write-a-skill` skill gained a mandatory **Validate** step: after scaffolding, it runs the
new skill through `skillspec doctor`, adapts the `SKILL.md` for any actionable finding, and
re-runs until clean — a skill is not "done" until SkillSpec has run and its findings are
resolved or explicitly justified. Finding-to-fix map in `references/skillspec-validation.md`.

### Fixed

- **`install-global.sh` (Option C flat install) rewritten for the multi-plugin layout.**
  The old script only looked at `bmad_v6` and expected flat `skills/*.md`, so against the
  current marketplace (4 plugins, directory-format `skills/<name>/SKILL.md`) it installed
  **zero skills** and missed three plugins. It now walks every plugin — installing all 23
  skills and 18 agents — and copies only the files Claude reads (`SKILL.md` + `references/`),
  skipping SkillSpec tool scaffolding.

### Housekeeping

- `.gitignore` added for SkillSpec tool artifacts and `.claude/settings.local.json`
  (machine-local permissions/state, now untracked).

## [1.0.0] — 2026-06-26

First tagged release. It combines the TDD-first + Harness foundation with an
efficiency/specialization pass (stack-aware coders, leaner context, self-dogfooding).
Highlights below.

### Specialized coders (shared core + thin overlays)
The single Coder is now a shared TDD **core** plus one of two thin tier overlays, chosen by
the story's tier:
- **Backend** (`coder-backend`) — Go/Java/JS-TS/PHP/Rust/server-Kotlin; table-driven, integration,
  race, security tests; api-spec **producer**.
- **Frontend** (`coder-frontend`) — React/Next.js/HTMX/HTML-CSS/Flutter/Kotlin-Android; Testing
  Library/Playwright, a11y, **SSR/RSC** (server render + hydration tests); api-spec **consumer**.

Dispatch is **stack-aware**: the orchestrator spawns only the coder(s) the story needs (a
backend-only repo never spawns a frontend coder), and each loads **only the detected
language's** rules — never all of them. Full-stack stories are split BE/FE around the
`api-spec.yaml` contract. QA stays a **single tier-aware auditor** — no agent sprawl.

### Leaner, drift-free context
- The two ~95%-identical `CLAUDE.md` files are deduped — the repo-root one now `@include`s the
  canonical plugin copy. One source, no drift.
- The heavy per-language standard tables left `CLAUDE.md` (loaded every session) and consolidated
  into the single `language-rules-reference.md`, loaded on demand. `CLAUDE.md` is ~50% lighter.
- Coverage thresholds now have one declared source of truth (`quality-gate-reference.md`).

### External dependencies dropped
- `superpowers:test-driven-development` reference removed — the Coder does TDD itself now; a
  direct change writes the failing test first, then runs `/code-review-gate`. `superpowers:using-git-worktrees`
  → native `git worktree`.
- Skill-routing trigger phrases in both `CLAUDE.md` files broadened and modernized; `/rote`
  (run) split from `/rote-adapter` (create).

### Harness wiring & self-CI
- Hooks now auto-install via the plugin manifest (`hooks/hooks.json`) — the SessionStart memory
  hook and env-guard are active by default, not a manual settings paste.
- The devkit dogfoods its own Sensors: a CI workflow runs shellcheck + bash syntax + JSON
  validation on the toolkit itself.
- All four plugins now carry a `version`.

### TDD-first, Harness-strict foundation

Rebuilds the devkit around two ideas: every line of code is driven by a test written
*first*, and the whole toolkit behaves like a proper agentic **Harness** (Guides, Sensors,
Memory, Orchestration). Here's what changed and why it matters day to day.

### The big shift: tests come first now

The pipeline used to be test-*after* — Amelia (Coder) wrote the implementation and was
forbidden to touch tests, then Quinn (QA) wrote tests against the finished code. That's
backwards, and it let untested-by-design code slip through.

- **Amelia now owns the full Red → Green → Refactor loop.** She writes the failing test
  first, watches it fail for the right reason, writes the least code to make it pass,
  then refactors under green. She owns both the test files and the implementation.
- **Quinn stopped writing tests and became the auditor.** Because the person who wrote
  the code is blind to what they skipped, Quinn now does the adversarial review: *does
  this test actually prove anything?* She hunts tautological and over-mocked tests
  (the ones that can never fail), demands the missing corner cases (boundaries, nulls,
  overflow, unicode, concurrency, time, error paths), and checks that no existing test
  was weakened to make a change pass. Gaps route back to Amelia via a new
  `QA→CODER TEST GAP` signal — Quinn never writes the test herself.

### Plans get stress-tested before anyone writes code

- `/grill-me` is now a **mandatory** step in planning, not an optional offer. Every plan
  gets poked for holes — missing error cases, auth gaps, undecided edge cases — while
  changes are still cheap.
- The architect no longer invents an answer to fill a gap. If the requirements support a
  decision, it's decided and written into the architecture. If they don't, it becomes an
  explicit open question for the human. Nothing ambiguous gets deferred into the
  implementation anymore — that's treated as a planning error.

### The toolkit is now a real Harness

- **Guides** — both `CLAUDE.md` files gained a Harness contract and a TDD discipline
  section, so the rules are stated up front instead of implied.
- **Sensors** — the existing git hooks (lint in error-mode, tests + coverage gate) are
  now explicitly framed as exit-code sensors: they block on failure and return a code,
  never prose to argue with.
- **Memory** — brand new. A `PROGRESS.md` at the repo root records what's done, what
  failed, and the current state. A new `session-bootstrap.sh` SessionStart hook reads it
  so a fresh session resumes with context instead of starting blind. Pipelines and
  `/handoff` keep it up to date.
- **Orchestration** — the implementer-is-not-the-validator split is now explicit, and the
  acceptance contract (ACs + Definition of Done) is frozen before any code is written.

### Right model for the right job

Agents now pick a model by task instead of defaulting to one tier: `haiku` for read-only
exploration and quick questions, `sonnet` for planning, reasoning, validation and long
sessions, `opus` for actually writing code. Cheaper where it can be, stronger where it
counts.

### Code-producing skills are test-first too

- **Database migrations** — write the migration test first (up applies, down fully
  reverses, idempotent), watch it go red, then write the SQL.
- **Observability** — assert the log fields and spans with an in-memory sink before
  instrumenting.
- **Performance profiling** — pin current behaviour with a characterization test before
  optimizing, so a speedup can't silently change results.
- **Quality gate / code-review gate / PR review** — all now check for tests-first
  evidence and reject tautological or absent tests for shipped behaviour.
- **rote-adapter** — define the acceptance test (which call, what a valid response looks
  like) before generating the adapter.

### Docs

- README, role diagrams, and the spec-driven workflow were rewritten to match the new
  Coder-builds / QA-audits reality, plus the new SessionStart hook and `PROGRESS.md`.

### Left alone on purpose

Read-only and non-coding pieces (analyst, PM, requirement analysis, business/technical
analysis, grill-me, rote, the rote API specialists, checkcomments, security-review,
release-management, write-a-skill) were not forced into a TDD shape that doesn't fit them.
