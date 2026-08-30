# Change Discipline — review rows for CLAUDE.md rules 1–3, 5, 6

**Single source of truth** for the change-discipline findings. `agents/reviewer.md` and
`pr-workflow/skills/pr-review/references/review-checklist.md` both check these rows; on conflict this
file wins — change it here first, then propagate.

Coding Discipline rules 2 (*Simplicity first*), 3 (*Surgical changes*), and 1/6
(*Think before coding* / *Surface conflicts*) were prose with no sensor: nothing in the
review path ever failed a diff for scope creep. These rows make them checkable.

**The operational test**: every changed line must trace to the request. Read the diff with
the story / AC / issue text open and ask of each hunk — *which sentence asked for this?*

**When the request text is unavailable**, CD1, CD3, and CD7 cannot be judged. Say so
explicitly and skip them. Never infer intent from the diff itself — the diff is the thing
under test.

## Rows

| Id | Finding | Reviewer | PR checklist |
|----|---------|----------|--------------|
| CD1 | Changed line not traceable to the request — drive-by refactor, rename, reformat, or "improvement" to adjacent code | MINOR (MAJOR if it changes behaviour of untouched code) | MEDIUM |
| CD2 | Abstraction with a single implementation and a single call site — interface, strategy, factory, config object | MINOR | MEDIUM |
| CD3 | Unrequested surface — feature, endpoint, CLI flag, config knob, or exported symbol nothing calls | MAJOR | HIGH |
| CD4 | Defensive branch for a state the type system or caller makes unreachable | NIT | LOW |
| CD5 | Pre-existing dead code deleted without being asked | MAJOR | HIGH |
| CD6 | Orphan left by the change itself — import, variable, or function this diff made unused | MINOR | MEDIUM |
| CD7 | Ambiguity in the request silently resolved in code, where two or more readings existed and none was stated | MAJOR | HIGH |

CD3 and CD5 are MAJOR because they change what ships: CD3 adds surface that must now be
maintained, tested, and secured; CD5 removes code whose callers were never surveyed.
CD7 is MAJOR because a wrong silent choice is discovered only after the work is built.

## CD1 — untraceable change

Request: *"add a `retries` field to `Config`."*

❌ Field added, plus the surrounding struct reordered, three comments rewritten, and
`parseTimeout` renamed to `parseTimeoutSeconds`. The diff is 40 lines; 4 were asked for.

✅ Field added. The rename is mentioned in the summary — *"`parseTimeout` returns seconds
and is misnamed; separate change?"* — and not made.

## CD2 — single-use abstraction

Request: *"apply a percentage discount to the order total."*

❌ `DiscountStrategy` interface, `PercentageDiscount` and `FixedDiscount` implementations,
a `DiscountConfig`, and a `DiscountCalculator` that selects between them. One is used.

✅ `func discount(amount, percent float64) float64`. Extract an interface when the third
case arrives — not the first (Universal: 3 cases before extracting).

## CD3 — unrequested surface

Request: *"add `GET /users/{id}`."*

❌ `GET /users/{id}`, plus `GET /users` with pagination, plus a `?fields=` projection
param, plus `include_deleted` "since it'll be needed." Three unasked endpoints/params now
need authz review, tests, and docs.

✅ `GET /users/{id}` only. The rest listed as a follow-up question, not built.

## CD4 — unreachable-state handling

❌ `if user == nil` inside a method whose only caller has just dereferenced `user`, with a
wrapped error and a log line for a branch no test can reach.

✅ No branch. If the invariant matters, encode it in the type or assert it once at the
boundary where untrusted input actually enters.

## CD5 — deleting pre-existing dead code

❌ While adding a handler, `legacyExportCSV` is deleted because nothing in this package
calls it. It was called by a cron job in another repo.

✅ Handler added. `legacyExportCSV` left alone, and reported: *"`legacyExportCSV` has no
in-repo callers — remove in a separate change?"*

## CD6 — orphan left by the change

❌ The change replaces `json.Marshal` with a streaming encoder. `encoding/json` stays
imported and `bufSize` is now unused — both introduced-as-dead by this diff.

✅ Import and constant removed in the same change. Cleaning up your own mess is surgical;
cleaning up someone else's is CD5.

## CD7 — silently resolved ambiguity

Request: *"make the export respect the user's timezone."*

❌ Implementation picks the *requesting* user's timezone. The other reading — the *exported
records'* owner timezone — is never mentioned. Both are plausible; one is wrong.

✅ Both readings stated before implementing, one recommended, and the answer recorded in
the story's AC so a reviewer can check the code against it.
