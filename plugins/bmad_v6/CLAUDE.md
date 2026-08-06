# Engineering Standards

## Harness Model (Guides · Sensors · Memory · Orchestration)

This devkit is a Harness. Four components, all mandatory:
- **Guides** (feed-forward): this CLAUDE.md, `architecture.md`, specs, conventions — inject the right context per task.
- **Sensors** (feedback): linters in ERROR mode + test runners that return exit 0/1, never prose to interpret. `git-hooks/pre-commit` (format+lint), `git-hooks/pre-push` (tests+coverage+vuln), and CI mirror each other. A task is not done until the sensors pass.
- **Memory & Progress**: `PROGRESS.md` at repo root (`Done` / `Failed` / `Current State` / `Next`) — appended at each checkpoint, read at session start by the SessionStart bootstrap hook. Atomic commits.
- **Orchestration**: an orchestrator spawns isolated subagents with pre-agreed contracts. **Implementer ≠ validator** — Amelia (Coder) builds; Quinn (QA), Reviewer, Stress validate. The acceptance contract (ACs + Definition of Done) is frozen BEFORE any code.

## TDD Discipline (non-negotiable — all code)

Every skill, agent, and pipeline drives code test-first:
- **Red → Green → Refactor**: failing test first, observed to fail for the right reason, minimum code to pass, refactor under green.
- No implementation line before a failing test exists for it. Coverage thresholds are met by tests written first — never back-filled to hit a number.
- **Coder (Amelia) owns tests + implementation; QA (Quinn) audits** the tests (intent-encoding, corner cases, no tautologies/over-mocking) and runs the gates — QA authors no primary tests.
- Plans are stress-tested with `/grill-me` before coding; questions the plan cannot resolve go to the human — never deferred into implementation.

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
| Read-only / quick answers / code execution | `haiku` | Explore, code mapping, "where is X", data fetch, locating callers, Coder (Amelia), Tuner (Tyler), DevOps (IaC/CI), any direct implementation or TDD red→green |

Front-load reasoning into planning and architecture so execution is mechanical: get the plan tight on `opus`/`sonnet` first, then `haiku` just has to follow it. Reserve `opus` for the Architect's design pass. Escalate one tier only with a stated reason.

## Tool Preferences
- **LSP first**: Use LSP (go-to-definition, find-references, diagnostics) for code navigation — grep only when LSP not applicable
- **context7 for docs**: Always fetch current docs via context7 for any library/framework/SDK/API — never rely on training data alone
- **Notifications**: Use PushNotification when waiting >30s on external process, CI, or user input
- **Parallel work**: Use native `git worktree` for parallel feature branches
- **Never read `.env` or `.envrc`**: May contain production secrets — never read, never echo, never log
- **After git push**: Hook surfaces open PR comments automatically — for each: if valid issue (bug/missing test/security hole), fix the code + reply via `gh pr comment` explaining what changed; if not actionable (style preference/opinion/already done), reply explaining why. Never leave PR comments unanswered.

## Pipeline & Skills (always use before acting)

Before writing code, designing architecture, reviewing security, or running quality gates — invoke the matching skill. Never free-form tasks that have a defined skill.

