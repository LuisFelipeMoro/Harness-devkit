# Reference: quality-gate — Gate Commands by Stack

> **Coverage thresholds — single source of truth.** The per-language minimums are defined in `coding-pipeline/references/quality-gate-reference.md` and **only** there: **Go · Java · JS/TS · Rust · React · Next.js · Kotlin ≥ 85% · PHP · Flutter ≥ 80%**. This file mirrors that table for standalone `engineering` plugin use (no `coding-pipeline` dependency) — on conflict, `coding-pipeline`'s copy wins; change it there first, then propagate here.

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
`coding-pipeline/references/frontend-hardening-reference.md`):

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

Spec gates fail = counts as any other gate failure — overall verdict FAIL.

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
