# Changelog

## [2.4.3] — 2026-08-31

### Fixed

- **`test-git-hooks.sh` was testing the machine, not the hook.** `run_hook` prepended the stub
  directory to the *caller's* `PATH`, leaving the real binaries reachable further down — so every
  case asserting a tool is absent silently depended on that tool not being installed. The suite was
  green until `jscpd` was installed on the author's machine, then failed nine assertions for a
  reason with nothing to do with the hooks. It now runs against `<stubs>:/usr/bin:/bin`, which
  carries git, python3 and the coreutils the hooks need while keeping anything from
  `/usr/local`, `/opt/homebrew` or an npm prefix out of reach unless a fixture stubs it explicitly.
  Verified green both with `jscpd` installed and with it hidden, and falsified by reverting to the
  caller's `PATH`.

- **`install.sh --dry-run` printed `npm install -gjscpd`** — a copy-pasteable command missing its
  space. The real install path was always correct; only the dry-run message was wrong.

### Changed

- **The engineering standards are no longer `@`-imported by the repo's own `CLAUDE.md`.** Anyone
  who installed the devkit already has that identical file imported globally, so working on the
  devkit itself loaded ~6,560 tokens of it twice per session. The repo file now points at the
  canonical path and tells an uninstalled contributor how to get it. This changes nothing for any
  other repository, where the file was only ever loaded once.

- **Both install routes documented as first-class, with their difference stated honestly.** A
  Claude Code plugin cannot write to `.git/hooks/` and cannot ship a `CLAUDE.md`. The skills and
  agents restate inline the rules they depend on, so the plugin route works correctly standalone —
  what it does not carry is the repo-wide contract (Coding Discipline, Proportionality, Security
  Defaults, and the objectives that break ties). The README now says so and gives the three lines
  that add it, alongside `install.sh` for a machine configured end to end. Neither route is going
  away.

- `marketplace.json` still described an 11-agent pipeline without the Plan Reviewer.


## [2.4.2] — 2026-08-31

### Changed

- **`reviewer.md` audited against its own new rule** — *additions must earn their tokens* — after it
  grew 2,894 → 5,972 tokens in one release. It loads on every review, so that growth was the
  session's worst token regression and had not been audited itself. Now 5,614: **358 tokens removed,
  zero rules removed.** Verified identical before and after: every PE/RD/CD identifier, all six hard
  gates, all nine security deep-dive sections, the scoring bands and the output block.

  What went, all of it duplication or prose restating a rule stated elsewhere: the Language-Specific
  section restated the specialist mandate and version policy that live in the language file the
  Reviewer is about to load (now a pointer plus the two severities the language file does not
  assign); the Design & Durability closing paragraph restated the slop/overengineering table twelve
  lines above it; the Reuse section restated the `jscpd` command that `quality-gate-reference.md`
  owns; and the Principal Engineer Standard and Correctness procedure were compressed without losing
  a property, a step, or a severity.

  What deliberately stayed: the three lines in the closing `Rules:` block that repeat the cost test,
  the linter rule and the idiom rule. Terminal repetition of the governing constraint is
  load-bearing for adherence, and trading that for ~90 tokens is the wrong side of quality-over-speed.


## [2.4.1] — 2026-08-31

### Fixed

- **The duplication scan was reading `.git/`.** jscpd's ignore list omitted it, so git's own
  sample hooks were counted as duplication — noise in the debt report, and a polluted denominator
  under every percentage the gate prints. Found by running the gate end-to-end against real jscpd
  output rather than the hand-written report fixtures the suites use: the stubbed tests prove the
  attribution logic and the hook's wiring, but they stub the invocation itself, so an ignore-list
  defect is structurally invisible to them. That limitation is now stated in the suite instead of
  left to be rediscovered.


## [2.4.0] — 2026-08-31

### Added

- **Duplication attribution — pre-existing debt no longer blocks a push it did not cause.**
  A repo-wide percentage answers the wrong question: on any codebase with history it is dominated
  by debt the current change never touched, so the gate either fails on day one (and gets disabled,
  taking the real finding with it) or is set so loose it never fires. `git-hooks/dup-attribution.py`
  now splits jscpd's clones by *who wrote them*, **line-level, not file-level**: a duplicated line
  counts against the delivery only when it lies in a range the diff actually added, so touching one
  function in a 900-line legacy file does not make its other clones yours. Introduced duplication
  blocks; pre-existing is reported as debt to route to a follow-up. With no merge-base the gate says
  `ATTRIBUTION UNAVAILABLE` and gates everything — loud, never a silent skip.

- **Blast radius became a measurement instead of a guess.** It is the number the whole delivery is
  sized and split on, and it was previously one line in the codebase map. Now: enumerate with
  find-references rather than estimate, one line per caller (`file:line — what it assumes — does the
  change hold?`), one hop past the direct callers for anything changing an error value, nil-ness,
  ordering or type width, and **the non-code callers counted too** — serialized payloads, DB
  columns, API consumers, generated clients, dashboards, alert queries, which `find-references`
  structurally cannot see. It becomes a table in the delivery file, rows in each story, a verified
  check in the Plan Reviewer (PR9, now MAJOR — *verify it, do not read it*), and the second step of
  the Reviewer's correctness procedure.

- **PR sizing, because review is where defects are actually caught.** Reviewer effectiveness
  collapses with diff size for an agent exactly as for a human: past a few hundred lines reading
  becomes skimming, and the resulting approval means nothing. Manifest rows now carry a
  `Projected diff` and are sized ≤ 200 lines (target) / 400 (soft ceiling) / 800 (hard — split, not
  justified). The Plan Reviewer gains PR11 for stories that cannot be reviewed at their planned
  size, and `/pr-review` measures the diff **first** and reports > 800 as a finding rather than
  absorbing it silently. Mechanical bulk mixed with logic is a finding at any size — 40 lines of
  logic inside 600 mechanical ones is the worst diff there is, and worse than either half alone.

- **One story, one branch, one PR, one review.** Story branches were optional and had no PR of their
  own; a whole delivery arrived as a single unreviewable diff. `feat/{key}-{story-slug}` is now the
  default unit of review, cut from the release branch with its own PR into it, where `/pr-review`
  runs with that story's ACs, Test Case table, Reuse Map and Blast Radius in context — the review
  with the tightest spec and the smallest diff. The release PR to `main` is the second review with a
  different job: cross-story duplication and drift from the plan, which no story review can see.
  Merges are `--no-ff` so each story stays legible as a unit, and the delivery can be read commit by
  commit instead of reconstructed from one giant merge.

- **`install.sh` installs the gate tools.** `jscpd` ships via npm, so it cannot ride the system
  package manager list. `--check` now reports it, and the installer offers it. Absent, the hook says
  UNENFORCED rather than blocking — a hook that dies on a fresh machine gets uninstalled, and that
  costs every gate rather than one.

### Changed

- **Every language file reaches Go's bar.** Go had a `Structure and Idiom` section with a named
  authority chain (Uber Go Style → ardanlabs → Effective Go); the other ten had nothing, so the
  devkit was measurably better at Go than at Java, and better at backend than frontend. All eleven
  now carry an authority chain and an idiom table: **Java** Effective Java 3e → Google Java Style;
  **TypeScript** Google TS Style Guide → `typescript-eslint` recommended-type-checked; **React**
  react.dev Rules of React → Testing Library principles; **Next.js** App Router docs (Server
  Components + caching); **PHP** PER Coding Style 2.0 → PHPStan level 9; **Rust** Rust API
  Guidelines → `clippy::pedantic`; **Kotlin** Kotlin Coding Conventions → Now in Android;
  **Flutter** Effective Dart; **htmx** htmx docs → *Hypermedia Systems*; **HTML/CSS** WHATWG →
  WAI-ARIA APG. `htmx.md` also gained the Linting Commands section it had been missing.

