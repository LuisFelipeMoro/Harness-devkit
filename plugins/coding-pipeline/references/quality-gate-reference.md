> **Numbers live in [`thresholds.md`](thresholds.md)** — coverage floors, duplication limit and
> score gates. This file carries the *commands*; that one carries the *values*.

# Reference: quality gates — Gate Commands by Stack

> **Coverage thresholds — single source of truth.** The per-language minimums are defined here and **only** here: **Go · Java · JS/TS · Rust · React · Next.js · Kotlin ≥ 85% · PHP · Flutter ≥ 80%**. Any other file (qa.md, reviewer.md, verdict.md, git hooks) restates them for local context but defers to this table on conflict. Change a threshold here first, then propagate.

> **RTK**: All commands below use `rtk` prefix. The `rtk hook claude` PreToolUse hook also intercepts every Bash call transparently — so even without an explicit prefix, RTK filters output. Use `rtk proxy <cmd>` when you need raw unfiltered output (debugging, structured parsing). Never prefix RTK meta-commands (`rtk gain`, `rtk discover`, `rtk proxy`) with `rtk` again.

> **Every change runs this mechanical checkpoint** — format, lint, build, existing tests, dup-gate,
> vuln, and (standard/full) coverage/race — whatever its size, with no exceptions. What
> scales is which *agents* get dispatched on top of it (reviewer, qa, stress), never
> these gates.

## Go
| Gate | Command | Pass |
|------|---------|------|
| Vet | `rtk go vet ./...` | Zero output |
| Lint | `rtk golangci-lint run` | Zero errors |
| Race | `rtk go test -race ./...` | No races |
| Vuln | `rtk govulncheck ./...` | No vulnerabilities |
| SQL | `rtk sqlc vet` | Zero *(skip if no sqlc.yaml)* |
| Coverage | `rtk go test -coverprofile=coverage.out -covermode=atomic ./... && go tool cover -func=coverage.out \| tail -1` | ≥ 85% |
| Modernize *(advisory)* | `rtk proxy go fix -diff ./...` | Reported, never fails the gate — needs Go toolchain ≥ 1.26 (`go version`); older toolchain: report `modernize: skipped (toolchain < 1.26)` |
> `modernize` is advisory: a non-zero exit means suggestions exist — or the build failed, which the Vet row owns. Report it as `modernize: ADVISORY {n} files`; it never fails a gate, never caps a score, and `-diff` never rewrites a file.

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

## Duplication *(all stacks — language-agnostic, runs regardless of the detected stack)*

**Threshold — single source of truth: ≤ 3%.** Any other file (reviewer.md, the
pre-push hook, CLAUDE.md) restates it for local context but defers here on conflict.

| Gate | Command | Pass |
|------|---------|------|
| Duplication | `bash ~/.claude/git-hooks/dup-gate.sh --worktree` | ≤ 3% **introduced** — exit 0 pass · 1 block · 2 UNENFORCED. Same flags and attribution as pre-push; `--worktree` includes uncommitted work. Never run raw repo-wide `jscpd`: it counts markdown and pre-existing debt, and disagrees with the hook |

- **Install**: `npm i -g jscpd` (or as a devDependency — the pre-push hook also accepts `node_modules/.bin/jscpd`).
- **Tuning belongs in a committed `.jscpd.json`**, which jscpd reads on its own: extra `ignore` globs, per-format thresholds, a `min-lines` suited to the language. Tuning by loosening the hook's flags is not tuning, it is turning the gate off for everyone.
- **Tool absent = UNENFORCED, not pass.** The pre-push hook WARNs rather than blocking when jscpd is missing (the convention every optional tool here follows — a hook that dies on a fresh machine gets uninstalled, which costs every gate). The Reviewer's hard gate does not have that excuse: an unmeasured duplication figure blocks.
- **Why it is its own gate**: a perfect duplicate lints clean, types clean, and covers clean. No other Sensor in this file can see it, and no reviewer reliably reads two files at once. It surfaces instead as rework, weeks later.

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
| `jscpd` above 3% | Copy-pasted block | Extract to the existing helper the Reuse Map named — never a new abstraction invented to absorb the copies (CD2) |

---

## Bug-Fix Loop Protocol

*Shared by `/code`, `/validate-code` fix rounds and `/bugfix`. Reference this section — do not copy-paste.*

**Trigger**: Any quality gate FAILS, or qa's audit finds a missing/weak test, after `CODER DONE`.

**Rule**: *Inside this loop only*, tests come RED-first — every iteration is fixing a known defect, and the RED is what proves the root cause was found rather than guessed. Everywhere else the work is spec-first (implement to the frozen Test Case table, then write those tests, then falsify each). the coder (Coder) owns BOTH the tests and the implementation; qa (QA) audits and runs gates but authors no tests. No exceptions.

