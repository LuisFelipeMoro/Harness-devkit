# Engineering Standards

## Harness Model (Guides · Sensors · Memory · Orchestration)

This devkit is a Harness. Four components, all mandatory:
- **Guides** (feed-forward): this CLAUDE.md, the delivery file (`docs/deliveries/delivery-{slug}-{key}.md`), specs, conventions — inject the right context per task.
- **Sensors** (feedback): linters in ERROR mode + test runners that return exit 0/1, never prose to interpret. `git-hooks/pre-commit` (format+lint), `git-hooks/pre-push` (tests+coverage+vuln), and CI mirror each other. A task is not done until the sensors pass. Session-level sensors run as hooks (`hooks/hooks.json`) and are deterministic — no model in the loop:

  | Hook | Event | Id (for `DEVKIT_DISABLED_HOOKS`) | Does |
  |---|---|---|---|
  | `env-guard.sh` | PreToolUse | `pre:read:env-guard` | Blocks any read of `.env` / `.envrc` |
  | `destructive-guard.sh` | PreToolUse(Bash) | `pre:bash:destructive-guard` | Blocks force-push, remote branch deletion, `reset --hard` on a mainline, root/home recursive deletes, `curl \| sh`, `chmod 777`, destructive DDL |
  | `secret-write-guard.sh` | PreToolUse(Write/Edit) | `pre:write:secret-guard` | Blocks writing a recognisable live credential into the tree |
  | `session-tracker.sh` | PostToolUse | `post:session-tracker` | Records which source files changed and whether any gate command ran |
  | `delivery-gate.sh` | Stop | `stop:delivery-gate` | Refuses to call a session done when source changed and no test/lint/typecheck ever ran |
  | `pr-review-responder.sh` | PostToolUse(Bash) | — | Surfaces open PR comments after a push |
  | `session-bootstrap.sh` | SessionStart | — | Injects `PROGRESS.md` as resume context |

  Dial them with `DEVKIT_HOOK_PROFILE` — `off`, `standard` (default), or `strict`, which makes `delivery-gate` block once instead of warn — or disable a single hook with `DEVKIT_DISABLED_HOOKS=<hook-id>,<hook-id>`. A guard that cannot parse its input exits 0 — failing open beats blocking every tool call on a payload change.
- **Memory & Progress**: `PROGRESS.md` at repo root (`Done` / `Failed` / `Current State` / `Next` / `Lessons`) — appended at each checkpoint, read at session start by the SessionStart bootstrap hook. Atomic commits.
- **Orchestration**: an orchestrator spawns isolated subagents with pre-agreed contracts. **Implementer ≠ validator** — Amelia (Coder) builds; Quinn (QA), Reviewer, Stress validate. The acceptance contract (ACs + Definition of Done) is frozen BEFORE any code.

## Spec-First Test Discipline (non-negotiable — all code)

Tests are written **after** the implementation, against a test specification frozen **before**
it. The rigour moves from ordering (test-first) to specification tightness and proof of
falsifiability. Four steps, in order, for every change:

1. **Spec** — the Test Case table is frozen before any code. Every row names the test, its
   input/precondition, its expected *observable* result, the AC it proves, and **why it
   matters** (the intent it encodes). Written by the Architect, filtered into the story by
   the Scrum Master. A behaviour with no row does not get built.
2. **Implement** — Coder (Amelia) builds to the frozen spec. No design decisions at code
   time: anything the spec did not decide is flagged, not invented.
3. **Test** — Amelia writes exactly the rows in the table, no more, no fewer. A row she
   cannot write is a spec defect, reported upward — never silently dropped or reshaped.
4. **Falsify** — the evidence step that replaces RED. For every test, break the code path it
   covers (invert the condition, return the zero value, delete the guard), run the test,
   observe it FAIL, then restore. A test that still passes against broken code is worthless
   and must be rewritten before handoff.

Rules:
- **Tautology is the blocking defect, not low coverage.** Asserting a literal you just set,
  asserting only that a mock was called, or mocking the system-under-test away = MAJOR,
  blocks handoff. Coverage stays a hard floor (per-language, see the gate table) but is
  never the goal — a green 85% of tautologies fails the audit.
