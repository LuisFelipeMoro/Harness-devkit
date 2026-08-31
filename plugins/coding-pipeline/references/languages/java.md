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

> **Version policy**: target the **current stable release** of the language and its toolchain —
> confirm what that is with context7 before writing, never from memory. When the project pins an
> older version (the release target in `pom.xml` / `build.gradle`), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing Java-flavoured code —
> you are a Java specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
`record`/immutable value objects; Bean Validation (`@NotNull`, `@Size`) on inputs; JPA named params or `PreparedStatement` — no SQL concat; `Optional<T>` for nullable returns; `BCrypt`/`Argon2` for passwords; `@PreAuthorize` for authz; `try-with-resources`; `SecureRandom` not `Random`; every HTTP endpoint must have Springdoc OpenAPI annotations (`@Operation`, `@ApiResponse`, `@Parameter`, `@Tag`); request/response types as `record`/final-field classes (no raw `Object` in schema); verify `swagger-ui` renders at `/swagger-ui.html` without errors.

## Structure and Idiom *(authority: [Effective Java, 3e](https://www.oreilly.com/library/view/effective-java-3rd/9780134686097/) → [Google Java Style](https://google.github.io/styleguide/javaguide.html) → the Spring Boot reference for the framework tier)*
| Rule | Requirement |
|------|-------------|
| Types | `record` for value objects; `sealed` hierarchies for closed sets; no raw types and no `Object` in a signature |
| Nullability | `Optional<T>` for an absent *return* only — never a field, never a parameter |
| Errors | A typed exception per failure mode; never `catch (Exception)`; an empty catch is a defect, not a style choice |
| Layout | `domain` (zero framework imports) · `application` · `infrastructure` · `web` — Spring annotations never reach `domain` |
| Immutability | Fields `final` by default; `List.copyOf` over `unmodifiableList`; defensive copies on collection accessors |
| Injection | Constructor injection only — no `@Autowired` fields, no setter injection |
| Streams | Streams to transform, loops to cause effects; a `forEach` that mutates outside state is a loop wearing a costume |
| Equality | `equals`/`hashCode` together or not at all — a `record` gets them right for free, so do not hand-write them |
| Concurrency | `java.util.concurrent` over `synchronized`; virtual threads for blocking I/O where the pinned release supports them |

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
