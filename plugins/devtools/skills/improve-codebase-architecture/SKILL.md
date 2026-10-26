---
name: improve-codebase-architecture
description: Find the architectural debt in a codebase (coupling, boundary violations, shallow modules and deepening opportunities, SRP failures) and write a severity-ranked HTML report, with optional ADRs. Usage: /improve-codebase-architecture [focus-path], e.g. "/improve-codebase-architecture internal/billing".
disable-model-invocation: true
---

**Input**: the working directory, optionally a focus path.
**Output**: `/tmp/arch-report-<YYYY-MM-DD>.html` grouped by severity; optionally `docs/adr/ADR-NNN-<title>.md` for findings you choose.
**Boundary**: reports only — never refactors. One Explore dispatch (`haiku`).

Any refactor that follows is protected by a characterization test first: pin today's observable behaviour with a passing test, then refactor under green.

## Steps

1. **Map.** At this step, read `references/arch-report-reference.md` § Phase 1 — Map sub-agent call: and dispatch the read-only Explore agent with its prompt (`subagent_type: "Explore"`, `model: "haiku"`). It returns raw observations only.
2. **Verify before scoring.** Open each observation's `file:line`; drop any that the code does not bear out. Every kept finding names the future change it makes harder — no cost, no finding. When you name a finding or apply the deletion test to a suspected shallow module, read `references/deep-modules.md` (once) and use its vocabulary — module, interface, depth, seam, adapter, leverage, locality — in every finding from here on.
3. **Score.**

   | Severity | Examples |
   |---|---|
   | Critical | domain logic in HTTP/DB layer · circular imports · unhandled errors on a mutation path |
   | High | 3+ callers duplicating logic · file > 500 lines · cross-feature deep imports |
   | Medium | file 300–500 lines · inconsistent patterns in one layer · magic values |
   | Low | naming inconsistency · minor duplication · dead code |

   A shallow module or leaking seam on frequently changed code ranks by the leverage and locality a deepening buys (`references/deep-modules.md` § Writing the finding). Rank, don't enumerate: more than ~5 in a severity → the 3 that matter plus one line naming the pattern behind the rest.
4. **Report.** At this step, use the scaffold in `references/arch-report-reference.md`; each finding shows severity, `file:line`, cost and a concrete recommendation — for a deepening: what moves behind which seam, the leverage and locality gained, and the new test surface. Print: `Architecture report: /tmp/arch-report-<date>.html — N critical, N high, N medium, N low.`
5. **ADRs (optional).** AskUserQuestion (`multiSelect: true`) over the Critical/High findings: which deserve an ADR? Write each with the template in `references/arch-report-reference.md`, `Status: Proposed`.

If the user picks a finding to explore, design its interface twice per `references/deep-modules.md` § Design it twice, inline — no extra dispatch.

Next: `/grill-me` on a finding to stress it, or `/planning` to plan the refactor.
