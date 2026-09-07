# Delivery: Workshop Standards Integration — WS1 (target v2.5.0)

**Status:** IN IMPLEMENTATION on branch `release/v2.5.0`, targeting v2.5.0.
- **S1, S2, S3 — built and verified**, uncommitted on the working tree (W1–W7).
- **S4 — in progress** (W8–W12), with two corrections applied mid-flight from plan review round 2.
- Reviewed twice (round 1: 6 major, all closed; round 2: see history). Implementation of S1–S3 was
  started by explicit maintainer instruction after round 1 closed, ahead of round 2 returning.

**Baseline:** v2.4.3 (`a63d607`). Tree was clean at plan time; it is not now — see Status.
**Sources:** `~/Downloads/go-engineering-standards.md` (1012 lines, GopherCon Latam 2026 — jba/concurrency-workshop + alexrios/gcl26-testing-workshop) and `~/Downloads/agent-skills-summary.md` (402 lines, skills.danicat.dev catalogue).
**Prior audit:** claude-mem observations #171–#174 (2026-09-07) — baseline established, no files modified.

---

## Plan review history

**Round 1 — Priya, 2026-09-07. Score 5/10, PLAN CHANGES REQUIRED.** 0 critical · 6 major · 2 minor ·
1 nit. All independently re-verified against the repo before being actioned; all closed:

| # | Finding | Resolution |
|---|---|---|
| MAJOR PR3 | D3 named `code-review-gate` as a PR path; it creates no PR | Verified (no `gh pr` in that skill). W6 now cites `multi-agent:68` and `bug-fix:19,22`. D3 reopened and re-closed |
| MAJOR PR3 | Verification called `tests/test-install.sh`; no `tests/` dir exists | Corrected to `.github/scripts/`, plus the three sibling test scripts |
| MAJOR PR9 | No Blast Radius | Added as its own section; identifies W8 as highest-radius and moves it last |
| MAJOR PR5 | W1 said "two-column style" above a three-column table | Third column marked plan-rationale, explicitly not shipped |
| MAJOR PR3 | W4 duplicated `qa.md:91`'s "no real sleeps" at a different severity | Verified. W4 now *moves* the clause into the blocking block instead of adding a second rule; severity change called out for the CHANGELOG |
| MAJOR PR11 | No manifest; sizing unverifiable | Task Manifest added (S1–S4) |
| MINOR | Verification items numbered 1,2,3,4,6,5 | Renumbered; a duplicated item removed |
| MINOR | No `PRD.md` / `codebase-map.md`, absence unexplained | Stated as a deliberate Proportionality call for the `/task` lane |
| NIT | W2 `extend:` sits close to a second `new:` | Addressed in the Reuse Map row with the reasoning for keeping `extend:` |

Also closed in the same pass: W13/F8, previously the last open question, decided as D5.

**Round 2 — pending.**

---

## Scope

Two halves, from the two source files:

- **W1–W7** fold the Go workshop material into the existing rule surface. Rules-and-references only;
  every addition lands in a file already lazy-loaded by an agent that already exists.
- **W8–W13** fix the skill surface against the `skill-optimizer` standard from
  `agent-skills-summary.md`, audited 2026-09-07 (findings F1–F8, recorded per workstream).

**Lane:** `/task` — behaviour change (agents will flag defects they previously passed, and skill
routing changes) spanning more than two files, no new dependency, no new external surface.

**Non-goals** (explicit, so they are not smuggled in later):
- No new agent, no new skill, no new plugin.
- No change to the installer or the session hooks. **W8 does extend `.github/scripts/validate-wiring.py`**
  — that is the one CI change in this delivery, and it exists to make W8/W10/W11 enforceable rather
  than restated.
- No change to coverage thresholds or the gate table's pass criteria.
- No Go code written anywhere in this repo — the devkit ships rules, not Go.
- No attempt to make `skillspec` run here: it is an arm64 build on an Intel host
  (`bad CPU type in executable`, re-confirmed 2026-09-07). W9 fixes the rule that depends on it,
  not the binary.

---

## Reuse Map

Every change extends an existing structure except one, which is justified below.

