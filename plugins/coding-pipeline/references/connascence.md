# Connascence and cohesion — the shared modularity vocabulary

Read this when naming a modularity finding (`/improve-codebase-architecture`) or judging PE16 (`agents/reviewer.md`). It is the one definition of these terms; both cite it and neither redefines them.

## Terms

| Term | Meaning |
|---|---|
| Cohesion | How strongly the responsibilities inside one module belong together; a module that changes for unrelated reasons has low cohesion. |
| Coupling | How much one module depends on another; the more it depends, the further one change spreads. |
| Afferent coupling (fan-in) | The number of other modules that depend on this one. |
| Efferent coupling (fan-out) | The number of other modules this one depends on. |
| Connascence | Two components are connascent when a change in one requires a matching change in the other to keep the whole correct. |
| Strength | How hard a form of connascence is to notice and to change; stronger forms need their parts closer together. |
| Locality | How close the connascent parts sit in the code. |
| Degree | How many places share the coupling; more places means a higher priority to fix. |

## Forms

Static forms are visible in the source text; dynamic forms appear only when the code runs.

| Form | Static/Dynamic | What must change together | Detectable sign | Filed by |
|---|---|---|---|---|
| Connascence of Name | Static | Every user of a name must change when the name changes | The same identifier is spelled in several files | Mysterious Name smell (`code-smells.md`) |
| Connascence of Type | Static | Every user must change when a type or field layout changes | Two callers rely on the same field layout | PE6 |
| Connascence of Meaning | Static | Every user must agree on what a value means | A magic number or string with no name is repeated | Maintainability magic numbers (`reviewer.md`) |
| Connascence of Position | Static | Every caller must agree on argument order | `f(a, b, c)` still compiles when two arguments are swapped | PE5 |
| Connascence of Algorithm | Static | Every user must use the same algorithm | The same rule (parse, hash, validation) is implemented in two places | RD1/RD2 inside one diff; PE16 across a boundary |
| Connascence of Execution | Dynamic | Operations must run in a fixed order | `init()` then `start()` with nothing enforcing the order | PE4 |
| Connascence of Timing | Dynamic | Operations must happen within a fixed time window | A sleep or timeout assumed to be long enough | `agents/stress.md` |
| Connascence of Value | Dynamic | Several values must change together | Two fields updated in one place must stay consistent | PE3 |
| Connascence of Identity | Dynamic | Components must reference the same entity | Two parts share one mutable object or one row | PE7 |

## Strength, locality, degree

Strength runs weakest to strongest: Name < Type < Meaning < Position < Algorithm < Execution < Timing < Value < Identity. Refactor toward the weaker forms; the stronger the form, the closer together its parts must live.

Connascence that crosses a module boundary weighs more than the same form inside one module, because the coupled parts then have different owners and change for different reasons, which makes them easy to miss. Name and Type across a boundary are how modules talk, so PE16 never files them; the same form inside one module stays at its own row.

Degree is the number of places that must change together. More places means a higher priority.

## Locality, two sides

Connascence locality is how close the connascent parts sit. Deep-module locality, from the deep-module vocabulary the `improve-codebase-architecture` skill uses, is the same goal seen from the module side: keep what changes together inside one module behind a small interface. Moving a strong form's parts together and pulling a shallow module's callers' knowledge inward both shorten the distance a change must travel.

## Credit

Mark Richards & Neal Ford, *Fundamentals of Software Architecture*, ch. 3 (cohesion, coupling, connascence). The term connascence comes from Meilir Page-Jones.
