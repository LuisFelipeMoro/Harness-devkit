# Artifact Schemas

Schema and handoff contracts for each artifact the skills produce. The plan section list lives in
`plan-template.md`; this file says what each artifact must carry and who consumes it.

---

## Artifact Chain

```
/map       → docs/plans/{slug}/codebase-map.md
/planning  → docs/plans/{slug}/plan.md              (reads the map; may start from your notes file)
/code      → the diff + docs/plans/{slug}/evidence.md   (reads the plan, one Tasks row at a time)
/validate-code  → report only (gates, qa, stress, verdict)
```

Each skill ends by *suggesting* the next one; none runs it. `{slug}` is kebab-case, ≤ 5 words.

---

## docs/plans/{slug}/codebase-map.md
Produced by: `/map` (also its first step inside `/planning`) | Consumed by: the plan author, `plan-reviewer`

Required sections: Blast radius (symbols · callers · test files · non-code callers) · Reusable symbols · Prior art · Conventions · Extension points · Contracts in force · Test conventions. Every entry cites `file:line`.

---

## docs/plans/{slug}/plan.md
Produced by: `/planning` (or a mini-plan by `/code`) | Consumed by: `plan-reviewer`, `coder` (via Task ID), `qa`, `/validate-code`

Required sections, in order: header (Status · Branch · Language · Tier) · Goal · Requirements & ACs (incl. **Security ACs**) · Out of scope · Codebase context · Reuse Map · Design (components and interfaces, Mermaid optional, decisions with rejected alternatives; auth checked and input validated shown in the data flow) · **Test Case table** (one row per AC/edge/security control — Test Name · Input / Precondition · Expected Observable Result · AC · Why It Matters · Falsified By; this is the frozen test contract, since tests are written after the implementation) · Tasks (with its `### New files` table) · Open questions · Review log.

Key rules: every functional requirement has ≥ 2 binary ACs · NFRs have measurable targets · ACs reference error/edge cases · security ACs are mandatory for auth/input/external-API work.

**Interface syntax by language** (use only the matching one):
| Language | Interface syntax |
|----------|-----------------|
| Java | `ReturnType methodName(ParamType p) throws DomainException;` in consumer-package interface |
| JS/TS | `methodName(p: ParamType): Promise<ReturnType>;` in `interface` block |
| PHP | `public function methodName(ParamType $p): ReturnType;` in `interface` |
| Go | `MethodName(ctx context.Context, p ParamType) (ReturnType, error)` in consumer-package interface |

**Type rules**: no `any`, no untyped `dict`, no raw `Object`. Java: `record`/final-field classes. PHP: typed properties (8+). Go: value types preferred.

---

## docs/plans/{slug}/evidence.md
Produced by: `/code`'s Final proof stage (the FINAL-PROOF coder dispatch appends each row's `Falsification evidence` lines under `## {Task ID}`; `skills/code/references/loop.md` § Final proof) | Consumed by: `/validate-code` (`scripts/verify/falsification.sh`), `qa`

---

## docs/plans/{slug}/validation/
Produced by: `/validate-code` step 8 — `qa.md` and `stress.md`, each the agent's return verbatim (no plan → `$TMPDIR/validate-{slug}/`) | Consumed by: the user, who reads the score, top findings and path printed by `/validate-code`

Generated output: release-excluded (`.devkit/release-exclude`), never committed.

---

## docs/plans/{slug}/run-state.json
Produced by: `scripts/drive.py` after every stage (written to a temp file, then renamed into place) | Consumed by: `drive.py --resume-from`, `headless.load_runs` (estimate-run `Measured $`, harness-metrics cache-hit row)

Schema 1: `schema`, `plan`, `slug`, `branch`, `base`, `mode`, `stages` (per stage: `stage`, `status`, `exit_code`, `subtype`, `model`, token and cost counts, `turns`, `session_id`, `sentinel`, `wall_s`, `finished_at`), `status`, `stop_reason`. Counts and identifiers only: no prompt, result or tool text. A file that does not match this schema is reported `UNMEASURED` and never half-read.

Generated output: release-excluded (`**/run-state.json`), never committed by the driver.

---

## Artifact Passing Rules

1. A `coder` dispatch receives the **plan path and one Task ID**, never pasted contents. It reads the Test Case rows listed in that task and the Design components it touches, not the whole plan.
2. `plan-reviewer` receives the plan path and the map path, and reads the repository itself.
3. `qa`, `reviewer` and `stress` receive the plan path (when one exists), the changed-file list and the base ref.
4. Between tasks, code and test output are dropped from the session. Only the plan, `evidence.md` and the scores are retained.
5. A missing required section → the receiving agent flags it and asks before proceeding.
6. A requirement change after approval → back to `/planning` for the affected sections; the Test Case table is re-frozen before more code.
7. Security ACs missing from a plan that touches I/O, auth or user input → flag to the user; the coder must not invent them.
