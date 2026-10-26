# Codebase map — procedure (shared by `/map` and `/planning`)

The mapper is a read-only Explore agent on `haiku`. It reports what exists; it never proposes a design.
A plan drawn without this map designs against an empty repository, which is where duplicated
components come from.

## Dispatch

```text
Agent(subagent_type: "Explore", model: "haiku", description: "map {topic}",
  prompt: "Read-only. Map the code relevant to: {topic}. Follow skills/map/references/map-procedure.md
  (sections + blast-radius rules). Return the seven sections as markdown tables, every entry cited
  file:line, ≤ 150 rows total. No design opinions.")
```

Two or more independent areas (separate services, plugins, packages): one mapper per area, within the
read-only width in `references/thresholds.md`, each returning tables. The skill merges them into the one
file; mappers never write it.

## Sections (all seven, in order — an empty one says so: `none — greenfield package`)

| Section | Contents |
|---|---|
| Blast radius | every existing symbol the change will touch, with every caller (rules below) |
| Reusable symbols | helpers, types, constants, validators, clients, middleware — `file:line — signature — what it does` |
| Prior art | features solving a similar problem, even partially; the near-miss is the duplication risk |
| Conventions | naming, error wrapping, dependency injection, context threading, layering — one `file:line` exemplar each |
| Extension points | interfaces, registries, hooks, config surfaces to plug into instead of a parallel path |
| Contracts in force | signatures, error shapes, table/column names, config keys the change must not contradict |
| Test conventions | where tests live, framework, fixture/mock style, naming |

## Blast radius rules

This row is a measurement, not a guess; it decides the size of the work.

- **Enumerate, do not estimate.** LSP find-references for every symbol to change; grep only where LSP
  cannot reach (templates, config keys, reflection, string-built queries, cross-language boundaries).
- **Every caller gets a line**: `file:line — what it assumes — does the change hold for it?`
- **One hop past direct callers** for any change to an error value, nil-ness, ordering or type width.
- **Count non-code callers**: serialized payloads, DB columns, migrations, API consumers, feature flags,
  dashboards, alert queries, generated clients.
- **Name the tests that will need to change.** Thirty test edits is a design signal.
- **State the total**: `Blast radius: N symbols · M callers · K test files · {wire/schema surfaces}`.
- **An empty blast radius is a finding** — say so explicitly; it usually means the search was too narrow.

## Output file

`docs/plans/{slug}/codebase-map.md`:

```markdown
# Codebase map — {topic}
Mapped: {date} · Base: {short sha} · Scope: {paths searched}
Blast radius: N symbols · M callers · K test files · {surfaces}

## Blast radius
| Symbol | Caller (file:line) | Assumes | Holds? |
...one `##` per section, tables as above...
```

Rules: every entry cites `file:line` (an uncited claim is not a finding) · report absence explicitly ·
never recommend.
