# Skill scaffold templates

## File structure

In this devkit (a plugin skill):

```text
plugins/<plugin>/skills/<name>/SKILL.md              # ≤60 lines — steps + the rules every branch needs
plugins/<plugin>/skills/<name>/references/<topic>.md # disclosed reference, read at the step that names it
```

In a project-local install:

```text
.claude/skills/<name>.md                 # ≤60 lines — the only file Claude reads
.claude/references/<name>-reference.md   # overflow: tables, templates, specs
```

Link overflow from the SKILL.md at the step that needs it: `At this step, read references/<topic>.md.` — a pointer that names its trigger, never a bare `See … for [topic].` at the bottom.

## Frontmatter

```yaml
---
name: kebab-case-name
description: '[One sentence: what it does]. Usage: /name [args], e.g. "/name example".'
disable-model-invocation: true
---
```

Description: one sentence plus `Usage:`; no trigger phrases (the skill is manual).
Always quote the value so colons inside it stay valid YAML.

## Body structure

```markdown
[One-sentence core rule]

## [Phase — Name]
Input: [...]
Output: [...]
Boundary: does NOT [...]

1. **Step.** What to do. At this step, read `references/<topic>.md` (only if this step needs it). Done when [checkable condition].
2. **Step.** What to do. Done when [checkable condition].

Next: `/other-skill` [why the user might start it now].

## Anti-patterns
- Don't [X] because [Y]
```
