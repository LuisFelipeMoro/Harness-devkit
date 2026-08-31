# PHP — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **PHP**.
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
> older version (`require.php` in `composer.json`), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing PHP-flavoured code —
> you are a PHP specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
`declare(strict_types=1)` in every file; typed properties (PHP 8+); PDO prepared statements — no `$_GET`/`$_POST` in queries; no `eval()`/`exec()`/`shell_exec()` with user data; `password_hash(PASSWORD_BCRYPT)` or `ARGON2ID`; `htmlspecialchars($v, ENT_QUOTES, 'UTF-8')` for output; `realpath()`+`open_basedir` for file paths; `random_bytes()` not `rand()`; every HTTP endpoint must have `zircote/swagger-php` PHP 8 attributes (`#[OA\Get]`/`#[OA\Post]`/etc., `#[OA\Response]`, `#[OA\Parameter]`, `#[OA\RequestBody]`); request/response schemas as typed classes (no `mixed`, no untyped `array`); run `vendor/bin/openapi src/ -o docs/openapi.yaml` — zero errors.

## Structure and Idiom *(authority: [PER Coding Style 2.0](https://www.php-fig.org/per/coding-style/) (supersedes PSR-12) + PSR-1/PSR-4 → Symfony/Laravel framework conventions → PHPStan level 9 idiom)*
| Rule | Requirement |
|------|-------------|
| Types | `declare(strict_types=1)` in every file; typed properties, parameters and returns — never a bare `array` where a shape exists |
| Value objects | Readonly classes and enums for domain values; a validated identifier is never passed as a bare string |
| Errors | A typed exception per failure mode; the `@` suppression operator never; a `Throwable` catch only with a rethrow |
| Layout | PSR-4 autoloading; a `Domain` namespace free of framework imports; controllers thin enough to read in one screen |
| Null | Explicit `?T` unions; null coalescing over `isset` chains |
| Database | Prepared statements or the ORM's binding — interpolating into SQL is never acceptable, including for an identifier |
| Immutability | Readonly promoted constructor properties; `clone with` semantics over setters |
| Collections | Named collection classes, or generics-annotated arrays (`@param list<Foo>`) — never a positional tuple array |

## Linting Commands
`phpstan analyse --level 8` · `phpcs` (PSR-12) · `php-cs-fixer check`

## Review Flags *(required linters: `phpstan` level 8, `phpcs` PSR-12, `php-cs-fixer`)*
| Issue | Severity |
|-------|----------|
| `eval()` / `system()` / `exec()` / `shell_exec()` with user input | CRITICAL |
| SQL string interpolation / concatenation instead of PDO | CRITICAL |
| `unserialize()` on untrusted input | CRITICAL |
| MD5/SHA1/plain passwords | CRITICAL |
| File path without `realpath()` + `open_basedir` check | CRITICAL |
| `rand()` / `mt_rand()` for tokens | CRITICAL |
| Missing `htmlspecialchars($v, ENT_QUOTES, 'UTF-8')` for HTML output | MAJOR |
| PHP errors exposed to client | MAJOR |
| Suppression operator `@` hiding errors | MAJOR |
| Missing `declare(strict_types=1)` | MINOR |
| Missing type declarations on public API (PHP 8+) | MINOR |
| HTTP endpoint missing `zircote/swagger-php` attributes | MAJOR |
| Request/response schema uses `mixed` or untyped `array` | MAJOR |
| New or modified endpoint not reflected in swagger docs (stale) | MAJOR |
| `vendor/bin/openapi` fails to compile | BLOCK |
| `phpstan` error at level 8 | MAJOR |
| `phpcs` PSR-12 violation | MINOR |
| `php-cs-fixer check` fails | MINOR |
| coverage < 80% | BLOCK (score ≤ 5) |

---
