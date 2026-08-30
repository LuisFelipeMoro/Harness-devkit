# PR Review Checklist

Apply in order: Security → language standards → test quality → general. Fail any CRITICAL immediately.

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

## General

- Commented-out code → LOW
- TODO/FIXME in production paths → LOW