- **Coder (Amelia) owns tests + implementation; QA (Quinn) audits** — falsification evidence,
  spec-row completeness, intent-encoding, corner cases, no over-mocking — and runs the gates.
  QA authors no primary tests.
- **Bug fixes are the one exception**: a failing reproduction test is written and observed RED
  *before* the fix, because it is what proves the root cause was found rather than guessed.
- Plans are stress-tested with `/grill-me` before coding; questions the plan cannot resolve go
  to the human — never deferred into implementation.

## Sub-agent Discipline

- **1 sub-agent** — default. Good for one focused task (exploration, data fetch, implementation).
- **2 sub-agents** — great. Use for two genuinely independent parallel tasks with no shared state.
- **3 sub-agents** — only when 3 tasks are clearly independent, time-critical, and cannot share context. Justify before spawning.
- **Never spawn 4+** in a single turn.

### Model assignment (match the model to the task — token & cost efficiency)

| Work | Model | Examples |
|------|-------|----------|
| Architecture design | `opus` | Architect — system design, ADRs, tech stack, data-flow decisions the whole plan depends on |
| Planning · reasoning · validation · long sessions | `sonnet` | Analyst, PM, Scrum Master, Bug Investigator (diagnosis), QA audit, Reviewer, Stress, Verdict, pipeline orchestrators |
| Read-only / quick answers / code execution | `haiku` | Explore, code mapping, "where is X", data fetch, locating callers, Coder (Amelia), Tuner (Tyler), DevOps (IaC/CI), any direct implementation against a frozen Test Case table |

Front-load reasoning into planning and architecture so execution is mechanical: get the plan tight on `opus`/`sonnet` first, then `haiku` just has to follow it. Reserve `opus` for the Architect's design pass. Escalate one tier only with a stated reason.

## Tool Preferences
- **LSP first**: Use LSP (go-to-definition, find-references, diagnostics) for code navigation — grep only when LSP not applicable
- **context7 for docs**: Always fetch current docs via context7 for any library/framework/SDK/API — never rely on training data alone
- **Notifications**: Use PushNotification when waiting >30s on external process, CI, or user input
- **Isolation**: every pipeline run is a *delivery* with its own worktree (`.worktrees/dlv-{key}/`) and release branch. Stories run sequentially inside it. The pipeline never commits or merges to `main` — the terminal step is a PR from a `release/*` or `hotfix/*` branch. See `references/delivery-and-worktree.md`
- **Never read `.env` or `.envrc`**: May contain production secrets — never read, never echo, never log
- **After git push**: Hook surfaces open PR comments automatically — for each: if valid issue (bug/missing test/security hole), fix the code + reply via `gh pr comment` explaining what changed; if not actionable (style preference/opinion/already done), reply explaining why. Never leave PR comments unanswered.

## Pipeline & Skills (always use before acting)

Before writing code, designing architecture, reviewing security, or running quality gates — invoke the matching skill. Never free-form tasks that have a defined skill.

