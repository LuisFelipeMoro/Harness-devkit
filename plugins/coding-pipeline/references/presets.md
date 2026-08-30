# Presets — Example Tasks & Expected Outputs

Use as test prompts when validating the skill or as quick-start examples.

---

## Rate Limiter (JS/Express)
**Task**: Sliding window rate limiter middleware — limits requests per IP, configurable window and max, returns 429 with Retry-After header.

| Artifact | Key points |
|----------|-----------|
| Brief | DDoS/abuse prevention; Security NFR: no bypass via X-Forwarded-For spoofing |
| PRD | FR: limit/IP, configurable params, 429+header; NFR: p99 < 1ms; Sec AC: X-Forwarded-For validation |
| Architecture | SlidingWindow + RateLimiterMiddleware; in-memory default, Redis optional; OWASP A01 mitigation |
| Stories | STORY-01: in-memory impl; STORY-02 (future): Redis backend |

**Expected scores**: Review ~8/10, Stress ~7/10 (race condition risk under concurrency)

---

## JWT Auth Middleware (JS/Node.js)
**Task**: JWT validation middleware with token expiry, refresh tokens, and RBAC.

| Artifact | Key points |
|----------|-----------|
| Brief | Stateless auth for APIs; OWASP A07 prominent |
| PRD | FR: validate, refresh, RBAC; NFR: HS256/RS256, token replay prevention; Sec ACs: rotation, short-lived tokens, HttpOnly |
| Architecture | TokenValidator + RefreshFlow + RoleGuard; ADR: symmetric vs asymmetric keys |
| Stories | STORY-01: validation + RBAC; STORY-02: refresh flow |

**Expected scores**: Review ~7/10 without token rotation; CRITICAL if tokens in localStorage

---

## LRU Cache (JS)
**Task**: LRU cache with configurable max size, TTL per entry, and cache statistics.

| Artifact | Key points |
|----------|-----------|
| Brief | Computation/I/O caching; Sec NFR: no sensitive data without TTL |
| PRD | FR: get/set, TTL, stats; NFR: O(1) get/set; Sec AC: key validation (prototype pollution) |
| Architecture | DoublyLinkedList + HashMap; ADR: Map vs plain object |
| Stories | STORY-01: LRU logic; STORY-02: TTL+expiry; STORY-03: stats |

**Expected scores**: Review ~9/10 if O(1) achieved; Stress flags memory under max-size pressure

---

## Task Queue (JS/Node.js)
**Task**: Persistent queue with priority, exponential backoff retry, dead letter queue, worker concurrency.

| Artifact | Key points |
|----------|-----------|
| Brief | Multiple user types; high reliability NFRs; Sec: payload validation, worker isolation |
| PRD | 6+ FRs; durability + exactly-once semantics; Sec ACs: payload size limits |
| Architecture | Queue + Worker + RetryPolicy + DLQ + Storage; Redis or SQLite ADR |
| Stories | 3+ stories minimum |

**Expected scores**: Stress finds concurrency issues if locking isn't explicit

---

## CSV Parser (JS/Node.js)
**Task**: Streaming CSV parser — quoted fields, escaped chars, custom delimiters, large files.

| Artifact | Key points |
|----------|-----------|
| Brief | Large data processing; Sec NFR: reject files exceeding size/row limits |
| PRD | FR: parse, streaming, configurable; NFR: < 50 MB RAM; Sec AC: max row + file size |
| Architecture | StateMachine parser + ReadableStream; ADR: push vs pull streaming |
| Stories | STORY-01: core parser; STORY-02: streaming + backpressure |

**Expected scores**: Review flags regex parser vs state machine; Stress finds OOM if backpressure missing

---

## REST API with Auth (Java / Spring Boot)
**Task**: Spring Boot REST API for user profiles — CRUD, JWT auth, RBAC, input validation, audit logging.

