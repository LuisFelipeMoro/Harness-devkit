# Presets — Example Tasks & Expected Outputs

Use as test prompts when validating `/planning` and `/code`, or as quick-start examples. Each table shows what the plan should carry: Goal and ACs in place of a brief/PRD, Design in place of an architecture file, and Tasks rows in place of stories.

---

## Rate Limiter (JS/Express)
**Task**: Sliding window rate limiter middleware — limits requests per IP, configurable window and max, returns 429 with Retry-After header.

| Artifact | Key points |
|----------|-----------|
| Goal / constraints | DDoS/abuse prevention; Security NFR: no bypass via X-Forwarded-For spoofing |
| Requirements & ACs | FR: limit/IP, configurable params, 429+header; NFR: p99 < 1ms; Sec AC: X-Forwarded-For validation |
| Design | SlidingWindow + RateLimiterMiddleware; in-memory default, Redis optional; OWASP A01 mitigation |
| Tasks | T1: in-memory impl; T2 (future): Redis backend |

**Expected scores**: `reviewer` ~8/10, `stress` ~7/10 (race condition risk under concurrency)

---

## JWT Auth Middleware (JS/Node.js)
**Task**: JWT validation middleware with token expiry, refresh tokens, and RBAC.

| Artifact | Key points |
|----------|-----------|
| Goal / constraints | Stateless auth for APIs; OWASP A07 prominent |
| Requirements & ACs | FR: validate, refresh, RBAC; NFR: HS256/RS256, token replay prevention; Sec ACs: rotation, short-lived tokens, HttpOnly |
| Design | TokenValidator + RefreshFlow + RoleGuard; ADR: symmetric vs asymmetric keys |
| Tasks | T1: validation + RBAC; T2: refresh flow |

**Expected scores**: `reviewer` ~7/10 without token rotation; CRITICAL if tokens in localStorage

---

## LRU Cache (JS)
**Task**: LRU cache with configurable max size, TTL per entry, and cache statistics.

| Artifact | Key points |
|----------|-----------|
| Goal / constraints | Computation/I/O caching; Sec NFR: no sensitive data without TTL |
| Requirements & ACs | FR: get/set, TTL, stats; NFR: O(1) get/set; Sec AC: key validation (prototype pollution) |
| Design | DoublyLinkedList + HashMap; ADR: Map vs plain object |
| Tasks | T1: LRU logic; T2: TTL+expiry; T3: stats |

**Expected scores**: `reviewer` ~9/10 if O(1) achieved; Stress flags memory under max-size pressure

---

## Task Queue (JS/Node.js)
**Task**: Persistent queue with priority, exponential backoff retry, dead letter queue, worker concurrency.

| Artifact | Key points |
|----------|-----------|
| Goal / constraints | Multiple user types; high reliability NFRs; Sec: payload validation, worker isolation |
| Requirements & ACs | 6+ FRs; durability + exactly-once semantics; Sec ACs: payload size limits |
| Design | Queue + Worker + RetryPolicy + DLQ + Storage; Redis or SQLite ADR |
| Tasks | 3+ task rows minimum |

**Expected scores**: Stress finds concurrency issues if locking isn't explicit

---

## CSV Parser (JS/Node.js)
**Task**: Streaming CSV parser — quoted fields, escaped chars, custom delimiters, large files.

| Artifact | Key points |
|----------|-----------|
| Goal / constraints | Large data processing; Sec NFR: reject files exceeding size/row limits |
| Requirements & ACs | FR: parse, streaming, configurable; NFR: < 50 MB RAM; Sec AC: max row + file size |
| Design | StateMachine parser + ReadableStream; ADR: push vs pull streaming |
| Tasks | T1: core parser; T2: streaming + backpressure |

**Expected scores**: Review flags regex parser vs state machine; Stress finds OOM if backpressure missing

---

## REST API with Auth (Java / Spring Boot)
**Task**: Spring Boot REST API for user profiles — CRUD, JWT auth, RBAC, input validation, audit logging.