| Task | Skill | Trigger phrases |
|------|-------|-----------------|
| New feature / epic / large task | `/multi-agent` | "build", "create", "new feature", "epic", "implement X from scratch", "greenfield", "develop", "stand up a service", "ship a new", "MVP", "build me a" |
| Bug investigation and fix | `/bug-fix` | "bug", "fix", "broken", "not working", "wrong behavior", "unexpected", "crash", "regression", "debug", "fails with", "throws", "stack trace", "flaky", "intermittent", "why does this happen", "stopped working" |
| Single task, small feature | `/task` | "small change", "quick task", "add X to existing", "implement this task", "single endpoint", "add a method", "add a field", "one focused task" |
| Architecture design | `/architecture` | "architect", "design the system", "how should we structure", "system design", "component design", "data flow", "high-level design", "X or Y for structure" |
| Requirements analysis (no code, no plan) | `/analysis` | "analyze requirements", "assess", "evaluate context", "investigate requirements", "what should we build", "what do we need", "scope this", "discovery", "requirements" |
| Execution plan (no implementation) | `/planning` | "plan", "planning", "make a plan", "create execution plan", "break down into tasks", "roadmap", "how would we approach", "task breakdown", "sequence the work" |
| Security audit | `/security-review` | "security", "audit", "vulnerability", "OWASP", "pen test", "check for issues", "prompt injection", "LLM security", "LLM01", "AI security", "GenAI risk", "is this safe", "threat model", "CVE", "auth bypass", "injection" |
| Quality gates / CI check | `/quality-gate` | "quality gate", "run gates", "CI check", "lint", "coverage", "run tests", "is it green", "does it pass", "type check", "vet", "format check" |
| PR review or post-push comments | `/pr-review` | "review PR", "check PR", "PR comments", "code review", "review this diff", "address review comments", "look at the pull request" |
| List open PR comments (read-only) | `/checkcomments` | "check comments", "PR comments", "what comments are open", "show review comments", "any feedback on my PR" |
| Business rules mapping | `/business-analysis` | "business rules", "business logic", "domain rules", "what does the business require", "validation rules", "domain model", "use cases" |
| Technical contract mapping | `/technical-analysis` | "technical contract", "interface design", "API contract", "map the interfaces", "routes", "endpoints", "infrastructure overview", "what calls what" |
| Cut a release | `/release-management` | "release", "cut a release", "ship", "version", "tag", "changelog", "bump version", "semver", "publish", "release notes" |
| Write a DB migration | `/database-migration` | "migration", "db migration", "schema change", "add column", "alter table", "drop column", "rename column", "add index", "backfill", "DDL" |
| Add logging / metrics / tracing | `/observability` | "logging", "metrics", "tracing", "observability", "add logs", "instrument", "spans", "OpenTelemetry", "structured logs", "monitoring" |
| Performance investigation | `/performance-profiling` | "performance", "slow", "profiling", "optimize", "latency", "throughput", "memory leak", "high CPU", "pprof", "benchmark", "bottleneck", "p99" |
| Run existing integration flow | `/rote` | "run my flow", "search flows", "list adapters", "use existing integration", "what flows do I have", "fetch from", "call the API", "list my tickets", "get data from" |
| Create a NEW integration adapter | `/rote-adapter` | "connect to X for the first time", "build adapter", "create integration", "new connector", "add new integration", "integrate with X" |
| Direct code change (spec-first) | inline Spec→Implement→Test→Falsify → `/code-review-gate` | direct code ask outside a pipeline — "write this function", "implement this method", "add this helper", "quick implement"; list the test cases (name · input · expected observable result · why it matters) first, implement, write exactly those tests, falsify each one, then run `/code-review-gate` |
| Gate + review after any code change | `/code-review-gate` | "gate and review", "pre-push check", "ready to push", "sign off my code", "check before PR", "done coding", "is my code ready", "review my changes" |
| Stress-test a plan/design | `/grill-me` | "grill me", "challenge this", "stress-test", "poke holes", "pick this apart", "interview me about", "find gaps in my plan", "what am I missing", "red team this" |
| Architectural health review | `/improve-codebase-architecture` | "improve architecture", "zoom out", "architectural review", "find coupling", "codebase health", "architectural debt", "tech debt audit", "refactor architecture" |
| End-of-session handoff doc | `/handoff` | "handoff", "wrap up", "end session", "save context", "compact this session", "summarize for next session", "update progress", "done for today" |
| Create a new skill | `/write-a-skill` | "write a skill", "create skill", "add skill", "new skill", "scaffold a skill" |

**Rule**: If the user's message contains any trigger phrase above — or the intent clearly matches a row — invoke the skill first. Do not start writing code or analysis until the skill has been loaded. A task that "feels simple" is not an exception.

**Mandatory gate rule**: After ANY coding task that is NOT inside a pipeline (inline spec-first session, ad-hoc code change, direct implementation request), ALWAYS run `/code-review-gate` as the mandatory final step before declaring the task done. Gates without a reviewer are insufficient — logic bugs and OWASP vulnerabilities are invisible to format/lint/coverage checks.

**Agents are loaded by pipeline skills** — never load `agents/*.md` files manually unless a pipeline skill instructs it.

## Coding Discipline (12 rules — non-negotiable)

