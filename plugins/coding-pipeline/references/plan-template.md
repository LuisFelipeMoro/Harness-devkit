# Plan template

One template for `/planning` (full plan) and `/code` (mini-plan). Path: `docs/plans/{slug}/plan.md`;
`{slug}` is kebab-case, ≤ 5 words. Never leave a section out: write `none` or `n/a — reason`, so a reader
can tell "checked" from "forgot". A **mini-plan** fills the header, Goal, Requirements & ACs, Test Case
table and Tasks; every other section says `n/a — small change` (a Security AC still applies whenever the
change touches I/O, auth or user input).

The plan is reviewed by `plan-reviewer` against the real codebase before the human sees it — write it
to survive a reader who has the repository open and has not seen you write it.

```markdown
# Plan — {feature title}

Status: draft | reviewed | approved · Branch: feat/{slug} · Language: {runtime + version + framework, e.g. Go 1.26} · Tier: Backend | Frontend | Both

## Goal
{One paragraph: what this solves, the user-visible outcome, and why it exists.}

## Requirements & ACs
- AC1 — {observable behaviour, one reading only}
- SEC-1 — {security AC: authn/authz, input validation, secrets, logging}
  (mandatory for any change touching I/O, auth or user input; otherwise `none — no I/O/auth/input surface`)
- NFR-1 — {constraint: latency, throughput, compatibility} (optional)

## Out of scope
- {what this plan deliberately does not do}

## Codebase context
Map: `docs/plans/{slug}/codebase-map.md`

Blast radius: {N} symbols · {M} callers · {K} test files · {wire/schema surfaces}

| Changed symbol | Callers | Second-order risk | Verdict |
|---|---|---|---|
| `pkg.Symbol` (`file:line`) | `file:line`, … | error value / nil-ness / ordering / type width a caller relies on | holds · needs updating · needs a migration |

Non-code callers get rows too — serialized payloads, DB columns, API consumers, generated clients,
dashboards, alert queries. If the radius is larger than the work it belongs to, that is the finding:
split it, or make the change additive (new symbol beside the old, callers migrated separately) and say so.

## Reuse Map
Every component in the Design appears here exactly once, and every row is decided.

| Planned component | Decision | Evidence |
|---|---|---|
| {Component} | `reuse: file:line — symbol` | what it already does that this needs |
| {Component} | `extend: file:line — symbol` | what it does, what this adds, why extending beats forking |
| {Component} | `new` | the closest existing thing (`file:line`) and the specific reason it does not fit |

## Design
{The ten sections of skills/planning/references/sections.md as ### headings, condensed to what this
change needs. The parts below are mandatory whenever they apply.}

### Technology decisions
| Decision | Choice | Version | Rationale | Alternatives rejected |
|---|---|---|---|---|

### Security architecture (mandatory — never skipped)
Threat model: where untrusted data enters · auth/authz enforcement points · sensitive data flows ·
external trust boundaries. Secrets: env / vault / KMS — never in code or committed config.

| # | Risk | Mitigation applied |
|---|---|---|
| A01 | Broken Access Control | |
| A02 | Cryptographic Failures | |
| A03 | Injection | |
| A04 | Insecure Design | |
| A05 | Security Misconfiguration | |
| A06 | Vulnerable Components | |
| A07 | Auth & Session Failures | |
| A08 | Integrity Failures | |
| A09 | Logging Failures | |
| A10 | SSRF | |

AI/LLM components present → add the OWASP LLM Top 10 (2025) matrix. Each row: a mitigation, or `N/A — why`.

### Components
#### {Component}
Reuse: `reuse: | extend: | new` (its Reuse Map row) · Responsibility: one sentence ·
Interface (target-language syntax): `{signatures}` · State · Concurrency model ·
Testable seam: dependencies behind interfaces, I/O injectable, pure logic separable from side effects.

### Data structures
| Type | Field | Field type | Purpose |
|---|---|---|---|
Fully typed — no `any`, untyped `dict` or raw `Object`. The coder implements these verbatim.

### API contracts
| Method | Route / Signature | operationId | Request | Response | Errors |
|---|---|---|---|---|---|
Any HTTP endpoint → `api-spec.yaml` at the project root (OpenAPI 3.1): every endpoint has a camelCase
`operationId`, every 4xx/5xx typed, schemas under `components/schemas`, `required` arrays, `security`
on protected endpoints and `security: []` on public ones; `spectral lint` passes. Detail:
`references/spec-driven-reference.md`.

### Data flow
Mermaid component diagram (always) + sequence diagram (auth, payment, multi-service or async flows),
real component names, showing where validation and auth happen. Must compile.

### Edge cases & error handling
| Scenario | Expected behaviour | Error type / status | Logged? | Retry? |
|---|---|---|---|---|
Never expose stack traces, internal codes or DB details to clients.

### Observability & performance
Signals to instrument (metric · log event · span) · complexity · caching (strategy, owner, TTL,
invalidation trigger) · pagination · remote calls per request (each justified, batched, or removed).

### Decisions (ADRs)
| Decision | Chosen | Rejected alternative — why | Consequences |
|---|---|---|---|

## Existing behaviour (brownfield only)
| Current behaviour | Where (file:symbol) | Depended on by | Disposition |
|---|---|---|---|
Disposition `Preserve` · `Change` · `Drop`. Greenfield → `n/a — no existing callers`.

## Test Case table
| Test Name | Input / Precondition | Expected Observable Result | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|

## Tasks
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|

## Open questions
- {question} — {who decides} — {status / answer}

## Review log
- {date} round {n}: {score}/10 · {findings fixed} · {findings carried to open questions}
```

