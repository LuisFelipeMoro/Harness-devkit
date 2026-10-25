# Execution Order and Report Format

## Execution order (fail-fast by default; `/validate-code` is report-only, so it runs every gate in this order and reports all results)

1. Format check *(fastest)*
2. Type check / vet / static analysis
3. Lint
4. Build — the project must actually build (`next build` / `vite build` / `go build` / `cargo build` / `mvn compile`, etc.); type-check alone does not catch bundler/compiler-only failures. FAIL blocks everything after it.
5. Tests + coverage — the mandatory test-runner sensor; every changed source file should have a corresponding test. Coverage below threshold = FAIL, but treat coverage as a floor: a green run at high coverage is not evidence the tests can fail. Spot-check that the tests for changed behaviour assert observable results rather than restating the implementation.
6. Race detector *(Go only)*
7. Vulnerability scan *(network — last)*

For common fixes per gate failure, see `references/quality-gate-reference.md`.

## Report format

```text
## Quality Gate Report — {Stack}

| Gate     | Status  | Details                               |
|----------|---------|---------------------------------------|
| vet      | ✅ PASS | —                                     |
| lint     | ❌ FAIL | handler.go:42 — unhandled error       |
| coverage | ✅ PASS | 87.3% (≥ 85%)                        |
| modernize | ADVISORY | 3 files — reported, never counts toward Overall |

Overall: ❌ FAIL — 1 gate failed. Fix before handoff.
```

Advisory rows (Go `modernize`) report `ADVISORY` or `skipped` and never count toward Overall.

Full pass line: `Overall: ✅ PASS — all gates green · {X}% coverage · {N} tests`
