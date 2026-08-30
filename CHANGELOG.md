# Changelog

## [1.3.0] — 2026-08-30

### Changed

- **TDD replaced with spec-first testing across every pipeline, agent, and skill.**
  Code is no longer written test-first. Instead the test specification is frozen *before*
  the code and the tests are written *after* it, then proven by falsification. Four steps:
  **Spec** (Architect freezes a Test Case table) → **Implement** (Coder builds to it) →
  **Test** (Coder writes exactly those rows) → **Falsify** (Coder breaks each code path,
  observes the test fail on its own assertion, restores).

  **Why this changed.** Red→Green→Refactor was dropped after real usage showed it wasn't
  paying for itself. It burns a large amount of tokens — every acceptance criterion costs an
  extra write-run-read cycle before any implementation exists, plus the RED output quoted
  back into context, multiplied across every story in a pipeline — and the code quality it
  bought did not measurably exceed what a tight plan plus a rigorous post-hoc test pass
  produces. Worse, agent-driven TDD degraded into writing whatever test would go red fastest,
  which is a bias toward shallow tests, not good ones. The leverage was never in the ordering;
  it was in deciding *what to assert and why*. So that decision moved upstream into the
  architecture, where it is made once on `opus` and reused, instead of being re-derived
  per-AC on `haiku` at execution time.

  **What replaces the RED guarantee.** Test-first's one real guarantee is that a test was
  observed to fail. Falsification restores it after the fact and more cheaply: apply the
  break the spec names, confirm the assertion fails, revert. One run per test, no
  implementation-blocking cycle.

  **Tautology is now the blocking defect; coverage is only a floor.** A green suite at 90%
  coverage that survives having its guards deleted fails the audit. QA scores a tautological
  or unfalsified test as MAJOR, capping the score at 4 — the same weight as a failing gate —
  and coverage above target never compensates. Tests added purely to move the percentage are
  explicitly rejected, and coverage-driven additions are re-audited as the highest-risk source
  of tautologies.

  **Bug fixes keep test-first**, and are the only exception: the RED reproduction test is what
  proves the root cause was found rather than guessed, so it is written and observed failing
  before the fix. There the RED *is* the falsification, obtained for free.

  Files: `plugins/bmad_v6/CLAUDE.md` (new "Spec-First Test Discipline" section replacing
  "TDD Discipline"); `architect.md` (Test Case Specification gains **Expected Observable
  Result**, **Why It Matters**, and **Falsified By** columns — the table is now the
  highest-leverage section of the architecture); `scrum-master.md` (story carries all columns
  verbatim; a row missing any of the three is an incomplete story; DoD checks rows +
  falsification + no tautologies); `coder.md` (Phase 1 TDD Cycle replaced by Phase 1 Implement
  → Phase 2 Write specified tests → Phase 3 Falsify; `CODER DONE` now reports spec coverage
  and one evidence line per test); `coder-backend.md`/`coder-frontend.md` (security and
  contract tests falsified by deleting the control); `qa.md` (audit lens 1 is now falsification
  evidence with mandatory spot-checks, lens 2 is an expanded tautology hunt, score table gains
  a Spec + Falsification column); `reviewer.md`, `verdict.md`, `tuner.md`; both pipeline
  skills + `task-coding-pipeline/references/loop.md`; `bug-fix/SKILL.md` (documents the
  exception); `engineering:observability` and `engineering:database-migration` (assert-then-
  falsify instead of RED-first; observability's `test-first-and-checklist.md` renamed to
  `test-and-checklist.md`); `engineering:code-review-gate`, `engineering:quality-gate`,
  `pr-workflow:pr-review` (TDD-compliance check → test-falsifiability check, with new HIGH
  findings for expected values re-derived from the implementation and for security tests that
  pass with the control removed); plus `references/` (`bmad-artifacts.md`,
  `language-rules-reference.md`, `output-format.md`, `progress-file.md`,
  `quality-gate-reference.md`, `spec-driven-reference.md`), `README.md`, and both plugin
  manifests.

### Added

