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

> **Version policy**: target the **current stable release** of the language and its toolchain —
> confirm what that is with context7 before writing, never from memory. When the project pins an
> older version (the browser support target in `browserslist`), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing HTML / CSS-flavoured code —
> you are a HTML / CSS specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
Semantic HTML — `<section>`, `<article>`, `<nav>`, `<main>`, `<header>`, `<footer>`, `<aside>`; `lang` on `<html>`; `alt` on every `<img>`; `<label>` for every `<input>`; no `style=""` attributes; **Tailwind preferred** — utility classes with `eslint-plugin-tailwindcss` class-order; no arbitrary values without justification; if vanilla CSS: BEM or CSS Modules; CSS custom properties for tokens; no `!important`; max 3 nesting levels; animations only `transform`/`opacity`; mobile-first responsive (`min-width` breakpoints); `stylelint` zero warnings; HTML passes `htmlhint` zero errors.

## Structure and Idiom *(authority: the [WHATWG HTML spec](https://html.spec.whatwg.org/) → [WAI-ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/) → MDN + a modern CSS reset)*
| Rule | Requirement |
|------|-------------|
| Semantics | The element that means the thing (`button`, `nav`, `dialog`, `table`). ARIA is a last resort, never a substitute for the right element |
| Focus | A visible focus indicator on every interactive element; logical tab order; focus trapped in a dialog and restored on close |
| Contrast | WCAG 2.2 AA as the floor, verified with a tool — not eyeballed |
| Layout | Grid/flex with logical properties (`inline-size`, `margin-block`); no fixed pixel height on a text container |
| Cascade | `@layer` or one documented methodology; `!important` only with a comment naming what it overrides and why |
| Units | `rem` for type, `ch` for measure, `clamp()` for fluid scales — never `px` for `font-size` |
| Motion | Every animation honours `prefers-reduced-motion` |
| Images | Intrinsic `width`/`height` to reserve space; `alt` written for the purpose, `alt=""` when genuinely decorative |

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