1. **Think before coding**: State assumptions, ask questions, stop when confused. Never guess.
2. **Simplicity first**: Write the minimum code needed. No speculative abstractions.
3. **Surgical changes**: Modify only necessary code, matching existing style. No drive-by refactors.
4. **Goal-driven execution**: Define clear success criteria before starting. Tasks are verifiable goals.
5. **Read before you write**: Review existing callers, exports, and related code before implementing.
6. **Surface conflicts**: Pick one approach, explain the tradeoff, flag contradictions — never average them.
7. **Match conventions**: Existing codebase conventions beat personal preference. Always.
8. **Checkpoint frequently**: After each phase, state: what's done, what's verified, what remains.
9. **Tests verify intent**: Tests encode the *why* of behavioral requirements, not just the *what*.
10. **Do not guess**: State limitations explicitly if code cannot be tested or verified immediately.
11. **One topic per file**: Split guidelines into focused files — never combine unrelated rules.
12. **Fail loudly**: Surface uncertainty and errors. Never hide them.

## Task Discipline (boundaries required)

Every task — before starting — must define:
- **Input**: What does this task receive? (spec, file, data)
- **Output**: What does this task produce? (file written, text printed, test passing)
- **Boundary**: What does this task NOT do? (explicit out-of-scope)

Tasks that lack defined outputs are not tasks — they are conversations. Convert first, then start.

Use `TaskCreate` to track tasks with >1 step. Mark `in_progress` when starting, `completed` when done.

## Universal
- **SOLID + DRY**: Single responsibility; no duplication. Composition over inheritance.
- **Clean Architecture**: Domain logic isolated from I/O layers. No domain leakage into transport/DB/cache.
- **Security-First**: OWASP Top 10 (web) + OWASP LLM Top 10 2025 (AI/GenAI) as hard baselines. Validate all inputs; encode all outputs. Fail secure. No secrets in source/logs/errors.
- **Comments**: Write the *why* only — never the *what*. Remove commented-out code immediately.
- **Scope**: No premature abstractions (3 cases before extracting). No speculative features (YAGNI).

## Quality Gates (hard requirement — never skip)
| Gate | Go | TypeScript |
|------|-----|------|
| Format | `gofmt` | `prettier --check` |
| Lint | `go vet` + `golangci-lint` (0 errors) | `eslint --max-warnings 0` |
| Types | — | `tsc --noEmit` (`strict: true`) |
| Coverage | ≥85% | ≥85% |
| Race | `go test -race ./...` | — |
| Vuln | `govulncheck ./...` | `npm audit --audit-level high` |
| PR Review | Reviewdog in CI pipeline | Reviewdog in CI pipeline |

> **Per-language standards** (Go · Java · JS/TS · PHP · Rust · React · Next.js · Flutter · HTMX · Kotlin · HTML/CSS) — full coding rules, linting commands, and review flags live one-per-file in `references/languages/<language>.md` (index: `references/language-rules-reference.md`). Load exactly the one file for the stack in play — never the whole set, never inline it here. Coverage thresholds + gate commands: `references/quality-gate-reference.md`.

## Security Defaults (all languages)
1. **Never read `.env` / `.envrc`** — these files may contain production secrets
2. Validate type · length · format · charset on every external input before any processing
3. Parameterized queries only — never string-concatenate SQL or shell commands
4. Logs: structured JSON; `error` level in prod; always include `request_id` + `timestamp`; never log PII/secrets/tokens/card data
5. Idempotency: UUID v4 key for outbound mutations, token refresh, payment calls; store result with TTL
6. Graceful shutdown: SIGTERM → stop accepting → drain in-flight (≤30s) → close in reverse acquisition order

## AI/GenAI Workloads
- **Inference serving**: Prefer [NVIDIA NIM](https://developer.nvidia.com/nim) for production LLM microservice deployment
- **OWASP LLM Top 10** applies as hard gates (see `/security-review` skill)
- Use context7 to verify any NVIDIA/HuggingFace/LangChain/OpenAI SDK API shapes before implementing

Full OWASP LLM Top 10 2025 checklist enforced by `/security-review` skill — invoke it for any AI/GenAI feature.
