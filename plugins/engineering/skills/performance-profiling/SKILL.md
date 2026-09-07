---
name: performance-profiling
description: Investigate performance issues in Go services with pprof setup, profile capture, an analysis workflow, and common optimizations. Trigger phrases — "performance", "slow", "profiling", "optimize", "latency", "throughput", "memory leak", "high CPU", "pprof", "benchmark", "bottleneck", "p99".
---

Optimization must never change behaviour: a characterization test pins the current output before any change and must stay GREEN through every optimization. The pprof endpoint must stay on an internal port, never a public one.

## Contract
- Input: a Go service with a suspected performance problem.
- Output: a profiled diagnosis plus an optimization guarded by a characterization test and a before/after benchmark.
- Tool boundary: profiling is read-only; optimizations land only behind a GREEN characterization test and a measured benchmark.
- Done when: the benchmark shows before/after numbers and the characterization test stays GREEN.

## Steps
1. Enable the pprof endpoint on an internal port per `references/pprof-setup-and-capture.md`.
2. Capture CPU, heap, goroutine, block, and mutex profiles with the commands in `references/pprof-setup-and-capture.md`.
3. Analyse the profiles at the pprof prompt (`top10`, `list`, flame graph) per `references/pprof-setup-and-capture.md`; the widest bars at the top of the flame mark the hot path.
4. Lock behaviour first: a characterization test pins the hot path's current output, per `references/optimize-and-benchmark.md`.
5. Apply the matching entry from the common-fixes table in `references/optimize-and-benchmark.md`.
6. Benchmark before and after per `references/optimize-and-benchmark.md`, then report the numbers in the PR description.
7. For production visibility, the continuous-profiling options in `references/pprof-setup-and-capture.md` apply.

## References
- `references/pprof-setup-and-capture.md` — endpoint setup, capture commands, pprof-shell analysis, continuous profiling.
- `references/optimize-and-benchmark.md` — characterization test, common-fixes table, before/after benchmark.
