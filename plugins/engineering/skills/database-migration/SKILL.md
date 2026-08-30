---
name: database-migration
description: Write or review a database migration safely with additive-only forward changes, a mandatory reversible down migration, zero-downtime patterns for large tables, and lock-acquisition analysis. Trigger phrases — "migration", "schema change", "add column", "alter table", "add index", "backfill", "drop column", "rename column".
---

A migration must be additive-only in one file, must ship a down migration that fully reverses the up, and must never drop-and-replace or rename a column directly. Any DDL on a table over 1M rows must carry a lock strategy.

## Contract
- Input: a requested schema change against a known database.
- Output: an up/down migration pair plus a falsified migration test, following the patterns in `references/migration-patterns.md`.
- Tool boundary: schema-only changes; expand-contract spreads risky changes across separate deploys, never one file.
- Done when: the four assertions are specified up front, the migration and its test are written, the test is falsified against the pre-migration schema, and the pre-handoff checklist passes.

## Steps
1. Classify the change against the risk table in `references/migration-patterns.md` to pick a strategy.
2. Specify the four assertions the test will make — up applies, down reverses, up is idempotent, data is safe — before writing SQL. They are enumerated in `references/test-and-checklist.md`.
3. Write the up/down SQL from the matching template in `references/migration-patterns.md`.
4. Write the migration test asserting those four things, then **falsify it**: run it against the pre-migration schema (or comment out the `up` body) and confirm each assertion fails, then restore. A migration test that passes without the migration is asserting nothing. Worked example in `references/test-and-checklist.md`.
5. For large tables, apply `CONCURRENTLY` or an explicit session lock timeout per `references/migration-patterns.md`.
6. Confirm the pre-handoff checklist in `references/test-and-checklist.md` before handing off.

## References
- `references/migration-patterns.md` — principles, change-classification table, up/down templates, large-table and lock-timeout patterns.
- `references/test-and-checklist.md` — the four assertions, the migration test, its falsification step, and the pre-handoff checklist.
