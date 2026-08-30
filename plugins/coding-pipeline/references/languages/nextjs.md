# Next.js — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **Next.js**.
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

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
App Router for new projects (Pages Router only for legacy); Server Components by default, `'use client'` only when state/events required; fetch data server-side — never expose server secrets to the client; zod/joi validation in Route Handlers + Server Actions before processing (`next-safe-action` for Server Action type safety); `next/image` for all images (no bare `<img>`); `next/font` for custom fonts (no external font CDN); `NEXT_PUBLIC_*` only for intentionally public values; `next/headers` for cookie/header access in Server Components; CSP via `next.config` headers.

## Linting Commands
`next lint` (eslint-config-next) — zero warnings · `tsc --noEmit` · `next build` (catches SSR/hydration issues `tsc` misses) · tests via Vitest/Jest + `@testing-library/react`, Playwright for E2E

`eslint-config-next` does not carry the security, regexp, or restricted-syntax rules — add
`eslint-plugin-security` and `eslint-plugin-regexp` explicitly, all rules at `"error"`, and
verify the flat-config blocks do not shadow one another
(`references/frontend-hardening-reference.md` §1–§2).

## Review Flags *(required linters: `next lint`, `tsc --noEmit`, `next build`)*
| Issue | Severity |
|-------|----------|
| Server secret referenced in a Client Component | CRITICAL |
| `NEXT_PUBLIC_*` holding a secret value | CRITICAL |
| No zod/joi validation in Route Handler / Server Action | MAJOR |
| `'use client'` on a component with no state/events (needless client bloat) | MINOR |
| Bare `<img>` instead of `next/image` | MINOR |
| External font CDN instead of `next/font` | MINOR |
| `next build` not run before handoff | MAJOR |
| `security/*` or `regexp/*` rules absent from the config, or present at `warn` **[FH]** | MAJOR |
| `coverageConfigDefaults.exclude` filtered in `vitest.config.*` / `jest.config.*` **[FH]** | MAJOR |
| `.github/workflows/` file present when the project deploys through another CI system **[FH]** | MAJOR |
| Client bundle grew without justification — check with `@next/bundle-analyzer` | MINOR |
| coverage < 85% | BLOCK (score ≤ 5) |

---