| Item | Decision | Existing thing |
|---|---|---|
| Concurrency rules | `extend:` | `references/languages/go.md:46-56` (Concurrency table) |
| Toolchain capability table (W3b) | `extend:` | `references/languages/go.md:16-21` (Version Policy) — same concern, currently states the policy without giving a mechanism |
| Trigger phrases (W8) | `extend:` | `plugins/coding-pipeline/CLAUDE.md` routing table (23 rows) + all 23 `SKILL.md` descriptions — consolidating two existing stores into one, not adding a third |
| Skill wiring check (W8) | `extend:` | `.github/scripts/validate-wiring.py` — already checks that skills point to real references; this adds two checks to the same validator |
| `allowed-tools` (W12) | `extend:` | `SKILL.md` frontmatter — a field the format already supports and no skill uses |
| Prose standards (W7) | **`new:`** | Nearest existing thing is `references/frontend-design-reference.md`, which carries anti-slop rules for *UI*, not prose. No prose catalogue exists; the `why-not-what` comment rule in `CLAUDE.md` covers code comments only. Justified as a new reference because it is loaded by two skills on demand and would be dead weight inside either one |
| Go testing rules | `extend:` | `references/languages/go.md:91-100` (Testing Idiom table) |
| Go review severities | `extend:` | `references/languages/go.md:111-153` (Review Flags table) |
| Dependency policy | `extend:` | `references/languages/go.md:40` (Dependencies row) |
| Concurrency overengineering (W2) | `extend:` | `references/change-discipline.md` CD2 + `agents/reviewer.md:40-68` (PE Standard). **Boundary noted in plan review:** the physical edit is a new table inside `go.md`, not a modification of either cited file. Kept as `extend:` because the *concept* is CD2's and already enforced — W2 expresses it in Go primitives so the existing rule can actually be applied to a concurrency diff. It introduces no new severity and no new finding class: the one review row it adds is MINOR, the band CD2 findings already use |
| Timing-coupled / probabilistic tests | `extend:` | `agents/qa.md:52-78` (tautology hunt), `:79-89` (corner cases) |
| Transaction races | `extend:` | `agents/stress.md:48-56` (§3 Concurrency & Race Conditions — already names TOCTOU) |
| Draft-PR ceremony | `extend:` | `references/delivery-and-worktree.md` + `skills/multi-agent` PR step |

---

## Blast Radius *(added after plan review — PR9)*

Rules files have no code callers; their "callers" are load relationships. Who is affected:

| Changed file | Loaded by | Radius |
|---|---|---|
| `references/languages/go.md` | Coder + Reviewer, on demand, when a story's `Language` is Go (`go.md:3`) | **Every future Go story and every review of one.** Zero effect on other languages |
| `agents/qa.md` | Quinn, every story, every language | **Every story.** W4 promotes sleeps from non-blocking to blocking — suites green today can cap at QA Score 4 |
| `agents/stress.md` | Stress Tester, every story | Every story; W5 adds no new severity, only sharpens §3 |
| `agents/reviewer.md` | Reviewer, every story | One NIT row (W7 prose wiring). *Corrected in round 2: W2's MINOR row lands in `go.md`'s Review Flags table (`go.md:197`), not here* |
| `references/delivery-and-worktree.md`, `skills/multi-agent`, `skills/bug-fix` | Every pipeline run and every hotfix | **Every PR the devkit opens** gets `--draft` + an explicit promotion step |
| All 23 `SKILL.md` descriptions + `CLAUDE.md` routing table | Skill discovery, every session, every project | **Every session.** W8 changes what phrases route where — the highest-radius change in the delivery |
| `.github/scripts/validate-wiring.py` | CI only | No runtime effect; a new way for CI to fail |

**Retroactive effect is real and intended:** W4 and W2 make agents flag defects they previously
passed, so an in-flight delivery reviewed after this ships can fail on code that passed before. That
is the point of tightening a standard, but it means this lands between deliveries, not during one.

**Highest-risk item is W8**, because it changes routing for every session in every project rather
than for one language or one pipeline stage. It ships last and in the two-step order stated there.

---

## W1 — go.md: concurrency hardening

**File:** `plugins/coding-pipeline/references/languages/go.md`
**Insertion point:** Concurrency table, `go.md:46-56`.

> **Ships as two columns.** The existing table is `| Rule | Requirement |` and stays that way. The
> third column below is **plan rationale for the reviewer of this document — it does not ship**.
> Carrying it into `go.md` would make every row roughly three times heavier in a file paid for on
> every Go story. (Ambiguity caught by plan review, PR5.)

