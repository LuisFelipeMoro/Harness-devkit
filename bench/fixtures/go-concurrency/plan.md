# Plan — concurrency-safe counter

Status: approved · Branch: feat/counter · Language: Go · Tier: backend · Trigger: concurrency (shared state)

## Goal
Add `counter.Counter`, a zero-value-usable integer counter whose `Inc` and `Value` methods are safe to call from many goroutines at once, so a request counter shared by handlers never loses an update.

## Requirements & ACs
- AC1 — A zero-value `Counter` reads `0`.
- AC2 — Each `Inc` adds exactly one, and `Value` returns the total.
- AC3 — Concurrent `Inc` calls never lose an update; the total equals the number of calls and `go test -race` reports no data race.
- SEC: none — in-process state, no I/O, no external input.

## Out of scope
- Persisting the count across restarts.
- Decrement, reset, or atomic compare-and-swap operations.

## Codebase context
Map: n/a — small change. The package `counter` (`counter/counter.go`) holds only its package clause; tests use table-driven or plain `t.Run` with `tt` where a table fits (Go convention, `references/languages/go.md`). Shared state is in scope, so the race row runs under `-race`.

## Reuse Map
| Planned component | Decision | Evidence |
|---|---|---|
| Counter | new: no existing counter type in the module | The module holds no type yet |

## Test Case table
| Test Name | Input / Precondition | Expected Observable Result | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| TestCounter_ZeroValueReadsZero | `var c Counter`; `c.Value()` | returns `0` | AC1 | A counter declared without a constructor must be usable | Make `Value` return `1` when the count is zero |
| TestCounter_IncrementsByOne | `c.Inc()` called twice on a zero value | `c.Value()` returns `2` | AC2 | Each call must add exactly one, or every metric is off | Drop the increment inside `Inc` |
| TestCounter_ConcurrentIncrementsRaceFree | 50 goroutines, each calling `Inc` 100 times; run under `go test -race` | `Value()` returns `5000` and the race detector reports no `DATA RACE` | AC3 | Unsynchronised increments lose updates and corrupt the shared total | Remove the `Lock`/`Unlock` pair from `Inc` |

## Tasks
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | Add Counter and its tests | counter/counter.go, counter/counter_test.go | TestCounter_ZeroValueReadsZero, TestCounter_IncrementsByOne, TestCounter_ConcurrentIncrementsRaceFree | Go | backend | — |

### New files
| Path | Why no existing file can hold it |
|---|---|
| counter/counter.go | One topic per file: the type gets its own source file. The seed holds only the package clause in it |
| counter/counter_test.go | Test file beside the new source file, named after it (G11) |

## Open questions
none

## Review log
- 2026-11-12: benchmark fixture plan, approved by construction.
