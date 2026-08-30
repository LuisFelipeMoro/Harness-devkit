# Changelog

## [2.1.0] — 2026-08-30

### Added

- **Change Discipline is now a review sensor, not just prose.** Coding Discipline rules 1–3
  and 6 had no enforcement path: nothing in the review chain ever failed a diff for scope
  creep, so "surgical changes" was aspirational. `coding-pipeline/references/change-discipline.md`
  defines CD1–CD7 — untraceable change, single-use abstraction, unrequested surface,
  unreachable-state handling, pre-existing dead code deleted unasked, self-inflicted orphan,
  silently-resolved ambiguity — each with a severity for both consumers and a worked ❌/✅
  pair. The operational test: every changed line must trace to a sentence of the request.

  Wired into all three review paths: `coding-pipeline:reviewer` (new review category),
  `pr-workflow`'s `review-checklist.md` (mirrored table), and `engineering:code-review-gate`,
  whose Reviewer payload now carries **the original request verbatim** — without it CD1, CD3,
  and CD7 are unjudgeable, and the reviewer is told to say so rather than infer intent from
  the diff under test.

- **Proportionality section in `CLAUDE.md`** — the standards previously read as uniformly
  "non-negotiable" with no guidance for a typo fix, so ceremony got applied by feel. Now
  explicit: ceremony scales with the change, standards never do. Security defaults, quality
  gates, spec-first discipline for behaviour changes, CD1–CD7, and never-merge-to-main apply
  at every size; the four lanes (Trivial → inline spec-first → `/task` → `/multi-agent`)
  scale artifacts. The lane is stated before starting; an unstated lane defaults to the
  heavier one. Lanes do not loosen skill routing.

- **"Is the Harness working?" section in `CLAUDE.md`** — five signals countable from artifacts
  the devkit already produces (scope-creep findings, question timing, rework, sensor escape,
  test honesty), with an explicit anti-Goodhart clause: they are human-read diagnostics, never
  targets and never a gate. A stretch of healthy readings is licence to remove ceremony.

### Changed

- Coding Discipline rules 2 and 3 carry their operational tests inline, pointing at the CD ids.

## [2.0.0] — 2026-08-30

### Changed — BREAKING

- **`bmad_v6` plugin renamed to `coding-pipeline`.** The pipeline used BMAD v6 as its
  starting point, but it has diverged far enough that the name was actively misleading:
  delivery worktrees and release branches, spec-first falsification instead of TDD, a
  per-agent model-tier table, an independent Reviewer/Stress/Verdict chain, and a Tuner and
  DevOps stage that BMAD has no equivalent of. The name now describes what the plugin is
  rather than where it came from.

  Namespaces move with it: `bmad_v6:coder` → `coding-pipeline:coder` (all 18 agents), and
  `/bmad_v6:<skill>` → `/coding-pipeline:<skill>` (all 6 pipeline skills).

- **Two pipeline skills renamed to remove the stutter** the new plugin name introduced:
  - `multi-agent-coding-pipeline` → `multi-agent` (`/coding-pipeline:multi-agent`)
  - `task-coding-pipeline` → `task` (`/coding-pipeline:task`)

  `analysis`, `planning`, `architecture`, and `bug-fix` are unchanged.

- **`references/bmad-artifacts.md` → `references/pipeline-artifacts.md`.** Same schemas and
  handoff contracts; the artifacts were never BMAD's.

- Marketplace and plugin descriptions rewritten to drop the BMAD framing, and the demo
  asset `assets/pipeline-ui.html` relabelled (its `bmad-*` CSS classes are now `plan-*`).

### Added — session sensors (deterministic, no model in the loop)

