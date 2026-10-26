# Architecture review reference

## Phase 1 — Map sub-agent call

Dispatch one read-only Explore sub-agent on `haiku`:

```text
Agent(
  subagent_type: "Explore",
  model: "haiku",
  prompt: "Map [cwd]. Return:
  1. Module/package dependency list (what imports what)
  2. Files >300 lines with line count
  3. Domain logic found in transport/DB/cache layers (file:line)
  4. 3+ callers of identical logic with no shared abstraction
  5. Circular or unexpected cross-feature imports
  6. Shallow modules: functions/types that mostly forward to one other call, or whose
     parameters and error modes are nearly as complex as their body (file:line)
  Keep each list under 20 entries. Raw observations only — no analysis."
)
```

## HTML report scaffold

Write the report to `/tmp/arch-report-<YYYY-MM-DD>.html`. Use a self-contained
HTML5 document with embedded CSS. Group findings by severity (Critical, High,
Medium, Low); each finding shows severity, `file:line` location, and a concrete
recommendation, worded in the deep-module vocabulary of `references/deep-modules.md`
(module · interface · depth · seam · adapter · leverage · locality).

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Architecture Report — <date></title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 2rem; }
    .critical { color: #b00020; }
    .high { color: #d35400; }
    .medium { color: #b8860b; }
    .low { color: #555; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; }
  </style>
</head>
<body>
  <h1>Architecture Report — <date></h1>
  <!-- one <section> per severity, each with a findings table -->
</body>
</html>
```

## ADR template

For each Critical/High finding the user chooses to address, offer
`docs/adr/ADR-NNN-title.md`:

```markdown
# ADR-NNN: <title>

## Status
Proposed

## Context
[The architectural problem and where it lives — file:line]

## Decision
[What will change]

## Consequences
[Trade-offs, follow-up work, and the characterization test that pins behaviour]
```
