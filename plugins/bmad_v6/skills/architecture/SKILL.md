---
name: architecture
description: Use when designing architecture for a domain or feature outside the full BMAD pipeline. Produces tech stack, security architecture, component design, ADRs, and Mermaid data-flow diagram.
---

# Architecture Design (Standalone)

Act as Winston (Staff Architect). Design architecture for a domain or feature without the full BMAD pipeline.

Behavior contract: [skill.spec.yml](skill.spec.yml) · dependency ledger: [deps.toml](deps.toml) · section templates: [references/sections.md](references/sections.md).

## Contract

- **Input**: a domain or feature; optionally tech stack, key requirements, constraints.
- **Output**: `docs/deliveries/delivery-{slug}-{key}.md` — all ten sections from [references/sections.md](references/sections.md), in order, real interfaces/types only.
- **Boundary**: design only; this skill writes no implementation code.
- **Rules (apply throughout)**: security section is mandatory; every ADR carries a "Rejected alternatives" entry; a component over ~200 lines is split; every component exposes a testable seam (untestable designs are rejected); the Mermaid diagram compiles; verify every library version and API shape with context7 before specifying it; stress the design with `/grill-me` before any code and resolve or escalate every open question — none deferred into implementation.

## Steps

1. Confirm the domain/feature and any stated stack, requirements, or constraints. Derive the slug + key from the feature name and write output to `docs/deliveries/delivery-{slug}-{key}.md` with the required header block, per [../../references/delivery-and-worktree.md](../../references/delivery-and-worktree.md) — the planning pipeline resolves it by key. Never write a bare `architecture.md`: that filename belongs to the host repo.
2. Draft sections 1–2 (Context, Tech Stack) from [references/sections.md](references/sections.md).
3. Draft section 3 (Security Architecture) — the OWASP threat matrix; add the OWASP LLM Top 10 matrix when AI/LLM components are present.
4. Draft sections 4–6 (Component Design with testable seams, Data Model, API Contracts that match the interfaces).
5. Draft sections 7–9 (Mermaid data flow per [references/data-flow-example.md](references/data-flow-example.md), Error Handling, Observability).
6. Draft section 10 (ADRs) — one per non-obvious choice, each with rejected alternatives.
7. Stress the result with `/grill-me`; fold resolved gaps back into the document, escalate the rest to the human.