**Loop (max 3 iterations)**:

1. qa emits a structured `QA→CODER BUG REPORT`:
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
2. The BUG REPORT goes to a fresh `coder` dispatch — the coder writes a test reproducing the bug and confirms it RED against the unfixed code (bug fixes are the one place a test comes first — the RED is what proves the root cause was found, not guessed), then fixes implementation to GREEN.
3. the coder emits `CODER DONE — BUGFIX [N]: [one-line description]` (N = iteration number).
4. qa re-runs ALL quality gates from scratch.
5. Repeat until PASS or max iterations reached.

**After 3 failures** — qa escalates:
```
QA ESCALATION: Implementation unresolved after 3 iterations.
[BUG REPORT attached]
Stop and hand the open report to the human (or `/review-code` with FAIL status).
```
The reviewer scores the FAIL-status artifact accordingly.

**Test-gap sub-path** (an AC lacks a real test — caught by qa's audit):

- qa emits `QA→CODER TEST GAP` (the AC + why the existing test is missing/weak).
- the coder rewrites the test so it asserts the row's Expected Observable Result, then falsifies it with the row's Falsified By break (apply, confirm the assertion fails, restore); emits `BUGFIX COMPLETE` with the evidence line.
- qa re-audits and re-runs gates (counts as one bug-fix iteration).

**Coverage failure sub-path** (distinct from bug failures):

If coverage < threshold AND uncovered paths are reachable behaviour with no test:
- qa emits `QA→CODER TEST GAP` citing the missing Test Case row — the coder adds the behaviour if absent, writes the test asserting its observable result, and falsifies it. Tests added only to raise the percentage are rejected by the tautology audit.
- qa re-runs coverage gate.

If coverage < threshold AND uncovered paths are dead code or framework-generated:
- qa emits `QA→CODER COVERAGE REQUEST`:
  ```
  QA→CODER COVERAGE REQUEST
  Coverage: {actual}% vs {target}% target
  Uncovered paths: [list file:line ranges]
  Reason untestable: [dead code / unreachable branch / framework-generated]
  Request: Refactor or remove the untestable code paths
  ```
- the coder refactors implementation to remove or expose the untestable paths.
- qa re-runs coverage (counts as one bug-fix iteration).

---

## Loop Integrity *(applies to every loop above)*

A loop that can edit its own verifier is not a gate, and a loop with no progress condition
burns tokens without converging. Three rules make the iteration count mean something:

**1. Never move the goalpost to reach it.** Within a fix loop, the coder may change implementation
and test *logic*, never the thing doing the judging. The following are BLOCKING defects, not
fixes, and qa fails the iteration outright when the diff contains one:

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

**3. Compact at the boundary, never mid-task.** Long runs lose context to auto-compaction
at arbitrary points, often mid-implementation where the frozen spec is still load-bearing. The
session compacts at task boundaries instead — after a Verdict is printed and its
`PROGRESS.md` entry is appended, which is exactly when the transcript is reconstructible from
artifacts and the in-flight context is worth least. Never compact between a task's dispatch and
its Verdict.


## Agent Handoff Signals

*Standardized output signals for reliable agent-to-agent routing. Every agent output that triggers a routing decision MUST start with one of these exact strings.*

| Signal | Emitted by | Meaning | Next action |
|--------|-----------|---------|-----------------|
| `CODER DONE` | coder | Tests-first cycle complete, ready for QA audit | Dispatch qa |
| `QA→REVIEWER APPROVAL` | qa | Audit passed, all gates green, coverage met | Proceed to `/review-code`; stress as `/validate-code` dispatches it |
| `QA→CODER BUG REPORT` | qa | Gate failed — implementation bug | Dispatch a fresh coder (count iteration) |
| `QA→CODER TEST GAP` | qa | AC lacks a real test, or test is tautological/over-mocked | Dispatch a fresh coder (count iteration) |
| `QA→CODER COVERAGE REQUEST` | qa | Coverage below threshold, implementation refactor needed | Dispatch a fresh coder (count iteration) |
| `QA ESCALATION` | qa | 3 iterations failed | Stop; hand the report to the human |
| `BUGFIX COMPLETE` | coder | Bug fix applied after QA report | qa re-runs gates |
| `COVERAGE REFACTOR COMPLETE` | coder | Untestable code refactored after coverage request | qa re-runs coverage gate |
| `VALIDATE PASSED` | `/validate-code` | Gates + qa + stress + verdict pass | Safe to run `/review-code`, then push / open PR when asked |