| Row | Requirement | *(rationale — not shipped)* |
|---|---|---|
| Transaction races | Check-and-act is one critical section. Releasing the lock between the check and the mutation is TOCTOU — every access is synchronised and `-race` still passes | The `-race` gate is already mandatory (`go.md:100`) and cannot see this class at all. Highest-value addition in W1 |
| Lock ordering | Two locks acquired in one operation are ordered by a stable id, the same order on every path | Deadlock that only appears under concurrent transfer |
| Mutex across I/O | Lock, snapshot, unlock, then do I/O. Never hold a mutex across a network or disk call | Serialises every contender behind an unbounded operation |
| Escaping references | Return `slices.Clone(...)`, never a slice or pointer backed by a guarded field (`buf.Bytes()` included) | Hands the caller unsynchronised write access to guarded state |
| `Locked` suffix | A helper that assumes the lock is held is named `…Locked` and carries `// +checklocks:mu` | Closes the gap where an unlocked call compiles silently |
| Channel capacity | A result channel is buffered to the number of senders, so a loser can deposit and exit | Unbuffered + timeout is the canonical goroutine leak |
| `defer` placement | Written on the line after acquisition, never at the end of the function; `defer wg.Done()` inside the goroutine closure | An early return or panic skips a defer placed late |
| `errgroup` context | Each `g.Go` closure uses `gctx`, never the outer `ctx` | Passing outer `ctx` silently disables first-error cancellation |
| Atomics | `sync/atomic` for a single `Add`/`CompareAndSwap`/`Swap` only. `Load` then `Store` is a TOCTOU | Looks synchronised, is not |
| Non-blocking ops | `select` with `default` when a send or receive must not block — and the dropped value is a stated decision, not an accident | |
| Generators | Range-over-function iterator over a goroutine-plus-channel generator when the goal is "yield all values" | No lifecycle, no close, no leak |

**Also amend** the existing `Mutexes` row (`go.md:54`) — it already requires guarded fields under the
mutex; add that the hat guards **only** the fields beneath it, and two lock domains need two mutexes.

**Amend** the `Dependencies` row (`go.md:40`) to state the stdlib-first test explicitly: an external
package is justified only when it is dramatically simpler, is an existing project choice, or is
already in use. Current row lists an allowlist but no test for adding to it.

---

## W2 — go.md: overengineering table (CD2 for concurrency)

**Insertion point:** new short block after the Concurrency table.

The workshop's "choose the right tool" matrix is CD2 (`no speculative abstractions`) expressed in Go
primitives, and CD2 is already a blocking review category. Six rows:

| Problem | Right tool | Overengineering signal |
|---|---|---|
| Fan out N tasks, collect first error | `errgroup` | `errgroup` where no goroutine returns an error → use `WaitGroup` |
| Shared mutable state, simple read/write | Mutex | Actor where a mutex suffices |
| One computation, many callers, same input | Promise/memo | |
| Staged work, genuinely different bottlenecks | Pipeline | Pipeline whose stages relay values — channel cost exceeds the work |
| Async access or access priorities | Actor | |
| Wait for N goroutines, no errors | `WaitGroup` | Goroutines for inherently sequential work |

**Reviewer wiring:** one row in `go.md` Review Flags — *concurrency primitive heavier than the
problem (actor for guarded state, pipeline with trivial stages, errgroup with no errors)* → **MINOR**,
same severity band as the existing overengineering findings in `reviewer.md:40-68`.

**Placement decided:** this table lives in `go.md`, not `change-discipline.md`. The primitives are
Go-specific and `go.md` is lazy-loaded per Go story, whereas `change-discipline.md` is loaded for
every review in every language — putting Go primitives there would charge a Flutter story for them.

---

## W3 — go.md: modern testing patterns

**Insertion point:** Testing Idiom table, `go.md:91-100`.

Every row states an **invariant** (never version-dependent) and, where the mechanism depends on the
toolchain, defers to the capability table in W3b rather than naming a version inline.

