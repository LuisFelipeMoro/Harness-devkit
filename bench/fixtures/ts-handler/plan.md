# Plan — create-note request handler

Status: approved · Branch: feat/create-note · Language: TypeScript 5 · Tier: backend

## Goal
Add `createNote(body: unknown): HandlerResult` that validates a POST body of the form `{ title: string }`, returns `201` with the trimmed title on success, and returns a `400` error on bad input that never echoes the submitted value.

## Requirements & ACs
- AC1 — A body with a non-empty string `title` of at most 200 characters returns status `201` and `{ title }` with surrounding whitespace trimmed.
- AC2 — A `title` longer than 200 characters returns status `400` with error code `title_too_long`.
- AC3 (SEC, input validation) — A `title` that is not a string returns status `400` with error code `invalid_title`, and the error body never contains the submitted value.

## Out of scope
- Persisting the note, authentication, and the HTTP framework adapter (the handler is framework-free).
- Rich-text or markup rules for the title.

## Codebase context
Map: n/a — small change. `src/handlers/createNote.ts` exports nothing yet. Handlers are plain functions returning `{ status, body }`. Test framework: `node:test` — `import { it } from "node:test"` and `import assert from "node:assert/strict"`, run by `node --test` with no install (TypeScript convention, `references/languages/typescript.md`). Test file `src/handlers/createNote.test.ts` sits beside `src/handlers/createNote.ts`.

## Reuse Map
| Planned component | Decision | Evidence |
|---|---|---|
| createNote | new: no existing note handler in the package | The package holds no handler yet |

## Test Case table
| Test Name | Input / Precondition | Expected Observable Result | AC | Why It Matters | Falsified By |
|---|---|---|---|---|---|
| it("creates a note from a valid body") | `createNote({ title: "  Buy milk  " })` | status `201`, body `{ title: "Buy milk" }` | AC1 | The happy path must store the trimmed title, not the raw padded one | Return status `400` for every input |
| it("rejects a title longer than 200 characters") | `createNote({ title: "a".repeat(201) })` | status `400`, error `title_too_long` | AC2 | An unbounded title is a storage and rendering risk | Delete the length check |
| it("rejects a non-string title without echoing the input") | `createNote({ title: { script: "<img onerror=alert(1)>" } })` | status `400`, error `invalid_title`, and `JSON.stringify` of the result does not contain `onerror` | AC3 (SEC) | A type-confused title must be refused, and echoing it back would reflect attacker markup | Include the rejected value in the error body, e.g. `{ error: "invalid_title", got: title }` |

## Tasks
| ID | Task | Files | Test rows | Language | Tier | Depends on |
|---|---|---|---|---|---|---|
| T1 | Add createNote and its tests | src/handlers/createNote.ts, src/handlers/createNote.test.ts | it("creates a note from a valid body"), it("rejects a title longer than 200 characters"), it("rejects a non-string title without echoing the input") | TypeScript 5 | backend | — |

### New files
| Path | Why no existing file can hold it |
|---|---|
| src/handlers/createNote.ts | One topic per file: the handler gets its own module. The seed holds only an empty export in it |
| src/handlers/createNote.test.ts | Test file beside the new source file, named after it (foo.ts → foo.test.ts) |

## Open questions
none

## Review log
- 2026-11-12: benchmark fixture plan, approved by construction.
