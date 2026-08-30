# Asserting Instrumentation and Checklist

## Specify the contract, instrument, then assert and falsify

Instrumentation is behaviour, so it gets a real test — but like all non-bug-fix work in this
devkit the test is written **after** the instrumentation, against a contract written **before**
it. Name the fields/span you intend to emit, add the instrumentation, then write a test that
asserts that contract using an in-memory sink (no real backend needed). Finally **falsify it**:
delete the `request_id` field (or the span attribute) and confirm the test fails, then restore.
A logging test that passes with the field removed is asserting nothing.

```go
// Go — zaptest/observer captures emitted log entries
core, logs := observer.New(zap.ErrorLevel)
logger := zap.New(core)
processOrder(ctxWith(requestID, traceID), logger, "order-123")
entry := logs.All()[0]
require.Equal(t, "failed to process order", entry.Message)
require.Equal(t, requestID, entry.ContextMap()["request_id"])    // falsify: drop this field from the
                                                                 // logger call — this line must fail
require.NotContains(t, entry.ContextMap(), "password")           // assert no secret leaked

// Go — tracetest.NewInMemoryExporter() asserts a span was recorded with attributes
// TS — pino: pass a stream that collects lines; assert JSON has requestId/traceId, no PII
```

Assert the **contract** (fields exist, secrets absent, span created with the right name/attributes), not exact formatting. Every assertion must have a break that falsifies it — if removing a field or attribute leaves the test green, the test is decorative.

## Checklist

- [ ] The field/span contract was written down before instrumenting, and a test now asserts it
- [ ] Each assertion falsified — the field/attribute was removed, the test observed to FAIL, then restored
- [ ] Logger initialized once at startup, injected via context or constructor
- [ ] Every error log includes `request_id` + `trace_id`
- [ ] No PII/secrets/tokens in any log field
- [ ] Spans created for every external call (DB, HTTP, queue)
- [ ] `span.RecordError(err)` called before returning errors
- [ ] Context propagated through entire call chain without breaking
- [ ] `defer span.End()` called immediately after span creation
