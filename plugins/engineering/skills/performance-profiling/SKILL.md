---
name: performance-profiling
description: Diagnose a slow or resource-hungry Go service ("pprof", "latency", CPU, memory, goroutines) and land an optimization behind a characterization test and a before/after benchmark. Usage: /performance-profiling [symptom], e.g. "/performance-profiling p99 latency on /checkout".
disable-model-invocation: true
---

**Input**: a Go service and the symptom (ask for the metric and the SLO/target if missing).
**Output**: a profiled diagnosis, an optimization, a GREEN characterization test, and before/after benchmark numbers.
**Boundary**: profiling is read-only; a change lands only behind a GREEN characterization test and a measured benchmark. The pprof endpoint stays on an internal port, never a public one. No dispatches.

Optimization never changes behaviour: the characterization test pins today's output first and stays GREEN through every change.

## Steps

1. **Pick the route.** Latency spread across layers or services rather than one hot function → `references/latency-budget.md` (trace first, then fix by layer), which routes back to steps 4–6 for the fix. One hot process → continue at step 2.
2. **Capture.** Enable pprof on an internal port and capture CPU, heap, goroutine, block and mutex profiles with the commands in `references/pprof-setup-and-capture.md`.
3. **Analyse** at the pprof prompt (`top10`, `list`, flame graph) per `references/pprof-setup-and-capture.md`; the widest bars at the top of the flame are the hot path. State the diagnosis as `{function file:line} — {share of CPU/alloc} — {why}`.
4. **Lock behaviour.** Write the characterization test for the hot path per `references/optimize-and-benchmark.md`; it passes before any change.
5. **Fix.** Apply the matching row of the common-fixes table in `references/optimize-and-benchmark.md` — one change at a time.
6. **Measure.** Run the before/after benchmark per `references/optimize-and-benchmark.md` (`-count=5` or more; compare with `benchstat` when installed) — a gain inside the run-to-run noise is not a gain. The characterization test is still GREEN.
7. **Report** the diagnosis, the change (`file:line`), the benchmark table and the test name. For production visibility, the continuous-profiling options in `references/pprof-setup-and-capture.md` apply.

Next: `/validate-code`, then `/review-code`; `/observability` if the trace showed blind spots.
