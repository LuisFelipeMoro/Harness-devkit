# claude-devkit

BMAD v6 AI-assisted development pipeline for [Claude Code](https://claude.ai/code). Drop this into any repository under `.claude/` (or install globally in one command) to get a full agentic development kit: every piece of code is built against a frozen test specification, proven by falsification, and clears quality gates plus an independent reviewer before it's considered done.

- **Spec-first testing** — the Architect freezes a Test Case table (expected observable result · why it matters · what break falsifies it) before any code. The Coder implements to it, writes exactly those tests, then **breaks the code to prove each test fails**. The QA agent audits that evidence instead of writing tests.
- **Tautology is the blocking defect, not low coverage** — a green suite at 90% coverage that survives having its guards deleted fails the audit. Coverage is a floor; falsifiability is the gate.
- **Isolated per delivery** — each pipeline run gets its own git worktree (`.worktrees/dlv-{key}/`) and release branch, and writes its plan to `docs/deliveries/delivery-{slug}-{key}.md` instead of clobbering your repo's own `architecture.md`. Two deliveries never share a file or a working tree. The pipeline never commits or merges to `main` — the furthest it goes on its own is opening a PR.
- **Harness-structured** — built on the four agentic-harness components: Guides (feed-forward context), Sensors (exit-code linters + test gates), Memory (cross-session `PROGRESS.md`), Orchestration (implementer ≠ validator, contract frozen before code).
- **11-agent coding pipeline** — Analyst → PM → Architect → grill-me plan stress → ScrumMaster → Coder → QA → Reviewer → StressTester → Tuner → Verdict → DevOps
- **Task-matched models** — `opus` for architecture design, `sonnet` for planning/validation, `haiku` for read/explore and code execution. Max reasoning goes into the plan; a tight plan means execution can be cheap.
- **Multi-language engineering standards** — Go, TypeScript, Java, PHP, Rust, React, Flutter, HTMX, Kotlin Android, HTML/CSS
- **Security-first quality gates** — OWASP Web Top 10 + OWASP LLM Top 10 2025 enforced at every stage
- **23 skills** (slash commands) — architecture, security review, DB migrations, observability, PR review, release management, and more
- **Git hooks** — pre-commit (format + lint), pre-push (full gates), commit-msg (Conventional Commits)
- **Claude Code hooks** — resumes from `PROGRESS.md` at session start; blocks `.env` reads; auto-reviews PR comments after every push
- **Integrated companion tools** — RTK (token savings), Caveman (compressed mode), Rote (adapter framework)

---

## How It Works — Harness + Spec-First Testing

This devkit is structured as an agentic **Harness** — four components that keep an
autonomous agent on the rails:

| Component | What it is here |
|-----------|-----------------|
| **Guides** (feed-forward) | `CLAUDE.md`, the delivery file (`docs/deliveries/delivery-{slug}-{key}.md`), API specs, per-language standards — the right context injected before each task |
| **Sensors** (feedback) | Linters in error-mode and test/coverage gates that return an exit code, not prose: `pre-commit` (format + lint), `pre-push` (tests + coverage ≥ 85% + vuln scan), mirrored in CI. A task isn't done until they pass. |
| **Memory** | `PROGRESS.md` at the repo root (Done / Failed / Current State / Next), every entry prefixed with its `[{delivery-key}]`. A `SessionStart` hook reads it so a new session resumes with context instead of starting blind. |
| **Orchestration** | An orchestrator spawns isolated subagents with a pre-agreed contract. **Implementer ≠ validator** — the Coder builds, the QA/Reviewer/Stress agents validate. ACs + Definition of Done are frozen before any code. |

### Spec-first, falsification-proven

Tests are written **after** the implementation, against a specification frozen **before** it.
The rigour moves from ordering to specification tightness plus proof that each test can fail:

1. **Spec** — the Architect (Winston) freezes a Test Case table: for every AC, edge case, and
   security control, one row giving the literal test name, the input, the **expected observable
   result**, **why it matters**, and the **break that falsifies it**. The Scrum Master copies the
   relevant rows verbatim into each story. A behaviour with no row does not get built.
2. **Implement** — the Coder (Amelia) builds to that table. Anything the spec didn't decide is
   flagged, never invented.
3. **Test** — she writes exactly those rows, no more, no fewer, asserting observable results.
4. **Falsify** — for each test she applies the row's break (invert the condition, delete the
   guard, return the zero value), confirms the test **fails on its own assertion**, and restores.
   A test never observed failing is unproven and does not ship.

