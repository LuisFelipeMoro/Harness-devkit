# Plan — clamp helper

Status: approved · Branch: feat/clamp · Language: Go · Tier: backend

## Goal
Add `clamp.Clamp(v, lo, hi int) int` that bounds an integer to the inclusive range `[lo, hi]`, so a pagination offset never leaves its valid window.

## Requirements & ACs
- AC1 — When `lo <= v <= hi`, `Clamp` returns `v` unchanged.
- AC2 — When `v < lo`, `Clamp` returns `lo`.
- AC3 — When `v > hi`, `Clamp` returns `hi`.
- SEC: none — pure function, no I/O, no external input beyond its arguments.

## Out of scope
- Floating-point or generic (type-parameter) variants.
- Validating that `lo <= hi`; that is the caller's contract.

## Codebase context
Map: n/a — small change. The package `clamp` (`clamp/clamp.go`) holds only its package clause; tests use table-driven `t.Run` with `tt` (Go convention, `references/languages/go.md`).

## Reuse Map
| Planned component | Decision | Evidence |
|---|---|---|
| Clamp | new: no existing helper in the module bounds integers | The module holds no function yet |

## Test Case table
| Test Name | Input / Precondition | Expected Observable Result | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| TestClamp_InsideRangeUnchanged | `Clamp(5, 0, 10)` | returns `5` | AC1 | A value already in range must not be moved to a bound | Return `lo` for every input |
| TestClamp_BelowRangeReturnsLow | `Clamp(-3, 0, 10)` | returns `0` | AC2 | An offset below zero would read before the first row | Delete the `v < lo` branch |
| TestClamp_AboveRangeReturnsHigh | `Clamp(42, 0, 10)` | returns `10` | AC3 | An offset past the last page would read beyond the data | Delete the `v > hi` branch |

## Tasks
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | Add Clamp and its tests | clamp/clamp.go, clamp/clamp_test.go | TestClamp_InsideRangeUnchanged, TestClamp_BelowRangeReturnsLow, TestClamp_AboveRangeReturnsHigh | Go | backend | — |

### New files
| Path | Why no existing file can hold it |
|---|---|
| clamp/clamp.go | One topic per file: the helper gets its own source file. The seed holds only the package clause in it |
| clamp/clamp_test.go | Test file beside the new source file, named after it (G11) |

## Open questions
none

## Review log
- 2026-11-12: benchmark fixture plan, approved by construction.