| Row | Requirement |
|---|---|
| No sleeps | `time.Sleep` in a test is a defect: it couples correctness to wall time. Mechanism per W3b — `testing/synctest` where available, otherwise an injected clock (`Now`/`After`) driven by the test |
| Test context | The test's context is cancelled before cleanup runs. Use `T.Context()` where available rather than hand-rolling `context.WithCancel` — that cancel-before-cleanup ordering is the whole point, and a hand-rolled version usually gets it backwards |
| Cleanup registration | `t.Cleanup` registered on the line after acquisition — a `t.Fatal` before a late registration skips the cleanup entirely |
| Benchmarks | `for b.Loop()` over `b.N` where available (it makes measuring setup work structurally impossible); `b.ReportAllocs()` always; sub-benchmarks per access pattern |
| Benchmark comparison | `-count=10` before and after, compared with `benchstat`. A single run is one sample. A `~` delta is a reportable result, not a failed measurement |
| Fuzz corpus | Seeds must include empty/zero, a valid representative, and boundary inputs (Unicode, NUL, non-ASCII). Out-of-domain input is `t.Skip`, never `t.Error`. Panic-safety and property targets are separate functions. Crash files under `testdata/fuzz/` are committed — replay is the regression test |
| Contract tests | `fstest.TestFS` for every `fs.FS`; `iotest.TestReader` for every `io.Reader`. A conditional inside a contract test is evidence the implementation is wrong |
| Failure injection | Deterministic — a stub field (`syncErr error`), never a probability. Assert the error **and** that no partial state survived |
| Stub scope | A stub's boundary is stated in a comment: an in-memory stub proves in-memory visibility, not durability or replay safety |
| Leak assertion | A type that exposes `Stop` proves `Stop` releases its goroutines. Where the leak profile is available, sample `pprof.Lookup("goroutineleak")` before and after with `runtime.Gosched()` before sampling; otherwise `goleak`. Either way `Stop` is close-once (`sync.Once`) plus drain, never fire-and-forget |
| Artifacts | Diagnostic files never go to the source tree — `T.ArtifactDir()` where available, else `t.TempDir()` |

**Amend** the existing `Fuzzing` row (`go.md:99`) rather than adding a second one — it currently says
only "a fuzz target exists".

**Amend** the existing `Leak detection` row (`go.md:56`) — `goleak.VerifyTestMain` stays; the profile
assertion is the stronger form for types that expose `Stop`.

**Review Flags** additions: `time.Sleep` in a test → **MAJOR** · probabilistic failure injection →
**MAJOR** · `fs.FS`/`io.Reader` implementation with no contract test → **MINOR** · benchmark without
`b.ReportAllocs()` → **NIT** · performance claim from a single benchmark run → **MINOR** (tightens
the existing `Measurement` row at `go.md:89`).

---

## W3b — Toolchain capability table (resolves the version-rot problem)

**Insertion point:** `go.md`, immediately after the Testing Idiom table. ~8 lines.

A version number written into a lazy-loaded rules file is an unverifiable memory claim that rots
silently. It rots fast: of the five version claims in the source material, **three were wrong** when
checked against the release notes — `T.Context` is 1.24 (claimed 1.21), `T.ArtifactDir` is 1.26
(claimed 1.24), and `synctest.Run` was the 1.24 *experimental* spelling, replaced by `synctest.Test`
at GA in 1.25 and **removed in 1.26**. A Coder following a rule that names `synctest.Run` on a
current toolchain writes code that does not compile.

So the rule is not the version — the rule is the invariant, and the mechanism is chosen by a
**detection command whose exit code is the sensor**:

| Capability | Detect with | If absent, use |
|---|---|---|
| Virtual-time testing | `go doc testing/synctest` | Injected clock interface (`Now`/`After`) |
| Test-scoped context | `go doc testing.T.Context` | `context.WithCancel` + `t.Cleanup`, cancel before cleanup |
| Allocation-safe benchmark loop | `go doc testing.B.Loop` | `b.N` with `b.ResetTimer()` after setup |
| Leak profile | `go doc runtime/pprof` (look for `goroutineleak`) | `goleak.VerifyTestMain` |
| Test artifact dir | `go doc testing.T.ArtifactDir` | `t.TempDir()` |

Plus one line, matching the existing context7 rule at `go.md:12-14`: **the spelling of any API in
this table is confirmed against live docs before use — `synctest` alone has changed spelling once
already.** This costs ~8 lines and removes five separate opportunities to be confidently wrong.

**This pattern generalises.** Every language reference in `references/languages/` has the same
exposure. Out of scope for v2.5.0 — flagged in `PROGRESS.md` as a follow-up, not fixed here.

---

## W4 — QA agent: two language-agnostic lenses

**File:** `plugins/coding-pipeline/agents/qa.md`, tautology/corner-case block (`:52-89`).

Only the language-neutral half belongs here; the Go specifics live in go.md.

**Collision found in plan review (MAJOR/PR3) — resolved by amendment, not addition.** `qa.md:91`
already says *"Determinism: no order dependence, **no real sleeps**, no real network/clock — flaky
tests are a gap"* — inside §4 Test quality, which is **non-blocking**. Adding a "timing-coupled test"
row to the blocking tautology block would leave Quinn holding two rules about one defect at two
severities with no precedence. So:

- **Move, don't duplicate.** Promote the sleep clause out of §4's determinism bullet and into the
  blocking block as **timing-coupled test** — the test's correctness depends on wall-clock duration
  (a sleep, a bare timeout, "wait 200ms and check"). It does not prove the behaviour; it proves the
  machine was fast enough. §4's determinism bullet keeps order-dependence and real network/clock, and
  loses "no real sleeps" so exactly one rule owns it.