| Task | Skill | Trigger phrases |
|------|-------|-----------------|
| New feature / epic / large task | `/multi-agent-coding-pipeline` | "build", "create", "new feature", "epic", "implement X from scratch", "greenfield", "develop", "stand up a service", "ship a new", "MVP", "build me a" |
| Bug investigation and fix | `/bug-fix` | "bug", "fix", "broken", "not working", "wrong behavior", "unexpected", "crash", "regression", "debug", "fails with", "throws", "stack trace", "flaky", "intermittent", "why does this happen", "stopped working" |
| Single task, small feature | `/task-coding-pipeline` | "small change", "quick task", "add X to existing", "implement this task", "single endpoint", "add a method", "add a field", "one focused task" |
| Architecture design | `/architecture` | "architect", "design the system", "how should we structure", "system design", "component design", "data flow", "high-level design", "X or Y for structure" |
| Requirements analysis (no code, no plan) | `/analysis` | "analyze requirements", "assess", "evaluate context", "investigate requirements", "what should we build", "what do we need", "scope this", "discovery", "requirements" |
| Execution plan (no implementation) | `/planning` | "plan", "planning", "make a plan", "create execution plan", "break down into tasks", "roadmap", "how would we approach", "task breakdown", "sequence the work" |
| Security audit | `/security-review` | "security", "audit", "vulnerability", "OWASP", "pen test", "check for issues", "prompt injection", "LLM security", "LLM01", "AI security", "GenAI risk", "is this safe", "threat model", "CVE", "auth bypass", "injection" |
| Quality gates / CI check | `/quality-gate` | "quality gate", "run gates", "CI check", "lint", "coverage", "run tests", "is it green", "does it pass", "type check", "vet", "format check" |
| PR review or post-push comments | `/pr-review` | "review PR", "check PR", "PR comments", "code review", "review this diff", "address review comments", "look at the pull request" |
| Business rules mapping | `/business-analysis` | "business rules", "business logic", "domain rules", "what does the business require", "validation rules", "domain model", "use cases" |
| Technical contract mapping | `/technical-analysis` | "technical contract", "interface design", "API contract", "map the interfaces", "routes", "endpoints", "infrastructure overview", "what calls what" |
| Cut a release | `/release-management` | "release", "cut a release", "ship", "version", "tag", "changelog", "bump version", "semver", "publish", "release notes" |
| Write a DB migration | `/database-migration` | "migration", "db migration", "schema change", "add column", "alter table", "drop column", "rename column", "add index", "backfill", "DDL" |
| Add logging / metrics / tracing | `/observability` | "logging", "metrics", "tracing", "observability", "add logs", "instrument", "spans", "OpenTelemetry", "structured logs", "monitoring" |
| Performance investigation | `/performance-profiling` | "performance", "slow", "profiling", "optimize", "latency", "throughput", "memory leak", "high CPU", "pprof", "benchmark", "bottleneck", "p99" |
| Run existing integration flow | `/rote` | "run my flow", "search flows", "list adapters", "use existing integration", "what flows do I have", "fetch from", "call the API", "list my tickets", "get data from" |
| Create a NEW integration adapter | `/rote-adapter` | "connect to X for the first time", "build adapter", "create integration", "new connector", "add new integration", "integrate with X" |
| Direct code change (test-first) | inline TDD → `/code-review-gate` | direct code ask outside a pipeline — "write this function", "implement this method", "add this helper", "quick implement"; write the failing test first (Red→Green→Refactor), then run `/code-review-gate` |
| Gate + review after any code change | `/code-review-gate` | "gate and review", "pre-push check", "ready to push", "sign off my code", "check before PR", "done coding", "is my code ready", "review my changes" |
| Stress-test a plan/design | `/grill-me` | "grill me", "challenge this", "stress-test", "poke holes", "pick this apart", "interview me about", "find gaps in my plan", "what am I missing", "red team this" |
| Architectural health review | `/improve-codebase-architecture` | "improve architecture", "zoom out", "architectural review", "find coupling", "codebase health", "architectural debt", "tech debt audit", "refactor architecture" |
| End-of-session handoff doc | `/handoff` | "handoff", "wrap up", "end session", "save context", "compact this session", "summarize for next session", "update progress", "done for today" |
| Create a new skill | `/write-a-skill` | "write a skill", "create skill", "add skill", "new skill", "scaffold a skill" |

**Rule**: If the user's message contains any trigger phrase above — or the intent clearly matches a row — invoke the skill first. Do not start writing code or analysis until the skill has been loaded. A task that "feels simple" is not an exception.

**Mandatory gate rule**: After ANY coding task that is NOT inside a pipeline (TDD, ad-hoc code change, direct implementation request), ALWAYS run `/code-review-gate` as the mandatory final step before declaring the task done. Gates without a reviewer are insufficient — logic bugs and OWASP vulnerabilities are invisible to format/lint/coverage checks.

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

> **Per-language standards** (Go · Java · JS/TS · PHP · Rust · React · Next.js · Flutter · HTMX · Kotlin · HTML/CSS) — full coding rules, linting commands, and review flags live in `references/language-rules-reference.md`. Load it on demand when coding that stack; don't inline it here. Coverage thresholds + gate commands: `references/quality-gate-reference.md`.

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