Ideas mined from [affaan-m/ecc](https://github.com/affaan-m/ecc) and adapted to this harness
rather than imported. ECC's catalog breadth was deliberately not taken; only the mechanisms that
close a gap the devkit already had were.

- **`destructive-guard.sh`** (PreToolUse → Bash) blocks force-push, remote branch deletion,
  `reset --hard`/`clean -fd` on a checked-out mainline, recursive deletes aimed at `/` or `$HOME`,
  `curl | sh`, `chmod 777`, and `DROP`/`TRUNCATE` issued from the shell. "A delivery ends in a PR,
  never a rewritten remote branch" was a Guide with no Sensor behind it; now it has one.

- **`secret-write-guard.sh`** (PreToolUse → Write/Edit) blocks writing a recognisable live
  credential into the tree. `env-guard` covered reading secrets; nothing covered writing one.
  Only provider-specific high-entropy prefixes are matched — a generic `password\s*=` rule would
  fire on documentation and fixtures, and a guard that cries wolf gets switched off.

- **`session-tracker.sh` + `delivery-gate.sh`** (PostToolUse / Stop) record which source files
  changed and whether any test, lint, or type-check ever ran, then refuse to call the session done
  when code changed and no gate did. CLAUDE.md already required `/engineering:code-review-gate`
  after every coding task; that requirement held only when the model remembered it.

- **Hook profiles.** `DEVKIT_HOOK_PROFILE=off|standard|strict` and
  `DEVKIT_DISABLED_HOOKS=<id>,<id>`. `strict` makes `delivery-gate` block — but only once per
  session, because a Stop hook that blocks forever traps the operator rather than the mistake.

- **`.github/scripts/test-hooks.sh`** — 30 behaviour assertions covering both directions for every
  guard (blocks what it must, stays out of the way otherwise) plus malformed-payload fail-open.
  Every case was falsified: the guard's logic was removed, the suite observed RED, then restored.
  Two delivery-gate tests were rewritten during that pass — they asserted only an exit code, and
  a warn and a clean pass both exit 0, so deleting the logic left them green.

- **`.github/scripts/validate-wiring.py`** — walks marketplace ↔ plugin manifests, hooks.json ↔
  scripts, every in-repo markdown link and path reference, and every `plugin:agent` reference.
  Each is a file pointing at another file that nothing executes at authoring time, so a rename
  breaks them silently. Both scripts run as CI jobs.

### Fixed

- **`env-guard.sh` had stopped blocking anything.** It read `file_path`/`command` from the top
  level of the hook payload only, while Claude Code sends them nested under `tool_input`. Every
  `.env` read had been passing the guard. Payload access now goes through a shared
  `hook-lib.sh` helper that accepts both shapes, and the regression is covered by six assertions.

- **Five `SKILL.md` files linked to `skill.spec.yml` and `deps.toml` as clickable relative
  links.** Both are git-ignored skillspec artifacts, so the links were dead in every clone and
  install. They now read as plain backticked filenames, matching how `pr-workflow`'s skills
  already referenced them.

- **`install-global.sh` copied `references/*.md` with a flat glob**, which would have shipped the
  new per-language index without the files it points at.

### Added — machine bootstrap

- **`install.sh` at the repo root.** One command takes a bare machine to a configured setup:
  detect the OS (macOS, Linux, WSL) and architecture, pick the package manager (Homebrew, apt,
  dnf, yum, pacman, zypper, apk), install what is missing, resolve the source tree, copy the
  devkit into `~/.claude`, wire the hooks, and record the installed commit. Flags: `--check`
  (report only, writes nothing), `--yes`, `--no-deps`, `--dry-run`, `--home DIR`.

  Re-running is the expected case, not the exception. The installed commit is recorded in
  `~/.claude/devkit/install-state.json` and compared against the source commit, so a second run
  reports "up to date" instead of redoing work. When run from inside a checkout it uses that
  checkout and fast-forwards it if it is behind its remote — but never touches a tree that is
  dirty or has diverged, because resolving that is the operator's call, not an installer's.
  Run from outside a checkout, it clones to `~/.local/share/claude-devkit`.

  It does not pipe anything into a shell. The devkit's own `destructive-guard` blocks
  `curl | sh`, and an installer that breaks its own rule is not worth shipping: the Claude Code
  installer is fetched to a file, its path shown, and executed only after confirmation — and
  `npm` is preferred where available so nothing is downloaded at all.

- **`wire-claude-settings.py`.** The hook wiring used to be printed as JSON for the operator to
  paste by hand, which meant a machine could have every guard installed and none of them active.
  It is now merged into `~/.claude/settings.json` directly, with the hook graph read from the
  plugin's own `hooks.json` so the two cannot drift.

  The merge is conservative because that file holds the operator's permissions and model config:
  unrelated keys and non-devkit hooks are preserved, devkit entries are replaced rather than
  appended (re-running never double-registers a hook), entries pointing at scripts the devkit no
  longer ships are dropped — which is what heals the `bmad_v6` → `coding-pipeline` rename — and a
  `settings.json` that is not valid JSON aborts the install instead of being overwritten.

- **claude-mem wired into the bootstrap.** [claude-mem](https://github.com/thedotmack/claude-mem)
  persists context across sessions, which is the same Memory leg `PROGRESS.md` serves from the
  other end: `PROGRESS.md` is the deliberate record a pipeline writes at each checkpoint,
  claude-mem compresses and replays the conversation itself. Installed with
  `npx claude-mem install` rather than a global npm install, because its own docs are explicit
  that the global install does not register its hooks.

  Treated as optional throughout: a preflight gates on Node >= 20 and `npx`, an already-installed
  copy is left alone, `--no-claude-mem` opts out, and a failure warns instead of aborting — a
  third-party tool must never take the devkit install down with it. The preflight is a separate
  function from the install so the gating is testable without a network call.

- **`install.sh` verifies its own work.** After the copy, it asserts every shipped hook script is
  referenced by `settings.json` and fails loudly otherwise. Staging the scripts and activating
  them are separate steps, and a machine with all seven guards on disk and none referenced is a
  silent failure worth catching.

- **`.github/scripts/test-install.sh`** — 20 assertions against a throwaway `HOME`, covering the
  merge semantics, the platform detection helpers, `--check` making no changes, the state file,
  and the up-to-date path. All 18 mutations were observed RED before the suite was accepted.

  Three defects surfaced during that falsification pass and were fixed: `install.sh` wired the
  hooks a second time after `install-global.sh` had already done it (dead duplication, now a
  verification step); sourcing `install.sh` leaked its `set -euo pipefail` into the test shell, so
  a failing assertion aborted the suite instead of reporting; and `detects_os` put a
  `$(detect_os)` call inside its own failure message, where the command substitution reset `$?`
  before it could be asserted — the test could not fail.

### Removed

- **`plugin.sh`.** A thin wrapper around `claude plugin marketplace add` / `install`, which is
  done directly in Claude Code. The README documents those two commands for anyone who prefers
  the plugin manager; the installer deliberately stays out of it.

- **`assets/pipeline-ui.html`.** Nothing referenced it, it re-implemented the agent personas as
  inline prompt strings that had already drifted from `agents/*.md`, and it called
  `api.anthropic.com` directly from a browser page — a shape this devkit tells people not to
  ship. Recoverable from history if it is ever wanted back.

### Changed — token and validation

- **`references/language-rules-reference.md` (343 lines, 11 languages) split into
  `references/languages/<language>.md`.** Agents were already told to "load only the section for
  the story's Language", but a section of one file costs the whole file — ~340 lines to read ~40.
  Each language file now repeats the test rule, the context7 rule, and the frontend-hardening
  rule so a single-file load is self-sufficient; the old path is now a 40-line index.

- **Architect gained a brownfield spec-mining step.** When a delivery modifies existing code, the
  behaviour it has today is an unwritten spec, and the Test Case table only covers what is being
  added — so anything the change silently alters is untested by construction. The architecture now
  inventories current observable behaviour with its callers and a Preserve/Change/Drop
  disposition, and folds it into the frozen table (Preserve rows become characterization rows and
  still need a falsifying break; Change rows need two entries; Drop rows need the caller search).

- **Verdict gained a five-axis self-check** — Evidence, Traceability, Independence, Residual risk,
  Actionability — with the rule that any axis below 5 must name the specific gap. A verdict is the
  one artifact nobody downstream re-checks. Evidence or Independence below 3 blocks PRODUCTION
  READY; Traceability below 3 is NOT READY.

- **Loop Integrity added to `quality-gate-reference.md`**, applying to every fix loop: the verifier
  may never be moved to reach it (lowering a coverage threshold, adding `skip`, weakening an
  assertion, downgrading a lint rule, editing a frozen Test Case row to match the code, widening a
  type to `any` — all blocking defects, not fixes); an iteration whose failing test, gate, and
  message are identical to the previous one stops the loop instead of spending the budget; and
  compaction happens at story boundaries, never between a story's dispatch and its Verdict.

- **`PROGRESS.md` gained a `Lessons` section** — the only part meant to outlive the delivery. A
  rule plus the evidence that produced it, project-scoped, deleted when it turns out to be wrong.

- The Bug-Fix Loop Protocol's "tests are written RED-first" rule is now scoped to that loop
  explicitly, where every iteration is fixing a known defect. Stated unscoped, it contradicted the
  spec-first discipline that governs everywhere else.

### Versions

| Plugin | Version | Why |
|---|---|---|
| `coding-pipeline` | 1.3.0 → **2.0.0** | Renamed from `bmad_v6`; skill names changed. Breaking for every install. |
| `engineering` | 1.1.2 → **1.2.0** | Depends on the renamed namespace (`coding-pipeline:reviewer`, coverage-threshold reference). |
| `devtools` | 1.1.1 → **1.2.0** | Dispatches `coding-pipeline:rote-adapter`. |
| `pr-workflow` | 1.1.0 | Unchanged. |

### Upgrading

There is no alias mechanism for renamed plugins, so an existing install must be replaced:

```
/plugin uninstall bmad_v6@claude-devkit
/plugin install coding-pipeline@claude-devkit
```

Anything that hardcodes the old namespace needs updating — most commonly a personal
`~/.claude/CLAUDE.md` skill table and the `enabledPlugins` key in `~/.claude/settings.json`.
Historical entries below intentionally keep their original `bmad_v6` paths; they describe
the tree as it was at the time.

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

  - **Broken skill path in all three pipeline entry points.** `multi-agent-coding-pipeline`,
    `task-coding-pipeline`, and its `references/loop.md` each instructed the orchestrator to
    "load and follow `skills/planning.md`" — a file that does not exist. The planning skill is
    `skills/planning/SKILL.md`. Every pipeline run was pointed at a missing file at its first
    planning step. Fixed in all three.
  - **Four unreachable reference files removed** — nothing loaded them and all predated the
    June restructure, so they drifted without any signal:
    `bmad_v6/references/api-integration.md` (taught raw `fetch` calls against the Messages API
    with a stale `claude-sonnet-4-6` model id, while agents actually dispatch via the Task
    tool), `bmad_v6/references/arch-report-reference.md` and
    `bmad_v6/references/rote-reference.md` (both outranked by the live copies under
    `devtools/`), and `engineering/skills/security-review/references/scope-and-checklists.md`
    (a superseded subset — 28 of its 42 content lines were already inlined verbatim in that
    skill's `SKILL.md`, which never referenced it).
  - **`multi-agent-coding-pipeline` description undercounted its own agents** — "all 9 agents"
    while `plugin.json`, `marketplace.json`, and `README.md` all say 11. Corrected to 11
    (Tuner and DevOps were missing from the list).
  - **`/checkcomments` was missing from the CLAUDE.md skill table** — the only one of the 23
    skills absent, so it would never be routed to by the trigger-phrase rule.

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
