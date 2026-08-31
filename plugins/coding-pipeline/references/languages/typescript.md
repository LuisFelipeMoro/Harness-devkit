# JavaScript / TypeScript — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **JavaScript / TypeScript**.
Do not pre-load; do not load a language the story does not name.

> **Test rule**: implement to the story's frozen Test Case table, then write exactly the tests it
> specifies, then falsify each one (apply the row's break, confirm the assertion fails, restore).
> Amelia owns both test and implementation files; Quinn (QA) audits the tests but authors none.
> Coverage thresholds below are a floor, not a target — a tautological or unfalsified test is a
> blocking defect no matter what the percentage says.

> **context7 rule**: before applying any rule that references a specific library, linter, annotation
> tool, or framework — fetch its current docs via context7. Rules here reflect known-good patterns;
> library APIs evolve. Verify import paths, method signatures, and config keys against live docs.

> **Frontend rule**: load `../frontend-hardening-reference.md` alongside this file. It carries the
> enforcement-integrity checks — lint-config shadowing, security rules left at `warn`, vacuous tests,
> validator format matrices, ReDoS regex, coverage-config filtering, dead CI files — that catch controls
> which *look* enforced but cannot fail. Rows tagged **[FH]** below are summaries of it; the reference
> has the fix and the gate command for each.

> **Version policy**: target the **current stable release** of the language and its toolchain —
> confirm what that is with context7 before writing, never from memory. When the project pins an
> older version (`engines` in `package.json` / `target` in `tsconfig.json`), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing TypeScript-flavoured code —
> you are a TypeScript specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
`const` > `let`, never `var`; async/await; no `any`; schema-validate inputs (zod/joi/yup); no `eval()`/`innerHTML` with user data; `crypto.randomBytes` not `Math.random()` for secrets; `helmet` for HTTP headers; `httpOnly`+`secure`+`sameSite` on cookies; every HTTP handler must have OpenAPI annotations — `swagger-jsdoc` JSDoc `@swagger` blocks for Express/Fastify, or `@nestjs/swagger` decorators for NestJS; request/response types must be fully typed interfaces/classes (no `any`); run doc generation — must succeed with zero errors before handoff.

## Structure and Idiom *(authority: [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html) → the TypeScript Handbook → `typescript-eslint` **recommended-type-checked**)*
| Rule | Requirement |
|------|-------------|
| Strictness | `strict: true` plus `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`; `any` never, `as` only at a boundary just validated |
| Boundaries | External input arrives as `unknown` and is narrowed by a schema parse — the TS type is *derived from* the schema, never asserted alongside it |
| Types | Discriminated unions over optional-field bags; `satisfies` over a type annotation for literal tables |
| Nullability | One nullish representation per field — `undefined` or `null`, never both in the same shape |
| Errors | A typed union / `Result` return for expected failure; `throw` reserved for programmer error |
| Modules | Named exports only; no default exports; no barrel `index.ts` re-export chains |
| Async | No floating promises (`no-floating-promises`); `await` inside try/catch with the error narrowed before use |
| Immutability | `readonly` on every public shape; `as const` for literal tables |

## Linting Commands
`eslint --max-warnings 0` (with `@typescript-eslint` + `eslint-plugin-security` + `eslint-plugin-regexp`) · `prettier --check`

Every `security/*`, `no-secrets/*`, and `regexp/*` rule must be `"error"` — `warn` is not
enforcement. `--max-warnings 0` is required on every invocation, in `package.json` scripts and
in CI. Staged files are linted pre-commit (`lint-staged`) with the identical command CI runs.

## Review Flags *(required linters: `eslint` with `@typescript-eslint` + `eslint-plugin-security`, `prettier`)*
| Issue | Severity |
|-------|----------|
| `eval()` / `Function()` / `new Function()` with any input | CRITICAL |
| `innerHTML` / `document.write` / `dangerouslySetInnerHTML` with user data | CRITICAL |
| `Math.random()` for security-sensitive values | CRITICAL |
| User-controlled `require()`/`import()` path | CRITICAL |
| `unserialize` equivalent on untrusted data | CRITICAL |
| `any` on public API surface | MAJOR |
| Unhandled `Promise` rejections | MAJOR |
| Prototype pollution: deep merge / `Object.assign` on untrusted nested input | MAJOR |
| `as T` type assertion without runtime validation | MAJOR |
| Missing `httpOnly` + `secure` + `sameSite` on auth cookies | MAJOR |
| No schema validation (zod/joi/yup/class-validator) at HTTP boundary | MAJOR |
| HTTP handler missing OpenAPI annotation | MAJOR |
| `any` type used in request/response schema definition | MAJOR |
| New or modified endpoint not reflected in swagger docs (stale) | MAJOR |
| Swagger doc generation fails | BLOCK |
| Regex applied to user input with overlapping adjacent character classes (ReDoS) **[FH]** | CRITICAL |
| `security/*` · `no-secrets/*` · `regexp/*` rule set to `warn` instead of `error` **[FH]** | MAJOR |
| Lint invoked without `--max-warnings 0` in any script or CI step **[FH]** | MAJOR |
| Two lint-config blocks with overlapping `files` globs declaring the same rule key **[FH]** | MAJOR |
| Test loop with an empty body, or a spy no `expect` ever reads **[FH]** | MAJOR |
| Validator/parser tested only on canonical format — no format-variant or real-caller case **[FH]** | MAJOR |
| `coverageConfigDefaults.exclude` filtered instead of extended **[FH]** | MAJOR |
| CI config file present for a CI system the project does not run **[FH]** | MAJOR |
| No pre-commit lint on staged files, or a pre-commit command weaker than CI's **[FH]** | MINOR |
| `eslint` error with `@typescript-eslint` rules | MAJOR |
| `eslint-plugin-security` finding | MAJOR |
| `prettier --check` fails | MINOR |
| coverage < 85% | BLOCK (score ≤ 5) |

---
