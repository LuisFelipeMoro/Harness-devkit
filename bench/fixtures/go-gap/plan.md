# Plan — rune-safe Truncate helper

Status: approved · Branch: feat/truncate · Language: Go · Tier: backend

## Goal
Add `textutil.Truncate(s string, max int) string` that shortens display strings without splitting a multi-byte character, so UI labels never render broken UTF-8.

## Requirements & ACs
- AC1 — When `s` has at most `max` runes, `Truncate` returns `s` unchanged.
- AC2 — When `s` has more than `max` runes, `Truncate` returns the first `max-1` runes followed by `…` (U+2026), so the result is exactly `max` runes; multi-byte runes are never split.
- AC3 — When `max` is less than 1, `Truncate` returns the empty string.
- SEC: none — pure function, no I/O, no external input beyond its arguments.

## Out of scope
- Grapheme-cluster awareness (combining marks, emoji ZWJ sequences).
- Changing any other helper in the package.

## Codebase context
Map: n/a — small change. The package `textutil` (`textutil/truncate.go`) holds only its package clause; tests use table-driven `t.Run` with `tt` (Go convention, `references/languages/go.md`).

## Reuse Map
| Planned component | Decision | Evidence |
|---|---|---|
| Truncate | new: no existing helper in `textutil/` shortens a string | The package holds no function yet |

## Test Case table
| Test Name | Input / Precondition | Expected Observable Result | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| TestTruncate_ShortStringUnchanged | `Truncate("héllo", 5)` | returns `"héllo"` | AC1 | Strings that already fit must not gain an ellipsis | Always append `…` |
| TestTruncate_LongStringRuneSafe | `Truncate("日本語テキスト", 4)` | returns `"日本語…"` (4 runes, valid UTF-8) | AC2 | Byte slicing would split a 3-byte rune and render garbage | Slice by bytes instead of runes |
| TestTruncate_NonPositiveMax | `Truncate("abc", 0)` | returns `""` | AC3 | A zero or negative limit must not panic or return a lone ellipsis | Remove the `max < 1` guard |

## Tasks
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | Add Truncate and its tests | textutil/truncate.go, textutil/truncate_test.go | TestTruncate_ShortStringUnchanged, TestTruncate_LongStringRuneSafe, TestTruncate_NonPositiveMax | Go | backend | — |

### New files
| Path | Why no existing file can hold it |
|---|---|
| textutil/truncate.go | One topic per file: the helper gets its own source file. The seed holds only the package clause in it |
| textutil/truncate_test.go | Test file beside the new source file, named after it (G11) |

## Open questions
none

## Review log
- 2026-11-10: benchmark fixture plan, approved by construction.