## Rules for the Test Case table

**This table is the highest-leverage section of the plan.** Tests are written after the implementation,
so this specification — not the coding order — is what guarantees the suite proves anything. One row per
AC, edge case, and non-N/A OWASP mitigation. The coder writes these tests as given and does not invent
or redesign them. Missing a case here means it doesn't get tested — be exhaustive.

- **Test Name**: a literal identifier in the language's test-naming convention (Go
  `Test_CreateOrder_RejectsNegativeQuantity`, Jest `it("rejects negative quantity")`). The coder copies it
  verbatim; `scripts/verify/spec-coverage.sh` matches it by exact string.
- **Expected Observable Result**: a return value, persisted state, HTTP status + body field, rendered
  output, or emitted error. Never "the method is called", never "no exception is thrown" alone. If you
  cannot name one, the component lacks a testable seam — fix the design, not the row.
- **Why It Matters**: one clause naming the requirement the row encodes ("negative quantities would let a
  customer credit their own account"). It stops a test that restates the implementation.
- **Falsified By**: the specific break that must make the test fail — "remove the `qty < 0` guard",
  "return `nil` instead of `ErrNotFound`". The coder performs exactly this break with
  `scripts/verify/break-run.sh`. If no break would fail the test, the row is tautological — rewrite it now.
- Every category the coder overlay requires (unit · integration · concurrency · security · E2E) has at least
  one row; every Edge Cases row and every non-N/A OWASP mitigation has a row — a security control with no
  row is unverifiable and must not ship.
- **Validators get a format matrix**: canonical input · format variants (spaced, hyphenated, surrounding
  whitespace, mixed case) · empty and junk · both off-by-one length boundaries · and the **exact string the
  real caller passes** (`references/frontend-hardening-reference.md` §4).
- **Brownfield**: every `Preserve` row in Existing behaviour becomes a characterization row (Falsified By
  names a break in the *existing* code); every `Change` row gets two rows — old behaviour gone, new holds;
  every `Drop` row names the caller search that found nothing.

## Rules for the Tasks table

One row = one unit `/code` executes (inline, by one coder, or in parallel — the user picks at `/code`).
- **Rows are vertical tracer-bullet slices**: each cuts a narrow but *complete* path through every layer
  of its tier (schema → repository → service → handler → tests, not "all the schemas" then "all the
  handlers"), is verifiable on its own through its Test rows, and is sized to fit one fresh coder context
  window. A full-stack slice is the producer/consumer row pair around the contract (below) — the pair
  together is the complete path.
- **Prefactoring first** — "make the change easy, then make the easy change": a refactor that makes the
  feature a small change is its own row, ahead of the rows it unblocks, which list it in `Depends on`.
- **`Depends on` is the explicit blocking edge**: list every row that must land before this one can start,
  and only those — a row with `—` can start immediately. A missing edge lets two rows race; a spurious one
  serialises rows that could run in parallel.
- **Wide refactors are the exception to vertical slicing.** One mechanical change whose blast radius fans
  across the codebase (rename a column, retype a shared symbol) cannot land as one green slice. Sequence it
  **expand → migrate → contract**: one expand row adds the new form beside the old so nothing breaks; then
  one migrate row per batch of call sites, batches sized by blast radius (per package or directory), each
  depending on the expand and keeping the gates green because the old form still exists; then one contract
  row deleting the old form, depending on every migrate batch. Each batch is its own row.
- **This is what makes parallel `/code` safe**: complete, independently verifiable slices with explicit
  edges are what let rows with no `Depends on` between them and disjoint `Files` run in separate worktrees
  without one breaking another's gates.
- ≤ ~200 lines of production code (400 soft ceiling, 800 hard — split past it); independently testable
  and independently reviewable.
- `Files` lists every file the row touches. It becomes the checkpoint's `--expect` set, and rows with no
  `Depends on` and disjoint `Files` are the ones that may run in parallel.
- `Test rows` names the Test Case rows the task implements; every Test Case row belongs to exactly one task.
- `Language` comes from the header / Technology decisions, never guessed; `Tier` picks the coder overlay
  (`Backend` → `coder-backend`, `Frontend` → `coder-frontend`, `—` → `coder`).
- A full-stack change is split around the `api-spec.yaml` contract: backend producer row first, frontend
  consumer row after it, depending on it.
- Mechanical bulk (generated code, renames, formatting) gets its own row, never mixed with logic.
- Adjacent doc-only rows in one package with a combined diff ≤ 120 lines become one row.
