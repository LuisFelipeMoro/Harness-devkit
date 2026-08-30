# Reference: quality-gate — Gate Commands by Stack

> **Coverage thresholds — single source of truth.** The per-language minimums are defined here and **only** here: **Go · Java · JS/TS · Rust · React · Next.js · Kotlin ≥ 85% · PHP · Flutter ≥ 80%**. Any other file (qa.md, reviewer.md, scrum-master DoD, verdict.md, git hooks) restates them for local context but defers to this table on conflict. Change a threshold here first, then propagate.

> **RTK**: All commands below use `rtk` prefix. The `rtk hook claude` PreToolUse hook also intercepts every Bash call transparently — so even without an explicit prefix, RTK filters output. Use `rtk proxy <cmd>` when you need raw unfiltered output (debugging, structured parsing). Never prefix RTK meta-commands (`rtk gain`, `rtk discover`, `rtk proxy`) with `rtk` again.

## Go
| Gate | Command | Pass |
|------|---------|------|
| Vet | `rtk go vet ./...` | Zero output |
| Lint | `rtk golangci-lint run` | Zero errors |
| Race | `rtk go test -race ./...` | No races |
| Vuln | `rtk govulncheck ./...` | No vulnerabilities |
| SQL | `rtk sqlc vet` | Zero *(skip if no sqlc.yaml)* |
| Coverage | `rtk go test -coverprofile=coverage.out -covermode=atomic ./... && go tool cover -func=coverage.out \| tail -1` | ≥ 85% |

## TypeScript / React / Next.js
| Gate | Command | Pass |
|------|---------|------|
| Types | `rtk tsc --noEmit` | Zero errors |
| Lint | `rtk lint` | Zero warnings |
| Format | `rtk prettier --check .` | No changes |
| Build | `rtk next build` *(Next.js)* / `rtk vite build` or `rtk npm run build` *(React SPA — Vite/CRA)* | Zero errors |
| Vuln | `rtk npm audit --audit-level=high` | No high/critical |
| Coverage | `rtk pnpm vitest run --coverage` | ≥ 85% |

> Build is a required gate for every JS/TS project, not just Next.js — `tsc --noEmit` catches type errors but not bundler-specific failures (unresolved imports, case-sensitive path mismatches, SSR/hydration issues). Skip only for a library published as source with no bundle step.

**Enforcement integrity** — run before trusting the Lint gate; a green lint proves nothing if
the rules were silenced. Any hit = FAIL (rationale + fixes:
`references/frontend-hardening-reference.md`):

| Check | Command | Pass |
|-------|---------|------|
| Security severity | `grep -rEn '"(security\|no-secrets\|regexp)/[^"]+"[[:space:]]*:[[:space:]]*"warn"' eslint.config.*` | No match — all at `"error"` |
| Rule shadowing | `grep -c "no-restricted-syntax" eslint.config.*` | If > 1, no two blocks' `files` globs overlap |
| Warning tolerance | `grep -rn "eslint" package.json .github/ .gitlab-ci.yml 2>/dev/null` | Every invocation has `--max-warnings 0` |
| Coverage config | `grep -rn "coverageConfigDefaults.exclude.filter" vitest.config.* jest.config.*` | No match — defaults extended, never filtered |
| Dead CI | `ls .github/workflows/ 2>/dev/null` | Every file present runs on the project's real CI system |

## Rust
| Gate | Command | Pass |
|------|---------|------|
| Lint | `rtk cargo clippy -- -D warnings` | Zero warnings |
| Format | `rtk cargo fmt --check` | No changes |
| Vuln | `rtk cargo audit` | No vulnerabilities |
| Coverage | `rtk cargo tarpaulin --out Xml` | ≥ 85% |

## Java
| Gate | Command | Pass |
|------|---------|------|
| Bugs | `rtk mvn spotbugs:check` / `rtk ./gradlew spotbugsMain` | Zero |
| Style | `rtk mvn checkstyle:check` | Zero |
| Vuln | `rtk mvn dependency-check:check` | No high/critical CVEs |
| Coverage | `rtk mvn verify` / `rtk ./gradlew test jacocoTestReport` | ≥ 85% |

## PHP
| Gate | Command | Pass |
|------|---------|------|
| Static | `rtk vendor/bin/phpstan analyse --level 8` | Zero |
| Style | `rtk vendor/bin/phpcs` | Zero |
| Vuln | `rtk composer audit` | No vulnerabilities |
| Coverage | `rtk vendor/bin/phpunit --coverage-text` | ≥ 80% |

