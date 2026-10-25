# Planning output contract

After `/planning` approves a plan (`Status: approved`), print this block verbatim, filled in:

```text
Plan: docs/plans/{slug}/plan.md  (Status: approved · review {score}/10 · {n} rounds)
Map:  docs/plans/{slug}/codebase-map.md  (Blast radius: N symbols · M callers · K test files)
Requirements: {n} ACs · {s} SEC ACs · Tasks: {t} rows · Test Case rows: {r}
Open questions left: {none | list}

Next steps:
  → /code docs/plans/{slug}/plan.md   — implement it (choose the run mode there)
  → /grill-me                         — stress one decision further before coding

This skill does not start implementation.
```

Print the plan-reviewer's result under `## 🔎 plan-reviewer — Plan Review  [Score: X/10]`.
