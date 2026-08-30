# React — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **React**.
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
Functional components + hooks only; `eslint-plugin-react-hooks` zero violations; `@testing-library/react` for tests (no Enzyme); `eslint-plugin-jsx-a11y` zero warnings; no `dangerouslySetInnerHTML` with user data — sanitize via `DOMPurify`; Tailwind utility classes if `tailwind.config.*` present; `memo`/`useCallback`/`useMemo` only when profiled; `crypto.randomUUID()` not `Math.random()` for IDs.

## Linting Commands
`eslint --max-warnings 0` (with `eslint-plugin-react-hooks`, `eslint-plugin-jsx-a11y`, `eslint-plugin-security`, `eslint-plugin-regexp`, `eslint-plugin-tailwindcss` if Tailwind present) · `prettier --check` · `tsc --noEmit`

The XSS and a11y `no-restricted-syntax` selectors that guard component files are the exact
rules a later overlapping config block silences without warning — see
`references/frontend-hardening-reference.md` §1, and prove they still fire with a lint
integration test rather than assuming.

## Review Flags *(required linters: `eslint-plugin-react-hooks`, `eslint-plugin-jsx-a11y`, `prettier`, `tsc --noEmit`)*
| Issue | Severity |
|-------|----------|
| `dangerouslySetInnerHTML` with user data — no `DOMPurify` | CRITICAL |
| XSS/a11y `no-restricted-syntax` selector silenced by an overlapping config block **[FH]** | CRITICAL |
| Regex on user input with overlapping adjacent character classes (ReDoS) **[FH]** | CRITICAL |
| `eslint-plugin-react-hooks` violations (missing deps, conditional hooks) | MAJOR |
| No lint integration test proving each `no-restricted-syntax` selector category still fires **[FH]** | MAJOR |
| Snapshot or empty-bodied loop standing in for a behavioural assertion **[FH]** | MAJOR |
| State mutation — direct array push or object property assignment | MAJOR |
| Missing error boundary around async/suspense subtrees | MAJOR |
| `Math.random()` for keys or IDs — use `crypto.randomUUID()` | MAJOR |
| Class components in new code | MINOR |
| Missing `eslint-plugin-jsx-a11y` zero-warning requirement | MINOR |
| Non-semantic HTML (`div onClick` instead of `button`) | MINOR |
| `useMemo`/`useCallback`/`memo` added without profiling evidence | MINOR |
| Tailwind arbitrary values (e.g. `w-[347px]`) without justification | MINOR |
| Missing loading/error state for async data | MINOR |
| coverage < 85% | BLOCK (score ≤ 5) |

---
