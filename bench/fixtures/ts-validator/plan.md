# Plan — ISBN-13 validator

Status: approved · Branch: feat/isbn13 · Language: TypeScript 5 · Tier: backend

## Goal
Add `validateIsbn13(input: string): boolean` that accepts a 13-digit ISBN written with or without hyphens or spaces, and rejects any string whose check digit is wrong, so a catalogue import never stores a mistyped ISBN.

## Requirements & ACs
- AC1 — A canonical 13-digit string with a correct check digit returns `true`.
- AC2 — Hyphens and spaces are separators: the same ISBN written with them returns `true`.
- AC3 — A 13-digit string whose check digit is wrong returns `false`.
- SEC: none — pure function, no I/O, no external input beyond its argument.

## Out of scope
- ISBN-10 and conversion between the two forms.
- Looking the ISBN up in any registry.

## Codebase context
Map: n/a — small change. The module `src/isbn.ts` exports nothing yet. Test framework: `node:test` — `import { it } from "node:test"` and `import assert from "node:assert/strict"`, run by `node --test` with no install (TypeScript convention, `references/languages/typescript.md`). Test file `src/isbn.test.ts` sits beside `src/isbn.ts`.

## Reuse Map
| Planned component | Decision | Evidence |
|---|---|---|
| validateIsbn13 | new: no existing ISBN helper in the package | The package holds no function yet |

## Test Case table
| Test Name | Input / Precondition | Expected Observable Result | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| it("accepts a canonical 13-digit ISBN") | `validateIsbn13("9780306406157")` | returns `true` | AC1 | A correct ISBN typed as digits must pass | Return `false` for every input |
| it("accepts a hyphenated ISBN") | `validateIsbn13("978-0-306-40615-7")` | returns `true` | AC2 | Catalogue data arrives with separators, and rejecting them drops valid books | Delete the separator-stripping step |
| it("rejects a wrong check digit") | `validateIsbn13("9780306406158")` | returns `false` | AC3 | A mistyped ISBN must not be stored as valid | Remove the check-digit comparison so any 13-digit string passes |

## Tasks
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | Add validateIsbn13 and its tests | src/isbn.ts, src/isbn.test.ts | it("accepts a canonical 13-digit ISBN"), it("accepts a hyphenated ISBN"), it("rejects a wrong check digit") | TypeScript 5 | backend | — |

### New files
| Path | Why no existing file can hold it |
|---|---|
| src/isbn.ts | One topic per file: the validator gets its own module. The seed holds only an empty export in it |
| src/isbn.test.ts | Test file beside the new source file, named after it (G11 analogue for TypeScript: foo.ts → foo.test.ts) |

## Open questions
none

## Review log
- 2026-11-12: benchmark fixture plan, approved by construction.