- **`go.md` deepened well past the others** (69 → 155 lines), with sections the file did not have at
  all: **Concurrency** (goroutine ownership, context threading, `errgroup` fan-out, channel
  direction, mutex placement, bounded work, `goleak`), a Go-specific **Security** table
  (constant-time comparison, `html/template` vs `text/template`, `ReadHeaderTimeout`/Slowloris,
  `MaxBytesReader`, `filepath.Clean` **plus** a containment check, zip slip, SSRF via a guarded
  `DialContext`, TLS `MinVersion`, `exec.Command` without a shell, gosec G115 narrowing conversions,
  JWT algorithm assertion), **Performance and Allocation**, **Testing Idiom** (`t.Parallel`,
  `t.Helper`, `httptest`, golden files, fuzz targets, `-race` always), **Module and Build Hygiene**,
  and **Observability**. 26 new review flags with severities. Lazy loading means this costs nothing
  to a story in another language.

- **Specialist mandate + version policy, in every language file and in the Coder and Reviewer.**
  For a story's language the agent is a specialist, not a generalist transliterating another
  language's habits — code that runs but that the language's own community would reject at review is
  a defect. Target the current stable release, confirmed via context7 rather than from memory; when
  the project pins an older version, code to *that* version's idiom and say so at handoff, because
  an API newer than the pin is a defect here, not an improvement. Libraries may be updated when the
  story needs it and the change is non-breaking; a major-version bump is its own story. The Reviewer
  flags use of a post-pin API as MAJOR — it builds on the author's machine and fails on the pinned
  toolchain.

- **Lazy language loading stays one file, and the stale figure is fixed.** The files are now 60–90
  lines (was "~45"), and the full set is ~790 — so loading one to use one is worth restating: the
  Coder and Reviewer load exactly the language in play, never the index.

- **CLAUDE.md opens with what the Harness optimises for**, priority-ordered, as the tie-breaker when
  two rules collide: confidence → production-ready → airtight plans → readability → language best
  practice → scalable and secure → token efficiency. Token efficiency is last deliberately: it is a
  constraint on *how* the other six are achieved, never a reason to skip one. Additions to that file
  must earn their tokens against one of the seven.

### Testing

- New suite `test-dup-attribution.sh` (11 assertions), wired into CI. It proves the split in both
  directions — a clone the delivery wrote blocks, an identical clone it did not does not — plus the
  line-level case that decides whether the gate is usable at all: a clone sitting in a file the
  delivery *did* touch, at lines the diff never went near, must not block.
- `test-git-hooks.sh` 25 → 27, rewritten for the new contract: the hook's job is now to honour the
  attribution verdict, and both directions are proven, on fixtures that are real git repos.
- Every assertion in both suites was falsified before commit — attribute-everything-to-debt,
  treat-everything-as-introduced, file-level instead of line-level, threshold never compared,
  no-baseline gating nothing, unreadable report passing, verdict ignored, gate nested inside the Go
  block. Each break was caught by the assertion written for it.


## [2.3.0] — 2026-08-31

### Added

- **Codebase discovery before architecture** (planning Phase 0.5). The Architect used to design
  from the PRD alone — as if the repository were empty — which is where duplicated components
  originate: a plan that never saw the existing rate limiter specifies a new one, and no gate
  downstream can compare the two. A read-only `haiku` pass now writes
  `docs/deliveries/{key}/codebase-map.md` first: blast radius · reusable symbols · **prior art**
  (the near-miss is the duplication risk) · conventions · extension points · contracts in force ·
  test conventions, every entry cited `file:line`. Greenfield repos record the empty result
  rather than skipping — "nothing exists yet" is a fact the plan needs stated, not inferred.

- **Reuse Map in the delivery file.** Every planned component now carries a decided row —
  `reuse: file:line` / `extend: file:line` / `new:` with the closest existing thing named and why
  it does not fit. A `new` with no citation is unjustified: "nothing similar exists" is a claim
  about the codebase and needs the same evidence as any other. The Scrum Master copies the
  relevant rows (plus the layer's convention exemplar) into each story, so the Coder is told what
  to reuse instead of being left to search for prior art on her own.

- **Plan Reviewer agent — Priya** (`agents/plan-reviewer.md`, `sonnet`, planning Phase 2.5).
  `/grill-me` interrogates a plan from inside the context that wrote it and never opens the
  repository, so a plan could survive it intact and still specify a component that already
  exists, an interface whose real signature differs, or an AC with two readings — each cheap
  here and expensive after the Coder has built to it. Priya is a fresh reader **with the
  codebase open**, and she runs *before* human validation: PR1 already exists · PR2 reuse not
  declared · PR3 contradicts existing code · PR4 convention breach · PR5 ambiguous AC (CD7 caught
  at plan time) · PR6 unfalsifiable Test Case row · PR7 untraced requirement · PR8 decision
  deferred into code · PR9 blast radius unstated · PR10 not independently testable. Any MAJOR
  returns the plan to the Architect; max 2 rounds, then the remainder goes to the human as
  questions rather than looping.

- **Duplication gate, ≤ 3%, all stacks.** `jscpd --threshold 3 --min-lines 8` in `pre-push`
  (language-agnostic, before any per-stack gate), in the QA gate list, in the story Definition of
  Done, and as a Reviewer hard gate. A perfect duplicate lints clean, types clean and covers
  clean — no other sensor in the harness can see it, and no reviewer reliably reads two files at
  once, so it surfaced only as rework weeks later. jscpd owns the comparison itself (it exits
  non-zero on the threshold), so this hook has no percentage to print-but-never-compare — the
  failure mode the 2.2.1 coverage gates were written to close. Per-repo tuning belongs in a
  committed `.jscpd.json`; loosening the hook's flags is not tuning. Missing tool WARNs rather
  than blocking, matching every other optional tool here.

- **PR review as the pipeline's terminal step.** `/pr-review` existed but no pipeline ever called
  it, and the story-scoped Reviewer never sees the delivery as one diff — so cross-story
  duplication and drift from the plan were structurally invisible. `/task` and `/multi-agent` now
  run it on the PR they open. It gained a **Gaps block** (posted as a general comment, since it
  has no line to attach to): unimplemented ACs · spec drift · missing Test Case rows · Reuse Map
  departures · duplication % · untraced changes.

### Changed

- **The Reviewer now receives the acceptance contract**, not just the diff. Both pipeline loops
  dispatched it with "full code, language-specific checks" — no story, no ACs, no delivery file —
  which silently fired the Reviewer's own escape clause and disabled CD1, CD3 and CD7 on every
  run. That is how a diff that builds the wrong thing scores 8/10. It now gets the story, the
  Reuse Map, and `codebase-map.md`, and states explicitly which checks are disabled if they are
  ever missing.

- **Correctness became a procedure instead of a one-line list.** It had ~40 lines of security
  checklist against a single line for logic. Now five ordered steps: trace every AC to a
  `file:line` and read that path · read the existing callers of every changed exported symbol ·
  check the diff against the delivery file's data-flow diagram · walk the boundaries (empty, zero,
  one, max, one-past-max, nil, duplicate, out-of-order, concurrent) · follow one error to its exit.

- **The Reviewer reviews at a principal-engineer bar, in any language** — *would I own this in
  three years, after the author has left and the requirements have moved twice?* Priority order
  **correct → legible → durable → small**, judged in the code's own idiom rather than another
  language's habits. New `Reuse & Duplication` (RD1–RD6) and `Design & Durability` (PE1–PE14:
  mixed abstraction levels, responsibility sprawl, leaky abstractions, temporal coupling, boolean
  parameters, primitive obsession on invariants, shared mutable state, hidden side effects,
  context-stripped errors, untestable seams, deep nesting, what-comments, invented conventions,
  speculative generality) categories, mirrored into the `/pr-review` checklist.

  **Slop and overengineering are symmetric findings** — a copy-pasted block and an interface with
  one implementation are both filed, because both ship "for flexibility" and neither is flexible.
  And strictness is not volume: every finding must pass the **cost test** (name the future change
  it makes harder, or the concrete way it breaks), style the linter owns is never a finding, and a
  category with more than ~5 findings reports the 3 that matter plus the pattern behind the rest.
  Twenty nits bury three MAJORs, and a review nobody finishes reading changes nothing.

