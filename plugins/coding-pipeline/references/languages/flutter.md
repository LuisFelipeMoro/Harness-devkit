# Flutter — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **Flutter**.
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
> older version (`environment.sdk` in `pubspec.yaml`), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing Flutter / Dart-flavoured code —
> you are a Flutter / Dart specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
Dart 3+ sound null safety — no `!` operator; `const` constructors everywhere possible; no `BuildContext` across async gaps (check `mounted`); Riverpod/BLoC/Provider — document choice; `flutter analyze` zero errors; `dart format --set-exit-if-changed`; no hardcoded secrets; `flutter_secure_storage` for sensitive data; `flutter test` unit + widget; `integration_test` for E2E.

## Structure and Idiom *(authority: [Effective Dart](https://dart.dev/effective-dart) (Style · Documentation · Usage · Design) → Flutter's architecture guidance → `flutter_lints`)*
| Rule | Requirement |
|------|-------------|
| Widgets | `const` constructors wherever the analyzer allows; composition over deep trees; `build` free of I/O and heavy allocation |
| State | One state-management approach per app, chosen in the architecture — not per feature; state lifted out of widgets that only render it |
| Null safety | No `late` without a documented initialisation guarantee; no `!` where a check can narrow |
| Async | Subscriptions cancelled in `dispose`; never `setState` after an `await` without a `mounted` check |
| Layout | Feature-first folders; internals under `lib/src/`, public surface via a single library file |
| Errors | Repositories return typed failures; a `dynamic` catch that hides a programming bug is a defect |
| Immutability | `final` fields on widgets; value equality via `==`/`hashCode` or a codegen package — never by identity |
| Performance | `ListView.builder` over materialising all children; keys on reorderable lists |

## Linting Commands
`flutter analyze` (zero errors/warnings) · `dart format --set-exit-if-changed`

## Review Flags *(required linters: `flutter analyze`, `dart format --set-exit-if-changed`)*
| Issue | Severity |
|-------|----------|
| Hardcoded API keys or secrets in Dart source or assets | CRITICAL |
| `BuildContext` used after `await` without `mounted` check | CRITICAL |
| `flutter_secure_storage` not used for tokens/passwords | MAJOR |
| `!` (null-check operator) without flow-proven justification | MAJOR |
| Expensive computation inside `build()` method | MAJOR |
| Stateful logic in UI layer (should be in ViewModel/BLoC/Provider) | MAJOR |
| Missing `flutter analyze` passing (zero errors/warnings) | MAJOR |
| Missing `const` on constructors/widgets that could be const | MINOR |
| Missing `integration_test` for at least one user-facing flow | MINOR |
| coverage < 80% | BLOCK (score ≤ 5) |

---