| Artifact | Key points |
|----------|-----------|
| Goal / constraints | Java 17+, Spring Boot 3; GDPR compliance; OWASP Top 10 baseline |
| Requirements & ACs | FR: CRUD, JWT, RBAC, audit log; NFR: p99 < 100ms; Sec ACs: BCrypt, HttpOnly, no PII in logs, PreparedStatement |
| Design | Controller→Service→Repository; Spring Security filter chain; BCrypt; OWASP A01–A10 |
| Tasks | T1: CRUD+validation; T2: JWT+Spring Security; T3: audit log |

**Expected scores**: Review CRITICAL if `@PreAuthorize` missing; Stress checks connection pool exhaustion

---

## API Gateway Middleware (PHP / Laravel)
**Task**: Laravel middleware — API key auth, request logging, rate limit per key, Redis IP blocklist.

| Artifact | Key points |
|----------|-----------|
| Goal / constraints | PHP 8.2, Laravel 11; Sec: timing-safe key comparison, no IP spoofing bypass |
| Requirements & ACs | FR: key auth, rate limit, IP blocklist, logging; NFR: < 5ms overhead; Sec ACs: `hash_equals()`, no key in logs, `strict_types=1` |
| Design | ApiKeyMiddleware→RateLimiter→IpBlocklist; Redis; key rotation strategy |
| Tasks | T1: key validation; T2: rate limiting; T3: IP blocklist |

**Expected scores**: Review CRITICAL if `hash_equals()` not used; Stress: Redis timeout degrading to allow-all

---

## HTTP Client Wrapper (Go)
**Task**: Go HTTP client with circuit breaker, retry+exponential backoff, structured logging, configurable timeouts.

| Artifact | Key points |
|----------|-----------|
| Goal / constraints | Go 1.26.2; Sec: TLS enforced, no InsecureSkipVerify, no secrets in logs |
| Requirements & ACs | FR: circuit breaker, retry+backoff, structured logging; NFR: zero goroutine leaks; Sec ACs: TLS 1.2+, timeouts mandatory |
| Design | Client struct + CircuitBreaker interface (consumer pkg); gobreaker; zap |
| Tasks | T1: base client+timeouts; T2: circuit breaker; T3: retry+backoff |

**Expected scores**: Review MAJOR if ReadTimeout unset; Stress finds goroutine leak if context not propagated; coverage ≥ 85%

---

## Flow examples

### Plan from notes, then implement

**Step 1 — `/map`** (optional; `/planning` runs the same map as its first step):
```
/map webhook delivery
```
Output: `docs/plans/webhook-delivery/codebase-map.md`.

**Step 2 — `/planning`** (normalizes your notes into the template, or builds from scratch):
```
/planning notes/webhooks.md
```
Output: `docs/plans/webhook-delivery/plan.md` (Mermaid diagram, Security ACs, Test Case table, Tasks), reviewed by `plan-reviewer`, status `approved` after your OK. Writes no code.

**Step 3 — `/code`**:
```
/code docs/plans/webhook-delivery/plan.md
```
One `coder` per Tasks row: spec → implement → test → falsify, then format, lint, existing tests.

**Step 4 — `/validate-code`, then `/review-code`**, then `/pr-fix` once a PR has comments.

---

### Small task (no plan)

```
/code Add idempotency key validation to the payments endpoint
```
`/code` writes a mini-plan in the same template (Test Case table + Tasks), shows it for a one-line OK, and implements it. Stack comes from the existing `go.mod` / `package.json`.

---

**When to use each entry point:**

| Situation | Command |
|-----------|---------|
| Need to see what exists before deciding | `/map <area>` → `/planning` |
| Requirements known; design is the hard part | `/planning <task>` → `/code` |
| Task is well-defined, single service, small scope | `/code <task>` |
| Large change, several services, stakeholder alignment | `/planning` (with a notes file) → `/code`, then `/validate-code` |
| Something is broken | `/bugfix` |
