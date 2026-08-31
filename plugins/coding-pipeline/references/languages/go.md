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

> **Version policy**: target the **current stable release** of the language and its toolchain —
> confirm what that is with context7 before writing, never from memory. When the project pins an
> older version (the `go` directive in `go.mod`), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing Go-flavoured code —
> you are a Go specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

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

## Concurrency *(the defect class Go makes easy to write and hard to see)*
| Rule | Requirement |
|------|-------------|
| Ownership | Every goroutine has a named owner and a way to stop: a `context.Context`, a closed channel, or a `sync.WaitGroup` the owner waits on. A `go` statement whose lifetime nobody controls is a leak |
| Context | `ctx` is the first parameter, threaded to every blocking call and every outbound request; never stored in a struct, never `context.Background()` below `main`/test |
| Cancellation | Honour `ctx.Done()` in any loop that can run long; `select` on it alongside the work channel |
| Groups | `errgroup.WithContext` for fan-out — first error cancels the rest; a bare `WaitGroup` with a shared `err` variable is a data race |
| Channels | Direction in the signature (`<-chan T`, `chan<- T`); the sender closes, never the receiver; a nil channel in a `select` is a deliberate disable, not an accident |
| Mutexes | `sync.Mutex` by value in the struct it guards, never embedded (it publishes `Lock` on the type); the guarded fields sit directly under it with a comment naming what it protects |
| Unbounded work | A goroutine per request is a capacity decision — bound it with a worker pool or a semaphore before it is a production incident |
| Leak detection | `goleak.VerifyTestMain` in packages that spawn goroutines; a leak that only shows under load is a leak nobody debugs |

## Security *(Go-specific — the general OWASP list is in `reviewer.md`)*
| Risk | Requirement |
|------|-------------|
| Randomness | `crypto/rand` for anything a user must not predict — tokens, ids, salts, nonces. `math/rand` even seeded is CRITICAL |
| Secret comparison | `crypto/subtle.ConstantTimeCompare` for tokens, HMACs and signatures — `==` on a secret leaks its prefix through timing |
| HTML output | `html/template`, never `text/template`, for anything reaching a browser; `template.HTML` on user data defeats the escaping and needs a stated justification |
| Server timeouts | `ReadTimeout`, `ReadHeaderTimeout`, `WriteTimeout`, `IdleTimeout` all set. A missing `ReadHeaderTimeout` is Slowloris (gosec G112) |
| Request size | `http.MaxBytesReader` on every body; `io.ReadAll` on an unbounded reader is a memory-exhaustion DoS |
| JSON | `Decoder.DisallowUnknownFields()` on external input; decode into a typed struct, never `map[string]any` that is then indexed by user-supplied keys |
| Path handling | `filepath.Clean` **and** a check that the result is still under the intended root — `Clean` alone does not stop `../` escaping |
| Archives | Zip/tar entries validated for path escape and decompressed size before writing (zip slip, decompression bomb) |
| Outbound / SSRF | A dedicated `http.Client` with a timeout and a `DialContext` that refuses private and link-local ranges; never `http.DefaultClient` for a user-supplied URL |
| Redirects | `CheckRedirect` bounded; do not let a redirect chain re-enter an internal address |
| TLS | `tls.Config{MinVersion: tls.VersionTLS12}`; `InsecureSkipVerify` is CRITICAL outside an explicitly named test |
| Shell | `exec.Command(bin, args...)` with a fixed binary — never `sh -c` with interpolation, never a user-controlled binary path |
| SQL | `database/sql` placeholders or `sqlc`; an identifier that must be dynamic comes from an allowlist, never from the request |
| Integer conversion | Bounds-check before narrowing (`int64`→`int32`, any→`uint`) — silent wrap is gosec G115 and a classic auth bypass |
| Passwords | `bcrypt` cost ≥ 12 or `argon2id`; never a bare SHA family hash |
| JWT | Algorithm asserted against an allowlist before parsing; `alg: none` and algorithm confusion are auth bypasses, not edge cases |
| File permissions | `0600` for secrets, `0644` for data, `0700`/`0755` for directories; never `0777` |
| Errors | Internal errors never returned to the client verbatim — log with `request_id`, return a generic message and a correct status |

