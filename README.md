# claude-devkit

Spec-first development skills for [Claude Code](https://claude.ai/code). Every skill is started
by you, does one job, and ends by *suggesting* the next one. Nothing is auto-routed, and no skill
runs another. The engineering bar underneath is unchanged: code is built against a frozen test
specification, proven by falsification, and cleared by gates and an independent reviewer.

## Quick start

Install (`bash install.sh`), open Claude Code in your repo, and type `/devkit-help` to list every skill.
Three worked examples follow. More task presets, each with what its plan should carry:
[`references/presets.md`](plugins/coding-pipeline/references/presets.md).

**1. A small change, no plan**

```
/code "Reject negative quantities in AddToCart with ErrInvalidQuantity"
/validate-code
```

`/code` writes a mini-plan (ACs, Test Case table, one Tasks row) and **asks for a one-line OK**. Then it
**asks for a run mode**: inline, one coder, or one coder per row, each with its token range. The test is
written, then broken and seen to fail, and the gates run. `/validate-code` prints the depth it measured
from the diff (for a change like this, typically `light`: `qa` only) and the verdict.

**2. A feature**

```
/planning notes/webhooks.md
/code docs/plans/webhook-delivery/plan.md
/validate-code docs/plans/webhook-delivery/plan.md
/review-code
/pr
```

`/planning` maps the codebase, drafts the plan, **asks whether to grill it**, has `plan-reviewer` check
it, then **asks you each open question** and **asks you to approve**. `/code` **asks for a run mode**
(parallel coders are offered only when rows are independent). `/validate-code` asks nothing; it reports.
`/review-code` prints its findings, then **asks whether to post them**, in which language and style.
`/pr` **asks you to approve the commit list and the PR body** before anything is pushed.

**3. A bug**

```
/bugfix "cart total goes negative after removing a coupon"
/validate-code
/review-code
/pr
```

`/bugfix` **asks for the symptom, a repro, the fix depth and the branch**. It shows the ranked hypotheses
without waiting, then **asks you to confirm the root cause and fix** after the failing test is RED. The
fix turns it GREEN with every gate run.

## Skills

Invoke by name. Each skill has `disable-model-invocation: true`, so Claude never starts one on its own.

| Skill | What it does |
|---|---|
| `/planning [notes.md]` | Reviewed plan in `docs/plans/{slug}/plan.md`. With a base file it normalizes your notes into the template; without, it builds one. Map, draft, optional grill, `plan-reviewer`, approval. Writes no code. |
| `/code [plan.md or task text]` | Implements. One `coder` dispatch per Tasks row: spec, implement, test, falsify, then format, lint and existing tests. No plan given: writes a mini-plan and asks for a one-line OK first. |
| `/validate-code [--full]` | Read-only check of the current diff: all gates and sensors, then `qa` and `stress` at the depth the diff needs, then the verdict. Reports, never fixes. |
| `/review-code [PR# or branch]` | Reviews a diff or PR with `reviewer` on two separate axes — Standards (repo standards, devkit rules, code smells) and Spec (does it do what the plan or issue asked). Prints all findings, then asks whether to post, in which language and in which style. `--split` reviews each axis in its own dispatch. |
| `/pr [base]` | Commits the branch as atomic conventional commits, then pushes and opens a PR (Summary · Evidence · Merge Danger) — only after you approve the commits and the body. |
| `/pr-fix` | Triages open PR comments into a table, you pick which to fix, `coder` fixes them, gates run, replies are drafted. Asks before posting or pushing. `--list` only lists. |
| `/bugfix` | Asks symptom, repro, fix depth and branch; `bug-investigator` builds a feedback loop that goes red on the bug, minimises it, shows you ranked hypotheses, confirms the root cause and writes a RED test; `coder` makes the minimal fix. |
| `/map [area]` | Read-only codebase map: blast radius, reusable symbols, prior art, conventions, `file:line` for each. |
| `/deps` | Dependency audit and upgrade in batches, majors separate, gates after each batch. |
| `/security-review` | OWASP Web and LLM Top 10 audit with severity-tagged findings. |
| `/database-migration` | Additive, reversible migration with a falsified test. |
| `/observability` | Structured logs, metrics and tracing with a falsified contract test. |
| `/performance-profiling` | Trace-first latency and pprof investigation. |
| `/release-management` | Semver bump, CHANGELOG, tag and a draft GitHub release from merged `main`. |
| `/improve-codebase-architecture` | Architectural health review, in deep-module terms (depth, seams, leverage, locality). |
| `/business-analysis`, `/technical-analysis` | Business-rule and technical-contract mapping of a domain. |
| `/grill-me` | Rounds of hard questions against a plan or design — every question that can be asked now, each with a recommended answer. |
| `/handoff` | End-of-session handoff plus `PROGRESS.md` refresh. |
| `/retro [session] [--metrics]` | Session retrospective: severity-ordered improvements to the agent environment (pointers, checks, reviewer rules, CLAUDE.md, tool economy); applies only what you pick. `--metrics` counts the five Harness health signals (`scripts/harness-metrics.py`) — diagnostics, never gates. |
| `/rote`, `/rote-adapter` | Run existing rote flows; build a new adapter. |
| `/write-a-skill` | Scaffold a new skill. |
| `/devkit-help [skill \| flows]` | Lists every skill grouped by job, read live from the installed `CLAUDE.md`; the typical flows; or one skill's usage, Input/Output/Boundary and next step. No dispatch. |

### A typical flow

```
/planning notes.md  ->  /code docs/plans/cart/plan.md  ->  /validate-code  ->  /review-code  ->  /pr  ->  /pr-fix
/bugfix                                                 ->  /validate-code  ->  /review-code  ->  /pr
```

At the end of a session, `/retro` turns what went wrong into environment fixes.

You can start at any step. `/code "rename X to Y"` needs no plan, because it writes a mini-plan
in the same template. Ceremony scales with the change; the standards do not.

### How `/code` runs

`/code` finds the plan (the path you pass, else an approved `docs/plans/*/plan.md`, else a mini-plan
it writes and you OK), then runs `scripts/estimate-run.py --plan <path>` and asks you to pick a mode:

| Mode | Fits | Dispatches |
|---|---|---|
| Inline | 1–2 small rows | none; your session codes |
| Single coder | tightly coupled rows, shared files (warns above 4 rows) | 1 |
| Sequential coders | most plans (default) | 1 per Tasks row, in dependency order |
| Parallel coders | rows with no `Depends on` and disjoint `Files` | 1 per row, ≤ 3 at once in worktrees, merged in row order with gates after each merge |

Each mode shows a token range labelled `measured`, `partly measured` or `assumed` by its weakest input, plus the measured fix-round factors, and you can override
the mode per row. Gates and falsification evidence run in every mode.

### Dispatches

| Skill | Agents dispatched |
|---|---|
| `/planning` | 1 map (haiku) + 1 `plan-reviewer` per round, max 2 rounds. Drafting happens in your session. |
| `/code` | per the mode you pick (above); `coder`, `coder-backend` or `coder-frontend` by the row's Tier |
| `/validate-code` | By the depth `scripts/verify/classify-diff.sh` measures: cosmetic (doc/style only) none · light (≤ 2 source files, no dependency change, no Stress trigger) `qa` · standard/full `qa` + `stress`. Depth only escalates: unmeasured is full, `--full` forces full. The verdict is `scripts/verify/verdict.sh` plus an inline self-check. |
| `/review-code` | 1 `reviewer` (2 in parallel with `--split`) |
| `/bugfix` | `bug-investigator` + `coder` |

Agents receive file paths, never pasted contents, and **load on demand**: one language file up
front, every other reference only when its trigger fires (each agent carries the trigger table).
`plan-reviewer`, `qa`, `reviewer`, `stress` and `bug-investigator` run on sonnet; `coder` and the
map on haiku. The model aliases resolve to the newest model in each family.
These agents (`reviewer`, `qa`, `coder`, …) are registered only when the devkit is installed — flat
(`install.sh`) or as a plugin; in an uninstalled checkout a skill must dispatch a `general-purpose`
agent pointed at the agent file (`plugins/coding-pipeline/agents/<name>.md`) instead.

## What is enforced

- **Spec-first, falsification-proven.** The Test Case table is frozen before code. The coder writes
  exactly those tests, then breaks the code (`scripts/verify/break-run.sh`) to prove each one fails.
  Tautology is the blocking defect, not low coverage.
- **Plans are checked against the real repo.** Every plan carries a codebase map and a Reuse Map
  (`reuse:` / `extend:` / `new:`, cited `file:line`). `plan-reviewer` reads it with the repository open.
- **Implementer is not the validator.** `coder` builds; `qa`, `reviewer` and `stress` cannot edit files.
- **Duplication is measured and attributed.** `jscpd` gates at 3% *introduced*; pre-existing debt is
  reported, never blocking (`git-hooks/dup-attribution.py`).
- **Principal-engineer bar** in any language: correct, legible, durable, small. Every finding names
  the future change it makes harder.
- **Security first.** OWASP Web and LLM Top 10, secrets never read or written, parameterized queries only.
- **80% context ceiling.** The hook measures it; at 80% the session checkpoints to `PROGRESS.md`.
- **Language specialists.** Go, TypeScript, Java, PHP, Rust, React, Next.js, Flutter, HTMX, Kotlin and
  HTML/CSS, one file each in `references/languages/`, loaded one at a time.

Full rules: [`plugins/coding-pipeline/CLAUDE.md`](plugins/coding-pipeline/CLAUDE.md).
Branching: work on the current branch; on `main` a `feat/{slug}` branch is cut first; nothing is
pushed or opened as a PR unless you ask ([`references/branching.md`](plugins/coding-pipeline/references/branching.md)).

## How it works — Harness + spec-first testing

The devkit is an agentic **Harness**: four components that keep an agent on the rails.

| Component | What it is here |
|-----------|-----------------|
| **Guides** (feed-forward) | `CLAUDE.md`, the plan (`docs/plans/{slug}/plan.md`), API specs, per-language standards, injected before each task |
| **Sensors** (feedback) | Linters in error mode and test/coverage gates that return an exit code, not prose: `pre-commit` (format + lint), `pre-push` (tests + coverage 85%+ + vuln scan), mirrored in CI. Session guards run as Claude Code hooks: secrets, destructive commands, and finishing without ever running a gate. `checkpoint-m.sh` runs spec coverage, diff scope, stray commits, leftover break markers and duplication to completion and reports every failure at once; `break-run.sh` makes falsification evidence real: it mutates exactly one literal, runs the test, requires the row's own `FAIL: <row>` in the output, then restores the file on every exit path. |
| **Memory** | `PROGRESS.md` at the repo root (Done / Failed / Current State / Next / Lessons), entries prefixed with the plan slug. A `SessionStart` hook reads it so a new session resumes with context. Git-ignored: local session memory, never committed, and the same holds for the handoff docs `/handoff` writes. |
| **Separation** | **Implementer is not the validator**: `coder` builds, `qa`/`reviewer`/`stress` validate. ACs and the Test Case table are frozen before any code. Read-only subagents may fan out wider than writers (width in `thresholds.md`); writers stay at 3 or fewer per turn. `/code` offers run modes (inline, single coder, sequential, parallel in worktrees) with token estimates from `scripts/estimate-run.py`. Agent teams are documented, opt-in, and never enabled by the installer. |

### Spec-first, falsification-proven

Tests are written **after** the implementation, against a specification frozen **before** it.
The rigour moves from ordering to specification tightness plus proof that each test can fail:

1. **Spec**: the plan's Test Case table gives, for every AC, edge case and security control, one row with the literal test name, the input, the **expected observable result**, **why it matters**, and the **break that falsifies it**. A behaviour with no row does not get built.
2. **Implement**: `coder` builds to that table. Anything the spec didn't decide is flagged, never invented.
3. **Test**: it writes exactly those rows, no more, no fewer, asserting observable results.
4. **Falsify**: for each test it applies the row's break (invert the condition, delete the guard, return the zero value), confirms the test **fails on its own assertion**, and restores. A test never observed failing is unproven and does not ship.

`qa` does **not** write these tests; it audits them. It checks every Test Case row is implemented, that every test carries valid falsification evidence (and re-breaks the highest-risk ones to verify), that assertions are real rather than tautological or over-mocked, that corner cases are covered (boundaries, nulls, overflow, unicode, concurrency, time, error paths), and that no existing test was weakened to make a change pass. A tautological or unfalsified test is a MAJOR finding that caps the QA score at 4, the same weight as a failing gate, no matter how high coverage is. Gaps go back to a fresh `coder` via `QA→CODER TEST GAP`.

**The one exception is bug fixes**: a failing reproduction test is written and observed RED *before* the fix, because that RED proves the root cause was found rather than guessed.

Plans can be stress-tested with `/grill-me` before any code is written: gaps the requirements can answer get decided into the design; the rest are escalated to the human. Nothing ambiguous is deferred into implementation.

### Scoring

| Result | Criteria |
|--------|---------|
| PRODUCTION READY | Overall 8.0 or higher, no CRITICAL security issues |
| READY WITH CONDITIONS | 6.5–7.9, or 8.0+ with 1 CRITICAL |
| NOT READY | below 6.5 or unmitigated CRITICAL security issue |

`/validate-code` weighs Stress 35% · QA 30%, renormalised (`verdict.sh --no-review`); at light depth QA alone (`--no-stress`), at cosmetic depth gates only. `/review-code` is a
separate gate: score ≥ 8.0 with no CRITICAL passes. The two never wait on each other. Numbers: `references/thresholds.md`.

## Engineering Standards

`CLAUDE.md` is injected into every Claude Code session and enforces:

### Go
- Authority: Uber Go Style → Ardan Labs/service → JetBrains Go Modern → Effective Go
- **Zero error discards** — `_ =` or `_ :=` on errors is a hard block
- Wrap all errors: `fmt.Errorf("doing X: %w", err)` — never bare `return err`
- `swaggo/swag` annotations required on every HTTP handler
- **Transaction races**, not just data races — check-and-act split across two critical sections passes `-race` and still corrupts state. Also: lock ordering by stable id, no mutex held across I/O, clone before returning guarded state, result channels buffered to sender count
- **No `time.Sleep` in tests** — virtual time where the toolchain provides it, an injected clock otherwise. Deterministic failure stubs, never probability
- Toolchain capabilities are **detected, not versioned**: rules name a `go doc` check and a fallback, because a version number in a rules file rots silently

### TypeScript
- `strict: true` in tsconfig; no `any` on public API or HTTP boundaries
- zod/joi validation at every HTTP boundary before processing request data

### React
- Functional components + hooks only; `eslint-plugin-react-hooks` zero violations
- `eslint-plugin-jsx-a11y` zero warnings; semantic HTML; no div-soup
- No `dangerouslySetInnerHTML` with user data — sanitize via `DOMPurify`

### Library API Rule

> **Always use context7.** Before writing any library-specific code — framework, SDK, ORM, auth library, cloud client — Claude fetches the current documentation via context7. Never infer API shapes from training data. A method that existed in v1 may not exist in v3.

This applies everywhere: coder, reviewer, QA gates, skill implementations. If context7 returns no results for a library, Claude falls back to the installed version's changelog before guessing.

### Spec-Driven Development

For any feature with HTTP endpoints, the devkit enforces a spec-first workflow:

1. **Architect** writes `api-spec.yaml` (OpenAPI 3.1) before any code — defines all endpoints, schemas, error shapes, auth
2. **Coder** writes failing contract tests first (status, schema, auth per `operationId`), then implements against the spec exactly; annotations must reproduce spec `operationId` + status codes
3. **QA** audits that a contract test exists per `operationId`, then runs Spectral lint + schema validation as quality gates
4. **Reviewer** checks for spec drift (annotation ↔ spec ↔ implementation alignment)

Spec is the source of truth — code follows spec, never the reverse.

### Quality Gates

| Gate | Go | TypeScript | React | Flutter | Kotlin |
|------|-----|------|-------|---------|--------|
| Format | `gofmt` | `prettier --check` | `prettier --check` | `dart format` | `ktlint` |
| Lint | `go vet` + `golangci-lint` (0) | `eslint --max-warnings 0` | `eslint` (react-hooks + a11y) | `flutter analyze` | `detekt` + `ktlint` |
| Types | — | `tsc --noEmit` | `tsc --noEmit` | — | — |
| Coverage | ≥ 85% | ≥ 85% | ≥ 85% | ≥ 80% | ≥ 85% |
| Race | `go test -race` | — | — | — | — |
| Vuln | `govulncheck` | `npm audit` | `npm audit` | — | — |
| Modernize *(advisory)* | `go fix -diff` (Go ≥ 1.26, reports only) | — | — | — | — |
| Spec lint | `spectral lint` | `spectral lint` | — | — | — |

### Security
- OWASP Web Top 10 (2025) enforced at Reviewer + Verdict stages
- OWASP LLM Top 10 2025 (v2.0) enforced for AI/GenAI workloads
- `.env` / `.envrc` reads blocked at Claude Code hook level; credential writes and destructive shell commands blocked the same way
- Never log PII, secrets, tokens, or card data

---

---

## Companion Tools

This devkit is designed to work alongside four companion tools. They're optional but strongly recommended — together they cut token usage by 60–90% and keep library usage current.

### RTK — Rust Token Killer

Token-optimized proxy for all CLI commands. Every `git`, `go test`, `jest`, `tsc`, `eslint`, `pnpm`, `docker`, `gh` call is automatically filtered to show only failures and errors — not the full verbose output.

```bash
# Before RTK: git status dumps 40 lines
# After RTK: git status → 3-line compact summary

rtk git status
rtk go test ./...         # failures only (90% savings)
rtk jest                  # failures only (99.5% savings)
rtk tsc                   # errors grouped by file (83% savings)
rtk next build            # route metrics + errors (87% savings)
```

RTK is wired via a `PreToolUse` hook — every Bash command automatically routes through it with zero overhead. Install: see [RTK repo](https://github.com/JuliusBrussee/rtk) (or your internal fork).

---

### Caveman — Compressed Mode

Cuts Claude's response verbosity by 60–70% without losing technical substance. Drops articles, filler, pleasantries, and hedging. All code, security warnings, and multi-step sequences remain fully expanded.

```
/caveman           # toggle on/off
/caveman lite      # mild compression
/caveman full      # default — classic caveman (recommended)
/caveman ultra     # maximum compression
/caveman-stats     # token savings report for current session
```

Activated automatically at session start via `SessionStart` hook. Mode persists across turns. Install: `claude plugin install caveman@caveman`.

---

### Rote — Adapter Framework

Crystallizes any API/MCP call into a reusable CLI flow. Claude and the rote CLI are a pair: Claude discovers + executes via the `/rote` skill; the CLI crystallizes + replays.

```bash
rote flow search "list my open PRs"   # find existing flow
rote adapter list                      # what adapters are installed
rote github_call list_open_prs '{}'    # invoke adapter directly
rote flow crystallize "github-list-open-prs" --adapter github --intent "list open PRs"
rote flow release "github-list-open-prs"   # now reusable by CLI + Claude
```

**How pairing works:**
1. `/rote` skill runs Phase 0 (state snapshot) at every invocation — shows installed adapters + all crystallized flows
2. After any successful adapter call, Claude crystallizes it as a CLI flow
3. Next session: Claude discovers the flow in Phase 0 and replays it — no re-discovery

Use `/rote` for existing flows, `/rote-adapter` to build a new integration from scratch.
Install: see your internal rote distribution.

---

### context7 — Always-Current Library Docs

**Rule: Claude always fetches current docs via context7 before using any library, framework, SDK, API, or CLI tool. Training data is never the source of truth for library APIs.**

Why this matters: Claude's training data has a cutoff. A library that was at v1.x during training may be at v3.x now — different API shapes, deprecated methods, new patterns. context7 fetches the live documentation and injects it into the session before Claude writes any library-specific code.

```
# Claude does this automatically before using any lib/framework:
context7 → fetch current React docs    → write components against v19 API
context7 → fetch current Go chi docs   → use correct middleware signatures
context7 → fetch current Prisma docs   → use current schema syntax
context7 → fetch current NestJS docs   → use current decorator API
```

**What triggers a context7 fetch:**
- Any library, framework, SDK, or cloud service API
- CLI tool flags and configuration (Next.js, Vite, Docker, kubectl)
- Database client APIs (Prisma, GORM, TypeORM, sqlc)
- Auth libraries (Passport, jose, golang-jwt)
- Third-party integrations (Stripe SDK, AWS SDK, OpenAI SDK)

**How to use it yourself:**

```
How do I configure middleware in the latest version of chi?
  → tell Claude to use context7 to check the current chi docs

What's the current Prisma migration workflow?
  → Claude fetches context7 docs before answering
```

Install: `claude plugin install context7@claude-plugins-official`

---

---

## Install

One command per machine. It detects the OS, installs what is missing, puts the devkit in
`~/.claude`, and wires the hooks into `settings.json`. macOS, Linux and WSL.

```bash
git clone https://github.com/LuisFelipeMoro/Harness-devkit
cd Harness-devkit
bash install.sh
```

Re-running is the normal case; it does nothing expensive when the installed commit matches.

```bash
bash install.sh --check          # report only, never writes
bash install.sh --yes            # no prompts
bash install.sh --no-deps        # skip package installation
bash install.sh --no-claude-mem  # skip the claude-mem memory layer
bash install.sh --dry-run        # print what would happen
```

| Step | Detail |
|---|---|
| Source | The clone you ran it from, or `~/.local/share/claude-devkit`. Fast-forwards only; never touches a dirty or diverged tree. |
| Dependencies | Required: `git`, `python3`, `curl`. Recommended: `gh`, `shellcheck`, `ripgrep`. |
| Devkit files | Agents, skills, references and `CLAUDE.md` into `~/.claude`, plus git-hook templates. |
| Hook wiring | Merges the hook graph into `~/.claude/settings.json` and verifies every shipped hook is referenced. |
| claude-mem | Optional (`npx claude-mem install`, Node 20+). Never fails the run. |

It never pipes a downloaded script into a shell. Existing `~/.claude/` files are safe: your own
files are untouched, `~/.claude/CLAUDE.md` gets one `@include` line, and `settings.json` keeps your
`model`, `permissions`, `env` and non-devkit hooks. Invalid JSON aborts rather than being rewritten.

The flat install also stages the sensor scripts (`scripts/verify/*`, `estimate-run.py`, `harness-metrics.py`) to
`~/.claude/devkit/scripts/`, where skills and agents resolve `scripts/…` paths.

Upgrading from 2.x retires the old skills, agents and hook (`multi-agent`, `task`,
`analysis`, `architecture`, `quality-gate`, `code-review-gate`, `pr-review`, `checkcomments`, `bug-fix`;
`analyst`, `pm`, `scrum-master`, `orchestrator`, `tuner`, `architect`, `devops`;
the orchestrator Bash-guard hook and its `settings.json` entry): each is moved to
`~/.claude/devkit/retired/<UTC timestamp>/` (same layout), never deleted, and only when its bytes match a version
the devkit shipped. A file of yours that shares one of these names is left in place and reported
`kept (not the devkit's): <path>`. Each move is printed with its destination. Nothing else in `~/.claude/` is touched.

Overrides: `DEVKIT_HOME` (managed clone location), `DEVKIT_REPO` (clone source), `TARGET_HOME` or `--home DIR`.

**As a Claude Code plugin instead:**

```
/plugin marketplace add LuisFelipeMoro/Harness-devkit
/plugin install coding-pipeline@claude-devkit
```

A plugin cannot ship a `CLAUDE.md` or write `.git/hooks/`. Add the standards with
`cp plugins/coding-pipeline/CLAUDE.md ~/.claude/devkit/CLAUDE.md` plus an `@~/.claude/devkit/CLAUDE.md`
line in `~/.claude/CLAUDE.md`, and the git hooks per repo with `bash ~/.claude/git-hooks/install.sh`.

**Codex CLI:** `bash plugins/coding-pipeline/scripts/install-codex.sh` places every skill in
`~/.agents/skills/`; `generate-codex-agents.sh` writes one `~/.codex/agents/<name>.toml` per agent.
Skill sequencing under Codex is not yet validated live; see `plugins/coding-pipeline/codex/harness-adapter.md`.

## Plugins

```
plugins/
├── coding-pipeline/   # planning, code, validate, bugfix, map; agents, hooks, references
├── engineering/       # deps, security-review, database-migration, observability,
│                      #   performance-profiling, release-management
├── pr-workflow/       # review-code, pr, pr-fix
└── devtools/          # improve-codebase-architecture, business/technical analysis,
                       #   grill-me, handoff, retro, write-a-skill, rote, rote-adapter,
                       #   devkit-help
```

## Hooks

| Hook | Trigger | Behaviour |
|------|---------|-----------|
| `session-bootstrap.sh` | SessionStart | Prints `PROGRESS.md` so a new session resumes with done/failed/current state |
| `env-guard.sh` | PreToolUse | Blocks reads of `.env`, `.envrc`, `.env.*`, including via `cat`/`grep` |
| `destructive-guard.sh` | PreToolUse(Bash) | Blocks force-push, remote branch deletion, `reset --hard` on a mainline, root/home recursive deletes, `curl \| sh`, `chmod 777`, destructive DDL |
| `secret-write-guard.sh` | PreToolUse(Write/Edit) | Blocks writing a recognisable live credential |
| `dispatch-budget.sh` | PreToolUse(Agent) | Warns once past the session dispatch budget (default 14, `DEVKIT_DISPATCH_BUDGET`); flags an oversized dispatch prompt |
| `session-tracker.sh` | PostToolUse | Records changed source files and whether a gate command ran |
| `context-budget.sh` | PostToolUse | Warns at 60% context, calls the 80% ceiling |
| `pr-review-responder.sh` | PostToolUse(Bash) | After `git push`, says how many PR comments are open and suggests `/pr-fix` |
| `precompact-snapshot.sh` | PreCompact | Records branch, dirty files and recent commits before compaction |
| `delivery-gate.sh` | Stop | Refuses to call a session done when source changed and no test, lint or type-check ran; suggests `/validate-code` |

The guards are deterministic (regex and exit codes, no model in the loop), each covered by `.github/scripts/test-hooks.sh`, and fail open on a payload they cannot parse.

|---|---|
| `DEVKIT_HOOK_PROFILE=off` | Every guard is inert |
| `DEVKIT_HOOK_PROFILE=standard` | Default. Guards block; `delivery-gate` warns |
| `DEVKIT_HOOK_PROFILE=strict` | `delivery-gate` blocks once per session instead of warning |
| `DEVKIT_DISABLED_HOOKS=id,id` | Disables individual hooks: `pre:read:env-guard`, `pre:bash:destructive-guard`, `pre:write:secret-guard`, `post:session-tracker`, `stop:delivery-gate` |

`strict` blocks a given session only once — a Stop hook that blocks forever traps the operator
rather than the mistake.

---



## Git hooks

| Hook | Runs | Checks |
|------|------|--------|
| `pre-commit` | Every commit | Go: `gofmt`, `go vet`, `golangci-lint --fast` · TS: `tsc --noEmit`, `eslint` |
| `pre-push` | Before push | Go: `go test -race`, coverage 85%+, `govulncheck` · TS: `jest --coverage`, `npm audit` · duplication |
| `commit-msg` | Every commit | Conventional Commits |

Both also run `release-content-guard.sh`: `PROGRESS.md`, handoff snapshots and generated test output
are rejected before they can enter a commit or push. Patterns come from the repo's own
`.devkit/release-exclude` (one glob per line). `PROGRESS.md` is local session state, git-ignored,
and stays out of releases.

## Required Tools

### Core (devkit needs these)
| Tool | Install | Used by |
|------|---------|---------|
| `gh` (GitHub CLI) | `brew install gh` / `apt install gh` | PR hook, `/review-code`, `/pr-fix`, release management |
| `golangci-lint` | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` | Go quality gates |
| `govulncheck` | `go install golang.org/x/vuln/cmd/govulncheck@latest` | Go vulnerability scan |
| `staticcheck` | `go install honnef.co/go/tools/cmd/staticcheck@latest` | Go static analysis |
| `swag` | `go install github.com/swaggo/swag/cmd/swag@latest` | Go OpenAPI generation |
| `spectral` | `npm i -g @stoplight/spectral-cli` | Spec-driven: OpenAPI spec linting (all stacks) |
| `swagger-cli` | `npm i -g @apidevtools/swagger-cli` | Spec-driven: OpenAPI spec validation |
| `schemathesis` | `pip install schemathesis` | Spec-driven: contract testing (integration phase) |
| `oapi-codegen` | `go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest` | Go: generate types/stubs from spec |

### Companion tools (optional — strongly recommended)
| Tool | Install | What it adds |
|------|---------|--------------|
| **RTK** | Internal / see RTK repo | 60–90% token savings on all CLI output via automatic filtering |
| **Caveman** | `claude plugin install caveman@caveman` | 60–70% response compression; mode persists across turns |
| **Rote** | Internal / see rote repo | Adapter framework; crystallizes API calls into reusable CLI flows |
| **claude-mem** | `npx claude-mem install` (or `bash install.sh`) | Compresses and replays prior sessions, so context survives a restart |

---


## Developing the devkit

CI fails on an exit code, never on prose. Run the same checks locally:

```bash
bash .github/scripts/test-hooks.sh
bash .github/scripts/test-git-hooks.sh
bash .github/scripts/test-install.sh
bash .github/scripts/test-verify.sh
bash .github/scripts/test-dup-attribution.sh
python3 .github/scripts/validate-wiring.py   # manifests, hooks, links, skills table, 60-line skills
```

`validate-wiring.py` exists because nearly every capability is one file pointing at another, and
nothing executes those links at authoring time. It also enforces that every skill is manual, at most
60 lines, and never invokes another skill.
