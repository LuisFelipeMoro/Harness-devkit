# PR Review Checklist

Apply in order: Security → language standards → test quality → change discipline → general. Fail any CRITICAL immediately.

## Security (OWASP Web Top 10)

**Coverage note**: This review checks A01, A02, A03, A05, A07, A09. Missing: A04 (Insecure Design), A06 (Vulnerable Components), A08 (Software Integrity), A10 (SSRF). For a full 10-point audit run `/security-review`.

| Check | Look for |
|-------|---------|
| A01 Broken Access Control | missing authz checks, IDOR, path traversal |
| A02 Crypto Failures | hardcoded secrets, weak algorithms, HTTP not HTTPS |
| A03 Injection | SQL concat, shell exec with user data, eval() |
| A05 Security Misconfiguration | debug flags in prod, permissive CORS, missing security headers |
| A07 Auth Failures | insecure token storage, no rate limiting on auth endpoints |
| A09 Logging Failures | PII/secrets in logs, missing request_id/trace_id |

## Go Standards (if .go files changed)

- Error discards: `_ =` or `_ :=` on error returns → CRITICAL
- Bare `return err` without `fmt.Errorf` wrap → HIGH
- `panic` outside unrecoverable init → HIGH
- `interface{}` / `any` on public API → MEDIUM
- Missing `context.Context` as first param → MEDIUM
- Missing swaggo annotations on new HTTP handlers → MEDIUM

## TypeScript Standards (if .ts/.tsx files changed)

- `any` on public API or HTTP boundary → HIGH
- No zod/joi validation at HTTP boundary → HIGH
- `Math.random()` for security use → CRITICAL
- `innerHTML` with user data → CRITICAL
- Missing `@swagger`/`@ApiOperation` on new endpoints → MEDIUM

## Test Quality (every behaviour in the diff)

Tests are written after the implementation, so the question is never "is there a test?" but
"would this test fail if the behaviour were wrong?" Read every test asking what break would
turn it red; if you cannot name one, it is a finding.

- Missing tests for new code paths → HIGH
- Test asserts nothing real — tautology, snapshot-only, or asserts a mock was called instead of the result → HIGH
- Test can never fail (system-under-test fully mocked away) → HIGH
- Expected value computed by calling the function under test, or re-derived with the implementation's own logic, instead of being a literal → HIGH
- Test name/description restates the implementation ("calls the repository") rather than the requirement it defends → MEDIUM
- Security control has a test that would still pass with the control deleted → HIGH
- Happy path only — no corner/error/boundary cases for the inputs the change touches → MEDIUM
- An existing test was weakened, deleted, or rewritten to make the change pass → HIGH
- Coverage raised by assertions that execute lines without proving behaviour → MEDIUM
- Coverage regression (check CI checks output) → MEDIUM

## Reuse & Duplication (the PR-level finding no per-file review can make)

A per-file or per-story review never sees the whole delivery at once, so a helper written twice in
two different stories is invisible until here. A perfect duplicate lints clean, types clean, and
covers clean — this is the only place it gets caught before it becomes rework.

Run `jscpd . --threshold 3 --min-lines 8 --reporters console` over the branch and quote the figure.

- RD1 New symbol reimplements one that already exists (cite both `file:line`) → HIGH
- RD2 Near-copy of an existing block, differing only in literals, types, or field names → HIGH
- RD3 Component built new where the delivery file's Reuse Map said `reuse:`/`extend:` → HIGH
- RD4 The same logic appears twice or more **inside this PR** → HIGH
- RD5 A second pattern introduced into a layer that already has one (parallel error handling, DI, validation) → MEDIUM
- RD6 Code copied instead of imported because of a package boundary — name the boundary → MEDIUM
- Duplication above 3% overall → HIGH

Every duplication finding cites **both** locations. One location is a hunch, not a finding.

## Design & Durability (the principal-engineer bar — any language)

The question is: **would a principal engineer own this in three years, after the author has left
and the requirements have moved twice?** Judge the code in its own language's idiom, never by
another language's habits. Priority order — when two conflict, the earlier wins: **correct →
legible → durable → small.**

Every finding must pass the **cost test**: *name the future change it makes harder, or the
concrete way it breaks.* No cost, no finding — that is a preference. Never file what the
formatter or linter already owns.

- PE1 Mixed levels of abstraction in one function — orchestration interleaved with byte-level detail → MEDIUM (HIGH if it hides a branch)
- PE2 Responsibility sprawl — two reasons to change; the test name needs an "and" → HIGH
- PE3 Leaky abstraction — the caller must know the implementation to use it correctly (call ordering, a field set before a method) → HIGH
- PE4 Temporal coupling — `init()` then `start()` then `use()` with nothing enforcing the order → HIGH
- PE5 Boolean or positional parameter deciding behaviour at the call site → MEDIUM
- PE6 Primitive obsession on a domain invariant — validated id, money, or unit passed as a bare string/int → MEDIUM (HIGH for a security or money invariant)
- PE7 Shared mutable state reachable from two paths with no single owner → HIGH
- PE8 Hidden side effect — a name promising a read that writes, logs, mutates an argument, or does I/O → HIGH
- PE9 Error stripped of context — wrapped without what was attempted, so production logs cannot locate it → HIGH
- PE10 Untestable seam — I/O, clock, randomness, or a client constructed inline instead of injected → HIGH
- PE11 Nesting past three levels, or a conditional needing a truth table → MEDIUM
- PE12 Comment explaining *what* (delete) — or a missing *why* where the code is surprising → LOW
- PE13 Invented convention — a pattern in this diff and nowhere else, where an existing one fit → MEDIUM
- PE14 Speculative generality — extension point, knob, hook, or type parameter with exactly one user → MEDIUM

**Overengineering and slop are symmetric findings.** An interface with one implementation, a
factory for one type, or a layer that only forwards costs every future reader a walk through
indirection that buys nothing — file it exactly as readily as a copy-pasted block. Three cases
before extracting; a duplication is an RD finding, not a licence to invent an abstraction the plan
never asked for.

**Rank, don't enumerate.** More than ~5 findings in a category: post the 3 that matter and one
line naming the pattern behind the rest. Twenty LOWs bury the HIGHs, and a review nobody finishes
reading changes nothing.

## Change Discipline (scope of the diff)

> Mirrored from `coding-pipeline/references/change-discipline.md`, which holds the worked
> ❌/✅ examples and is the single source of truth — on conflict, change it there first.

Every changed line must trace to the request. Read the diff with the PR description / linked
issue open and ask of each hunk: *which sentence asked for this?*

- CD1 Changed line not traceable to the request — drive-by refactor, rename, reformat, or "improvement" to adjacent code → MEDIUM
- CD2 Abstraction with a single implementation and a single call site (interface, strategy, factory, config object) → MEDIUM
- CD3 Unrequested surface — feature, endpoint, CLI flag, config knob, or exported symbol nothing calls → HIGH
- CD4 Defensive branch for a state the type system or caller makes unreachable → LOW
- CD5 Pre-existing dead code deleted without being asked → HIGH
- CD6 Orphan left by this diff — import, variable, or function the change itself made unused → MEDIUM
- CD7 Ambiguity in the request silently resolved in code, where two or more readings existed and none was stated → HIGH

If the PR has no description and no linked issue, CD1, CD3, and CD7 cannot be judged: report
that in the summary and skip them. Never infer intent from the diff under review.

## General

- Commented-out code → LOW
- TODO/FIXME in production paths → LOW
