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

> **Version policy**: target the **current stable release** of the language and its toolchain —
> confirm what that is with context7 before writing, never from memory. When the project pins an
> older version (`jvmToolchain` / `compileSdk` in `build.gradle.kts`), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing Kotlin-flavoured code —
> you are a Kotlin specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
No `!!` operator; no `GlobalScope` — use `viewModelScope`/`lifecycleScope`; MVVM or MVI architecture; no logic in Activity/Fragment; JUnit5 + MockK for unit tests; `detekt` + `ktlint` + Android Lint zero warnings; no hardcoded secrets; `EncryptedSharedPreferences` for sensitive data; `build.gradle.kts` only (Kotlin DSL); version catalog (`libs.versions.toml`).

## Structure and Idiom *(authority: [Kotlin Coding Conventions](https://kotlinlang.org/docs/coding-conventions.html) → the [Android Kotlin style guide](https://developer.android.com/kotlin/style-guide) → the *Now in Android* architecture sample)*
| Rule | Requirement |
|------|-------------|
| Nullability | Platform types resolved at the boundary; `!!` is a finding — `requireNotNull(x) { "why" }` states the invariant instead |
| Types | `data class` for state, `sealed interface` for result/UI states — never two booleans encoding three states |
| Coroutines | Structured concurrency: every launch has a lifecycle-owned scope, and `Dispatchers` are injected, never hard-coded |
| Flows | Cold `Flow` in the data layer, `StateFlow` at the ViewModel; collected only in a lifecycle-aware scope |
| Layout | `ui` · `domain` (pure Kotlin, zero Android imports) · `data`; the ViewModel exposes state, never an Android type |
| Immutability | `val` by default; expose `List`, hold `MutableList` privately |
| Compose | State hoisted; composables free of side effects outside `LaunchedEffect`/`DisposableEffect`; `remember` keyed on what it depends on |
| Resources | No hard-coded user-facing strings or dimensions in code |

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
