---
name: write-a-skill
description: 'Use when creating a new skill. Scaffolds proper structure with clear input/output/boundary per phase. Skill files must be concise — under 100 lines, overflow to references/. Trigger phrases: "write a skill", "create skill", "add skill", "new skill", "scaffold skill".'
---

Every skill is a focused playbook for one problem. Define input, output, and boundary before writing.

## Rules

- Each phase must declare Input, Output, and Boundary.
- No phase should produce raw tool output — always compact before handing off to the next phase.
- Keep the SKILL.md ≤100 lines; move tables, templates, and examples into `references/`.
- The description must state, in third person, what the skill does and when it fires.
- Trigger phrases: at least one, no upper bound — the Tier-1 token budget below is the real constraint.
- Keep the description under ~150 tokens (Tier-1 budget).

## Pre-flight

Answer all four before writing:
- **Problem**: What failure mode does this skill prevent?
- **Trigger**: What user phrases invoke it? (at least one, no upper bound)
- **Input**: What does the user provide? What does the skill read?
- **Output**: What does the user receive? What files are written?

## Scaffold

Use the file-structure, frontmatter, and body templates in `references/skill-template.md`.

## Validate (before declaring done)

After scaffolding, run the new skill through SkillSpec and act on what it finds:

1. Run `skillspec doctor <new-skill-dir>` (skip only if `skillspec` is not installed or cannot execute — say so explicitly, and fall back to `.github/scripts/validate-wiring.py`).
2. Read the findings. For each CRITICAL/HIGH — and any MEDIUM you can resolve without changing behavior — adapt the SKILL.md: fix the frontmatter/description, declare dependencies, defer heavy text to `references/`, label code fences, move late obligations up.
3. Re-run `skillspec doctor` and repeat until findings stop dropping without harming the skill.

The skill is **not done** until SkillSpec has run — or, when `skillspec` is not installed or cannot execute, until `.github/scripts/validate-wiring.py` has run in its place — and the actionable findings are resolved or explicitly justified. See `references/skillspec-validation.md` for the finding-to-fix map.
