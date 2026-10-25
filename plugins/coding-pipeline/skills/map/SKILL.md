---
name: map
description: Write a read-only, file:line-cited map of the code a topic touches (blast radius, reuse, prior art, conventions, contracts, tests). Usage: /map <topic> [--print], e.g. "/map rate limiting on the public API".
disable-model-invocation: true
---

**Input**: a topic or area (ask if missing); `--print` to print instead of writing.
**Output**: `docs/plans/{slug}/codebase-map.md`, or the map printed.
**Boundary**: read-only — no design, no plan, no code. One Explore dispatch on `haiku` (one per area if the topic spans independent areas).

## Steps

1. Derive `{slug}` from the topic (kebab-case, ≤ 5 words). If `docs/plans/{slug}/codebase-map.md` exists, say so and ask: refresh or keep.
2. At this step, read `references/map-procedure.md` (this skill's) and dispatch the mapper exactly as it says — `subagent_type: "Explore"`, `model: "haiku"`, file paths in the prompt, never pasted contents.
3. Check the return before writing: all seven sections present, every entry has `file:line`, the blast-radius total line is stated. A section missing or uncited → one narrow re-dispatch for that section only.
4. Spot-check the blast radius yourself: run LSP find-references (or grep) on the two most-changed symbols and compare counts. A mismatch is corrected in the map and noted under the total line.
5. Write the file (or print with `--print`) using the output shape in `references/map-procedure.md`. Print the total line and the path.

Next: `/planning` for the same topic — it reuses this map instead of re-mapping.
