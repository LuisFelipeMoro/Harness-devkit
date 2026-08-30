# Kotlin Android — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **Kotlin Android**.
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
No `!!` operator; no `GlobalScope` — use `viewModelScope`/`lifecycleScope`; MVVM or MVI architecture; no logic in Activity/Fragment; JUnit5 + MockK for unit tests; `detekt` + `ktlint` + Android Lint zero warnings; no hardcoded secrets; `EncryptedSharedPreferences` for sensitive data; `build.gradle.kts` only (Kotlin DSL); version catalog (`libs.versions.toml`).

## Linting Commands
`./gradlew detekt` (zero violations) · `ktlint --reporter plain` (zero) · `./gradlew lint` (zero errors)

## Review Flags *(required linters: `detekt`, `ktlint`, `./gradlew lint`)*
| Issue | Severity |
|-------|----------|
| `GlobalScope` usage — use `viewModelScope`/`lifecycleScope` | CRITICAL |
| Blocking main thread (`runBlocking` on UI thread) | CRITICAL |
| Hardcoded credentials in `strings.xml` or Kotlin source | CRITICAL |
| `!!` operator without documented justification | MAJOR |
| Business logic in Activity/Fragment (should be in ViewModel) | MAJOR |
| Missing `EncryptedSharedPreferences` for sensitive local storage | MAJOR |
| `SharedPreferences` for auth tokens | MAJOR |
| Missing `detekt` passing (zero violations) | MAJOR |
| Groovy DSL in `build.gradle` (use Kotlin DSL `.kts`) | MINOR |
| Missing version catalog (`libs.versions.toml`) | MINOR |
| coverage < 85% | BLOCK (score ≤ 5) |

---
