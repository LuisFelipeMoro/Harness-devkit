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

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
No `unwrap()` in prod — use `?` or `match`; ownership over clone; `thiserror` for domain errors; every HTTP handler must have `utoipa` annotations (`#[utoipa::path(...)]`); request/response types must derive `#[derive(utoipa::ToSchema)]`; the `#[derive(OpenApi)]` struct must compile and `openapi().to_pretty_json()` must succeed.

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