## Performance and Allocation
| Rule | Requirement |
|------|-------------|
| Preallocation | `make([]T, 0, n)` and `make(map[K]V, n)` when `n` is known — repeated growth is the most common avoidable allocation |
| Strings | `strings.Builder` for concatenation in a loop; `+=` on a string in a loop is O(n²) |
| Receivers | Consistent per type; pointer receivers when the type has a mutex, is large, or any method mutates — never mixed on one type |
| Defer | Not inside a hot loop — it accumulates until return; scope it with an inner function or call cleanup explicitly |
| Interfaces | Accept interfaces, return concrete types; an interface return forces an allocation and hides the real type from the caller |
| Copies | Range by index (or `for i := range`) when the element is large; `for _, v := range` copies every element |
| Measurement | A performance claim without a `testing.B` benchmark or a pprof profile is an opinion (see `/performance-profiling`) |

## Testing Idiom
| Rule | Requirement |
|------|-------------|
| Shape | Table-driven with named cases; the case name is what a failure prints, so it names the behaviour, not `case 3` |
| Isolation | `t.Parallel()` in leaf tests, with the loop variable captured; `t.Cleanup` over `defer` for teardown |
| Helpers | `t.Helper()` in every assertion helper so the failure points at the caller's line |
| HTTP | `httptest.Server` / `httptest.NewRecorder` — never a real network call in a unit test |
| Golden files | Regenerated behind a `-update` flag, and reviewed as part of the diff — a golden file nobody read is a snapshot of a bug |
| Fuzzing | `func FuzzX` for any parser, decoder, or input-validation boundary |
| Race | `-race` on every package, every run — a race that only CI catches is a race that already shipped |

## Module and Build Hygiene
`go mod tidy` clean before handoff · dependencies pinned in `go.sum` (committed) · `-trimpath` on release builds · build tags for integration tests (`//go:build integration`) so the default `go test ./...` stays fast and hermetic · `//go:embed` over runtime file reads for static assets · `internal/` for anything not deliberately public — an exported symbol outside `internal/` is a compatibility promise.

## Observability
`log/slog` (or `go.uber.org/zap`) structured, ERROR level in production paths · `request_id`/`trace_id` pulled from `ctx` on every error log · never log a token, password, PII, or full request body · OpenTelemetry spans across service boundaries with the context propagated, not reconstructed.

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
| goroutine with no owner, no `ctx`, and no stop mechanism | MAJOR |
| `context.Background()` below `main`/test, or `ctx` stored in a struct | MAJOR |
| Blocking loop that never selects on `ctx.Done()` | MAJOR |
| `sync.Mutex` embedded in an exported struct (publishes `Lock`) | MINOR |
| Unbounded goroutine-per-request with no pool or semaphore | MAJOR |
| `==` used to compare a token, HMAC, or signature | CRITICAL |
| `text/template` rendering to a browser, or `template.HTML` on user data | CRITICAL |
| `http.Server` missing `ReadHeaderTimeout` (Slowloris) | MAJOR |
| Request body read without `http.MaxBytesReader`, or `io.ReadAll` on an unbounded reader | MAJOR |
| `filepath.Clean` without a containment check against the intended root | CRITICAL |
| Archive extraction without path-escape and size validation | CRITICAL |
| User-supplied URL fetched via `http.DefaultClient` or with no private-range guard | CRITICAL |
| `InsecureSkipVerify: true`, or TLS `MinVersion` unset | CRITICAL |
| `exec.Command` via `sh -c` with interpolated input | CRITICAL |
| Narrowing integer conversion with no bounds check (gosec G115) | MAJOR |
| JWT parsed without asserting the algorithm against an allowlist | CRITICAL |
| Internal error text returned to the client | MAJOR |
| `+=` string building in a loop, or a slice/map grown without a known-capacity `make` | MINOR |
| Mixed pointer and value receivers on one type | MINOR |
| `defer` inside a hot loop | MINOR |
| Test without `t.Parallel()` where nothing prevents it, or an assertion helper missing `t.Helper()` | NIT |
| Parser or decoder boundary with no fuzz target | MINOR |
| Package spawning goroutines with no `goleak` verification | MINOR |
| `go mod tidy` not clean | MINOR |
| coverage < 85% | BLOCK (score ≤ 5) |

---