- **`references/frontend-hardening-reference.md` — enforcement-integrity checks for frontend
  work.** Distilled from a post-merge review cycle on a production checkout frontend, where
  every pattern in it was a defect that *passed a green pipeline*: the lint ran, the tests were
  green, coverage met the floor, the docs claimed the gate was enforced — and the control was
  not actually in effect. Eight sections: config-merge shadowing (a rule silently replaced by a
  later block), security rules left at `warn` instead of `error`, vacuous tests, missing
  boundary-format cases on validators, ReDoS via overlapping regex character classes, fragile
  coverage config, dead CI files as phantom gates, and enforcement that runs only in CI rather
  than locally.

  This pairs directly with the spec-first change above — both target controls that *look*
  enforced but cannot fail. Wired in as mandatory for any web stack in `coder-frontend.md`,
  as `[FH]`-tagged review flags in `language-rules-reference.md`, as a QA audit lens in
  `qa.md` (canonical-only validators, vacuous loops, spies no `expect` reads), as a
  design-time obligation in `architect.md`, and into both `quality-gate-reference.md` copies.

- **`architecture.md` replaced by a keyed delivery file.** The pipeline no longer writes
  `architecture.md` to the project root. It now writes
  `docs/deliveries/delivery-{slug}-{key}.md`, where the key is the first 6 hex chars of the
  SHA-256 of the feature name. Two problems went away: the devkit was overwriting the host
  repo's own `architecture.md` — a file that usually documents the whole system, not one
  feature — and a single fixed filename meant two deliveries against the same repo fought over
  it. The delivery file opens with a signature header (`Delivery-Key`, Status, base commit,
  release branch, worktree path), and manifests, stories, and `api-spec.yaml` are keyed
  alongside it under `docs/deliveries/{key}/`. `PROGRESS.md` stays at the repo root with every
  entry prefixed `[{key}]` so concurrent deliveries interleave readably.

  Because the key is a pure function of the feature name, re-running a pipeline for the same
  feature resolves to the same delivery and **resumes** it rather than forking a duplicate. The
  trade-off is that two genuinely independent passes at one feature need distinct names.

  If the repo has its own `architecture.md`, the Architect now reads it as context and never
  modifies it.

- **Per-delivery git worktree and a branching model that never touches `main`.** Each pipeline
  run creates `.worktrees/dlv-{key}/` on branch `release/{slug}-{key}`, and everything —
  stories, gates, QA, review — happens in there, leaving the human's main working tree free.
  An existing worktree for a key means resume, not recreate.

  Branching: every delivery gets a release branch; per-story `feature/{key}-{story-slug}`
  branches are optional and merged back with `--no-ff` when a story is substantial enough to
  keep in history; `/bug-fix` instead cuts `hotfix/{slug}` straight from `main` with no
  delivery file, release branch, or worktree. **The pipeline never commits or merges to
  `main`** — its terminal step is opening a PR from a `release/*` or `hotfix/*` branch, and it
  asks before the first push.

  **Behavior change**: `multi-agent-coding-pipeline`'s "Parallel Coding" phase is now
  sequential. One worktree per delivery means stories share a working tree, so two concurrent
  Coder subagents would overwrite each other; story N is green and merged before story N+1 is
  dispatched. Read-only Explore/mapping subagents still run in parallel. This trades
  wall-clock for the cross-story isolation the worktree exists to provide.

  New reference: `plugins/bmad_v6/references/delivery-and-worktree.md` (key derivation, header
  block, setup/resume/teardown commands, branch table, PR rules). Wired into `architect.md`,
  `scrum-master.md`, `coder.md`, `devops.md`, `CLAUDE.md`, both pipeline skills +
  `task-coding-pipeline/references/loop.md`, `bug-fix/SKILL.md`, `planning/SKILL.md` +
  `references/phases.md`, `architecture/SKILL.md`, `references/` (`bmad-artifacts.md`,
  `output-format.md`, `presets.md`, `progress-file.md`), `README.md`, and `.gitignore`
  (`/.worktrees/`).

### Fixed