## Spec Validation *(run first — only if `api-spec.yaml` exists in project root)*

| Gate | Command | Pass |
|------|---------|------|
| Spec lint | `rtk npx @stoplight/spectral-cli lint api-spec.yaml --ruleset .spectral.yaml` | Zero errors |
| Spec validate | `rtk npx swagger-cli validate api-spec.yaml` | Valid |
| Go annotations | `rtk swag init ./...` | Zero errors |
| TS annotations | `rtk tsc --noEmit` | Zero errors |
| Java annotations | `rtk mvn compile` | Zero errors |
| Contract test | `rtk schemathesis run api-spec.yaml --url http://localhost:{port} --checks all` | Zero failures *(integration only)* |

Spec gates fail = QA Score capped at 4, same as any other gate failure.

See `references/spec-driven-reference.md` for `.spectral.yaml` template, annotation patterns, and drift detection guide.

---

## Common Fixes

| Gate | Failure | Fix |
|------|---------|-----|
| `golangci-lint` errcheck | Unhandled error | `if err := fn(); err != nil { return fmt.Errorf("ctx: %w", err) }` |
| `go test -race` | Data race | `sync.Mutex` or `sync.Map` |
| `govulncheck` | CVE | `go get module@patched` + `go mod tidy` |
| `tsc --noEmit` | Implicit `any` | Add explicit type annotation |
| `eslint` detect-object-injection | User input in bracket notation | `Object.prototype.hasOwnProperty.call(obj, key)` |
| `cargo clippy` | `unwrap()` in prod | `?` or `match` |
| Coverage below threshold | Untested paths | Table-driven tests for every error path |

---

## Bug-Fix Loop Protocol

*Shared by task, multi-agent, and bug-fix. Reference this section — do not copy-paste.*

**Trigger**: Any quality gate FAILS, or Quinn's audit finds a missing/weak test, after `CODER DONE`.

**Rule**: *Inside this loop only*, tests come RED-first — every iteration is fixing a known defect, and the RED is what proves the root cause was found rather than guessed. Everywhere else the pipeline is spec-first (implement to the frozen Test Case table, then write those tests, then falsify each). Amelia (Coder) owns BOTH the tests and the implementation; Quinn (QA) audits and runs gates but authors no tests. No exceptions.

**Loop (max 3 iterations)**:

1. Quinn emits a structured `QA→CODER BUG REPORT`:
   ```
   QA→CODER BUG REPORT
   File: path/to/file.ext
   Line: [line number]
   Test: [failing test name]
   Expected: [what should happen]
   Actual: [what happens instead]
   Gate: [which gate failed — lint / race / coverage / test]
   Classification: LOGIC | TYPING | CONCURRENCY | SECURITY | PERFORMANCE
   ```
2. Pipeline routes BUG REPORT to Amelia — Amelia writes a test reproducing the bug and confirms it RED against the unfixed code (bug fixes are the one place a test comes first — the RED is what proves the root cause was found, not guessed), then fixes implementation to GREEN.
3. Amelia emits `CODER DONE — BUGFIX [N]: [one-line description]` (N = iteration number).
4. Quinn re-runs ALL quality gates from scratch.
5. Repeat until PASS or max iterations reached.

**After 3 failures** — Quinn escalates:
```
QA ESCALATION: Implementation unresolved after 3 iterations.
[BUG REPORT attached]
Routing to Reviewer with FAIL status.
```
Reviewer receives the FAIL-status artifact and scores accordingly.

