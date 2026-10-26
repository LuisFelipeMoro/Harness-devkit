# Deep-module vocabulary

Read when naming or ranking a finding. Every finding in the report uses these terms exactly — not
"component", "service", "API" or "boundary" — so findings compare with one another and with the next
report. The aim of a deepening is **leverage** for callers, **locality** for maintainers, and a test
surface that is the interface itself.

## Terms

| Term | Meaning |
|---|---|
| **Module** | Anything with an interface and an implementation — a function, a type, a package, a slice across tiers. Scale-agnostic on purpose. |
| **Interface** | Everything a caller must know to use the module correctly: the signature, and also its invariants, ordering constraints, error modes, required configuration and performance characteristics. Wider than the language's `interface` keyword or a type's public methods. |
| **Implementation** | The body behind the interface. |
| **Depth** | Leverage at the interface: how much behaviour a caller (or a test) gets per unit of interface it has to learn. **Deep** = a lot of behaviour behind a small interface; **shallow** = an interface nearly as complex as what it hides. Measured as leverage, never as a ratio of implementation lines to interface lines (that rewards padding). |
| **Seam** | A place where behaviour can be altered without editing in that place — the location where a module's interface lives. Where the seam goes is its own decision, separate from what sits behind it. A module may have **internal seams** (private, used by its own tests) as well as the **external seam** at its interface. |
| **Adapter** | A concrete thing that satisfies an interface at a seam. Names a role (which slot it fills), not its size: an in-memory fake is a small adapter, a database repository a large one. |
| **Leverage** | What callers gain from depth: more capability per unit of interface learned; one implementation pays back across N call sites and M tests. |
| **Locality** | What maintainers gain from depth: change, bugs, knowledge and verification concentrate in one place instead of spreading across callers. Fixed once, fixed everywhere. |

## Principles a finding can cite

- **The deletion test.** Imagine deleting the module. If its complexity vanishes, it was a pass-through (shallow — a deepening candidate). If the complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.** Callers and tests cross the same seam. Tests that must reach past the interface mean the module is the wrong shape.
- **One adapter is a hypothetical seam; two adapters make it real.** A seam with a single adapter (and no test adapter) is indirection — cf. CD2 / PE14.
- **Depth is a property of the interface, not the implementation.** A deep module can be built from small swappable parts; they just are not part of its interface.

## Deepening opportunities — what to look for

- Understanding one concept means bouncing between many small modules.
- An interface nearly as complex as its implementation (shallow), or a module that only forwards.
- Pure functions extracted only for testability while the real bugs hide in how they are called (no locality).
- Tightly coupled modules leaking across their seam — callers knowing ordering or internals (PE3, PE4).
- Code that is untested, or testable only past its interface (PE10).

Classify the candidate's dependencies, because the category decides how the deepened module is tested at its seam:

| Dependency | Deepening |
|---|---|
| In-process (pure computation, in-memory state) | Merge and test through the new interface directly; no adapter |
| Local-substitutable (a local stand-in exists: in-memory filesystem, embedded database) | Test with the stand-in; the seam stays internal |
| Remote but owned (your own services across a network) | A port at the seam: production adapter (HTTP/gRPC/queue) + in-memory test adapter |
| True external (third-party) | Inject it as a port; tests use a fake adapter |

Testing after a deepening **replaces, never layers**: tests at the new interface take over, and the old
tests on the shallow modules become waste to delete in the same plan.

## Writing the finding

`[Severity] <module> — shallow | leaking seam | no locality — file:line. Cost: <the future change it makes harder>. Deepening: <what moves behind which seam>; leverage: <what callers stop knowing>; locality: <where change concentrates>; tests: <what the new test surface is>.`

Rank deepening findings by the leverage and locality they buy on code that changes often (`git log --format= --name-only | sort | uniq -c | sort -rn | head`) — a deep module nobody edits pays back nothing.

## Design it twice (when the user picks a finding to explore)

The first interface idea is rarely the best (Ousterhout). Before recommending one, sketch 2–3
**radically different** interfaces for the deepened module, in the main session — each under a
different constraint: the smallest interface (1–3 entry points), the most flexible, the one that makes
the most common caller trivial, and — when a dependency is remote or external — ports & adapters. For
each: the interface (types, invariants, error modes), one caller's usage, what hides behind the seam,
the adapters, and where leverage is high or thin. Compare them by depth, locality and seam placement,
then recommend one — or a hybrid — and say why.

Credit: adapted from ideas in mattpocock/skills.
