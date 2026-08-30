# Java — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **Java**.
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
`record`/immutable value objects; Bean Validation (`@NotNull`, `@Size`) on inputs; JPA named params or `PreparedStatement` — no SQL concat; `Optional<T>` for nullable returns; `BCrypt`/`Argon2` for passwords; `@PreAuthorize` for authz; `try-with-resources`; `SecureRandom` not `Random`; every HTTP endpoint must have Springdoc OpenAPI annotations (`@Operation`, `@ApiResponse`, `@Parameter`, `@Tag`); request/response types as `record`/final-field classes (no raw `Object` in schema); verify `swagger-ui` renders at `/swagger-ui.html` without errors.

## Linting Commands
`checkstyle` · `SpotBugs` · `PMD` (all three must pass with zero violations at configured severity)

## Review Flags *(required linters: `checkstyle`, `SpotBugs`, `PMD`)*
| Issue | Severity |
|-------|----------|
| SQL string concatenation (not `PreparedStatement`/JPA) | CRITICAL |
| MD5/SHA1/plain text passwords | CRITICAL |
| `Random` for tokens/nonces | CRITICAL |
| Missing `@PreAuthorize` / security check on protected endpoint | CRITICAL |
| `ObjectInputStream` on untrusted data | CRITICAL |
| `catch (Exception e) {}` without rethrow or meaningful log | MAJOR |
| Missing null check / `Optional<T>` on public API | MAJOR |
| Public mutable fields on domain objects | MAJOR |
| `Closeable` not in `try-with-resources` | MAJOR |
| HTTP endpoint missing Springdoc `@Operation` / `@ApiResponse` annotations | MAJOR |
| Request/response schema uses raw `Object` instead of typed `record`/class | MAJOR |
| New or modified endpoint not reflected in swagger docs (stale) | MAJOR |
| `swagger-ui` fails to render (broken annotations or missing `springdoc` dependency) | BLOCK |
| `SpotBugs` high-severity finding | MAJOR |
| `checkstyle` violation at configured severity | MINOR |
| `PMD` violation (priority ≤ 2) | MAJOR |
| coverage < 85% | BLOCK (score ≤ 5) |

---
