# Go — Safety Pitfalls

Loaded when Go code does type assertions, shares slices or maps, converts numeric types, defers inside a loop, or lazy-initialises state. Read with `languages/go.md`. Severities live only in go.md's Review Flags table; a rule go.md already states is cited by its line here, never restated.

Rules adapted (rewritten) from samber/cc-skills-golang (MIT), golang-safety, commit d68d80a.

### A typed nil is not a nil interface or error

Why: an interface holding a nil pointer has a type, so `== nil` is false and the caller takes the error path for a success.

❌
```go
func check(id string) error {
    var e *NotFound
    if missing(id) {
        e = &NotFound{ID: id}
    }
    return e // non-nil interface even when e is nil
}
```
✅ return the untyped `nil` on the success path:
```go
func check(id string) error {
    if missing(id) {
        return &NotFound{ID: id}
    }
    return nil
}
```

### Writing to a nil map panics

Why: a nil map reads as empty but panics on assignment, and a struct field or returned map is nil until something makes it.

❌ `var index map[string]int` then `index["a"] = 1`
✅ `index := make(map[string]int)` or `index := map[string]int{}` before the first write

### `append` may write into the caller's backing array

Why: when capacity remains, `append` reuses the array the slice shares, so the write is visible through the original slice. Capping the slice with `s[:len(s):len(s)]` forces `append` to allocate a copy.

❌ `child := append(parent[:1], x)` overwrites `parent[1]` when capacity allows.
✅ `child := append(parent[:len(parent):len(parent)], x)` allocates; `parent` is untouched.

### Exported functions return copies of internal slices and maps

Why: a returned slice or map is an alias of the struct's state, so a caller's mutation changes the value the struct guards.

❌ `func (c *Cart) Items() []Item { return c.items }`
✅ `func (c *Cart) Items() []Item { return slices.Clone(c.items) }` (the `maps.Clone` row of go-modern-idioms.md covers maps)

### Narrowing conversions

The bounds check before any narrowing conversion is go.md:99 (Integer conversion, gosec G115). Not restated here.

### `defer Close()` or `Unlock()` inside a loop holds every resource until return

Why: deferred calls run when the function returns, so each loop iteration's file or lock stays held until the whole function ends. This is a resource leak; go.md:111 (Defer) covers the separate cost of a hot loop.

❌
```go
for _, p := range paths {
    f, err := os.Open(p)
    if err != nil {
        return fmt.Errorf("open %s: %w", p, err)
    }
    defer f.Close() // every file stays open until the function returns
}
```
✅ move the body into a helper, so its `defer` runs once per iteration:
```go
for _, p := range paths {
    if err := readOne(p); err != nil {
        return fmt.Errorf("read %s: %w", p, err)
    }
}

func readOne(p string) error {
    f, err := os.Open(p)
    if err != nil {
        return err
    }
    defer f.Close()
    // ...
}
```

### Type assertions use comma-ok unless the type is guaranteed

Why: a single-value assertion panics on a mismatch, and the input that triggers it is often untrusted.

❌ `name := payload["name"].(string)` on decoded input
✅ `name, ok := payload["name"].(string)`, then `if !ok { return ErrBadType }`

### Floats are never compared with `==`

Why: binary floats cannot represent most decimal values exactly, so an expected equality fails by a rounding step. Money is an integer count of the smallest unit, which needs no tolerance.

❌ `if total == 0.3 {`
✅ `if math.Abs(total-0.3) < 1e-9 {` for a measured quantity; `if totalCents == 30 {` for money

### Guard integer division by zero on untrusted input

Why: integer division by zero panics, and a divisor taken from a request is an attacker-chosen input.

❌ `avg := sum / n` where `n` comes from the request
✅ `if n == 0 { return 0, ErrEmpty }` before `avg := sum / n`

### Useful zero values; `sync.Once` for lazy initialisation

The zero-value design rule is go.md:46 (Zero values). Lazy setup is the case it leaves open: a check-then-set without a lock races when two goroutines reach it.

❌ `if c.cache == nil { c.cache = build() }` called from concurrent requests
✅ `c.once.Do(func() { c.cache = build() })` with `once sync.Once` in the struct, so the zero value still works

### A nil channel blocks forever

Why: a receive or send on a nil channel never proceeds, so a goroutine that reaches it waits with no exit. go.md:57 (Channels) covers the deliberate disable inside a `select`; this is the accidental case.

❌ `<-results` where `results` was never made, in a goroutine nothing else can unblock
✅ create the channel before starting its goroutines, and wait with `select` on `ctx.Done()` as well
