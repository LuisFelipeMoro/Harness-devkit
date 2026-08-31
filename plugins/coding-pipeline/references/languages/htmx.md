# HTMX — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **HTMX**.
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
> older version (the pinned htmx script version), **code to the pinned version's idiom** and say so at handoff: an API
> added after that version is a defect here, not an improvement. Libraries are the exception —
> update one when the story needs it and the change is non-breaking; a major-version library bump
> is its own story, never a side effect of this one.

> **Specialist mandate**: for this story you are not a generalist writing htmx-flavoured code —
> you are a htmx specialist. The idiom below, the standard library, and the authority chain named
> in *Structure and Idiom* are the baseline. Code that works but would fail review by this
> language's own community is a defect, and "it compiles" is not the bar.

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
Server returns HTML fragments not JSON; CSRF verified server-side via `HX-Request` header; all server-rendered user content HTML-encoded; strict CSP (no `unsafe-inline`); semantic HTML only — no div-soup; no inline `<script>` or `onclick`; ARIA live regions for dynamic swap targets; Tailwind utility classes if `tailwind.config.*` present.

## Structure and Idiom *(authority: [htmx docs](https://htmx.org/docs/) → *Hypermedia Systems* (Gross · Stepinski · Akşimşek) → the server framework's own template conventions)*
| Rule | Requirement |
|------|-------------|
| Response shape | `hx-` requests return HTML fragments, not JSON; content negotiation is explicit on the server, not guessed |
| Targets | `hx-target` and `hx-swap` stated on every interactive element — never leaning on the default when the intent is specific |
| State | The server holds the state. Shadow state in a JS global is the failure mode this stack exists to avoid |
| Validation | Server-side validation re-renders the fragment with its errors; client-side hints are additive only, never the gate |
| Security | No unescaped user data in an `hx-*` attribute; a CSRF token on every mutating request; `hx-vals` built from server-rendered data only |
| Progressive enhancement | The flow works as a plain form POST with htmx absent, unless the story scopes that out explicitly |
| Events | `hx-trigger` carries explicit modifiers (`changed delay:500ms`) — an un-debounced `input` trigger is a load defect |
| Boosting | `hx-boost` applied at a container with `hx-push-url` chosen deliberately, not inherited by accident |

## Linting Commands
`htmlhint` on rendered templates · `djlint` (or the server framework's template linter) · `eslint` on any accompanying JS with `eslint-plugin-security` · the server language's own linter for the handlers returning the fragments — an htmx feature is half backend, and the fragment endpoints are gated by that stack's file, not this one.

## Review Flags
| Issue | Severity |
|-------|----------|
| Server-rendered user content not HTML-encoded | CRITICAL |
| Missing `HX-Request` header check server-side (CSRF vector) | CRITICAL |
| Inline `<script>` or `onclick` handler (CSP violation) | MAJOR |
| Non-semantic HTML (div-soup, missing landmarks) | MINOR |
| Missing ARIA live region on `hx-swap` target | MINOR |
| `hx-trigger` without debounce/throttle on high-frequency events | MINOR |
| Missing `hx-indicator` on slow server responses | MINOR |
| Playwright spec whose loop body is empty or whose assertion cannot fail **[FH]** | MAJOR |
| CI config file present for a CI system the project does not run **[FH]** | MAJOR |

---
