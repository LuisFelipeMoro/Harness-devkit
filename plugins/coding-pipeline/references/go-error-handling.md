# Go — Error Handling

Loaded by the Coder and the Reviewer when Go code creates, wraps, inspects, logs or returns errors. Read with `languages/go.md`. Severities live only in go.md's Review Flags table; a rule go.md already states is cited by its line here, never restated.

Rules adapted (rewritten) from samber/cc-skills-golang (MIT), golang-error-handling, commit d68d80a.

### Check every returned error; `_ =` needs a reason

Why: a dropped error is a silent failure whose cause is lost. The errcheck flag in go.md catches the unchecked call; this rule says what a justified skip looks like.

❌ `os.Remove(tmp)`
✅ `if err := os.Remove(tmp); err != nil { return fmt.Errorf("remove temp file: %w", err) }`
✅ `_ = conn.Close() // response already written; a close error cannot lose data`

### Handle an error once: log it or return it, never both

Why: an error logged and then returned is written again by every layer above it, and the layer that finally handles it logs it a second time.

❌
```go
if err != nil {
    logger.Error("load order", "err", err)
    return fmt.Errorf("load order: %w", err)
}
```
✅ return it with context, and log once at the boundary that decides the outcome (the request handler or the goroutine owner):
```go
if err != nil {
    return fmt.Errorf("load order %s: %w", id, err)
}
```

### Wrap with `%w` inside the module; cut the chain at a public boundary

Why: `%w` keeps the chain so `errors.Is` works higher up; `%v` deliberately severs it where callers must not depend on an internal type. The bare `return err` is go.md's Review Flags row for it.

❌ `return fmt.Errorf("query user: %v", err)` inside the module: the caller's `errors.Is(err, sql.ErrNoRows)` now fails.
✅ `return fmt.Errorf("query user: %w", err)`
✅ `return fmt.Errorf("find order: %v", err) // public API: driver types stop here; callers match ErrOrderNotFound`

### Inspect with `errors.Is` / `errors.As`, never `==`

Why: `==` compares only the outermost value, so a wrapped sentinel never matches. Matching on the message text is go.md:41 (Error inspection) and is not repeated here. On Go 1.26+ use `errors.AsType` (go-modern-idioms.md).

❌ `if err == sql.ErrNoRows {`
✅ `if errors.Is(err, sql.ErrNoRows) {`
❌ `if pe, ok := err.(*fs.PathError); ok {` (misses a wrapped error)
✅ `var pe *fs.PathError` then `if errors.As(err, &pe) {`

### Independent errors are joined, not reduced to the first

Independent failures, such as closing several resources, are reported together with the `errors.Join` row of [`go-modern-idioms.md`](go-modern-idioms.md), which gives the joined error by Go version.

### Sentinels for expected conditions, a type for data; lowercase messages

Why: callers match a sentinel with `errors.Is` and read fields from a type with `errors.As`; a capitalised or punctuated message breaks the `outer: inner` chain format the wrapping rule relies on.

❌ `var ErrNotFound = errors.New("Order not found.")`
✅ `var ErrOrderNotFound = errors.New("order not found")`
✅ a custom type when the caller needs data: `type ValidationError struct { Field string }`, matched with `errors.As`.

### Never return nil on a path where `err != nil` (nilerr)

Why: a nil return with a live error discards the failure, and the caller proceeds on zero values as if the read succeeded.

❌
```go
func loadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, nil // caller treats a failed read as an empty config
    }
    return parse(data)
}
```
✅ `return nil, fmt.Errorf("read config: %w", err)`

### `panic` is for programmer errors; `recover` at boundaries

Why: a panic unwinds every caller's frame unhandled, so one bad request can kill the process. Library and service code returns errors (go.md Review Flags: `panic` in library/service code). A recover at a goroutine or request boundary turns a panic into an error for that unit of work only.

❌ `if id == "" { panic("empty id") }` on a request path: user input is not a programmer error.
✅ `if id == "" { return ErrInvalidID }`
✅ at the request boundary, log the recovered value and return a generic error (go.md:103 keeps internal text off the client):
```go
func serve(w http.ResponseWriter, r *http.Request) (err error) {
    defer func() {
        if rec := recover(); rec != nil {
            logger.ErrorContext(r.Context(), "handler panic", "panic", rec)
            err = ErrInternal
        }
    }()
    return handle(w, r)
}
```

### Stable log messages; variables go in slog attributes

Why: a fixed message groups in log search, and attributes stay queryable. `request_id` comes from `ctx` on every error log (go.md:155).

❌ `logger.Error(fmt.Sprintf("order %s failed: %v", id, err))`
✅ `logger.ErrorContext(ctx, "order failed", "order_id", id, "err", err)`
