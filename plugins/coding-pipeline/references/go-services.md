# Go — Services (context, database, outbound HTTP, gRPC, metrics)

Loaded by the Coder and the Reviewer when Go code touches context lifecycle, `database/sql`/sqlx/pgx, an outbound `http.Client`, gRPC, file paths from input, or metrics. Read with `languages/go.md`. Severities live only in go.md's Review Flags table; a rule go.md already states is cited by its line here, never restated.

Rules adapted (rewritten) from samber/cc-skills-golang (MIT), golang-context, golang-database, golang-grpc, golang-observability, golang-design-patterns, commit d68d80a.

### Work that outlives the request uses `context.WithoutCancel`

Why: a request's context is cancelled when its handler returns or the client disconnects. A background audit write or cache fill that inherits it stops at that moment, silently. A detached copy keeps the values (request id, tenant) and drops the cancellation (Go 1.21+). Give the detached work its own deadline and an owner per go.md:53.

❌
```go
go writeAudit(r.Context(), event) // lost when the client disconnects
```
✅
```go
bg := context.WithoutCancel(r.Context())
bgCtx, cancel := context.WithTimeout(bg, 5*time.Second)
go func() {
    defer cancel()
    writeAudit(bgCtx, event)
}()
```

### Every `WithCancel` or `WithTimeout` is cancelled on every path

Why: the derived context holds a timer and parent registration until it is cancelled. A cancel called only on the happy path leaks on each early return. The Review Flags row for this is in go.md.

❌
```go
ctx, _ := context.WithTimeout(ctx, 2*time.Second)
```
✅
```go
ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
defer cancel() // on the line after acquisition, so every return path runs it
```

### Context keys are unexported types

Why: a string key collides with any other package that uses the same string. A key of an unexported type cannot be built outside its package, so no collision is possible.

❌ `context.WithValue(ctx, "user", u)`
✅
```go
type userKey struct{}
ctx = context.WithValue(ctx, userKey{}, u)
```

### `context.TODO()` marks the gap, never a nil context

Why: a nil context panics at the first cancellable call and hides that no context was decided. `context.TODO()` is greppable and says so. go.md's Concurrency Context row (go.md:54) bans `context.Background()` below `main`; this rule is its counterpart for the caller's side.

❌ `rows, err := db.QueryContext(nil, query)`
✅ `rows, err := db.QueryContext(ctx, query)` where `ctx` is the caller's context.

### Database calls take a context: `QueryContext` and `ExecContext`

Why: `Query` and `Exec` ignore cancellation, so a disconnected client leaves its statement running on the server.

❌ `db.Query(query, id)`
✅ `db.QueryContext(ctx, query, id)`

### A statement with no rows uses `ExecContext`

Why: `QueryContext` returns a rows handle that must be closed and scanned. An `UPDATE` or `DELETE` without `RETURNING` has nothing to scan, so the handle is only overhead.

❌
```go
rows, err := db.QueryContext(ctx, "DELETE FROM sessions WHERE id = $1", id)
```
✅
```go
if _, err := db.ExecContext(ctx, "DELETE FROM sessions WHERE id = $1", id); err != nil {
    return fmt.Errorf("delete session: %w", err)
}
```

### `sql.ErrNoRows` is matched with `errors.Is`

Why: the repository wraps the driver error with `%w` (go-error-handling.md, wrapping and inspection rules). A plain `==` misses the wrapped sentinel, so "not found" reaches the client as a 500. Map it to a domain sentinel at the repository boundary.

❌ `if err == sql.ErrNoRows { return nil, ErrNotFound }`
✅
```go
if errors.Is(err, sql.ErrNoRows) {
    return nil, ErrOrderNotFound
}
```

### Check `rows.Err()` after the loop, every time

Why: `rows.Next()` returns false both at the end of the result and when the connection fails mid-read. Only `rows.Err()` tells the two apart. Without it a dropped connection reads as a short, successful result. Closing the rows is go.md's Review Flags row for unclosed DB rows, not repeated here.

