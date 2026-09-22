# Test audit reference — mock patterns + security test cases

Lookup material for `agents/qa.md`. It lived inline, which meant every QA dispatch paid for the
security test table even on a story with no external I/O, and for the mock patterns whether or not
the suite used a mock. Load it when the story's audit actually needs it.

## Mock Patterns *(audit reference — the patterns Amelia's tests must follow)*

> Use context7 to verify current mock/test framework API when auditing tests — mock interfaces, assertion methods, and test runner configuration change across versions.

| Language | Framework | Pattern |
|----------|-----------|---------|
| JS/TS | Jest | `jest.mock('../dep', () => ({ fn: jest.fn() }))` · `jest.useFakeTimers()` · `nock`/`msw` for HTTP |
| Java | JUnit 5 + Mockito | `@ExtendWith(MockitoExtension.class)` · `@Mock` + `@InjectMocks` · `when(...).thenReturn(...)` · `verify(...)` · `@SpringBootTest`+Testcontainers for integration |
| PHP | PHPUnit + Mockery | `Mockery::mock(Interface::class)->shouldReceive('method')->andReturn(val)` · `Mockery::close()` in `tearDown` · `RefreshDatabase` for Laravel integration |
| Go | testify + fake structs | Interface in consumer/test pkg → fake struct impl · `testify/mock` for complex · `//go:build integration` tag |
| Rust | mockall | `#[automock]` on traits · `MockTrait::new()` + `.expect_method()` · `#[cfg(test)]` modules |

## Security Test Cases *(required for epics with external I/O, auth, or user input)*

| Scenario | Input | Expected |
|----------|-------|----------|
| SQL injection | `'; DROP TABLE users; --` | safe error / empty result; no crash; no data leak |
| Command injection | `$(rm -rf /)` | 400 invalid input |
| Missing auth token | *(no Authorization header)* | 401 |
| Expired token | *(expired JWT)* | 401 |
| Wrong role | valid token, insufficient role | 403 |
| IDOR | valid token, other user's resource ID | 403 |
| Oversized input | 10 000-char string field | 400; no truncation bypass |
| Integer overflow | MAX_INT+1 | 400 or clamped; no overflow |
| Null / empty input | null / undefined / "" | 400; no NPE/panic exposed |
| Error response leakage | trigger any error | response must NOT contain stack trace / SQL / internal path |
| Log leakage | auth failure | logs must NOT contain attempted password or token |
| DoS — rapid requests | 100 req/s same IP | 429 after threshold; service stays up |
| DoS — large payload | 1 MB body | 413 or rejection; no OOM |
| React XSS | `dangerouslySetInnerHTML` with unsanitized user input | `DOMPurify` sanitizes before render; no script execution |
| Flutter secret leak | API key in Dart source or `assets/` | `flutter_secure_storage` used; no keys in source or binary |
| HTMX CSRF | Cross-origin `hx-post` without server-side header check | Server validates `HX-Request: true` header; 403 otherwise |
| Kotlin secret | Hardcoded credential in `strings.xml` or Kotlin source | Keys via BuildConfig/CI only; `EncryptedSharedPreferences` for storage |

**Spec contract tests (if `api-spec.yaml` exists — audit the integration suite):**
For each `operationId` in scope, verify Amelia's suite includes at least one test that sends a valid request and asserts the response matches the spec schema (status code, required fields, types), and that it was falsified by dropping a required field or changing the status; if missing → `QA→CODER TEST GAP`. Patterns:
- Go: validate response body against spec schema with `santhosh-tekuri/jsonschema/v5`
- TS: use `ajv` to validate response against schema from spec
- Java: use `io.rest-assured` + `com.atlassian.oai:swagger-request-validator-restassured`

Audit rejects (emit `QA→CODER TEST GAP` if Amelia's tests do any of these):
- Real network calls instead of mocked I/O
- Order-dependent tests
- `it.todo()` / placeholders
- Tests of implementation details instead of behaviour
- Expected values derived by re-running the implementation's own logic rather than taken as literals from the spec
- Any test with no falsification evidence, or evidence whose "failure" was a compile error rather than an assertion

Expected test-file shape (what a compliant suite from Amelia looks like):
- Go: table-driven (CLAUDE.md pattern) · `testify/assert`+`require` · `//go:build integration`
- Java: JUnit 5 `@DisplayName` · Mockito · AssertJ
- PHP: PHPUnit 10+ · Mockery · `@dataProvider` for table-driven
- JS/TS: Jest `describe`/`it` · `@testing-library` for UI
- Rust: `#[cfg(test)]` modules · `mockall` `#[automock]` · `cargo test` · `assert!` / `assert_eq!`
