# Rust — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **Rust**.
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
> older version (`rust-version` / `edition` in `Cargo.toml`), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing Rust-flavoured code —
> you are a Rust specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
No `unwrap()` in prod — use `?` or `match`; ownership over clone; `thiserror` for domain errors; every HTTP handler must have `utoipa` annotations (`#[utoipa::path(...)]`); request/response types must derive `#[derive(utoipa::ToSchema)]`; the `#[derive(OpenApi)]` struct must compile and `openapi().to_pretty_json()` must succeed.

## Structure and Idiom *(authority: [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) → The Rust Book → `clippy::pedantic` (opt in, then `allow` individually with a stated reason))*
| Rule | Requirement |
|------|-------------|
| Errors | `thiserror` for library errors, `anyhow` only at the binary edge; `unwrap()`/`expect()` outside tests and `main` is a finding |
| Ownership | Borrow by default. `Clone` is a decision to justify, never the fix for a borrow-checker complaint |
| Types | Newtypes carry domain invariants; `Option`/`Result` in signatures, never a sentinel value |
| Traits | Small traits defined at the consumer; `impl Trait` in argument position; generics over `dyn` unless a boundary needs erasure |
| Unsafe | Forbidden without a `// SAFETY:` comment stating the invariant upheld and why it holds here |
| Concurrency | `Send`/`Sync` bounds stated explicitly; `Arc<Mutex<T>>` only where shared mutation is genuinely required |
| API surface | `#[non_exhaustive]` on public types that may grow; `#[must_use]` on pure returns |
| Modules | `mod.rs`-free layout; `pub(crate)` by default and `pub` deliberately |

## Linting Commands
`cargo clippy -- -D warnings` · `cargo fmt --check` · `cargo audit`

## Review Flags *(required linters: `cargo clippy -- -D warnings`, `cargo fmt --check`, `cargo audit`)*
| Issue | Severity |
|-------|----------|
| `unwrap()` / `expect()` in production code (not tests) | MAJOR |
| `panic!()` in library code | MAJOR |
| `clone()` where ownership transfer is possible | MINOR |
| Missing `thiserror` — plain strings or `Box<dyn Error>` for domain errors | MAJOR |
| HTTP handler missing `#[utoipa::path(...)]` annotation | MAJOR |
| Request/response type missing `#[derive(utoipa::ToSchema)]` | MAJOR |
| `#[derive(OpenApi)]` fails to compile or `openapi().to_pretty_json()` errors | BLOCK |
| New or modified endpoint not reflected in swagger docs (stale) | MAJOR |
| `cargo clippy -- -D warnings` finding | MAJOR |
| `cargo audit` — known CVE in dependency | MAJOR |
| `cargo fmt --check` fails | MINOR |
| coverage < 85% | BLOCK (score ≤ 5) |

---
