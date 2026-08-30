# Go — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **Go**.
Do not pre-load; do not load a language the story does not name.

> **Test rule**: implement to the story's frozen Test Case table, then write exactly the tests it
> specifies, then falsify each one (apply the row's break, confirm the assertion fails, restore).
> Amelia owns both test and implementation files; Quinn (QA) audits the tests but authors none.
> Coverage thresholds below are a floor, not a target — a tautological or unfalsified test is a
> blocking defect no matter what the percentage says.

> **context7 rule**: before applying any rule that references a specific library, linter, annotation
> tool, or framework — fetch its current docs via context7. Rules here reflect known-good patterns;
> library APIs evolve. Verify import paths, method signatures, and config keys against live docs.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
`fmt.Errorf("ctx: %w", err)` — no bare `return err`; `context.Context` first param; interfaces in consumer package; no `panic` in library code; `crypto/rand` not `math/rand`; parameterized queries; `ReadTimeout`/`WriteTimeout` on `http.Server`; `defer` for cleanup; every HTTP handler must have complete `swaggo/swag` annotations (`@Summary`, `@Description`, `@Tags`, `@Accept`, `@Produce`, `@Param`, `@Success`, `@Failure`, `@Router`); request/response types must be fully-typed Go structs (no `any`, no `interface{}`); types consumed across packages must be behind an interface in the consumer package; run `swag init ./...` — zero errors before handoff.

## Structure and Idiom *(authority: [Uber Go Style](https://github.com/uber-go/guide/blob/master/style.md) → [ardanlabs/service](https://github.com/ardanlabs/service) → Effective Go)*
| Rule | Requirement |
|------|-------------|
| Error inspection | `errors.Is` / `errors.As` — never string-match an error message |
| Types | Concrete types or generics `[T any]` — never `interface{}` / `any` in a signature |
| Layout | `cmd/` (main only) · `internal/` · `business/` · `foundation/` |
| Dependencies | Stdlib first; then `go.uber.org/zap` · `testify` · `golang.org/x/sync` · `ardanlabs/conf/v3` |
| Package names | Lowercase single word — no `utils` / `helpers` / `common` |
| Zero values | Design types so the zero value is safe and usable without a constructor |
| `init()` | Avoid unless unavoidable; never in a library package |
| Reflection | `reflect` only for serialization libraries, with explicit justification |

## Linting Commands
`go vet ./...` · `staticcheck ./...` · `golangci-lint run` (with `gosec`, `errcheck`, `revive` enabled)

## Review Flags *(required linters: `go vet`, `staticcheck`, `golangci-lint` with `gosec`/`errcheck`)*
| Issue | Severity |
|-------|----------|
| `go vet` violations | MAJOR |
| bare `return err` without `fmt.Errorf("ctx: %w", err)` | MAJOR |
| `math/rand` for security randomness | CRITICAL |
| `http.Server` missing `ReadTimeout`/`WriteTimeout` | MAJOR |
| goroutine without documented owner or cancel mechanism | MAJOR |
| `panic` in library/service code | MAJOR |
| DB rows / response bodies not closed | MAJOR |
| HTTP handler missing `swaggo/swag` annotations | MAJOR |
| Swagger annotation references a type with `any` / `interface{}` field | MAJOR |
| `swag init` fails to compile (broken annotations) | BLOCK |
| New or modified endpoint not reflected in swagger docs (stale) | MAJOR |
| Cross-package request/response type not behind an interface in consumer package | MAJOR |
| `staticcheck` error | MAJOR |
| `golangci-lint` `gosec` finding | MAJOR |
| `errcheck` violation: unchecked error return | MAJOR |
| coverage < 85% | BLOCK (score ≤ 5) |

---
