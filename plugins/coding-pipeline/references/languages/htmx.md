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

Gate commands: `../quality-gate-reference.md`. All languages: `../language-rules-reference.md`.

---
## Coding Rules
Server returns HTML fragments not JSON; CSRF verified server-side via `HX-Request` header; all server-rendered user content HTML-encoded; strict CSP (no `unsafe-inline`); semantic HTML only — no div-soup; no inline `<script>` or `onclick`; ARIA live regions for dynamic swap targets; Tailwind utility classes if `tailwind.config.*` present.

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
