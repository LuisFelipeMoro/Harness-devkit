# HTML / CSS — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **HTML / CSS**.
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
Semantic HTML — `<section>`, `<article>`, `<nav>`, `<main>`, `<header>`, `<footer>`, `<aside>`; `lang` on `<html>`; `alt` on every `<img>`; `<label>` for every `<input>`; no `style=""` attributes; **Tailwind preferred** — utility classes with `eslint-plugin-tailwindcss` class-order; no arbitrary values without justification; if vanilla CSS: BEM or CSS Modules; CSS custom properties for tokens; no `!important`; max 3 nesting levels; animations only `transform`/`opacity`; mobile-first responsive (`min-width` breakpoints); `stylelint` zero warnings; HTML passes `htmlhint` zero errors.

## Linting Commands
`htmlhint` (zero errors) · `stylelint --config stylelint-config-standard` (zero warnings) · `eslint-plugin-tailwindcss` (if Tailwind present)

## Review Flags *(required linters: `htmlhint`, `stylelint`; `eslint-plugin-tailwindcss` if Tailwind present)*
| Issue | Severity |
|-------|----------|
| Non-semantic HTML (div-soup, missing landmark elements) | MAJOR |
| Missing `alt` on `<img>` element | MAJOR |
| Missing `<label>` for `<input>` element | MAJOR |
| Missing `lang` attribute on `<html>` element | MINOR |
| Inline `style=""` attribute (use utility classes or stylesheet) | MINOR |
| `!important` in CSS without documented justification | MINOR |
| CSS nesting deeper than 3 levels | MINOR |
| Tailwind arbitrary value (e.g. `w-[347px]`) without justification | MINOR |
| Animation on layout-triggering property (use `transform`/`opacity`) | MINOR |
| Fixed-width layout — not responsive (`min-width` breakpoints required) | MAJOR |
| `stylelint` `overrides` block silently replacing a rule declared in a wider block **[FH]** | MAJOR |
| `htmlhint` error | MAJOR |
| `stylelint` warning | MINOR |