The QA agent (Quinn) does **not** write these tests — she audits them. She checks every Test
Case row is implemented, that every test carries valid falsification evidence (and re-breaks the
highest-risk ones herself to verify), that assertions are real rather than tautological or
over-mocked, that corner cases are covered (boundaries, nulls, overflow, unicode, concurrency,
time, error paths), and that no existing test was weakened to make a change pass. A tautological
or unfalsified test is a MAJOR finding that caps the QA score at 4 — the same weight as a failing
gate, no matter how high coverage is. Gaps route back to the Coder via `QA→CODER TEST GAP`.

**The one exception is bug fixes**: there, a failing reproduction test is written and observed
RED *before* the fix, because that RED is what proves the root cause was found rather than
guessed.

Plans are stress-tested with `/grill-me` **before** any code is written — gaps the
requirements can answer get decided into the architecture; the rest are escalated to the
human. Nothing ambiguous is deferred into the implementation.

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

## Quick Start

Three installation paths. Pick one based on your situation. Supports Linux and macOS.

---

### Option A — Plugin only (no git hooks needed)

```bash
claude plugin install github:LuisFelipeMoro/claude-devkit
```

**Use when:** you only care about Claude Code skills and agents (no format/lint/push enforcement via git), or you're evaluating the pipeline before committing to full setup, or your team already has git hooks in place.

**What you get:** all skills, all agents, CLAUDE.md standards, env-guard hook — everything Claude-facing.

**What you don't get:** `pre-commit` format check, `pre-push` quality gates, `commit-msg` enforcement.

Updates: `claude plugin update LuisFelipeMoro/claude-devkit`

---

### Option B — Plugin + git hooks (recommended for teams)

**Step 1:** install Claude Code integration via plugin manager
```bash
claude plugin install github:LuisFelipeMoro/claude-devkit
```

