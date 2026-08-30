---
name: observability
description: Add structured logging, metrics, or distributed tracing to a service, covering Go (zap + OpenTelemetry) and TypeScript (pino + OpenTelemetry) with enforced log-field standards and trace-context propagation. Trigger phrases — "logging", "metrics", "tracing", "observability", "instrument", "OpenTelemetry", "structured logs", "monitoring".
---

Instrumentation is behaviour: write the field/span contract down first, instrument, then assert that contract in a test and falsify it by removing the field. Every error log must carry `request_id` + `trace_id`, and PII, secrets, and tokens must never appear in any field.

## Contract
- Input: a Go or TypeScript service that needs logging, metrics, or tracing.
- Output: instrumentation plus a falsified test asserting its field/span contract, matching the standards and code in `references/logging-and-tracing.md`.
- Tool boundary: the contract under test is field presence, absent secrets, and span name/attributes — never exact log formatting.
- Done when: the test passes, each assertion has been falsified by removing its field/attribute, and the checklist in `references/test-and-checklist.md` holds.

## Steps
1. Scope the work: logging only, or metrics + tracing too? Go or TypeScript (or both)? Greenfield, or extending existing instrumentation?
2. Write down the intended field/span contract (which fields, which span name + attributes, which secrets must be absent) — this is what the test will assert, per `references/test-and-checklist.md`.
3. Add structured logging from `references/logging-and-tracing.md` — Go zap or TypeScript pino, with the required fields and the no-PII rules.
4. Add OpenTelemetry tracing from `references/logging-and-tracing.md` — a span around each outbound request, `RecordError` before returning, `defer span.End()`.
5. Propagate `context.Context` through the request chain (Go) per `references/logging-and-tracing.md`.
6. Write the test asserting the Step 2 contract against an in-memory sink, then falsify each assertion (remove the field/attribute, confirm FAIL, restore), then confirm the checklist.

## References
- `references/logging-and-tracing.md` — Go/TS logging, OpenTelemetry tracing, context propagation, field rules.
- `references/test-and-checklist.md` — the contract-assertion test, its falsification step, and the completion checklist.