### Testing

- `test-git-hooks.sh`: 19 → 25 assertions. The duplication gate is proven to block above
  threshold, to pass a clean repo, to warn (not block) when jscpd is absent, and to run outside
  any stack block. Each was falsified before commit — swallow the exit code, force a failure,
  make the missing-tool branch block, and nest the gate inside the Go block; every break was
  caught by the assertion written for it.


## [2.2.1] — 2026-08-31

### Fixed

- **Coverage gates that could not fail.** `pre-push` announced "tests + coverage" for Rust,
  PHP, Java (Maven and Gradle) and Kotlin and then compared nothing — the threshold existed
  only in `quality-gate-reference.md`. Five languages had a declared minimum and a sensor
  incapable of enforcing it, which reads as green. Each now parses a real number and blocks
  below it: Rust ≥85% via `cargo tarpaulin`, PHP ≥80% from `--coverage-text`, Java ≥85% from
  JaCoCo's csv, Kotlin Android ≥85% from Kover's xml (one parser — Kover emits JaCoCo's shape).

  The same hole one step later: Go and Flutter *did* compare their numbers but passed silently
  when the number came back empty. `coverage_gate` now refuses an unmeasured gate outright.
  Flutter's percentage extraction also moved off `grep -oP`, which BSD grep has no PCRE for and
  this hook ships to macOS.

  Where the measuring tool is absent entirely the hooks still WARN rather than block — the
  file's existing convention for `govulncheck` and `cargo-audit` — but the warning now says
  UNENFORCED out loud instead of printing nothing.

- **Android projects on the Kotlin DSL got no Gradle gates at all.** Both hooks detected Android
  with `grep 'android {' build.gradle`, which fails on a `build.gradle.kts`-only project. In
  `pre-push` the inverted copy of that test then routed such a project into the **Java** branch,
  where `jacocoTestReport` is not a registered task; in `pre-commit` the Java block correctly
  excluded it and the Kotlin block never claimed it, so nothing ran. One `is_android_gradle`
  helper per hook now checks both DSLs.

- **`/handoff` never wrote the one section meant to outlive the delivery.** CLAUDE.md and
  `coding-pipeline/references/progress-file.md` define `PROGRESS.md` as
  Done/Failed/Current State/Next/**Lessons**, and assign `Lessons` to `/handoff` explicitly.
  The handoff skill's schema line and its own divergent copy of `progress-file.md` both stopped
  at `Next`, so the cheapest cross-session memory the harness has was specified everywhere and
  written nowhere. The skill now requires it, and the mirror carries the section plus the
  precedence header the `engineering` mirror already uses (canonical wins on conflict).

### Added

- **`.github/scripts/test-git-hooks.sh` — 19 assertions across `pre-commit` / `pre-push`.**
  CI ran shellcheck and `bash -n` over these files, proving they parse, never that they gate.
  Both defect classes above survive a syntax check. Fixtures stub every external the hooks shell
  out to, so a case exercises the hook's own logic and not the machine's toolchain; each
  language is asserted below its minimum, at it, and — where the number is parsed from tool
  output — with it unreadable. Wired into the `hooks` CI job.

  Written RED-first against the unfixed hooks (11 failures reproducing both defects), then every
  fix falsified in turn: the `.kts` arm removed from each helper, `coverage_gate`'s comparison
  deleted, its empty-value guard deleted, and the Kover xml parser stubbed out — each break
  observed to fail exactly the assertions that encode it, then restored.

## [2.2.0] — 2026-08-30

### Added

- **Go reference gained a Structure and Idiom table** — error inspection with `errors.Is` /
  `errors.As` rather than string matching, concrete types or generics instead of
  `interface{}` / `any`, the `cmd/` · `internal/` · `business/` · `foundation/` layout, the
  preferred dependency set, package naming, safe zero values, `init()` avoidance, and the
  reflection restriction. The file already named Uber Go Style and ardanlabs/service as its
  authorities but carried none of the structural rules those authorities are consulted for.

- **Next.js reference gained a bundle-growth review flag** (`@next/bundle-analyzer`).

  Both gaps were found by diffing a real operator's personal `CLAUDE.md` against the shipped
  references: 52 per-language rules were compared, and these six were the only ones the devkit
  could not account for. They are the reason a personal standards file could not simply be
  replaced by the devkit `@include` — the rules load on demand now, so it can.

## [2.1.1] — 2026-08-30

### Fixed

- **`destructive-guard` blocked legitimate commands.** Two checks matched a substring appearing
  anywhere in the command rather than the command's structure, and both fired during real use:

  - The force-push check scanned the whole line for a space-plus sequence, so a push followed by
    `&& echo 1 + 2` was refused over an unrelated plus sign. The check now extracts only the
    `git push` invocation, cut at the first `;`, `&`, or `|`, and inspects that segment. The same
    fix stops a `-f` belonging to a *later* command in the line from reading as a force push.
  - The DDL check matched `DROP TABLE` anywhere, so grepping for that string in a migrations
    directory was refused for reading about DDL rather than running any. It now also requires a
    database client (`psql`, `mysql`, `sqlite3`, `mongosh`, and similar) in the command.

  Precision is not a nicety for a guard: one that fires on safe commands trains the operator to
  disable it, and a disabled guard blocks nothing at all. Both false positives were found by the
  guard blocking this session's own tool calls.

- Coverage widened while tightening: the short `-f` flag, a force refspec (`+branch`), and a
  delete refspec (`:branch`) are now caught, none of which the previous `--force`-only match
  detected reliably.

  Seven test cases added (37 total), each falsified — every check removed in turn, the suite
  observed to fail on its own assertion, then restored. One mutation confirmed the segment
  extraction is load-bearing: scanning the whole line again made `rm -rf ./build` trip the
  force-flag check.

## [2.1.0] — 2026-08-30

### Added

- **Change Discipline is now a review sensor, not just prose.** Coding Discipline rules 1–3
  and 6 had no enforcement path: nothing in the review chain ever failed a diff for scope
  creep, so "surgical changes" was aspirational. `coding-pipeline/references/change-discipline.md`
  defines CD1–CD7 — untraceable change, single-use abstraction, unrequested surface,
  unreachable-state handling, pre-existing dead code deleted unasked, self-inflicted orphan,
  silently-resolved ambiguity — each with a severity for both consumers and a worked ❌/✅
  pair. The operational test: every changed line must trace to a sentence of the request.

  Wired into all three review paths: `coding-pipeline:reviewer` (new review category),
  `pr-workflow`'s `review-checklist.md` (mirrored table), and `engineering:code-review-gate`,
  whose Reviewer payload now carries **the original request verbatim** — without it CD1, CD3,
  and CD7 are unjudgeable, and the reviewer is told to say so rather than infer intent from
  the diff under test.

- **Proportionality section in `CLAUDE.md`** — the standards previously read as uniformly
  "non-negotiable" with no guidance for a typo fix, so ceremony got applied by feel. Now
  explicit: ceremony scales with the change, standards never do. Security defaults, quality
  gates, spec-first discipline for behaviour changes, CD1–CD7, and never-merge-to-main apply
  at every size; the four lanes (Trivial → inline spec-first → `/task` → `/multi-agent`)
  scale artifacts. The lane is stated before starting; an unstated lane defaults to the
  heavier one. Lanes do not loosen skill routing.

- **"Is the Harness working?" section in `CLAUDE.md`** — five signals countable from artifacts
  the devkit already produces (scope-creep findings, question timing, rework, sensor escape,
  test honesty), with an explicit anti-Goodhart clause: they are human-read diagnostics, never
  targets and never a gate. A stretch of healthy readings is licence to remove ceremony.

### Changed

- Coding Discipline rules 2 and 3 carry their operational tests inline, pointing at the CD ids.

## [2.0.0] — 2026-08-30

### Changed — BREAKING

- **`bmad_v6` plugin renamed to `coding-pipeline`.** The pipeline used BMAD v6 as its
  starting point, but it has diverged far enough that the name was actively misleading:
  delivery worktrees and release branches, spec-first falsification instead of TDD, a
  per-agent model-tier table, an independent Reviewer/Stress/Verdict chain, and a Tuner and
  DevOps stage that BMAD has no equivalent of. The name now describes what the plugin is
  rather than where it came from.

  Namespaces move with it: `bmad_v6:coder` → `coding-pipeline:coder` (all 18 agents), and
  `/bmad_v6:<skill>` → `/coding-pipeline:<skill>` (all 6 pipeline skills).

- **Two pipeline skills renamed to remove the stutter** the new plugin name introduced:
  - `multi-agent-coding-pipeline` → `multi-agent` (`/coding-pipeline:multi-agent`)
  - `task-coding-pipeline` → `task` (`/coding-pipeline:task`)

  `analysis`, `planning`, `architecture`, and `bug-fix` are unchanged.

- **`references/bmad-artifacts.md` → `references/pipeline-artifacts.md`.** Same schemas and
  handoff contracts; the artifacts were never BMAD's.

- Marketplace and plugin descriptions rewritten to drop the BMAD framing, and the demo
  asset `assets/pipeline-ui.html` relabelled (its `bmad-*` CSS classes are now `plan-*`).

### Added — session sensors (deterministic, no model in the loop)

Ideas mined from [affaan-m/ecc](https://github.com/affaan-m/ecc) and adapted to this harness
rather than imported. ECC's catalog breadth was deliberately not taken; only the mechanisms that
close a gap the devkit already had were.

- **`destructive-guard.sh`** (PreToolUse → Bash) blocks force-push, remote branch deletion,
  `reset --hard`/`clean -fd` on a checked-out mainline, recursive deletes aimed at `/` or `$HOME`,
  `curl | sh`, `chmod 777`, and `DROP`/`TRUNCATE` issued from the shell. "A delivery ends in a PR,
  never a rewritten remote branch" was a Guide with no Sensor behind it; now it has one.

- **`secret-write-guard.sh`** (PreToolUse → Write/Edit) blocks writing a recognisable live
  credential into the tree. `env-guard` covered reading secrets; nothing covered writing one.
  Only provider-specific high-entropy prefixes are matched — a generic `password\s*=` rule would
  fire on documentation and fixtures, and a guard that cries wolf gets switched off.

- **`session-tracker.sh` + `delivery-gate.sh`** (PostToolUse / Stop) record which source files
  changed and whether any test, lint, or type-check ever ran, then refuse to call the session done
  when code changed and no gate did. CLAUDE.md already required `/engineering:code-review-gate`
  after every coding task; that requirement held only when the model remembered it.

- **Hook profiles.** `DEVKIT_HOOK_PROFILE=off|standard|strict` and
  `DEVKIT_DISABLED_HOOKS=<id>,<id>`. `strict` makes `delivery-gate` block — but only once per
  session, because a Stop hook that blocks forever traps the operator rather than the mistake.

- **`.github/scripts/test-hooks.sh`** — 30 behaviour assertions covering both directions for every
  guard (blocks what it must, stays out of the way otherwise) plus malformed-payload fail-open.
  Every case was falsified: the guard's logic was removed, the suite observed RED, then restored.
  Two delivery-gate tests were rewritten during that pass — they asserted only an exit code, and
  a warn and a clean pass both exit 0, so deleting the logic left them green.

- **`.github/scripts/validate-wiring.py`** — walks marketplace ↔ plugin manifests, hooks.json ↔
  scripts, every in-repo markdown link and path reference, and every `plugin:agent` reference.
  Each is a file pointing at another file that nothing executes at authoring time, so a rename
  breaks them silently. Both scripts run as CI jobs.

### Fixed

- **`env-guard.sh` had stopped blocking anything.** It read `file_path`/`command` from the top
  level of the hook payload only, while Claude Code sends them nested under `tool_input`. Every
  `.env` read had been passing the guard. Payload access now goes through a shared
  `hook-lib.sh` helper that accepts both shapes, and the regression is covered by six assertions.

- **Five `SKILL.md` files linked to `skill.spec.yml` and `deps.toml` as clickable relative
  links.** Both are git-ignored skillspec artifacts, so the links were dead in every clone and
  install. They now read as plain backticked filenames, matching how `pr-workflow`'s skills
  already referenced them.

- **`install-global.sh` copied `references/*.md` with a flat glob**, which would have shipped the
  new per-language index without the files it points at.

### Added — machine bootstrap

- **`install.sh` at the repo root.** One command takes a bare machine to a configured setup:
  detect the OS (macOS, Linux, WSL) and architecture, pick the package manager (Homebrew, apt,
  dnf, yum, pacman, zypper, apk), install what is missing, resolve the source tree, copy the
  devkit into `~/.claude`, wire the hooks, and record the installed commit. Flags: `--check`
  (report only, writes nothing), `--yes`, `--no-deps`, `--dry-run`, `--home DIR`.

  Re-running is the expected case, not the exception. The installed commit is recorded in
  `~/.claude/devkit/install-state.json` and compared against the source commit, so a second run
  reports "up to date" instead of redoing work. When run from inside a checkout it uses that
  checkout and fast-forwards it if it is behind its remote — but never touches a tree that is
  dirty or has diverged, because resolving that is the operator's call, not an installer's.
  Run from outside a checkout, it clones to `~/.local/share/claude-devkit`.

  It does not pipe anything into a shell. The devkit's own `destructive-guard` blocks
  `curl | sh`, and an installer that breaks its own rule is not worth shipping: the Claude Code
  installer is fetched to a file, its path shown, and executed only after confirmation — and
  `npm` is preferred where available so nothing is downloaded at all.

- **`wire-claude-settings.py`.** The hook wiring used to be printed as JSON for the operator to
  paste by hand, which meant a machine could have every guard installed and none of them active.
  It is now merged into `~/.claude/settings.json` directly, with the hook graph read from the
  plugin's own `hooks.json` so the two cannot drift.

  The merge is conservative because that file holds the operator's permissions and model config:
  unrelated keys and non-devkit hooks are preserved, devkit entries are replaced rather than
  appended (re-running never double-registers a hook), entries pointing at scripts the devkit no
  longer ships are dropped — which is what heals the `bmad_v6` → `coding-pipeline` rename — and a
  `settings.json` that is not valid JSON aborts the install instead of being overwritten.

- **claude-mem wired into the bootstrap.** [claude-mem](https://github.com/thedotmack/claude-mem)
  persists context across sessions, which is the same Memory leg `PROGRESS.md` serves from the
  other end: `PROGRESS.md` is the deliberate record a pipeline writes at each checkpoint,
  claude-mem compresses and replays the conversation itself. Installed with
  `npx claude-mem install` rather than a global npm install, because its own docs are explicit
  that the global install does not register its hooks.

  Treated as optional throughout: a preflight gates on Node >= 20 and `npx`, an already-installed
  copy is left alone, `--no-claude-mem` opts out, and a failure warns instead of aborting — a
  third-party tool must never take the devkit install down with it. The preflight is a separate
  function from the install so the gating is testable without a network call.

- **`install.sh` verifies its own work.** After the copy, it asserts every shipped hook script is
  referenced by `settings.json` and fails loudly otherwise. Staging the scripts and activating
  them are separate steps, and a machine with all seven guards on disk and none referenced is a
  silent failure worth catching.

- **`.github/scripts/test-install.sh`** — 20 assertions against a throwaway `HOME`, covering the
  merge semantics, the platform detection helpers, `--check` making no changes, the state file,
  and the up-to-date path. All 18 mutations were observed RED before the suite was accepted.

  Three defects surfaced during that falsification pass and were fixed: `install.sh` wired the
  hooks a second time after `install-global.sh` had already done it (dead duplication, now a
  verification step); sourcing `install.sh` leaked its `set -euo pipefail` into the test shell, so
  a failing assertion aborted the suite instead of reporting; and `detects_os` put a
  `$(detect_os)` call inside its own failure message, where the command substitution reset `$?`
  before it could be asserted — the test could not fail.

### Removed

- **`plugin.sh`.** A thin wrapper around `claude plugin marketplace add` / `install`, which is
  done directly in Claude Code. The README documents those two commands for anyone who prefers
  the plugin manager; the installer deliberately stays out of it.

- **`assets/pipeline-ui.html`.** Nothing referenced it, it re-implemented the agent personas as
  inline prompt strings that had already drifted from `agents/*.md`, and it called
  `api.anthropic.com` directly from a browser page — a shape this devkit tells people not to
  ship. Recoverable from history if it is ever wanted back.

### Changed — token and validation

- **`references/language-rules-reference.md` (343 lines, 11 languages) split into
  `references/languages/<language>.md`.** Agents were already told to "load only the section for
  the story's Language", but a section of one file costs the whole file — ~340 lines to read ~40.
  Each language file now repeats the test rule, the context7 rule, and the frontend-hardening
  rule so a single-file load is self-sufficient; the old path is now a 40-line index.

- **Architect gained a brownfield spec-mining step.** When a delivery modifies existing code, the
  behaviour it has today is an unwritten spec, and the Test Case table only covers what is being
  added — so anything the change silently alters is untested by construction. The architecture now
  inventories current observable behaviour with its callers and a Preserve/Change/Drop
  disposition, and folds it into the frozen table (Preserve rows become characterization rows and
  still need a falsifying break; Change rows need two entries; Drop rows need the caller search).

- **Verdict gained a five-axis self-check** — Evidence, Traceability, Independence, Residual risk,
  Actionability — with the rule that any axis below 5 must name the specific gap. A verdict is the
  one artifact nobody downstream re-checks. Evidence or Independence below 3 blocks PRODUCTION
  READY; Traceability below 3 is NOT READY.

- **Loop Integrity added to `quality-gate-reference.md`**, applying to every fix loop: the verifier
  may never be moved to reach it (lowering a coverage threshold, adding `skip`, weakening an
  assertion, downgrading a lint rule, editing a frozen Test Case row to match the code, widening a
  type to `any` — all blocking defects, not fixes); an iteration whose failing test, gate, and
  message are identical to the previous one stops the loop instead of spending the budget; and
  compaction happens at story boundaries, never between a story's dispatch and its Verdict.

- **`PROGRESS.md` gained a `Lessons` section** — the only part meant to outlive the delivery. A
  rule plus the evidence that produced it, project-scoped, deleted when it turns out to be wrong.

- The Bug-Fix Loop Protocol's "tests are written RED-first" rule is now scoped to that loop
  explicitly, where every iteration is fixing a known defect. Stated unscoped, it contradicted the
  spec-first discipline that governs everywhere else.

### Versions

| Plugin | Version | Why |
|---|---|---|
| `coding-pipeline` | 1.3.0 → **2.0.0** | Renamed from `bmad_v6`; skill names changed. Breaking for every install. |
| `engineering` | 1.1.2 → **1.2.0** | Depends on the renamed namespace (`coding-pipeline:reviewer`, coverage-threshold reference). |
| `devtools` | 1.1.1 → **1.2.0** | Dispatches `coding-pipeline:rote-adapter`. |
| `pr-workflow` | 1.1.0 | Unchanged. |

### Upgrading

There is no alias mechanism for renamed plugins, so an existing install must be replaced:

```
/plugin uninstall bmad_v6@claude-devkit
/plugin install coding-pipeline@claude-devkit
```

Anything that hardcodes the old namespace needs updating — most commonly a personal
`~/.claude/CLAUDE.md` skill table and the `enabledPlugins` key in `~/.claude/settings.json`.
Historical entries below intentionally keep their original `bmad_v6` paths; they describe
the tree as it was at the time.

## [1.3.0] — 2026-08-30

### Changed

- **TDD replaced with spec-first testing across every pipeline, agent, and skill.**
  Code is no longer written test-first. Instead the test specification is frozen *before*
  the code and the tests are written *after* it, then proven by falsification. Four steps:
  **Spec** (Architect freezes a Test Case table) → **Implement** (Coder builds to it) →
  **Test** (Coder writes exactly those rows) → **Falsify** (Coder breaks each code path,
  observes the test fail on its own assertion, restores).

  **Why this changed.** Red→Green→Refactor was dropped after real usage showed it wasn't
  paying for itself. It burns a large amount of tokens — every acceptance criterion costs an
  extra write-run-read cycle before any implementation exists, plus the RED output quoted
  back into context, multiplied across every story in a pipeline — and the code quality it
  bought did not measurably exceed what a tight plan plus a rigorous post-hoc test pass
  produces. Worse, agent-driven TDD degraded into writing whatever test would go red fastest,
  which is a bias toward shallow tests, not good ones. The leverage was never in the ordering;
  it was in deciding *what to assert and why*. So that decision moved upstream into the
  architecture, where it is made once on `opus` and reused, instead of being re-derived
  per-AC on `haiku` at execution time.

  **What replaces the RED guarantee.** Test-first's one real guarantee is that a test was
  observed to fail. Falsification restores it after the fact and more cheaply: apply the
  break the spec names, confirm the assertion fails, revert. One run per test, no
  implementation-blocking cycle.

  **Tautology is now the blocking defect; coverage is only a floor.** A green suite at 90%
  coverage that survives having its guards deleted fails the audit. QA scores a tautological
  or unfalsified test as MAJOR, capping the score at 4 — the same weight as a failing gate —
  and coverage above target never compensates. Tests added purely to move the percentage are
  explicitly rejected, and coverage-driven additions are re-audited as the highest-risk source
  of tautologies.

  **Bug fixes keep test-first**, and are the only exception: the RED reproduction test is what
  proves the root cause was found rather than guessed, so it is written and observed failing
  before the fix. There the RED *is* the falsification, obtained for free.

  Files: `plugins/bmad_v6/CLAUDE.md` (new "Spec-First Test Discipline" section replacing
  "TDD Discipline"); `architect.md` (Test Case Specification gains **Expected Observable
  Result**, **Why It Matters**, and **Falsified By** columns — the table is now the
  highest-leverage section of the architecture); `scrum-master.md` (story carries all columns
  verbatim; a row missing any of the three is an incomplete story; DoD checks rows +
  falsification + no tautologies); `coder.md` (Phase 1 TDD Cycle replaced by Phase 1 Implement
  → Phase 2 Write specified tests → Phase 3 Falsify; `CODER DONE` now reports spec coverage
  and one evidence line per test); `coder-backend.md`/`coder-frontend.md` (security and
  contract tests falsified by deleting the control); `qa.md` (audit lens 1 is now falsification
  evidence with mandatory spot-checks, lens 2 is an expanded tautology hunt, score table gains
  a Spec + Falsification column); `reviewer.md`, `verdict.md`, `tuner.md`; both pipeline
  skills + `task-coding-pipeline/references/loop.md`; `bug-fix/SKILL.md` (documents the
  exception); `engineering:observability` and `engineering:database-migration` (assert-then-
  falsify instead of RED-first; observability's `test-first-and-checklist.md` renamed to
  `test-and-checklist.md`); `engineering:code-review-gate`, `engineering:quality-gate`,
  `pr-workflow:pr-review` (TDD-compliance check → test-falsifiability check, with new HIGH
  findings for expected values re-derived from the implementation and for security tests that
  pass with the control removed); plus `references/` (`bmad-artifacts.md`,
  `language-rules-reference.md`, `output-format.md`, `progress-file.md`,
  `quality-gate-reference.md`, `spec-driven-reference.md`), `README.md`, and both plugin
  manifests.

### Added

- **`references/frontend-hardening-reference.md` — enforcement-integrity checks for frontend
  work.** Distilled from a post-merge review cycle on a production checkout frontend, where
  every pattern in it was a defect that *passed a green pipeline*: the lint ran, the tests were
  green, coverage met the floor, the docs claimed the gate was enforced — and the control was
  not actually in effect. Eight sections: config-merge shadowing (a rule silently replaced by a
  later block), security rules left at `warn` instead of `error`, vacuous tests, missing
  boundary-format cases on validators, ReDoS via overlapping regex character classes, fragile
  coverage config, dead CI files as phantom gates, and enforcement that runs only in CI rather
  than locally.

  This pairs directly with the spec-first change above — both target controls that *look*
  enforced but cannot fail. Wired in as mandatory for any web stack in `coder-frontend.md`,
  as `[FH]`-tagged review flags in `language-rules-reference.md`, as a QA audit lens in
  `qa.md` (canonical-only validators, vacuous loops, spies no `expect` reads), as a
  design-time obligation in `architect.md`, and into both `quality-gate-reference.md` copies.

- **`architecture.md` replaced by a keyed delivery file.** The pipeline no longer writes
  `architecture.md` to the project root. It now writes
  `docs/deliveries/delivery-{slug}-{key}.md`, where the key is the first 6 hex chars of the
  SHA-256 of the feature name. Two problems went away: the devkit was overwriting the host
  repo's own `architecture.md` — a file that usually documents the whole system, not one
  feature — and a single fixed filename meant two deliveries against the same repo fought over
  it. The delivery file opens with a signature header (`Delivery-Key`, Status, base commit,
  release branch, worktree path), and manifests, stories, and `api-spec.yaml` are keyed
  alongside it under `docs/deliveries/{key}/`. `PROGRESS.md` stays at the repo root with every
  entry prefixed `[{key}]` so concurrent deliveries interleave readably.

  Because the key is a pure function of the feature name, re-running a pipeline for the same
  feature resolves to the same delivery and **resumes** it rather than forking a duplicate. The
  trade-off is that two genuinely independent passes at one feature need distinct names.

  If the repo has its own `architecture.md`, the Architect now reads it as context and never
  modifies it.

- **Per-delivery git worktree and a branching model that never touches `main`.** Each pipeline
  run creates `.worktrees/dlv-{key}/` on branch `release/{slug}-{key}`, and everything —
  stories, gates, QA, review — happens in there, leaving the human's main working tree free.
  An existing worktree for a key means resume, not recreate.

  Branching: every delivery gets a release branch; per-story `feature/{key}-{story-slug}`
  branches are optional and merged back with `--no-ff` when a story is substantial enough to
  keep in history; `/bug-fix` instead cuts `hotfix/{slug}` straight from `main` with no
  delivery file, release branch, or worktree. **The pipeline never commits or merges to
  `main`** — its terminal step is opening a PR from a `release/*` or `hotfix/*` branch, and it
  asks before the first push.

  **Behavior change**: `multi-agent-coding-pipeline`'s "Parallel Coding" phase is now
  sequential. One worktree per delivery means stories share a working tree, so two concurrent
  Coder subagents would overwrite each other; story N is green and merged before story N+1 is
  dispatched. Read-only Explore/mapping subagents still run in parallel. This trades
  wall-clock for the cross-story isolation the worktree exists to provide.

  New reference: `plugins/bmad_v6/references/delivery-and-worktree.md` (key derivation, header
  block, setup/resume/teardown commands, branch table, PR rules). Wired into `architect.md`,
  `scrum-master.md`, `coder.md`, `devops.md`, `CLAUDE.md`, both pipeline skills +
  `task-coding-pipeline/references/loop.md`, `bug-fix/SKILL.md`, `planning/SKILL.md` +
  `references/phases.md`, `architecture/SKILL.md`, `references/` (`bmad-artifacts.md`,
  `output-format.md`, `presets.md`, `progress-file.md`), `README.md`, and `.gitignore`
  (`/.worktrees/`).

### Fixed

- **Consistency audit across the whole devkit** after the two changes above. Gaps closed:
  - **Brief and PRD had the same collision `architecture.md` did.** `product-brief.md` and
    `PRD.md` were written to the repo root, so a second delivery clobbered the first's. Both
    are now keyed under `docs/deliveries/{key}/`, along with manifests and stories.
  - **`api-spec.yaml` location settled at the project root.** The new delivery reference had
    put it under `docs/deliveries/{key}/`, contradicting seven agents that check the project
    root. Root wins: it is the application's shared, cumulative API contract, tooling expects a
    fixed path, and worktree isolation already gives each delivery its own checkout — two
    deliveries touching the same endpoints surface as a merge conflict at PR time, as they
    should.
  - **`/release-management` no longer appears to contradict "never merge to `main`".** It now
    states it is the step *after* a human merges the delivery PR — it tags an already-merged
    `main` — and that `release/{slug}-{key}` branches are a different thing from "cutting a
    release". It must not be used to get delivery work onto `main`.
  - **`/handoff` now records the delivery identity** (key, delivery file, release branch,
    worktree, next story). Without the key a resumed session derives a fresh one and forks the
    work. Its `PROGRESS.md` schema copy also gained the `[{key}]` entry prefix and the
    falsification tie, matching `bmad_v6/references/progress-file.md`.
  - **Verdict gained a gate** asserting all work sits on `release/*` or `hotfix/*` and nothing
    on `main`.
  - **Stress Tester's regression-test instruction clarified** — a stress-found failure mode is
    written test-first like a bug fix, and the reference now says why (the RED proves the mode
    was reproduced, not assumed) rather than reading as leftover TDD.
  - **"Architecture + Manifest" retained-context wording** updated to "the delivery file +
    Manifest" in four places.
  - **README pipeline diagram** gained the Delivery Setup and Delivery Close phases, marks
    implementation SEQUENTIAL, and shows the keyed artifact paths.
  - **`AGENTS.md` and `codex/harness-adapter.md`** now state both conventions for non-Claude
    harnesses; the adapter notes delivery isolation is plain `git` and should port cleanly,
    with sequencing still the unvalidated part.
  - Verified: every relative `.md` link in the repo resolves, every `SKILL.md` is under 100
    lines, both plugin manifests parse, and the global/codex installers use globs so the new
    reference files ship without a manifest edit.

  - **Broken skill path in all three pipeline entry points.** `multi-agent-coding-pipeline`,
    `task-coding-pipeline`, and its `references/loop.md` each instructed the orchestrator to
    "load and follow `skills/planning.md`" — a file that does not exist. The planning skill is
    `skills/planning/SKILL.md`. Every pipeline run was pointed at a missing file at its first
    planning step. Fixed in all three.
  - **Four unreachable reference files removed** — nothing loaded them and all predated the
    June restructure, so they drifted without any signal:
    `bmad_v6/references/api-integration.md` (taught raw `fetch` calls against the Messages API
    with a stale `claude-sonnet-4-6` model id, while agents actually dispatch via the Task
    tool), `bmad_v6/references/arch-report-reference.md` and
    `bmad_v6/references/rote-reference.md` (both outranked by the live copies under
    `devtools/`), and `engineering/skills/security-review/references/scope-and-checklists.md`
    (a superseded subset — 28 of its 42 content lines were already inlined verbatim in that
    skill's `SKILL.md`, which never referenced it).
  - **`multi-agent-coding-pipeline` description undercounted its own agents** — "all 9 agents"
    while `plugin.json`, `marketplace.json`, and `README.md` all say 11. Corrected to 11
    (Tuner and DevOps were missing from the list).
  - **`/checkcomments` was missing from the CLAUDE.md skill table** — the only one of the 23
    skills absent, so it would never be routed to by the trigger-phrase rule.

- **`plugins/bmad_v6/.claude-plugin/plugin.json` version corrected to `1.3.0`.** It had been
  left at `1.2.0` through the `1.2.1` release, so the manifest under-reported the installed
  version by two releases. Note the git tags lag further still — the last tag is `v1.1.2`, so
  `1.2.0`, `1.2.1`, and `1.3.0` are recorded here in the CHANGELOG but untagged.

- **`multi-agent-coding-pipeline` epic-loop detail extracted to `references/loop.md`.** Adding
  the delivery-setup phase pushed `SKILL.md` from 98 to 115 lines, past the devkit's own
  "under 100 lines, overflow to `references/`" rule. Steps A–F now live in
  `skills/multi-agent-coding-pipeline/references/loop.md` (mirroring what
  `task-coding-pipeline` already did), leaving a 69-line `SKILL.md` with a phase summary and a
  link. No behavior change.

## [1.2.1] — 2026-08-06

### Changed

- **Model tiering rebalanced: heavy reasoning on planning, `haiku` on code execution.**
  The Model assignment table (`plugins/bmad_v6/CLAUDE.md`) previously ran all
  planning/validation agents on `sonnet` and every code-writing agent (`coder` + tier
  overlays, `tuner`, `devops`) on `opus`. Now: `opus` is reserved for the Architect's
  design pass only (system design, ADRs, tech-stack calls — the one artifact everything
  downstream depends on); `sonnet` keeps the rest of planning/validation (Analyst, PM,
  Scrum Master, Bug Investigator diagnosis, QA audit, Reviewer, Stress, Verdict, pipeline
  orchestrators); `coder` (+ backend/frontend overlays), `tuner`, and `devops` move to
  `haiku`. Updated in agent frontmatter, `CLAUDE.md`'s table, both pipeline `SKILL.md`
  files (`multi-agent-coding-pipeline`, `task-coding-pipeline`), `bug-fix`'s dispatch
  (`SKILL.md` + `references/dispatch.md`), `README.md`, and `codex/harness-adapter.md`.
- **Architecture and story artifacts made airtight so `haiku` execution stays mechanical.**
  A cheaper Coder only works if it isn't asked to design anything. `architect.md` now
  requires a field-by-field table for every data structure (`### Data Structures`) and a
  new `### Test Case Specification` section enumerating the exact test cases — one row per
  AC, edge case, and non-N/A OWASP mitigation, with a literal test name Coder copies
  verbatim. `scrum-master.md`'s story template carries a new `### Test Cases` section
  filtered from that spec, and the Definition of Done now checks against table rows instead
  of ACs directly. `coder.md`'s RED phase changed from "write a test that encodes the AC's
  intent" to "execute the next row from the Test Cases table" — the design decision moved
  upstream to Architect/Scrum Master. `coder-backend.md`/`coder-frontend.md` reframe their
  TDD category checklists as gap-detection rather than design guidance. `qa.md` gained a
  spec-completeness check (every Test Cases row implemented) ahead of its existing
  intent/tautology/corner-case audit lenses.

## [1.2.0] — 2026-07-03

### Added

- **Database selection reference for the Architect.** `references/db-selection-reference.md` —
  a PACELC-classified comparison of 15 databases (Cassandra, MongoDB, DynamoDB, CockroachDB,
  Spanner, PostgreSQL, Redis, etcd, Riak, Neo4j, Elasticsearch, FoundationDB, ScyllaDB,
  Couchbase, YugabyteDB) with use cases and refactor-risk notes. `architect.md` loads it only
  when a feature introduces a new datastore or an existing one takes on a materially different
  use case — not part of every Architecture Document.
- **Frontend design-quality checklist (anti-AI-slop).** `references/frontend-design-reference.md`,
  condensed from [Impeccable](https://github.com/pbakaus/impeccable) (Apache 2.0): absolute
  bans (gradient text, glassmorphism-as-default, side-stripe borders, identical card grids,
  eyebrow-on-every-section, etc.) plus color/typography/layout/motion rules. `coder-frontend.md`
  carries the hard-ban shortlist inline and loads the full reference only for stories that
  create or materially redesign visual surface. Quinn's frontend audit lens (`qa.md`)
  spot-checks the same bans as a MINOR/aesthetic finding, never a gate blocker.
- **`/frontend-design` dispatch wired into the task and epic pipelines.** Before dispatching
  the frontend coder on a story that creates/redesigns visual surface,
  `multi-agent-coding-pipeline` and `task-coding-pipeline` now invoke Anthropic's
  `frontend-design` skill for a design plan (palette, type pairing, layout concept, signature
  element) and pass it into the coder's dispatch prompt. Skipped for backend-only and
  non-visual frontend work — zero overhead otherwise. Doesn't change the TDD cycle: tests
  still come first, the plan only governs visual direction.

## [1.1.2] — 2026-07-02

### Fixed

- **Agent model tier pinned in frontmatter.** Pipeline agents (`analyst`, `pm`, `architect`,
  `scrum-master`, `bug-investigator`, `qa`, `reviewer`, `stress`, `verdict`, `coder` +
  overlays, `tuner`, `devops`, `rote-adapter`) had no `model:` field, so the Agent tool fell
  back to inheriting the parent session's model on every spawn regardless of the CLAUDE.md
  model-assignment table. Now pinned (`sonnet` for reasoning/validation, `opus` for
  code-writing). Also fixes `DevOps` being listed `opus` in CLAUDE.md but `sonnet` in both
  pipeline `SKILL.md` files — standardized on `opus` (it writes IaC files).
- **`bug-fix`'s Phase 3 only ran the test command** — no lint, typecheck, or build — so a fix
  could reach Reviewer with a broken build. Now runs the full gate set (same as the other
  pipelines), with reloop-to-fix on any failure via the existing Bug-Fix Loop Protocol.
- **Missing build gate for React SPA.** Only Next.js had a `next build` gate; `tsc --noEmit`
  doesn't catch bundler-only failures (unresolved imports, case-sensitive path mismatches).
  Added to `quality-gate-reference.md`, Quinn's gate list, and the `pre-push` git hook.
- **`env-guard.sh` only fired on the `Read` tool.** `cat .env`, `grep SECRET .env`, and nested
  `bash -c "cat .env"` all bypassed the "never read `.env`" rule entirely. Now covers
  `Read|Bash|Grep|Glob`; regex hardened to catch `.env` anywhere in a command string, not
  just as a suffix.
- **Indirect prompt-injection surface in `pr-review-responder.sh`.** Untrusted GitHub PR
  comment bodies were piped straight into Claude's context with no delimiter, immediately
  followed by an "ACTION REQUIRED" directive Claude is instructed to obey — exploitable by
  anyone who can comment on the PR. Now wrapped in explicit untrusted-content markers.
- **`engineering/quality-gate` depended on a `bmad_v6`-only reference file**
  (`quality-gate-reference.md`), the same class of bug fixed for the Reviewer agent ref in
  1.1.1 but missed here — breaks when `engineering` is installed standalone. Gave it its own
  trimmed local copy instead of a hard cross-plugin dependency.
- **`security-review` did its full-codebase scan inline** instead of dispatching a read-only
  Explore/haiku sub-agent like `improve-codebase-architecture` does for identical-shaped
  work — burning main-thread context on pure grunt work. Now dispatches the same way.
- **Missing Contract blocks.** `multi-agent-coding-pipeline` and `security-review` had no
  explicit Input/Output/Boundary/Done-when block, unlike their sibling skills — a SkillSpec
  HIGH finding (agent follow-through risk). Added, matching the existing pattern.

## [1.1.1] — 2026-07-01

### Fixed

- **Cross-plugin agent references now resolve under the plugin install.** Two skills pointed
  at `agents/<name>.md` for an agent that lives in a *different* plugin, so the relative path
  dangled once installed via the plugin manager (all 18 agents ship in `bmad_v6`):
  - `engineering/code-review-gate` → the **Reviewer** (its Phase 2 gate). Now dispatches the
    `bmad_v6:reviewer` subagent (falls back to `reviewer` in a flat `~/.claude/agents` install)
    instead of reading `agents/reviewer.md`. This was the quality-gate wiring bug — the gate
    could skip its independent Reviewer under the plugin install.
  - `devtools/rote-adapter` → the `bmad_v6:rote-adapter` subagent, same treatment.

  In-plugin references (all `bmad_v6` pipeline skills) were already correct and are unchanged.
  Git and Claude Code hooks invoke no agents by design (exit-code sensors + shell), so they were
  not affected.

## [1.1.0] — 2026-07-01

### SkillSpec validation pass — all 23 skills

Ran every `SKILL.md` through [SkillSpec](https://github.com/modiqo/skillspec) `doctor`, which
scores **agent follow-through risk** (the chance an agent skips, reorders, improvises, or
finishes without proof given a skill's shape), and acted on the findings:

- **Leaner activation bodies** — heavy tables, templates, and examples moved out of the
  always-loaded `SKILL.md` into on-demand `references/*` (net −1236/+278 lines across the 23
  skills). Lower per-session context cost, same coverage.
- **Sharper discovery** — descriptions rewritten use-case-first; trigger phrases preserved.
- **Tidier structure** — labeled code fences, critical rules lifted toward the top.

Only the files Claude actually reads (`SKILL.md` + linked `references/`) are committed. The
SkillSpec contract scaffolding (`skill.spec.yml`, `deps.toml`, `source/`, `imports/`,
`resources/`, `.skillspec/`) is tool-only — Claude never loads it — and is `.gitignore`d.

### `write-a-skill` now self-validates

The `/write-a-skill` skill gained a mandatory **Validate** step: after scaffolding, it runs the
new skill through `skillspec doctor`, adapts the `SKILL.md` for any actionable finding, and
re-runs until clean — a skill is not "done" until SkillSpec has run and its findings are
resolved or explicitly justified. Finding-to-fix map in `references/skillspec-validation.md`.

### Fixed

- **`install-global.sh` (Option C flat install) rewritten for the multi-plugin layout.**
  The old script only looked at `bmad_v6` and expected flat `skills/*.md`, so against the
  current marketplace (4 plugins, directory-format `skills/<name>/SKILL.md`) it installed
  **zero skills** and missed three plugins. It now walks every plugin — installing all 23
  skills and 18 agents — and copies only the files Claude reads (`SKILL.md` + `references/`),
  skipping SkillSpec tool scaffolding.

### Housekeeping

- `.gitignore` added for SkillSpec tool artifacts and `.claude/settings.local.json`
  (machine-local permissions/state, now untracked).

## [1.0.0] — 2026-06-26

First tagged release. It combines the TDD-first + Harness foundation with an
efficiency/specialization pass (stack-aware coders, leaner context, self-dogfooding).
Highlights below.

### Specialized coders (shared core + thin overlays)
The single Coder is now a shared TDD **core** plus one of two thin tier overlays, chosen by
the story's tier:
- **Backend** (`coder-backend`) — Go/Java/JS-TS/PHP/Rust/server-Kotlin; table-driven, integration,
  race, security tests; api-spec **producer**.
- **Frontend** (`coder-frontend`) — React/Next.js/HTMX/HTML-CSS/Flutter/Kotlin-Android; Testing
  Library/Playwright, a11y, **SSR/RSC** (server render + hydration tests); api-spec **consumer**.

Dispatch is **stack-aware**: the orchestrator spawns only the coder(s) the story needs (a
backend-only repo never spawns a frontend coder), and each loads **only the detected
language's** rules — never all of them. Full-stack stories are split BE/FE around the
`api-spec.yaml` contract. QA stays a **single tier-aware auditor** — no agent sprawl.

### Leaner, drift-free context
- The two ~95%-identical `CLAUDE.md` files are deduped — the repo-root one now `@include`s the
  canonical plugin copy. One source, no drift.
- The heavy per-language standard tables left `CLAUDE.md` (loaded every session) and consolidated
  into the single `language-rules-reference.md`, loaded on demand. `CLAUDE.md` is ~50% lighter.
- Coverage thresholds now have one declared source of truth (`quality-gate-reference.md`).

### External dependencies dropped
- `superpowers:test-driven-development` reference removed — the Coder does TDD itself now; a
  direct change writes the failing test first, then runs `/code-review-gate`. `superpowers:using-git-worktrees`
  → native `git worktree`.
- Skill-routing trigger phrases in both `CLAUDE.md` files broadened and modernized; `/rote`
  (run) split from `/rote-adapter` (create).

### Harness wiring & self-CI
- Hooks now auto-install via the plugin manifest (`hooks/hooks.json`) — the SessionStart memory
  hook and env-guard are active by default, not a manual settings paste.
- The devkit dogfoods its own Sensors: a CI workflow runs shellcheck + bash syntax + JSON
  validation on the toolkit itself.
- All four plugins now carry a `version`.

### TDD-first, Harness-strict foundation

Rebuilds the devkit around two ideas: every line of code is driven by a test written
*first*, and the whole toolkit behaves like a proper agentic **Harness** (Guides, Sensors,
Memory, Orchestration). Here's what changed and why it matters day to day.

### The big shift: tests come first now

The pipeline used to be test-*after* — Amelia (Coder) wrote the implementation and was
forbidden to touch tests, then Quinn (QA) wrote tests against the finished code. That's
backwards, and it let untested-by-design code slip through.

- **Amelia now owns the full Red → Green → Refactor loop.** She writes the failing test
  first, watches it fail for the right reason, writes the least code to make it pass,
  then refactors under green. She owns both the test files and the implementation.
- **Quinn stopped writing tests and became the auditor.** Because the person who wrote
  the code is blind to what they skipped, Quinn now does the adversarial review: *does
  this test actually prove anything?* She hunts tautological and over-mocked tests
  (the ones that can never fail), demands the missing corner cases (boundaries, nulls,
  overflow, unicode, concurrency, time, error paths), and checks that no existing test
  was weakened to make a change pass. Gaps route back to Amelia via a new
  `QA→CODER TEST GAP` signal — Quinn never writes the test herself.

### Plans get stress-tested before anyone writes code

- `/grill-me` is now a **mandatory** step in planning, not an optional offer. Every plan
  gets poked for holes — missing error cases, auth gaps, undecided edge cases — while
  changes are still cheap.
- The architect no longer invents an answer to fill a gap. If the requirements support a
  decision, it's decided and written into the architecture. If they don't, it becomes an
  explicit open question for the human. Nothing ambiguous gets deferred into the
  implementation anymore — that's treated as a planning error.

### The toolkit is now a real Harness

- **Guides** — both `CLAUDE.md` files gained a Harness contract and a TDD discipline
  section, so the rules are stated up front instead of implied.
- **Sensors** — the existing git hooks (lint in error-mode, tests + coverage gate) are
  now explicitly framed as exit-code sensors: they block on failure and return a code,
  never prose to argue with.
- **Memory** — brand new. A `PROGRESS.md` at the repo root records what's done, what
  failed, and the current state. A new `session-bootstrap.sh` SessionStart hook reads it
  so a fresh session resumes with context instead of starting blind. Pipelines and
  `/handoff` keep it up to date.
- **Orchestration** — the implementer-is-not-the-validator split is now explicit, and the
  acceptance contract (ACs + Definition of Done) is frozen before any code is written.

### Right model for the right job

Agents now pick a model by task instead of defaulting to one tier: `haiku` for read-only
exploration and quick questions, `sonnet` for planning, reasoning, validation and long
sessions, `opus` for actually writing code. Cheaper where it can be, stronger where it
counts.

### Code-producing skills are test-first too

- **Database migrations** — write the migration test first (up applies, down fully
  reverses, idempotent), watch it go red, then write the SQL.
- **Observability** — assert the log fields and spans with an in-memory sink before
  instrumenting.
- **Performance profiling** — pin current behaviour with a characterization test before
  optimizing, so a speedup can't silently change results.
- **Quality gate / code-review gate / PR review** — all now check for tests-first
  evidence and reject tautological or absent tests for shipped behaviour.
- **rote-adapter** — define the acceptance test (which call, what a valid response looks
  like) before generating the adapter.

### Docs

- README, role diagrams, and the spec-driven workflow were rewritten to match the new
  Coder-builds / QA-audits reality, plus the new SessionStart hook and `PROGRESS.md`.

### Left alone on purpose

Read-only and non-coding pieces (analyst, PM, requirement analysis, business/technical
analysis, grill-me, rote, the rote API specialists, checkcomments, security-review,
release-management, write-a-skill) were not forced into a TDD shape that doesn't fit them.