❌
```go
for rows.Next() {
    // scan into out
}
return out, nil
```
✅
```go
for rows.Next() {
    // scan into out
}
if err := rows.Err(); err != nil {
    return nil, fmt.Errorf("scan orders: %w", err)
}
return out, nil
```

### Pool limits are set: `SetMaxOpenConns`, `SetMaxIdleConns`, `SetConnMaxLifetime`

Why: the default pool is unbounded, so a traffic spike opens connections until the database refuses them. Set `SetMaxOpenConns` below the server's connection cap, keep `SetMaxIdleConns` at or below it, and set `SetConnMaxLifetime` so a connection behind a load balancer is recycled.

❌ `db, _ := sql.Open("pgx", dsn)` followed by no pool configuration.
✅
```go
db.SetMaxOpenConns(25)
db.SetMaxIdleConns(25)
db.SetConnMaxLifetime(5 * time.Minute)
```

### Every outbound `http.Client` has a `Timeout` and a tuned Transport

Why: a client with no `Timeout` waits forever on a stalled upstream, and each stalled call holds a goroutine. This applies to every outbound client, not only to user-supplied URLs (go.md:94 covers those). Tune `MaxIdleConnsPerHost` on the `http.Transport`: the default of 2 idle connections per host forces a new TCP and TLS handshake under bursty load to one upstream.

❌ `client := &http.Client{}`
✅
```go
transport := &http.Transport{
    MaxIdleConns:        100,
    MaxIdleConnsPerHost: 20,
    IdleConnTimeout:     90 * time.Second,
}
client := &http.Client{Timeout: 10 * time.Second, Transport: transport}
```

### gRPC returns `status.Errorf` with a specific code

Why: a raw Go `error` returned from a handler becomes `codes.Unknown` on the wire, so every client sees the same opaque failure and cannot retry or map it correctly. Set client deadlines on every outbound call, and register reflection only in development builds.

❌ `return nil, fmt.Errorf("order %s not found", id)`
✅ `return nil, status.Errorf(codes.NotFound, "order %s not found", id)`

Client side:
```go
ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
defer cancel()
resp, err := client.GetOrder(ctx, req)
```

### Latency is a `Histogram`; label values are a bounded set

Why: a histogram gives the percentiles an alert needs, where a counter or average hides the slow tail. A label whose values are unbounded (a user id, a raw URL path with ids) creates one time series per value and exhausts the metrics backend. Label with the route template and a status class instead.

❌ `requests.WithLabelValues(r.URL.Path).Inc()`
✅ `latency.WithLabelValues(routeTemplate, statusClass).Observe(elapsed.Seconds())`

### Regexps compile once, at package level

Why: `regexp.Compile` inside a request handler recompiles the pattern on every call. A package-level `regexp.MustCompile` of a literal runs once at init, and a bad literal fails fast at startup.

❌
```go
func valid(s string) bool {
    return regexp.MustCompile(`^[a-z]+$`).MatchString(s)
}
```
✅
```go
var validName = regexp.MustCompile(`^[a-z]+$`)

func valid(s string) bool {
    return validName.MatchString(s)
}
```

### Enums start at an Unknown zero value

Why: the zero value of an int-backed enum is a real state if the first named constant is zero. A struct that is never set then looks like a valid order status rather than a missing one.

❌ `const ( StatusPaid Status = iota; StatusRefunded )`
✅
```go
const (
    StatusUnknown Status = iota
    StatusPaid
    StatusRefunded
)
```

### Compile-time interface checks: `var _ I = (*T)(nil)`

Why: a type that silently stops satisfying an interface fails at the call site far from the cause. A blank assignment fails at the type's own package, at compile time, with no runtime cost.

✅ `var _ OrderStore = (*pgOrderStore)(nil)`

### Untrusted file paths on Go 1.24+

Use the `os.Root` row of [`go-modern-idioms.md`](go-modern-idioms.md). On an older module, the path rule is go.md's Security table (`filepath.Clean` plus a containment check).
