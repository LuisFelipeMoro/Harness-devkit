# Latency Budget — Trace First, Fix by Layer

Use when latency is spread across layers or services rather than one hot function (that case is pprof — SKILL.md steps 1-3). This file sets no millisecond thresholds: the target comes from the service's SLO or the PRD.

## Trace first

Instrument each boundary per `/observability`: the handler, the data store, each outbound call, and each queue publish. Take the trace of one slow request and fill a table:

| Layer | Span | Observed | Share of total |
|-------|------|----------|----------------|

The largest share is the first candidate. Do not pick a fix before the table is filled: a layer that looks slow in code may be a small share of the trace.

## Fix by layer

Work the table biggest share first. Map each layer to its lever, and follow the link to the matching row in [optimize-and-benchmark.md](optimize-and-benchmark.md):

- Service calls: remove, batch, or parallelize (the chained-calls row).
- Data store: index, remove N+1, or resize the pool (the connection and N+1 rows).
- Repeated reads: cache with a named owner and invalidation (the cache row).
- Payload: paginate or compress (the large-responses row).
- Non-critical work: move it off the request path (the request-path row).

## Re-measure

Take the same trace again and run the before/after benchmark from optimize-and-benchmark.md. The characterization test stays green through every change; a faster trace with a red characterization test is not a fix.

Source note: paraphrased from a pasted checklist. Its illustrative millisecond figures are deliberately not carried over.
