# Code-smell baseline (Standards axis)

A fixed set of code smells from Fowler's *Refactoring* (ch. 3) that the reviewer applies on the
**Standards** axis even when the repository documents no standards of its own. Loaded by
`agents/reviewer.md` when the diff adds or changes non-test source code.

Three rules bind it:

- **The repository overrides.** A documented repo standard (`CONTRIBUTING.md`, `CODING_STANDARDS.md`,
  the repo's own `AGENTS.md`/`CLAUDE.md`, a style guide under `docs/`) always wins; where it
  endorses something a smell below would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic — *"possible Feature Envy"* —
  never a hard violation, and never blocks on its own. Default severity MINOR; it rises only by
  passing the reviewer's cost test the same way any other finding does.
- **Skip what tooling enforces.** A smell a linter rule in the repo's config already catches is
  the linter's, not the review's.

Where a smell coincides with a numbered row, file it under that row, which carries the severity:
Duplicated Code → RD2/RD4 · Primitive Obsession → PE6 · Speculative Generality → PE14/CD2 ·
Divergent Change → PE2. The smell label is for what no row names.

| Smell | What it is | Fix |
|---|---|---|
| **Mysterious Name** | A function, variable or type whose name does not say what it does or holds | Rename it; if no honest name comes, the design is murky — say so |
| **Duplicated Code** | The same logic shape in more than one hunk or file of the change | Extract the shared shape and call it from both |
| **Feature Envy** | A method that reaches into another object's data more than its own | Move the method onto the data it envies |
| **Data Clumps** | The same few fields or parameters keep travelling together — a type wanting to be born | Bundle them into one type and pass that |
| **Primitive Obsession** | A primitive or string standing in for a domain concept that deserves its own type | Give the concept its own small type |
| **Repeated Switches** | The same `switch` / `if`-cascade on the same type recurs across the change | Replace with polymorphism, or one map both sites share |
| **Shotgun Surgery** | One logical change forces scattered edits across many files in the diff | Gather what changes together into one module |
| **Divergent Change** | One file or module edited for several unrelated reasons | Split it so each module changes for one reason |
| **Speculative Generality** | Abstraction, parameters or hooks added for needs the spec does not have | Delete it; inline back until a real need shows |
| **Message Chains** | Long `a.b().c().d()` navigation the caller should not depend on | Hide the walk behind one method on the first object |
| **Middle Man** | A class or function that mostly just delegates onward | Cut it; call the real target directly |
| **Refused Bequest** | A subclass or implementer that ignores or overrides most of what it inherits | Drop the inheritance; use composition |

Report line: `[MINOR] file:line — possible <Smell>: <the hunk, quoted briefly>. Fix: <the fix>. Cost: <the change it makes harder>.`

Credit: the smell list and the two-axis review shape are adapted from ideas in mattpocock/skills.