- **Consistency audit across the whole devkit** after the two changes above. Gaps closed:
  - **Brief and PRD had the same collision `architecture.md` did.** `product-brief.md` and
    `PRD.md` were written to the repo root, so a second delivery clobbered the first's. Both
    are now keyed under `docs/deliveries/{key}/`, along with manifests and stories.
  - **`api-spec.yaml` location settled at the project root.** The new delivery reference had
    put it under `docs/deliveries/{key}/`, contradicting seven agents that check the project
    root. Root wins: it is the application's shared, cumulative API contract, tooling expects a
    fixed path, and worktree isolation already gives each delivery its own checkout — two
    deliveries touching the same endpoints surface as a merge conflict at PR time, as they
    should.
  - **`/release-management` no longer appears to contradict "never merge to `main`".** It now
    states it is the step *after* a human merges the delivery PR — it tags an already-merged
    `main` — and that `release/{slug}-{key}` branches are a different thing from "cutting a
    release". It must not be used to get delivery work onto `main`.
  - **`/handoff` now records the delivery identity** (key, delivery file, release branch,
    worktree, next story). Without the key a resumed session derives a fresh one and forks the
    work. Its `PROGRESS.md` schema copy also gained the `[{key}]` entry prefix and the
    falsification tie, matching `bmad_v6/references/progress-file.md`.
  - **Verdict gained a gate** asserting all work sits on `release/*` or `hotfix/*` and nothing
    on `main`.
  - **Stress Tester's regression-test instruction clarified** — a stress-found failure mode is
    written test-first like a bug fix, and the reference now says why (the RED proves the mode
    was reproduced, not assumed) rather than reading as leftover TDD.
  - **"Architecture + Manifest" retained-context wording** updated to "the delivery file +
    Manifest" in four places.
  - **README pipeline diagram** gained the Delivery Setup and Delivery Close phases, marks
    implementation SEQUENTIAL, and shows the keyed artifact paths.
  - **`AGENTS.md` and `codex/harness-adapter.md`** now state both conventions for non-Claude
    harnesses; the adapter notes delivery isolation is plain `git` and should port cleanly,
    with sequencing still the unvalidated part.
  - Verified: every relative `.md` link in the repo resolves, every `SKILL.md` is under 100
    lines, both plugin manifests parse, and the global/codex installers use globs so the new
    reference files ship without a manifest edit.

- **`plugins/bmad_v6/.claude-plugin/plugin.json` version corrected to `1.3.0`.** It had been
  left at `1.2.0` through the `1.2.1` release, so the manifest under-reported the installed
  version by two releases. Note the git tags lag further still — the last tag is `v1.1.2`, so
  `1.2.0`, `1.2.1`, and `1.3.0` are recorded here in the CHANGELOG but untagged.

- **`multi-agent-coding-pipeline` epic-loop detail extracted to `references/loop.md`.** Adding
  the delivery-setup phase pushed `SKILL.md` from 98 to 115 lines, past the devkit's own
  "under 100 lines, overflow to `references/`" rule. Steps A–F now live in
  `skills/multi-agent-coding-pipeline/references/loop.md` (mirroring what
  `task-coding-pipeline` already did), leaving a 69-line `SKILL.md` with a phase summary and a
  link. No behavior change.

## [1.2.1] — 2026-08-06

### Changed

- **Model tiering rebalanced: heavy reasoning on planning, `haiku` on code execution.**
  The Model assignment table (`plugins/bmad_v6/CLAUDE.md`) previously ran all
  planning/validation agents on `sonnet` and every code-writing agent (`coder` + tier
  overlays, `tuner`, `devops`) on `opus`. Now: `opus` is reserved for the Architect's
  design pass only (system design, ADRs, tech-stack calls — the one artifact everything
  downstream depends on); `sonnet` keeps the rest of planning/validation (Analyst, PM,
  Scrum Master, Bug Investigator diagnosis, QA audit, Reviewer, Stress, Verdict, pipeline
  orchestrators); `coder` (+ backend/frontend overlays), `tuner`, and `devops` move to
  `haiku`. Updated in agent frontmatter, `CLAUDE.md`'s table, both pipeline `SKILL.md`
  files (`multi-agent-coding-pipeline`, `task-coding-pipeline`), `bug-fix`'s dispatch
  (`SKILL.md` + `references/dispatch.md`), `README.md`, and `codex/harness-adapter.md`.
- **Architecture and story artifacts made airtight so `haiku` execution stays mechanical.**
  A cheaper Coder only works if it isn't asked to design anything. `architect.md` now
  requires a field-by-field table for every data structure (`### Data Structures`) and a
  new `### Test Case Specification` section enumerating the exact test cases — one row per
  AC, edge case, and non-N/A OWASP mitigation, with a literal test name Coder copies
  verbatim. `scrum-master.md`'s story template carries a new `### Test Cases` section
  filtered from that spec, and the Definition of Done now checks against table rows instead
  of ACs directly. `coder.md`'s RED phase changed from "write a test that encodes the AC's
  intent" to "execute the next row from the Test Cases table" — the design decision moved
  upstream to Architect/Scrum Master. `coder-backend.md`/`coder-frontend.md` reframe their
  TDD category checklists as gap-detection rather than design guidance. `qa.md` gained a
  spec-completeness check (every Test Cases row implemented) ahead of its existing
  intent/tautology/corner-case audit lenses.

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
