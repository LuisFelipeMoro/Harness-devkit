# Reference: Language Rules — Coding Standards + Review Flags

Shared reference for Coder (Amelia) and Reviewer. Load on demand. Do not pre-load.

> **Test rule**: Amelia implements to the story's frozen Test Case table, then writes exactly the tests it specifies, then falsifies each one (apply the row's break, confirm the assertion fails, restore). Amelia owns both test and implementation files; Quinn (QA) audits the tests but authors none. Coverage thresholds below are a floor, not a target — a tautological or unfalsified test is a blocking defect no matter what the percentage says.

> **context7 rule**: Before applying any rule that references a specific library, linter, annotation tool, or framework — fetch its current docs via context7. Rules in this file reflect known-good patterns; library APIs evolve and the current version may differ. Always verify import paths, method signatures, and config keys against live docs before writing code.

> **Specialist rule**: whoever loads one of these files is, for that story, a specialist in that
> language — not a generalist transliterating another language's habits into it. Each file names an
> **authority chain** (Go has Uber Go Style; Java has Effective Java; Rust has the API Guidelines;
> and so on) and that chain is the baseline, not a suggestion. Code that runs but that the
> language's own community would reject at review is a defect. Judge a diff in its own idiom: a Go
> `(T, error)` is not a missing exception, a Rust `match` is not a switch that wants polymorphism,
> and a React hook is not a lifecycle method.

> **Version rule**: target the current stable release of the language, confirmed via context7 —
> never from memory. When the project pins an older version, code to *that* version's idiom and say
> so at handoff; an API newer than the pin is a defect here, not an improvement. Libraries are the
> exception: update one when the story needs it and the change is non-breaking, but a major-version
> bump is its own story.

For quality gate commands, see `references/quality-gate-reference.md`.

> **Frontend rule**: when the story's language is JS/TS, React, Next.js, HTMX, or HTML/CSS,
> load `references/frontend-hardening-reference.md` alongside that language's file. It carries the
> enforcement-integrity checks — lint-config shadowing, security rules left at `warn`, vacuous
> tests, validator format matrices, ReDoS regex, coverage-config filtering, dead CI files — that
> catch controls which *look* enforced but cannot fail. The rows tagged **[FH]** in those files
> are summaries of it; the reference has the fix and the gate command for each.

---

## Load one file, not this one

Each language lives in its own file so an agent loads ~30 lines instead of ~340. Load exactly the
row matching the story's `Language` field.

| Language | File |
|---|---|
| Go | [`languages/go.md`](languages/go.md) |
| Java | [`languages/java.md`](languages/java.md) |
| JavaScript / TypeScript | [`languages/typescript.md`](languages/typescript.md) |
| PHP | [`languages/php.md`](languages/php.md) |
| Rust | [`languages/rust.md`](languages/rust.md) |
| React | [`languages/react.md`](languages/react.md) |
| Next.js | [`languages/nextjs.md`](languages/nextjs.md) |
| Flutter | [`languages/flutter.md`](languages/flutter.md) |
| HTMX | [`languages/htmx.md`](languages/htmx.md) |
| Kotlin Android | [`languages/kotlin.md`](languages/kotlin.md) |
| HTML / CSS | [`languages/html-css.md`](languages/html-css.md) |

Every file repeats the test rule, the context7 rule, and (for frontend stacks) the frontend-hardening
rule, so a single-file load is self-sufficient.
