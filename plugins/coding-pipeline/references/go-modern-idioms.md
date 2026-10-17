# Go — Modern Idioms by Minimum Version

Loaded by the Coder on every Go story, alongside `languages/go.md`. **Apply a row only when the module's `go` directive is at least its Min Go.** Below it the newer API is a defect (go.md *Version policy*). A file-level `//go:build go1.N` constraint raises the version for that file only.

| Idiom | Min Go | Prefer | Over |
|---|---|---|---|
| `any` for an unavoidable empty interface | 1.18 | `any` | `interface{}` |
| `strings.Cut` / `bytes.Cut` | 1.18 | one call returning before, after, found | index arithmetic around `Index` |
| `atomic.Int64`, `atomic.Bool`, `atomic.Pointer[T]` | 1.19 | typed atomic values | bare `atomic.AddInt64` on a raw field |
| `errors.Join` | 1.20 | joined error from a list | a hand-rolled multi-error type |
| `context.WithCancelCause` + `context.Cause` | 1.20 | a cause attached to cancellation | sentinel errors to explain a cancel |
| `strings.CutPrefix` / `strings.CutSuffix` | 1.20 | one call returning rest, found | `HasPrefix` followed by slicing |
| builtins `min` / `max` / `clear` | 1.21 | the builtin | hand-written helpers and clearing loops |
| `slices.Contains` / `Index` / `Sort` / `SortFunc` / `BinarySearch` | 1.21 | `slices` package | manual loops and `sort.Slice` |
| `maps.Clone` / `maps.Copy` | 1.21 | `maps` package | manual range-copy loops |
| `sync.OnceFunc` / `sync.OnceValue` | 1.21 | once helpers | `sync.Once` with captured result variables |
| `context.AfterFunc` | 1.21 | callback on cancellation | a goroutine blocked on `ctx.Done()` |
| `context.WithTimeoutCause` | 1.21 | a cause on timeout | `WithTimeout` plus a separate error |
| `for i := range n` | 1.22 | range over an integer | C-style counted loop |
| per-iteration loop variables | 1.22 | the loop variable as-is | `v := v` copy inside the loop |
| `cmp.Or` | 1.22 | first non-zero value | `if` chains that set defaults |
| `http.ServeMux` method and wildcard patterns, `r.PathValue` | 1.22 | `"GET /items/{id}"` with `PathValue` | manual path splitting |
| iterators `maps.Keys` / `slices.Sorted` / `slices.Collect` | 1.23 | iterator helpers | building slices by hand from maps |
| `omitzero` JSON tag | 1.24 | `json:",omitzero"` | `omitempty` on structs and times |
| `strings.SplitSeq` / `strings.FieldsSeq` | 1.24 | iterator forms | allocating a slice only to range over it |
| `sync.WaitGroup.Go` (`wg.Go(f)`) | 1.25 | `wg.Go(f)` | `Add(1)`, `go`, `defer Done()` |
| `errors.AsType[T]` | 1.26 | generic typed match | `errors.As` with a declared target variable |
| `new(expr)` | 1.26 | `new(expr)` | a temporary variable and its address |

`testing.T.Context` and `testing.B.Loop` are not repeated here: see the Toolchain Capability Table in `languages/go.md`.

**Excluded on purpose**: the Go 1.27 items (the next-generation JSON package, generic methods, and the stdlib UUID type). The local toolchain is go1.26.3, so they cannot be verified, and the JSON package interacts with the `DisallowUnknownFields` rule in go.md.

Mechanical check: the advisory `go fix -diff ./...` row in `quality-gate-reference.md` applies the same version gate.
Idea source: JetBrains/go-modern-guidelines (Apache-2.0), paraphrased — no text copied.
