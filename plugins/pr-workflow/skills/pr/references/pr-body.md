# PR body

Skip preambles; keep prose brief; use the project's own domain words. Write the body to
`$TMPDIR/pr-body.md` and pass it with `--body-file` — never inline it in a shell string.

```markdown
## Summary

<the smallest view that makes the change clear: diagram, pseudocode, diff sketch or tree>

<one or two sentences of why, if the view does not carry it>

## Evidence

- **Before:** <failing test run / output / screenshot>
  **After:** <passing test run / output / screenshot>
- **Gates:** <the overall line /validate-code printed — omit the bullet if /validate-code did not run>

## Merge Danger

**Door:** <one-way | two-way> — <optional: why>

**Blast Radius:** <one word> — <the ramifications of merging: who and what this can break>

**Plan:** `docs/plans/{slug}/plan.md` (as a link to the file on the branch)   <!-- only when a plan exists -->
```

## Summary — pick the smallest view

Choose the one view (occasionally two) that answers "what changed?" fastest; place each visual next to
the sentence it supports and keep only the calls, files, states and boundaries that matter.

- **Pseudocode** for logic or an algorithm:
  ```text
  on(save)
    if content unchanged → return cached result
    write content; return fresh result
  ```
- **Call tree** for runtime control flow:
  ```text
  submitOrder
    validateCart
    reserveStock
    chargePayment
  ```
- **Shallow file tree** for file responsibilities or a broad refactor:
  ```text
  internal/cart/
  ├── store.go     # owns persistence
  └── total.go     # pricing rules
  ```
- **Mermaid** (`sequenceDiagram`, `flowchart`) when components talk to each other.
- **`diff` sketch** when the surrounding shape already exists and the point is what moved — shaped like the topic (a call tree, a file tree, a state machine), not like the real patch:
  ```diff
   submitOrder
     validateCart
  +  applyCoupon
     chargePayment
  ```
- The **whole block** only when most of it is new or the reader needs a copyable target shape.

## Evidence — before and after

- **Screenshots** first when the change is visual and the environment can capture them.
- Otherwise **execution evidence**: the exact test that failed and now passes (name + the quoted
  failing line, then the passing line), a command's output before and after, a timing.
- A `/bugfix` PR states the **confirmed hypothesis** here, so the next debugger learns from it.
- The **gate line** is quoted as `/validate-code` printed it in this session — never re-run, never
  paraphrased, never invented. No `/validate-code` in the session → drop the bullet, do not write "passing".

## Merge Danger

- **Door** — a **two-way** door can be walked back cheaply (revert the commit and nothing is lost);
  a **one-way** door cannot: a destructive migration, a published API or event shape, deleted data,
  a sent notification, a key rotated. Say which, and why when it is one-way.
- **Blast Radius** — one word (`isolated` · `module` · `service` · `consumers` · `platform`), then the
  ramifications: callers or consumers that can break, performance or layout shift, config or deploy
  ordering, mobile, migrations. Take it from the plan's blast radius when one exists.

## Plan link

When `docs/plans/{slug}/plan.md` exists for the branch, link it, so the reviewer can check the change
against its ACs (`/review-code` reads it as the Spec axis).

Credits: the Summary / Evidence / Merge Danger template is adapted from ideas in mattpocock/skills,
whose Summary visual menu in turn credits Dex Horthy's `show-me` skill (humanlayer).
