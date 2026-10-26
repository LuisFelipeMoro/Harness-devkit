---
name: write-a-skill
description: 'Scaffold a new skill with a clear input, output and boundary per phase. Usage: /write-a-skill [args], e.g. "/write-a-skill changelog-writer".'
disable-model-invocation: true
---

Every skill is a focused playbook for one problem. Define input, output, and boundary before writing.

## Rules

- Frontmatter: `disable-model-invocation: true` and a one-sentence description ending in `Usage: /name [args], e.g. "..."` — skills are started by the user, never auto-routed; a skill never invokes another skill, it may only suggest a next one.
- Each phase must declare Input, Output, and Boundary.
- No phase should produce raw tool output — always compact before handing off to the next phase.
- Keep the SKILL.md ≤60 lines; move tables, templates, and examples into `references/`.
- Keep the description to one sentence (~40 tokens): no trigger-phrase lists, since nothing is auto-routed.
- Every step ends on a completion criterion the agent can check ("Done when …"); every reference is reached by a pointer at the step that needs it ("At this step, read …"), front-loaded with its trigger — one trigger per branch.
- Inline what every branch needs; disclose behind a pointer what only some branches reach; keep each concept's rules and caveats under one heading.
- End with a `Next:` line suggesting the skill the user might start after this one.

## Pre-flight

Answer all four before writing:
- **Problem**: What failure mode does this skill prevent?
- **Trigger**: What does the user type to start it? (the `Usage:` example)
- **Input**: What does the user provide? What does the skill read?
- **Output**: What does the user receive? What files are written?

## Scaffold

Use the file-structure, frontmatter, and body templates in `references/skill-template.md`.

## Write the body

At this step, read `references/writing-for-agents.md` (context pointers, context vs cognitive load, the information hierarchy, progressive disclosure by branch, co-location, sprawl, completion criteria). Then place every piece on its rung — in-file step, in-file reference, or disclosed reference behind a pointer — and give each step its completion criterion. Done when every step has a checkable criterion, every `references/` file is named by exactly one step or load-on-demand row, and `SKILL.md` is ≤ 60 lines.

## Validate (before declaring done)

After scaffolding, run the new skill through SkillSpec and act on what it finds:

1. Run `skillspec doctor <new-skill-dir>` (skip only if `skillspec` is not installed or cannot execute — say so explicitly, and fall back to `.github/scripts/validate-wiring.py`).
2. Read the findings. For each CRITICAL/HIGH — and any MEDIUM you can resolve without changing behavior — adapt the SKILL.md: fix the frontmatter/description, declare dependencies, defer heavy text to `references/`, label code fences, move late obligations up.
3. Re-run `skillspec doctor` and repeat until findings stop dropping without harming the skill.

The skill is **not done** until SkillSpec has run — or, when `skillspec` is not installed or cannot execute, until `.github/scripts/validate-wiring.py` has run in its place — and the actionable findings are resolved or explicitly justified. See `references/skillspec-validation.md` for the finding-to-fix map.

Next: `/review-code` on the new skill's diff, then `/pr`.