- **Add** **probabilistic failure injection** — a stub that fails on a random draw. Non-reproducible,
  so a red run cannot become a committed regression test. No existing rule covers this; checked.

**Severity call, stated rather than assumed:** promoting sleeps from non-blocking to blocking is a
real tightening — suites that pass today will cap at QA Score 4 tomorrow. That is the intent (a
sleep-based test is the flakiness source the Harness keeps paying for), but it belongs in the
CHANGELOG as a breaking-for-existing-suites note, not smuggled in as a wording tweak.

---

## W5 — Stress agent: transaction races

**File:** `plugins/coding-pipeline/agents/stress.md`, §3 (`:48-56`).

The section already names TOCTOU. Make the distinction that gives it teeth:

- A **data race** is caught by `-race`. A **transaction race** is not — every access is
  synchronised, the *sequence* is wrong. `-race` passing is not evidence against this class.
- Add to the Go language-risks line: mutex held across I/O; two-lock operation with no stable
  acquisition order; unbuffered channel plus timeout (leaks the sender).

---

## W6 — Draft-PR ceremony

**Files — corrected after plan review (Priya, MAJOR/PR3).** The first draft named
`skills/code-review-gate` as a PR path. It is not one: that skill has no `gh pr` anywhere, and its
Phase 3 ends at a `PASS`/`BLOCK` verdict. Verified — the only two PR-creating paths are:

| Path | File | Current step |
|---|---|---|
| Delivery PR | `skills/multi-agent/SKILL.md:68` | `gh pr create` for the delivery |
| Hotfix PR | `skills/bug-fix/SKILL.md:19,22` | Contract output "a PR from `hotfix/{slug}` to `main`"; Phase 5 "Summary + PR to `main`" |

Plus `references/delivery-and-worktree.md`, which states the branch-and-PR contract both rely on.

The workshop's loop is: open **draft** → run the reviewer loop until clean → promote to ready. The
devkit already runs a reviewer pass and already has `pr-review-responder.sh`; what is missing is that
the PR is created with `--draft` and promoted with `gh pr ready` only after the reviewer returns no
findings. This moves review cost from the reviewer to the author's local loop — the same argument the
Harness already makes for sensors over prose.

**One caveat carried from the review:** `bug-fix` Phase 4 is a *single* review pass with a
user-confirm branch when the score is below 8, not a loop that runs until clean. So on the hotfix
path, "promote when the loop is clean" has no loop to attach to. Do **not** invent one — W6 adds the
`--draft` flag and the `gh pr ready` promotion to both paths, and promotion on the hotfix path is
gated on the existing single pass. Converting that pass into a loop is a separate change and is not
in this delivery.

Cost: two sentences and one flag per path.

---

## W7 — Prose standards as a `/handoff`-time editorial pass

**New file:** `plugins/coding-pipeline/references/prose-standards.md` (~40 lines).
**Wired into:** `skills/handoff`, `skills/release-management` (CHANGELOG entries), and the PR-body
step that W6 already touches.

**Not a gate.** There is no exit code for prose quality, and a subjective check wired into a blocking
gate is exactly the "unverifiable claim" the Harness ranks below no claim at all. It runs as an
editorial pass over text the agents *author* — handoff docs, `PROGRESS.md` entries, PR bodies,
CHANGELOG lines — at the point that text is written.

Contents, condensed from the source catalogue to the tells that actually show up in agent output:

| Tell | Instead |
|---|---|
| Magic adverbs — *quietly, deeply, fundamentally* | Cut, or give the number |
| Pompous vocabulary — *delve, tapestry, landscape, leverage, harness* | *explore, look at, use* |
| The "serves as" dodge — *serves as a reminder, stands as a testament* | *is, shows* |
| Negative parallelism — *"It's not X — it's Y"* | State it directly |
| Dramatic countdown — *"Not a bug. Not a feature. A design flaw."* | One sentence |
| Self-answering rhetoric — *"The result? Devastating."* | Say what happened |
| Filler transitions — *"It's worth noting that…"* | Delete the preamble |
| Pedagogical signposting — *"Let's break this down"* | Present the facts |
| Fractal summaries — a conclusion at the end of every section | Let the content stand |

**Reviewer wiring:** one **NIT** row, docs and PR prose only, never code comments — the *why-not-what*
comment rule at `CLAUDE.md` already governs those and is stricter.