**Step 2:** wire OS-level git hooks (plugin can't touch `.git/hooks/`)
```bash
git clone https://github.com/LuisFelipeMoro/claude-devkit .claude-tmp
bash .claude-tmp/plugins/bmad_v6/scripts/install-git-hooks.sh
rm -rf .claude-tmp
```

**Use when:** you want quality gates enforced at commit/push time, not just during AI sessions. Onboarding teammates — they each run these two commands once per machine.

**What you get:** everything in Option A plus `pre-commit` (format + lint), `pre-push` (full quality gates), `commit-msg` (Conventional Commits).

Updates: `claude plugin update LuisFelipeMoro/claude-devkit` (re-run install-git-hooks after hook changes)

---

### Option C — Full manual install (no plugin manager)

```bash
git clone https://github.com/LuisFelipeMoro/claude-devkit
cd claude-devkit
bash plugins/bmad_v6/scripts/install-global.sh
```

**Use when:** private internal fork not on public GitHub; no internet at install time; or you're iterating on the devkit itself — edit locally, run the script, changes land in `~/.claude/` immediately.

**Safe on existing `~/.claude/`:** same-named files updated; your custom files untouched. `~/.claude/CLAUDE.md` is **never overwritten** — an `@include` line is injected once. Re-running is idempotent.

---

### Adding git hooks to a new repo (after any option)

```bash
bash ~/.claude/git-hooks/install.sh
```

---

### Codex CLI / Other Harnesses

Every `SKILL.md` in this devkit uses only `name:`/`description:` frontmatter — the same
shape Codex CLI's own Skills convention expects. A dedicated installer places them where
Codex scans for skills:

```bash
bash plugins/bmad_v6/scripts/install-codex.sh
```

**What you get:** every skill installed to `~/.agents/skills/` (Codex's user-level skills
path), plus the 18 `agents/*.md` persona docs copied to `~/.agents/agents-reference/` for
manual reference. Root `AGENTS.md` documents the same engineering standards for any
harness working in this repo directly.

To also give Codex real, dispatchable subagents (not just reference docs) — one
`~/.codex/agents/<name>.toml` per persona, reasoning effort mapped from that persona's
Claude model tier (`opus`→`high`, `sonnet`→`medium`, `haiku`→`low`):

```bash
bash plugins/bmad_v6/scripts/generate-codex-agents.sh
```

**Scope:** single-agent skills (`security-review`, `quality-gate`, `pr-review`, etc.) work
identically to Claude Code. Multi-agent pipeline skills (`multi-agent-coding-pipeline`,
`bug-fix`, etc.) now have real per-persona Codex subagents at the right reasoning effort,
but pipeline **sequencing** — which persona runs when, reading handoff signals like
`CODER DONE` — hasn't been exercised end-to-end in a live Codex session yet. See
`plugins/bmad_v6/codex/harness-adapter.md` for the vocabulary mapping and current gaps.

---

## Plugin Structure

The devkit is split into focused plugins. Each installs independently or together:

```
plugins/
├── bmad_v6/            # Core BMAD v6 pipeline — agents, pipeline skills, references
├── engineering/        # Quality skills — security-review, quality-gate, code-review-gate,
│                       #   DB migration, observability, performance, release management
├── devtools/           # Developer tools — architecture review, business/technical analysis,
│                       #   grill-me, handoff, skill authoring, rote, rote-adapter
└── pr-workflow/        # PR skills — pr-review, checkcomments
```

---

## Pipeline Overview

### Full BMAD v6 — `/multi-agent-coding-pipeline <task>`

For large features and epics. Runs up to 11 agents (9 core + Tuner + DevOps):

```
DELIVERY SETUP
  orchestrator        → slug + key from the feature name
                        .worktrees/dlv-{key}/ on branch release/{slug}-{key}
                        (existing worktree for the key = resume, not recreate)

PLANNING  (all artifacts keyed under docs/deliveries/{key}/)
  Mary (Analyst)      → {key}/product-brief.md
  John (PM)           → {key}/PRD.md
  Winston (Architect) → docs/deliveries/delivery-{slug}-{key}.md  (+ api-spec.yaml at repo root)
  /grill-me           → stress the plan (mandatory) ← human resolves open questions
  Bob (ScrumMaster)   → {key}/story-{slug}.md per task (ACs + Test Case table = frozen contract)

IMPLEMENTATION (per story, SEQUENTIAL — stories share the delivery worktree)
  Amelia (Coder)      → impl to spec → write specified tests → falsify each (owns tests + code)  [emits CODER DONE]
     stack-aware: shared core + backend OR frontend overlay (chosen by story Tier);
     frontend overlay covers SSR/RSC; loads only the detected language's rules;
     full-stack stories split BE/FE around the api-spec contract (BE producer, FE consumer)
        ↕ QA loop (max 3 iterations)
  Quinn (QA)          → audits spec rows + falsification evidence (spot-checks breaks), no tautologies, corner cases + runs gates  [one tier-aware auditor]
        │ gate fail   → QA→CODER BUG REPORT  → Amelia fixes → Quinn re-runs
        │ weak/missing test → QA→CODER TEST GAP → Amelia writes it → Quinn re-audits
        │ coverage gap → QA→CODER COVERAGE REQUEST → Amelia refactors
        └ all green → QA→REVIEWER APPROVAL  ← Reviewer never runs before this

REVIEW (parallel — triggered by QA approval only)
  Reviewer            → score X/10  (MINOR/NIT → Tyler)
  StressTester        → score X/10  (optimizations → Tyler)

TUNING (optional — score ≥ 7, MINOR/NIT/optimization only)
  Tyler (Tuner)       → apply fixes → Reviewer re-scores (max 2 iterations)

  Verdict             → PRODUCTION READY / READY WITH CONDITIONS / NOT READY

POST-VERDICT (if PRODUCTION READY)
  Ops (DevOps)        → Dockerfile + .dockerignore + docker-compose.yml + optional CI/k8s

DELIVERY CLOSE (terminal — the pipeline stops here)
  orchestrator        → push release/{slug}-{key} (asks first) → open PR to main
                        never commits or merges to main; a human merges
                        then /release-management tags the merged main
```

### Fast Pipeline — `/task-coding-pipeline <task>`

Skips Analyst + PM. Starts directly at Architecture → grill-me plan stress → Decompose into sub-tasks → Implement per sub-task. Same agent protocol (Coder implements to the frozen Test Case table, writes those tests, falsifies each → QA audit loop → QA approval → Reviewer).

### Progressive Workflow

```
Exploring requirements only
  → /analysis <task>                   Brief + PRD only
         ↓
  → /planning                          Load Brief+PRD → delivery file + manifest
         ↓
  → /multi-agent-coding-pipeline       Full Epic Loop → Verdict
         — or —
  → /task-coding-pipeline              Sub-Task Loop → Verdict

Fast path (one known task)
  → /task-coding-pipeline <task>       Architect → sub-tasks → code → QA → Verdict

Ad-hoc code change (spec-first, direct edit)
  → list the test cases first, then code, then write those tests and falsify each
         ↓ (mandatory final step)
  → /code-review-gate                  Gates + Reviewer on changed files
```

### Scoring

| Result | Criteria |
|--------|---------|
| PRODUCTION READY | Overall ≥ 8.0, no CRITICAL security issues |
| READY WITH CONDITIONS | 6.5–7.9, or ≥ 8.0 with 1 CRITICAL |
| NOT READY | < 6.5 or unmitigated CRITICAL security issue |

Score weighted: Review 35% · StressTest 35% · QA 30%.

---

## Skills Reference

### Quick decision guide

```
What are you trying to do?
│
├─ Build something new
│   ├─ Large feature / epic / new service  →  /multi-agent-coding-pipeline
│   ├─ Single task / small change          →  /task-coding-pipeline
│   ├─ Just need a plan, no code yet       →  /planning
│   └─ Just explore requirements           →  /analysis
│
├─ Fix something broken
│   └─ Bug / wrong behavior / crash        →  /bug-fix
│
├─ Finished coding (outside a pipeline)
│   └─ Gate + review before pushing        →  /code-review-gate  ← mandatory
│
├─ Audit or investigate
│   ├─ Security vulnerabilities            →  /security-review
│   ├─ Architectural health / coupling     →  /improve-codebase-architecture
│   ├─ Performance / latency / profiling   →  /performance-profiling
│   ├─ Business rules and domain logic     →  /business-analysis
│   └─ HTTP contracts / API surfaces       →  /technical-analysis
│
├─ Ship or maintain
│   ├─ Cut a release                       →  /release-management
│   ├─ Write a DB migration                →  /database-migration
│   ├─ Add logging / tracing               →  /observability
│   ├─ Run all quality gates               →  /quality-gate
│   ├─ Review a PR                         →  /pr-review
│   └─ Check open PR comments              →  /checkcomments
│
├─ Plan and design
│   ├─ Standalone architecture design      →  /architecture
│   └─ Stress-test a plan before coding   →  /grill-me
│
├─ Integrate with external APIs
│   ├─ Run an existing integration flow    →  /rote
│   └─ Build a new integration from scratch →  /rote-adapter
│
└─ Meta
    ├─ Wrap up a session                   →  /handoff
    └─ Add a new skill to the devkit       →  /write-a-skill
```

---

### Pipeline skills

#### `/multi-agent-coding-pipeline <task>`

**Use when:** building a large feature, epic, or new service from scratch.

**What happens:** Runs all 11 agents in sequence. Mary (Analyst) writes a product brief → John (PM) writes a PRD → Winston (Architect) designs the architecture and API spec → **`/grill-me` stresses the plan + human resolves open questions** → Bob (ScrumMaster) decomposes into stories (ACs + Test Case table = frozen contract) → Amelia (Coder) implements to the spec, writes exactly the specified tests, then falsifies each one → Quinn (QA) audits the falsification evidence and runs the gates → Reviewer + StressTester score in parallel → Tyler (Tuner) polishes minor findings → Verdict issues PRODUCTION READY / NOT READY → Ops (DevOps) generates Dockerfile + docker-compose.

**Example:**
```
/multi-agent-coding-pipeline Build a cart service for our e-commerce platform.
  It should support adding/removing items, applying discount codes, and
  persisting carts for logged-in users. Go + PostgreSQL.
```

---

#### `/task-coding-pipeline <task>`

**Use when:** implementing a single known task — a new endpoint, a refactor, a small feature. You already know what needs to be built.

**What happens:** Skips Analyst + PM. Winston architects the solution + writes API spec → **`/grill-me` stresses the plan + human validates** → Bob writes a story with its frozen Test Case table → Amelia implements to spec → writes those tests → falsifies each → Quinn audits evidence + gates → Reviewer + StressTester → Tuner → Verdict → DevOps. Same quality bar as the full pipeline, faster start.

**Example:**
```
/task-coding-pipeline Add rate limiting to the POST /checkout endpoint.
  Max 5 requests per minute per user. Return 429 with Retry-After header.
```

---

#### `/bug-fix [description]`

**Use when:** something is broken — wrong behavior, crash, regression, or a test that fails.

**What happens:** Sam (Bug Investigator) explores the codebase, finds root cause, and writes a RED failing test — bug fixes are the one place a test comes first, because the RED proves the root cause was found rather than guessed. Amelia makes it GREEN with the minimum fix (and may add regression tests — never weakening Sam's RED test). Quinn verifies all gates still pass. Reviewer scores the fix. Maximum 3 fix iterations before escalation.

**Example:**
```
/bug-fix Cart total shows wrong amount when a percentage discount is applied
  after a fixed-amount discount. Expected: discounts stack correctly.
  Actual: second discount applies to original price, not discounted price.
```

---

#### `/analysis <task>`

**Use when:** exploring requirements — you want a product brief and PRD before committing to any architecture or implementation.

**What happens:** Mary writes a product brief, John writes a PRD with ACs and security requirements. No architecture, no code. Stops there — you decide what to do next.

**Example:**
```
/analysis We need a notification service that sends email and push
  notifications based on user preferences and event types.
```

---

#### `/planning <task>`

**Use when:** you have requirements (or run `/analysis` first) and want an execution plan — architecture + epic/task manifest — but no implementation yet.

**What happens:** Runs Architect (Winston) to produce the delivery file + `api-spec.yaml` (if HTTP endpoints) → **human validates both** → ScrumMaster produces the epic or task manifest. Stops before any code. Use `/grill-me` on the spec before approving.

**Example:**
```
/planning  (after running /analysis)
```
or:
```
/planning Design the architecture for a payments webhook handler.
  It receives Stripe events, verifies signatures, and enqueues processing jobs.
```

---

#### `/architecture <domain>`

**Use when:** you want a standalone architecture design for a domain or component, not tied to an active pipeline run.

**What happens:** Winston produces a full delivery file (`docs/deliveries/delivery-{slug}-{key}.md`) — threat model, component design, data flow, API contracts, Test Case Specification, Mermaid diagrams, ADRs. No story decomposition, no implementation.

**Example:**
```
/architecture Design the authentication subsystem — JWT issuance, refresh
  rotation, session invalidation, and per-device token management.
```

---

### Engineering quality skills

#### `/code-review-gate` ← mandatory after any non-pipeline code change

**Use when:** you wrote or modified code outside a pipeline (inline spec-first session, direct edit, ad-hoc fix). This is a hard rule — never push without running this first.

**What happens:** Detects changed files → runs all quality gates for your stack (format, lint, types, coverage, race, vuln, spec) → loads Reviewer on changed files only → issues APPROVED / BLOCK / APPROVE WITH CHANGES.

**Example:**
```
/code-review-gate
```
*(no arguments — detects changed files automatically)*

---

#### `/quality-gate`

**Use when:** you want to run all quality gates for the current stack without the Reviewer step — CI check, pre-push sanity, or after a dependency update.

**What happens:** Detects stack (go.mod / package.json / Cargo.toml / etc.) → runs format + lint + types + coverage + race + vuln + spec gates → reports PASS/FAIL per gate.

**Example:**
```
/quality-gate
```

---

#### `/security-review`

**Use when:** auditing a feature or service for security issues — before shipping, after adding auth, or when touching any I/O boundary.

**What happens:** Full OWASP Web Top 10 (2025) audit + OWASP LLM Top 10 2025 (for AI workloads) across all code in scope. Each finding has severity (CRITICAL/MAJOR/MINOR), file + line, and a concrete fix.

**Example:**
```
/security-review Audit the user authentication flow — login, token issuance,
  refresh, logout, and password reset endpoints.
```

---

#### `/database-migration`

**Use when:** making any schema change — adding columns, creating tables, dropping indexes.

**What happens:** Writes an additive-only migration (never destructive in a single step). Generates the migration file with up/down, ensures backward compatibility with running app, adds index concurrently for large tables, validates the migration is rollback-safe.

**Example:**
```
/database-migration Add a discount_code_id nullable foreign key to the orders
  table referencing discount_codes(id). PostgreSQL, using golang-migrate.
```

---

#### `/observability`

**Use when:** adding structured logging, metrics, or distributed tracing to a service or feature.

**What happens:** Instruments the code with structured JSON logging (zap / pino / SLF4J), adds OpenTelemetry spans and attributes at service boundaries, wires metrics counters and histograms. Follows the no-PII-in-logs rule throughout.

**Example:**
```
/observability Add tracing and structured logging to the checkout service —
  span per external call, log errors with request_id, metric for checkout
  success/failure rate.
```

---

#### `/performance-profiling`

**Use when:** a service is slow, latency is high, or you need to find the bottleneck before optimizing.

**What happens:** For Go: runs `pprof` CPU + memory profile, interprets the flamegraph, identifies the hot path, proposes targeted fixes. For other stacks: applies language-appropriate profiling workflow. Never optimizes without data.

**Example:**
```
/performance-profiling The product search endpoint is slow under load —
  p99 latency is 800ms, target is 200ms. Go service with PostgreSQL.
```

---

#### `/release-management`

**Use when:** cutting a release — version bump, changelog, tag, GitHub release.

**What happens:** Reads git log since last tag → determines semver bump (major/minor/patch) → updates version file → generates CHANGELOG entry → commits → creates annotated tag → creates GitHub release with notes.

**Example:**
```
/release-management Cut a minor release — we added the cart discount feature
  and fixed the total calculation bug.
```

---

### Developer tools

#### `/grill-me [plan or design]`

**Use when:** you have a plan, architecture, or API design and want it stress-tested before committing. Use it during `/planning` Phase 2 before approving the spec.

**What happens:** Acts as an adversarial reviewer — pokes holes in assumptions, finds missing error cases, identifies scaling risks, surfaces security gaps, challenges tech choices. Returns a prioritized list of concerns with suggested resolutions.

**Example:**
```
/grill-me Here's our API spec for the checkout flow — POST /checkout creates
  an order, charges the card, sends a confirmation email, and decrements
  inventory. All in one request. Does this design hold up?
```

---

#### `/improve-codebase-architecture`

**Use when:** you want a health check on the codebase — coupling, boundary violations, over-large files, domain logic leaking into transport layers.

**What happens:** Explores the full codebase, builds a dependency map, identifies Critical/High/Medium/Low findings (domain leakage, circular imports, 3+ callers duplicating logic, files >500 lines, etc.), writes an HTML report to `/tmp/arch-report-{date}.html`.

**Example:**
```
/improve-codebase-architecture
```
or with focus area:
```
/improve-codebase-architecture Focus on the payment and order domains —
  we've been moving fast and suspect boundary violations.
```

---

#### `/business-analysis <domain>`

**Use when:** you need to map the business rules and constraints for a domain before designing or refactoring it. Answers "what does the business actually require here?"

**What happens:** Explores code, comments, tests, and any available docs. Produces a structured map: entities, rules, constraints, invariants, edge cases, and open questions.

**Example:**
```
/business-analysis Map the discount and pricing rules for the cart —
  what combinations are allowed, how stacking works, what the current
  invariants are.
```

---

#### `/technical-analysis <domain>`

**Use when:** you need to map the HTTP contracts, interface boundaries, and integration points for a domain — before refactoring, before writing a spec, or when onboarding.

**What happens:** Reads handlers, routes, request/response types, middleware, and external calls. Produces a contract map: endpoints, request/response schemas, auth requirements, downstream dependencies.

**Example:**
```
/technical-analysis Map all HTTP endpoints and external integrations
  in the order service — what it exposes and what it calls.
```

---

#### `/rote [intent]`

**Use when:** you want to run an existing integration flow (list open PRs, fetch Linear tickets, get calendar events) via an installed adapter.

**What happens:** Phase 0 always runs first — lists installed adapters and all crystallized flows. If a matching flow exists, replays it. If not, discovers the right adapter tool and invokes it. After any new adapter call, crystallizes it as a reusable CLI flow automatically.

**Example:**
```
/rote list my open Linear tickets assigned to me
```
```
/rote show all open PRs in this repo
```

---

#### `/rote-adapter [target]`

**Use when:** connecting to an API or service for the first time — building a brand-new integration.

**What happens:** Runs an 8-phase autonomous process: discover the API spec in the catalog → analyze spec structure → research auth scheme → scope what tools to expose → create the adapter → verify it works. At the end you have a working adapter and a crystallized flow.

**Example:**
```
/rote-adapter Connect to the Datadog API so I can query metrics and create monitors
```
```
/rote-adapter Build an integration with our internal inventory service at https://inventory.internal/openapi.json
```

---

#### `/handoff`

**Use when:** ending a session and wanting to preserve context for the next one — what was done, what's pending, decisions made, open questions.

**What happens:** Compacts the session into a structured handoff document: summary of changes, current state, pending tasks, open decisions, and what to do next. Saves it to a file.

**Example:**
```
/handoff
```
*(run at end of session — no arguments needed)*

---

#### `/write-a-skill [name]`

**Use when:** adding a new slash command to the devkit.

**What happens:** Scaffolds the skill file with correct frontmatter, phase structure, input/output/boundary definitions, and mirrors it to `~/.claude/skills/`. Follows the same structure as existing skills. Before declaring the skill done, it runs the new skill through [SkillSpec](https://github.com/modiqo/skillspec) `doctor` and adapts the `SKILL.md` for any actionable finding (frontmatter, implicit dependencies, dense activation body, late obligations).

**Example:**
```
/write-a-skill dependency-update — a skill that checks for outdated
  dependencies, runs security audit, and updates safely with test verification
```

---

### PR workflow

#### `/pr-review [PR# or URL]`

**Use when:** reviewing a pull request — your own before merge, or a teammate's.

**What happens:** Fetches the PR diff, runs a structured code review (security, correctness, performance, reliability, maintainability), posts findings as PR comments via `gh`, and optionally requests changes or approves.

**Example:**
```
/pr-review 142
```
```
/pr-review   (reviews the PR for current branch automatically)
```

---

#### `/checkcomments`

**Use when:** checking what comments are open on your current branch's PR — read-only, no changes.

**What happens:** Lists all open PR review comments for the current branch, grouped by file and severity. Read-only — does not post or resolve anything.

**Example:**
```
/checkcomments
```

---

> Claude routes to the correct skill automatically when your message matches a trigger phrase. You can also invoke any skill explicitly by name. See `CLAUDE.md` for the full routing table.

---

## Engineering Standards

`CLAUDE.md` is injected into every Claude Code session and enforces:

### Go
- Authority: Uber Go Style → Ardan Labs/service → JetBrains Go Modern → Effective Go
- **Zero error discards** — `_ =` or `_ :=` on errors is a hard block
- Wrap all errors: `fmt.Errorf("doing X: %w", err)` — never bare `return err`
- `swaggo/swag` annotations required on every HTTP handler

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

For any feature with HTTP endpoints, the pipeline enforces a spec-first workflow:

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
| Spec lint | `spectral lint` | `spectral lint` | — | — | — |

### Security
- OWASP Web Top 10 (2025) enforced at Reviewer + Verdict stages
- OWASP LLM Top 10 2025 (v2.0) enforced for AI/GenAI workloads
- `.env` / `.envrc` reads blocked at Claude Code hook level
- Never log PII, secrets, tokens, or card data

---

## Claude Code Hooks

| Hook | Trigger | Behaviour |
|------|---------|-----------|
| `session-bootstrap.sh` | SessionStart | Harness memory — prints `PROGRESS.md` so a new session resumes with done/failed/current state |
| `env-guard.sh` | PreToolUse → Read/Bash/Grep/Glob | Blocks reads of `.env`, `.envrc`, `.env.*` — hard exit, including `cat`/`grep` via Bash |
| `pr-review-responder.sh` | PostToolUse → Bash | After `git push`: surfaces PR comments; Claude fixes valid issues and replies |
| RTK hook | PreToolUse → Bash | Every Bash command routed through RTK for compact output |
| Caveman activate | SessionStart | Loads compressed mode; persists across turns |
| Caveman tracker | UserPromptSubmit | Prevents caveman mode from drifting off mid-session |

---

## Git Hooks

| Hook | Runs | Checks |
|------|------|--------|
| `pre-commit` | Every commit (fast, < 5s) | Go: `gofmt` + `go vet` + `golangci-lint --fast` · TS: `tsc --noEmit` + `eslint` |
| `pre-push` | Before push (full gates) | Go: `go test -race` + coverage ≥ 85% + `govulncheck` · TS: `jest --coverage` + `npm audit` |
| `commit-msg` | Every commit | Conventional Commits: `type(scope): description` |

Valid types: `feat` · `fix` · `docs` · `style` · `refactor` · `perf` · `test` · `chore` · `build` · `ci` · `revert`

---

## Required Tools

### Core (devkit needs these)
| Tool | Install | Used by |
|------|---------|---------|
| `gh` (GitHub CLI) | `brew install gh` / `apt install gh` | PR review hook, release management |
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