| Artifact | Key points |
|----------|-----------|
| Brief | Java 17+, Spring Boot 3; GDPR compliance; OWASP Top 10 baseline |
| PRD | FR: CRUD, JWT, RBAC, audit log; NFR: p99 < 100ms; Sec ACs: BCrypt, HttpOnly, no PII in logs, PreparedStatement |
| Architecture | Controller→Service→Repository; Spring Security filter chain; BCrypt; OWASP A01–A10 |
| Stories | STORY-01: CRUD+validation; STORY-02: JWT+Spring Security; STORY-03: audit log |

**Expected scores**: Review CRITICAL if `@PreAuthorize` missing; Stress checks connection pool exhaustion

---

## API Gateway Middleware (PHP / Laravel)
**Task**: Laravel middleware — API key auth, request logging, rate limit per key, Redis IP blocklist.

| Artifact | Key points |
|----------|-----------|
| Brief | PHP 8.2, Laravel 11; Sec: timing-safe key comparison, no IP spoofing bypass |
| PRD | FR: key auth, rate limit, IP blocklist, logging; NFR: < 5ms overhead; Sec ACs: `hash_equals()`, no key in logs, `strict_types=1` |
| Architecture | ApiKeyMiddleware→RateLimiter→IpBlocklist; Redis; key rotation strategy |
| Stories | STORY-01: key validation; STORY-02: rate limiting; STORY-03: IP blocklist |

**Expected scores**: Review CRITICAL if `hash_equals()` not used; Stress: Redis timeout degrading to allow-all

---

## HTTP Client Wrapper (Go)
**Task**: Go HTTP client with circuit breaker, retry+exponential backoff, structured logging, configurable timeouts.

| Artifact | Key points |
|----------|-----------|
| Brief | Go 1.26.2; Sec: TLS enforced, no InsecureSkipVerify, no secrets in logs |
| PRD | FR: circuit breaker, retry+backoff, structured logging; NFR: zero goroutine leaks; Sec ACs: TLS 1.2+, timeouts mandatory |
| Architecture | Client struct + CircuitBreaker interface (consumer pkg); gobreaker; zap |
| Stories | STORY-01: base client+timeouts; STORY-02: circuit breaker; STORY-03: retry+backoff |

**Expected scores**: Review MAJOR if ReadTimeout unset; Stress finds goroutine leak if context not propagated; coverage ≥ 85%

---

## Progressive Workflow Examples

### Analysis → Planning → Pipeline

**Step 1 — `/analysis` only** (understand requirements before committing to architecture):
```
/analysis Build a webhook delivery system with retry, signature verification, and dead letter queue
```
Output: `docs/deliveries/{key}/product-brief.md` + `docs/deliveries/{key}/PRD.md` + Epic Summary table. No delivery file produced yet.

**Step 2 — `/planning`** (loads existing Brief+PRD, produces architecture):
```
/planning
```
Output: docs/deliveries/delivery-{slug}-{key}.md (with Mermaid diagram + OWASP threat table) + Epic Manifest. Halts — no code.

**Step 3 — `/multi-agent`** (loads all artifacts, implements):
```
/multi-agent
```
Loads Brief, PRD, the delivery file, Epic Manifest. Runs ScrumMaster → Coder → QA → Review → Verdict.

---

### Fast Single Task (skip analysis + planning)

**`/task`** runs inline architecture → sub-tasks → code:
```
/task Add idempotency key validation to the payments endpoint
```
Architect derives tech stack from existing `go.mod`. Produces Task Manifest → implements sub-tasks → Verdict.

---

**When to use each entry point:**

| Situation | Command |
|-----------|---------|
| Requirements unclear; need to explore before committing | `/analysis` → `/planning` → pipeline |
| Architecture is the hard problem; requirements known | `/planning <task>` → pipeline |
| Task is well-defined, single service, small scope | `/task <task>` |
| Large epic, multiple services, stakeholder alignment needed | `/multi-agent <task>` |