**Self-application is the honest test.** This repo's own docs use negative parallelism and em-dashes
heavily — this delivery file included. If the standard is worth shipping, the first pass runs over
`README.md` and `CHANGELOG.md`. If that pass produces nothing anyone wants to keep, the standard was
not worth shipping and W7 should be dropped rather than quietly retained.

---

## Skill-surface audit (2026-09-07) — basis for W8–W13

Source: the `skill-optimizer` standard in `agent-skills-summary.md` (3-tier progressive disclosure:
Tier 1 routing ≤150 tokens, Tier 2 body <500 lines, Tier 3 on-demand `references/`).

`skillspec` could not be used: `~/.local/bin/skillspec` is an arm64 build on an Intel host and exits
`bad CPU type in executable`. Audit run natively over all 23 skills instead.

**Passing today:** Tier 1 budget 23/23 (largest `rote`, ~127 tokens) · Tier 2 23/23 (largest
`security-review`, 100 lines) · Tier 3 20/23 use `references/`. The devkit's own ≤100-line rule is
stricter than the standard's 500 and holds everywhere. The findings below are all in Tier 1 metadata.

---

## W8 — Trigger phrases get one source of truth *(F1 — MAJOR, highest value in W8–W13)*

Trigger phrases are stored twice — the routing table in `plugins/coding-pipeline/CLAUDE.md` and each
`SKILL.md` description — and **all 23 pairs disagree**. Nine skills carry zero phrases in their own
description while the routing table lists many:

| Skill | CLAUDE.md | SKILL.md description |
|---|---|---|
| `security-review` | 16 | 0 |
| `analysis`, `planning` | 9 | 0 |
| `architecture`, `technical-analysis`, `task` | 8 | 0 |
| `pr-review`, `business-analysis` | 7 | 0 |
| `checkcomments` | 5 | 0 |

**Failure mode:** skill discovery reads the description, not the user's global `CLAUDE.md`. Any
install of these plugins without that file — or any session where it is not loaded — silently loses
roughly 90 trigger phrases. Today "is this safe", "threat model", "auth bypass" and "CVE" reach
`security-review` **only** through `CLAUDE.md`.

**Fix, in order:**
1. Merge the union of both sources into each `SKILL.md` description. Measured: 22/23 land under the
   150-token Tier 1 ceiling after the merge; only `rote` overflows at ~161, and W11 trims it anyway.
2. Then thin the `CLAUDE.md` routing table to task → skill, dropping the phrase lists. Measured
   saving: **~747 tokens on every session in every project** (the table is 23 rows / ~1145 tokens
   inside a 6232-token file that loads unconditionally).
3. Extend `.github/scripts/validate-wiring.py` with the check that makes it stay fixed: every routed
   skill exists, and every skill description carries at least one trigger phrase.

Step 1 must land before step 2. Reversing them removes the phrases from the loaded file before the
descriptions can carry them, and routing degrades in the window between.

---

## W9 — Unblock `write-a-skill`'s validator *(F2 — MAJOR, three words)*

`plugins/devtools/skills/write-a-skill/SKILL.md:35` — "The skill is **not done** until SkillSpec has
run". The escape hatch at `:31` reads *"skip only if `skillspec` is not installed"*. On this machine
it **is** installed and cannot execute, so the stated completion condition is unreachable and the
escape clause does not cover the actual failure.

Widen the condition to "not installed **or cannot execute**", and name the fallback the repo already
has: `.github/scripts/validate-wiring.py` plus the W8 description check. Same edit in
`references/skillspec-validation.md:15`.

---

## W10 — Delete pointers to files that do not exist *(F3 — MINOR)*

Five skills (`analysis`, `architecture`, `bug-fix`, `planning`, `task`) each carry:

> Machine-checkable behavior contract: `skill.spec.yml` · dependency ledger: `deps.toml` (both
> generated by the `skillspec` CLI and git-ignored — Claude never loads them).

Verified: **zero** such files exist anywhere in the repo, they are git-ignored (`.gitignore:6-7`),
and the generator cannot run here. The sentence asserting Claude never loads them is itself loaded by
Claude on every invocation of those five skills — roughly 35 tokens each, for a note addressed to a
human maintainer. `checkcomments` and `pr-review` carry a shorter variant of the same line.

Delete all seven. If the maintainer note has value it belongs in `CONTRIBUTING`, not in a file the
agent pays for at runtime. Same class as the `reviewer.md` token audit in `dafdbef`.

---

## W11 — Make `write-a-skill`'s rules match reality *(F4, F5, F7 — MINOR)*

The skill states rules that nothing measures and most skills break:

- `:13` "description must start with **Use when**" — broken by 9/23. **Fix the rule, not the skills.**
  The standard's 3-part blueprint requires no such prefix, and `checkcomments`/`pr-review` read
  better leading with what they produce.
- `:13` "**2–5 trigger phrases**" — broken by 13/23, up to 10. The standard asks for trigger
  *discipline*, not a count. Retire the cap; W8's validator check (≥1 phrase) replaces it.
- `rote`'s description opens *"Use rote BEFORE calling any MCP server or CLI tool directly"* and adds
  *"Always run `rote flow search` first"*. That is body content in Tier 1 and is what the standard's
  anti-pushy rule names. Trimming it also brings it under the ceiling W8 needs (~161 → <150).

---

## W12 — Declare `allowed-tools` on read-only skills *(F6 — MINOR)*

No skill declares `allowed-tools`. The read-only ones — `checkcomments`, `technical-analysis`,
`business-analysis`, `quality-gate` — each state read-only behaviour in prose and get no enforcement.
Declaring the field converts a promise into a constraint. Scope to those four; do not speculatively
annotate the rest.

---

## W13 — `business-analysis` output language *(F8 — NIT, decided as D5)*

`business-analysis` hard-codes Brazilian Portuguese output. In a publicly published marketplace that
is contamination under the standard's zero-contamination gate; for this maintainer it is plausibly
deliberate.

**Decided (D5): make the language a parameter that defaults to the user's language, and state the
default in the description.** This keeps today's behaviour for this maintainer — the default resolves
to Portuguese for them — while removing the hard-code that makes the skill unusable for anyone else
who installs the marketplace. No behaviour change for the current user, so it needs no approval to
proceed; reversible in one line if the hard-code was intentional and wanted.

---

## Rejected (recorded so it is not re-proposed)

- **`double-diamond`, `swarm-coding` (DOP 20–50 swarms), `intercom`** — directly contradict Sub-agent
  Discipline in `CLAUDE.md` ("never spawn 4+ in a single turn"). The devkit's orchestration is
  sequential-with-isolated-subagents by design; a 20-agent swarm is the failure mode that rule
  exists to prevent. Adopting these would be a change to the Harness model, not an improvement to it.
- **`godoctor` (Selene mutation testing)** — plausible, but it is a new dependency and a new gate.
  Falsification already covers the same failure (a test that passes against broken code). Revisit
  only if falsification evidence starts coming back thin.
- **`deslopify` as a blocking gate** — the catalogue itself is now **in scope as W7**, but as an
  editorial pass, not a gate. Gating prose means a subjective check with no exit code, which is the
  failure mode the Harness's first objective exists to prevent.
- **`pyhd`, `latest-version`** — Python is not in the devkit's language set; version checking is
  already the `context7` rule at `go.md:12-14`.

---

## Verification

Docs-and-rules change: there is no unit test for a table row, and pretending otherwise would be the
unfalsifiable-claim failure the Harness exists to prevent. What actually gates this:

1. `python3 .github/scripts/validate-wiring.py` — every cross-reference still resolves, plus W8's
   new checks (routed skill exists · description carries ≥1 trigger phrase).
2. `bash .github/scripts/test-install.sh`, plus `test-hooks.sh`, `test-git-hooks.sh` and
   `test-dup-attribution.sh` — unchanged, must stay green. *(Path corrected in plan review: there is
   no `tests/` directory in this repo.)*
3. `bash install.sh --check` — no drift between repo and `~/.claude`.
4. **Token audit**, the same one applied to `reviewer.md` in `dafdbef`: `go.md` is lazy-loaded per Go
   story, so every added line is paid for on every Go story. Count lines before/after and justify
   the delta against the seven objectives. Budget: **go.md must stay under 250 lines** (from 155;
   +10 over the original budget to pay for W3b's capability table, which removes five wrong-version
   failure modes for eight lines). If W1+W2+W3+W3b do not fit, cut rows — do not raise the budget.
5. W7 only: run the pass over `README.md` and `CHANGELOG.md` and show the diff. An empty or
   unwanted diff means W7 ships nothing and is dropped.
6. W8 only: re-run the drift audit and confirm it reports **0 drifting skills** (it reports 23 today),
   and re-measure `CLAUDE.md` to confirm the ~747-token reduction actually landed.
7. Self-application: run `/code-review-gate` on the diff. The reviewer reads the same CD1–CD7 rows
   this delivery edits.

---

## Decisions

