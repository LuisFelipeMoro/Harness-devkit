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

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
Dart 3+ sound null safety — no `!` operator; `const` constructors everywhere possible; no `BuildContext` across async gaps (check `mounted`); Riverpod/BLoC/Provider — document choice; `flutter analyze` zero errors; `dart format --set-exit-if-changed`; no hardcoded secrets; `flutter_secure_storage` for sensitive data; `flutter test` unit + widget; `integration_test` for E2E.

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
