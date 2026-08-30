---
name: analysis
description: Use when you need to analyze requirements, assess code state, or evaluate context — runs Analyst then PM to produce product-brief.md and PRD.md without architecture or execution steps.
---

Run BMAD v6 analysis phase (Analyst + PM only). If no task is provided, ask first.
Load agent files on demand — never pre-load both at once. Use `references/output-format.md` section headers for all agent output.

> **Scope**: requirements analysis only — no architecture decisions, no Language column, no sub-task decomposition.
> To create an execution plan from this output, run `/planning`.
> To implement end-to-end (includes planning), run `/multi-agent-coding-pipeline`.

---

## Step 1 — Analyst (Mary)

Load `agents/analyst.md`. Run against the task description.

- Include: language context, security constraints, business goals
- Output: **`docs/deliveries/{key}/product-brief.md`** (show in full) — derive the slug + key from the feature name per `references/delivery-and-worktree.md`; a root-level `product-brief.md` would be clobbered by the next delivery

---

## Step 2 — PM (John)

Load `agents/pm.md`. Run against the Brief from Step 1.

- Security ACs are mandatory for any I/O, auth, or data-handling epic
- Output: **`docs/deliveries/{key}/PRD.md`** (show in full)

---

## Step 3 — Epic Summary

Extract every epic from the PRD and display the **Epic Summary**:

| Epic | Tasks | Acceptance Criteria | Security ACs |
|------|-------|---------------------|--------------|
| Epic N: {title} | T{N}.1: {imperative}, T{N}.2: … | AC1, AC2, … | SEC-1, … (or —) |

After showing the summary, print the closing block from [references/output-contract.md](references/output-contract.md).

---


---

Behavior contract: [skill.spec.yml](skill.spec.yml) · dependency ledger: [deps.toml](deps.toml).
