# Bench — end-to-end eval of the coder pipeline

`bench/run.py` runs every fixture × arm × repetition as fresh headless sessions (one `claude -p`
per skill stage: `/code`, `/validate-code`, `/review-code`) through
`plugins/coding-pipeline/scripts/headless.py`, then writes one summary per arm.

## Run

    python3 bench/run.py --arms B-haiku,B-sonnet --reps 3 [--fixtures all|go-gap] --yes

- Without `--yes` the runner prints the run count and a cost estimate and exits 2. Nothing
  is created and no stage starts. The estimate is `est_usd_per_run` from `arms.json` times the
  run count. It is a planning figure, not a bound; each stage is capped at USD 8, the driver's per-stage default.
- `--out DIR` overrides the default `bench/results/<UTC stamp>/`. Results are release-excluded (G10).
- Each arm writes `<arm>.summary.json`: per-run pass, gate result, verdict score, falsification
  exit, cost and stage statuses, plus aggregates (pass rate, score and cost median/min/max, and
  `flipped`: fixtures whose pass outcome differed across repetitions).

## Pass and gates

A run passes when every stage ends `ok` and the measured gate result equals `expected.json`
`gates_green`. The gate is scored per stack, offline, with nothing installed:

- Go seed (`go.mod`): `go test ./...`.
- TypeScript seed (`package.json`): `node --experimental-strip-types --test` over every `*.test.ts`
  under the run repo, using the built-in `node:test` (Node >= 22.6). No test file, or no Node
  at that version, is UNMEASURED.
- Doc-only seed (no `go.mod`, no `package.json`): green when every path changed against `main`
  (the seed commit) ends `.md`. Any other changed path is UNMEASURED.

Any other seed, or a gate that cannot run, is UNMEASURED and fails closed (`stop_reason:
gates unmeasured`, pass = false). The TypeScript fixture plans name `node:test` as their test
framework, with test files `<source>.test.ts` beside the source.

## Fixtures

`bench/fixtures/<name>/` holds `seed/` (the starting repository), `plan.md` (must carry
`Status: approved`) and `expected.json` (exactly `gates_green`, `plan_gap`, `depth`). A fixture
that fails these checks refuses the whole run (exit 2) before any stage starts.

- `go-gap` — Go, one task, three Test Case rows, with the negative-max row deliberately missing (`plan_gap: true`).

## Arms

`arms.json` maps an arm to `topology` (only `fresh` is wired) and one model per stage. The
`est_usd_per_run` figures are the measured totals from the 2026-11-10 n=1 run on the go-gap
fixture (research notes, bench-e2e/README.md). They are not a bound.

## ADR-6 decision rule

A default (main model, topology, fold) changes only if a candidate arm, over at least 3
repetitions on all six fixtures, has a pass rate at or above the baseline, flags the gap
fixture in at least as many repetitions, and flips no fixture from pass to fail. A single
benchmark run (n=1) is not enough to change a default.