**Test-gap sub-path** (an AC lacks a real test — caught by Quinn's audit):

- Quinn emits `QA→CODER TEST GAP` (the AC + why the existing test is missing/weak).
- Amelia rewrites the test so it asserts the row's Expected Observable Result, then falsifies it with the row's Falsified By break (apply, confirm the assertion fails, restore); emits `BUGFIX COMPLETE` with the evidence line.
- Quinn re-audits and re-runs gates (counts as one bug-fix iteration).

**Coverage failure sub-path** (distinct from bug failures):

If coverage < threshold AND uncovered paths are reachable behaviour with no test:
- Quinn emits `QA→CODER TEST GAP` citing the missing Test Case row — Amelia adds the behaviour if absent, writes the test asserting its observable result, and falsifies it. Tests added only to raise the percentage are rejected by the tautology audit.
- Quinn re-runs coverage gate.

If coverage < threshold AND uncovered paths are dead code or framework-generated:
- Quinn emits `QA→CODER COVERAGE REQUEST`:
  ```
  QA→CODER COVERAGE REQUEST
  Coverage: {actual}% vs {target}% target
  Uncovered paths: [list file:line ranges]
  Reason untestable: [dead code / unreachable branch / framework-generated]
  Request: Refactor or remove the untestable code paths
  ```
- Amelia refactors implementation to remove or expose the untestable paths.
- Quinn re-runs coverage (counts as one bug-fix iteration).

---

## Loop Integrity *(applies to every loop above)*

A loop that can edit its own verifier is not a gate, and a loop with no progress condition
burns tokens without converging. Three rules make the iteration count mean something:

**1. Never move the goalpost to reach it.** Within a fix loop, Amelia may change implementation
and test *logic*, never the thing doing the judging. The following are BLOCKING defects, not
fixes, and Quinn fails the iteration outright when the diff contains one:

| Move | Why it is a defect |
|------|--------------------|
| Lowering a coverage threshold, or excluding files from coverage config | The gate now passes because it measures less |
| Adding `skip` / `only` / `t.Skip` / `xit` / `@Disabled` to a failing test | The failure is hidden, not fixed |
| Deleting or weakening an assertion so a test passes | The test stops encoding the requirement |
| Downgrading a lint rule to `warn`, or adding a blanket disable comment | The rule still exists and no longer fails |
| Editing a Test Case row so it matches what the code does | The spec was frozen before the code — this inverts that |
| Broadening a type to `any` / `interface{}` to clear a type error | The type error was the signal |

A genuine spec defect is reported upward as a spec defect and escalated to the human — it is
never resolved by quietly editing the spec at code time.

**2. Progress must be observable each iteration.** Before iteration N+1, compare the failure to
iteration N's. If the failing test, gate, and message are identical, stop the loop immediately
and escalate rather than spending the remaining budget — the same input produced the same output,
so a third attempt is a coin flip, not a fix. Iterations are for converging, not for retrying.

**3. Compact at the boundary, never mid-story.** Long deliveries lose context to auto-compaction
at arbitrary points, often mid-implementation where the frozen spec is still load-bearing. The
orchestrator compacts at story/sub-task boundaries instead — after a Verdict is printed and its
`PROGRESS.md` entry is appended, which is exactly when the transcript is reconstructible from
artifacts and the in-flight context is worth least. Never compact between a story's dispatch and
its Verdict.


## Agent Handoff Signals

*Standardized output signals for reliable agent-to-agent routing. Every agent output that triggers a routing decision MUST start with one of these exact strings.*

| Signal | Emitted by | Meaning | Pipeline action |
|--------|-----------|---------|-----------------|
| `CODER DONE` | Coder (Amelia) | Tests-first cycle complete, ready for QA audit | Route to Quinn |
| `QA→REVIEWER APPROVAL` | QA (Quinn) | Audit passed, all gates green, coverage met | Route to Reviewer (and Stress in parallel) |
| `QA→CODER BUG REPORT` | QA (Quinn) | Gate failed — implementation bug | Route to Amelia (count iteration) |
| `QA→CODER TEST GAP` | QA (Quinn) | AC lacks a real test, or test is tautological/over-mocked | Route to Amelia (count iteration) |
| `QA→CODER COVERAGE REQUEST` | QA (Quinn) | Coverage below threshold, implementation refactor needed | Route to Amelia (count iteration) |
| `QA ESCALATION` | QA (Quinn) | 3 iterations failed | Route to Reviewer with FAIL status |
| `BUGFIX COMPLETE` | Coder (Amelia) | Bug fix applied after QA report | Quinn re-runs gates |
| `COVERAGE REFACTOR COMPLETE` | Coder (Amelia) | Untestable code refactored after coverage request | Quinn re-runs coverage gate |
| `TUNER REQUEST` | Reviewer / StressTester | Score ≥ 7, MINOR/NIT only | Route to Tyler (Tuner) |
| `TUNER COMPLETE` | Tuner (Tyler) | Tuning done, re-score | Reviewer re-scores changed files only |
| `CODE REVIEW GATE PASSED` | code-review-gate skill | Gates + Reviewer both pass | Safe to push / open PR |