D1–D3 closed 2026-09-07 (D3 reopened and re-closed after plan review round 1). D5 closes W13
provisionally — see the caveat on it below. There is no D4: the numbering skipped it when the
`allowed-tools` item became a workstream (W12) rather than a decision. Recorded so the gap is not
read as a dropped decision.

**D1 — Version gates.** Resolved by W3b: no version numbers in `go.md`. Rules state the invariant;
mechanism is selected by a `go doc` detection command whose exit code is the sensor. Verified against
the release notes rather than asserted from memory, which is how the source material's three wrong
claims were found. Source verification, for the record:

| API | Source material claims | Verified |
|---|---|---|
| `testing.T.Context` | 1.21+ | **1.24** — source wrong |
| `testing.B.Loop` | 1.24+ | 1.24 — correct |
| `testing/synctest` | 1.24+, spelled `synctest.Run` | 1.24 experimental behind `GOEXPERIMENT=synctest`; **GA in 1.25 as `synctest.Test`**; `Run` **removed in 1.26** — source spelling is already dead |
| `testing.T.ArtifactDir` | 1.24+ | **1.26** — source wrong |
| `pprof.Lookup("goroutineleak")` | 1.27+ | 1.26 behind `GOEXPERIMENT=goroutineleakprofile`, GA 1.27 — correct for GA |

Sources: [Go 1.24](https://go.dev/doc/go1.24), [Go 1.25](https://go.dev/doc/go1.25),
[Go 1.26](https://go.dev/doc/go1.26), [goroutine leak profiles](https://go.dev/blog/goroutine-leak-profiles).

**D2 — Overengineering table placement.** `go.md`, not `change-discipline.md`. Stated in W2.

**D5 — `business-analysis` output language.** Parameterised, defaulting to the user's language.
Stated in W13. No behaviour change for the current maintainer.

> **Caveat, raised in review round 2 and accepted:** this is a maintainer question closed by the
> author choosing a default, which is PR8 in form. It stands only because the choice is behaviour-
> preserving for this maintainer and reversible in one line. **W13 is not implemented in v2.5.0** —
> it is carried as the delivery's one open item for the maintainer to confirm or overrule.

**D3 — Draft-PR ceremony scope.** *Reopened and re-closed after plan review.* The first answer
("both paths, including `/code-review-gate`") was wrong: `code-review-gate` creates no PR. Corrected
answer — both **real** PR paths: the delivery PR in `skills/multi-agent` and the hotfix PR in
`skills/bug-fix`. `code-review-gate` is out of scope for W6 because it has no PR step to flag.
Stated in W6 with the verified line citations.

---

## Task Manifest *(added after plan review — PR11)*

Lightweight, for the `/task` lane. Four stories, each independently reviewable and independently
revertible. Ordered so the highest-radius change ships last.

| # | Story | Workstreams | Files | Why grouped |
|---|---|---|---|---|
| S1 | PR ceremony + stress/QA sharpening | W6, W5, W4 | `delivery-and-worktree.md`, `multi-agent`, `bug-fix`, `stress.md`, `qa.md` | Small independent diffs across agent and skill files; no shared text |
| S2 | Prose standards | W7 | new `references/prose-standards.md`, `handoff`, `release-management` | Fully independent; droppable on its own self-application test |
| S3 | Go rules | W1, W2, W3, W3b | `go.md` only | One token-budgeted edit to one file, verified against the ≤250-line ceiling as a unit |
| S4 | Skill surface | W8, W9, W10, W11, W12 | 23 `SKILL.md`, `CLAUDE.md`, `validate-wiring.py` | Must land together: W8 step 2 depends on step 1, and W11's `rote` trim is what gets W8 under budget |

W13 is not a story — it is an open question for the maintainer (see W13).

**Artifact ceremony, stated deliberately.** There is no `PRD.md` and no `codebase-map.md` for this
delivery. Under Proportionality the `/task` lane does not require them, and the Reuse Map with
`file:line` citations substitutes for the map. Recorded here so a later reader reads the absence as
a decision rather than an omission.

---

## Sequencing

**S1** (W6 → W5 → W4) → **S2** (W7) → **S3** (W1 → W2 → W3 → W3b) → **S4** (W9 → W10 → W11 → W12 → W8).

Smallest and most independent first. The four `go.md` workstreams land together as one
token-budgeted edit rather than four. W7 is independent and can be dropped without disturbing
anything else if its self-application test comes back empty.

Inside S4 the cheap corrections (W9, W10) go first, then W11's `rote` trim — which is a
precondition for W8 fitting under the Tier 1 ceiling — and **W8 last**, because it is the only change
in this delivery that affects every session in every project.
