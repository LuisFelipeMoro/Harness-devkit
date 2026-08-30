# Migration Test, Falsification, and Pre-Handoff Checklist

## Specify the four assertions, then write SQL, then test and falsify

Before writing any migration SQL, write down the four things the test will assert (below).
Write the up/down SQL, then the test. Finally **falsify it**: run the test against the
pre-migration schema — or comment out the body of `up` — and confirm every assertion fails,
then restore. A migration test that stays green without the migration proves nothing, and
that is the failure mode a test written after the SQL falls into.

The test asserts, against a throwaway database seeded to production-like shape (Testcontainers, an ephemeral schema, or a transaction rolled back at teardown):

1. **Up applies**: after running the `up` migration, the new schema state exists (column/index/constraint present, type correct, nullability correct).
2. **Down reverses**: after running the `down` migration, the schema is byte-for-byte back to the prior state (no orphan objects).
3. **Idempotency**: running `up` twice does not error (the `IF NOT EXISTS` / `IF EXISTS` guards hold).
4. **Data safety** (when backfilling): existing rows get the expected values; no row is lost or corrupted.

```go
// migration_0042_test.go — asserts the contract specified before 0042_add_external_ref.sql
func TestMigration0042_UpAddsColumn_DownRemovesIt(t *testing.T) {
    db := newEphemeralDB(t)            // Testcontainers / template DB
    require.NoError(t, migrateUp(db, 42))
    require.True(t, columnExists(db, "orders", "external_ref"))  // falsify: run with `up` body
                                                                 // commented out — must FAIL
    require.NoError(t, migrateDown(db, 42))
    require.False(t, columnExists(db, "orders", "external_ref"))
}
```

Only once this test fails for the right reason do you write the SQL, then re-run to GREEN.

## Pre-handoff checklist

- [ ] The four assertions were specified before the SQL was written
- [ ] Migration test falsified — run against the pre-migration schema, every assertion observed to FAIL, then restored
- [ ] Down migration fully reverses the up migration
- [ ] No column drop and replacement in the same file
- [ ] Large table DDL uses `CONCURRENTLY` or explicit lock timeout
- [ ] Migration is idempotent (`IF NOT EXISTS` / `IF EXISTS` guards)
- [ ] Migration has been tested on a copy of prod data volume (or noted if not)
- [ ] App code is backward-compatible with both old and new schema during rollout
