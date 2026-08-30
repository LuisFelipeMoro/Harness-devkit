---
name: multi-agent-coding-pipeline
description: Use when running the full BMAD v6 agile pipeline for a large feature or epic — runs all 9 agents (Analyst, PM, Architect, ScrumMaster, Coder, QA, Reviewer, StressTester, Verdict) from planning through verdict. Trigger phrases — "build", "new feature", "epic", "implement from scratch", "greenfield", "MVP".
---

Run the BMAD v6 agile pipeline. If no task is provided, ask first.

## Contract
- **Input**: a feature/epic description (ask if not provided).
- **Output**: implemented, tested epics with Review/Stress/QA/Verdict scores; a `[{key}]`-prefixed `PROGRESS.md` entry per epic; DevOps artifacts on final PRODUCTION READY; a PR from `release/{slug}-{key}` to `main`.
- **Boundary**: Coder owns tests + implementation, written against the Architect's frozen Test Case table and falsified before handoff; Reviewer/StressTester run only after QA approval or escalation; unmitigated CRITICAL security is automatic NOT READY.
- **Done when**: the Pipeline Summary prints after the final epic's Verdict with Security Gate, Falsification evidence, and Coverage shown.

> **Model assignment** (see CLAUDE.md Model assignment table): dispatch the Architect on `opus`; Analyst, PM, Scrum Master, QA, Reviewer, Stress, Verdict, and the orchestrator on `sonnet`; the Coder (core + backend/frontend overlay), Tuner, DevOps, and any read-only Explore/mapping sub-agent on `haiku`. Don't run exploration on opus or the Architect's design pass on haiku.

---

## Phase 0 — Delivery setup (once, before planning)

Derive the delivery slug + key from the feature name, create `.worktrees/dlv-{key}/` on
`release/{slug}-{key}`, and run everything inside it. An existing worktree for the key means
**resume** (read the delivery file's Status + `[{key}]` `PROGRESS.md` entries), not recreate.
Ask before the first `git push`. Never commit or merge to `main` — the terminal step is a PR
from the release branch. Commands, header block, and branch rules:
[../../references/delivery-and-worktree.md](../../references/delivery-and-worktree.md).

---

## Phase 1 — Planning (once)

Load and follow `skills/planning.md` (Phase 0 through Phase 4). Phase 2 (grill-me plan stress) and Phase 3 (human validation of unresolved questions) are mandatory before any coding.

- If `docs/deliveries/{key}/product-brief.md` + `PRD.md` already exist (from a prior `/analysis` run for this key): load them and skip Phase 0 (inline analysis).
- If the delivery file for this key already exists and was approved: skip Phases 0–2 and proceed directly to Phase 3 (Manifest).
- On changes requested during human validation: update the delivery file → re-confirm before continuing.

Complete Phases 0–4 of the planning skill (Phase 5 is informational when invoked from a pipeline). The plan MUST clear the Phase 2 grill-me stress and Phase 3 human validation before any code. Once the **Epic Manifest** is confirmed, continue with Phase 2 below.

---

## Phase 2 — Epic Loop (repeat per epic)

Repeat A–F per epic. Full dispatch prompts, routing signals, Bug-Fix Loop, Tuner limits, and
the checkpoint table are in [references/loop.md](references/loop.md).

**A** Stories (ScrumMaster: Epic Manifest rows + delivery file → one `story-{slug}.md` per task)
→ **B** Coding (one Coder subagent per story, **dispatched one at a time** — stories share the
delivery's single worktree, so two concurrent Coders would overwrite each other; core +
one tier overlay; implement to spec → write the specified tests → falsify each)
→ **C** QA audit + gates (Quinn; route on her signal — approval proceeds to D, any gap enters
the Bug-Fix Loop, escalation proceeds to D with FAIL)
→ **D** Review + Stress in parallel, only after QA's signal (Tuner on `TUNER REQUEST`, max 2)
→ **E** Verdict (unmitigated CRITICAL security = automatic NOT READY)
→ **F** Checkpoint + a `[{key}]`-prefixed `PROGRESS.md` entry at the repo root.

Read-only Explore/mapping subagents may still run in parallel. On the final epic's
PRODUCTION READY, load `agents/devops.md`, then push the release branch (ask first) and open a
PR to `main` — never commit or merge to `main` directly.

> **Context Budget**: Between epics: drop implementation code, test files, and stories for completed epics. Retain: the delivery file + Manifest + all scores (Review/Stress/QA/Verdict per epic).
> If running 4+ epics or context >75% full: summarize completed epics to one-line refs:
> `"Epic {N}: {title} — DONE (Review: X/10, Stress: Y/10, QA: Z/10)"` — never drop scores.
> At context >90%: pause, summarize all prior artifacts, confirm with user before continuing.

---

Use `references/output-format.md` headers. Show Pipeline Summary (with Security Gate + Coverage) after each Verdict.
Load agent files on demand — never pre-load all at once.
For example tasks and progressive workflow patterns, see `references/presets.md`.
