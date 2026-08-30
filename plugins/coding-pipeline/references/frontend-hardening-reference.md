# Frontend hardening — enforcement integrity reference

Load when writing, reviewing, or gating frontend code (JS/TS · React · Next.js · HTMX ·
HTML/CSS), and whenever a story touches a lint config, a test config, or a CI file.

Distilled from a post-merge review cycle on a production checkout frontend. Every pattern
below is a defect that **passed a green pipeline**: the lint ran, the tests were green, the
coverage met the floor, the docs said the gate was enforced — and the control was not
actually in effect. The unifying rule:

> **A gate that cannot fail is documentation, not enforcement.** For every control, name the
> input that makes it fail. If you cannot name one, the control is not installed.

The four Harness sensors this file hardens: the linter, the test runner, the coverage
report, and CI itself. Language equivalents are given per pattern — the failure mode is not
JS-specific.

---

## 1. Config-merge shadowing — a rule silently replaced by a later block

**The defect**: two ESLint flat-config blocks whose `files` globs overlap both declare
`no-restricted-syntax`. Flat config is **last-matching-block-wins per rule key** — the second
block's options array *replaces* the first's. XSS and a11y selectors stopped firing. No
error, no warning, no coverage change. Nothing signalled that the rules were gone.

**Rule**: one declaration per rule key per file scope. Merge selectors into the narrowest
block, and `ignores` those paths from the wider block.

```js
// WRONG — both blocks match src/features/**/*.tsx; the second silently kills the first
{ files: ["src/features/**/*.tsx"], rules: { "no-restricted-syntax": ["error", A11Y, XSS] } },
{ files: ["src/**/*.tsx"],          rules: { "no-restricted-syntax": ["error", CARD_FIELD] } },

// RIGHT — merged into the narrow block, excluded from the wide one
{ files: ["src/features/**/*.tsx", "src/shared/components/**/*.tsx"],
  rules: { "no-restricted-syntax": ["error", A11Y, XSS, CARD_FIELD] } },
{ files: ["src/**/*.tsx"], ignores: ["src/features/**/*.tsx", "src/shared/components/**/*.tsx"],
  rules: { "no-restricted-syntax": ["error", CARD_FIELD] } },
```

**Proof it is enforced** — an integration test that lints a known-bad snippet per selector
category and asserts the violation fires. Without it, no future change is detectable.

**Same failure mode elsewhere**: webpack `module.rules`, stylelint `overrides`, tsconfig
`extends` chains, Tailwind config merges, `.golangci.yml` `issues.exclude-rules`,
`checkstyle` suppression files, Gradle `lintOptions` overlays.

## 2. Security rules at `warn` instead of `error`

**The defect**: `"security/detect-possible-timing-attacks": "warn"` in a runner without
`--max-warnings 0`. Reported, never blocking. Found in human PR review, not CI.

**Rule**: every rule from a security-oriented plugin is `"error"`. `warn` in a security
plugin is a comment. Applies to `eslint-plugin-security`, `eslint-plugin-no-secrets`,
`eslint-plugin-regexp`, `eslint-plugin-jsx-a11y` (a11y is a security-adjacent hard gate
here), and the type-aware `@typescript-eslint` security rules.

**Gate** (add to the JS/TS quality gate — exits non-zero on violation):

```bash
grep -rEn '"(security|no-secrets|regexp)/[^"]+"[[:space:]]*:[[:space:]]*"warn"' eslint.config.* \
  && { echo "FAIL: security lint rules must be \"error\", not \"warn\""; exit 1; }
```

Also assert `--max-warnings 0` is present on every lint invocation in `package.json` scripts
and CI — a rule at `error` in a runner that tolerates warnings is still enforced, but a rule
at `warn` anywhere is not.

## 3. Vacuous tests — green because they assert nothing

**The defect**: an empty `for…of` body over a spy's calls, marked with a `// TODO`. Passed
for months while PII flowed through the logger it was meant to guard.

```ts
for (const _ of logSpy.calls) { /* TODO: check for PII */ }   // always green
```

**Rule**: no loop body without an assertion; a spy in a test must be reached by an `expect`.
This is the same defect the Harness calls a **tautology** — it is a MAJOR finding and blocks
handoff regardless of coverage.

```ts
expect(logSpy).not.toHaveBeenCalled();                        // direct
for (const call of logSpy.mock.calls) {                       // or per-call
  expect(containsPii(call[0])).toBe(false);
}
```

**Lint gate** — in the test-file block:

```js
{ selector: "ForOfStatement[body.type='BlockStatement'][body.body.length=0]",
  message: "Empty for-of loop in test — add an assertion or remove the loop." }
```

**Equivalents**: Python `pylint W0107` / `flake8-bugbear B007`; Go `testify`
`AssertExpectations(t)`; Java SpotBugs + PIT. The universal detector is **mutation testing**
(Stryker · PIT · mutmut · cargo-mutants) — the only tool that answers "would this suite go
red if the code were wrong?" mechanically. Falsification is the Harness's manual equivalent
and is not optional; mutation testing is the automation of it.

## 4. Missing boundary-format cases on validators

**The defect**: `luhn()` was tested with bare digit strings only. Production called it with
display-formatted PANs (`"4111 1111 1111 1111"`) — every valid card returned `false`, and PAN
detection was silently dead. Coverage was fine. The golden path was tested; the *format users
actually produce* was not.

**Rule**: every validation, parsing, masking, or detection function that touches user input
gets a **format matrix**, not a golden-path test. The Test Case table must carry one row per
line below; a validator row set without them is a spec defect (Architect fixes the table —
Coder does not invent the cases).

| Category | Rows required |
|----------|---------------|
| Golden path | canonical input accepted |
| Format variants | space-delimited · hyphen-delimited · surrounding whitespace · mixed case · unicode digits or lookalikes where reachable |
| Empty / junk | empty string · whitespace only · all-non-digit / all-separator |
| Off-by-one | exactly at minimum length (accept) · one short of minimum (reject) · one over maximum (reject) |
| Caller reality | at least one row using the **exact string the real caller passes** (display-formatted, from the input mask, from the API payload) |

The last row is the one that would have caught this defect. Table-driven in every language;
Go table tests and `it.each` / `test.each` are the idiomatic shapes.

## 5. ReDoS via overlapping regex character classes

**The defect**: `/[^\s@]+@[^\s@.]+\.[^\s@]+/g`. The final `[^\s@]+` matches everything
`[^\s@.]+` matches *plus dots*, so the engine can backtrack between adjacent segments.
`"a@b." + "c".repeat(50)` stalls the event loop for seconds — in a checkout flow, one crafted
input denies service to the payment step. Caught by SonarQube S5852 *after* merge.

**Rule**: adjacent regex segments must use **mutually exclusive** character classes — no
character accepted by one segment may be accepted by its neighbour.

```js
/[^\s@]+@[^\s@.]+\.[^\s@]+/g    // BEFORE — last segment re-matches dots
/[^\s@]+@[^\s@.]+\.[^\s@.]+/g   // AFTER  — all three segments unambiguous
```

**Enforce**: `eslint-plugin-regexp` with `regexp/no-super-linear-backtracking`,
`regexp/no-misleading-capturing-group`, `regexp/no-control-character` — all at `error`
(see §2). Any regex applied to user-controlled input is in scope, including one-line
validators inside components.

| Language | Enforcement |
|----------|-------------|
| JS/TS | `eslint-plugin-regexp` — `no-super-linear-backtracking: error` |
| Python | `regexploit` in CI; `re2` binding for user-controlled input (`re` has no backtrack limit) |
| Go | safe by design — stdlib `regexp` is RE2, linear time |
| Rust | safe by design — `regex` crate is RE2 |
| Java | ban `java.util.regex.Pattern` on user input; use `com.google.re2j` |
| PHP | `ini_set('pcre.backtrack_limit', 1000)` + possessive quantifiers |

## 6. Fragile coverage config — never filter the framework defaults

**The defect**:

```ts
exclude: [...coverageConfigDefaults.exclude.filter((p) => p !== "**/__tests__/**"), "src/app/**"]
```

Removing an entry from the defaults re-included test directories in coverage. A helper moved
into one was then measured as production code, distorting the metric — and the filter breaks
silently whenever the framework changes its default list.

**Rule**: spread the defaults untouched and add explicit paths.

```ts
exclude: [...coverageConfigDefaults.exclude, "src/app/**", "src/test/**"]
```

**Lint gate** — on `vitest.config.*` / `jest.config.*`:

```js
{ selector: "CallExpression[callee.property.name='filter'][callee.object.name='coverageConfigDefaults']",
  message: "Don't filter coverageConfigDefaults.exclude — add explicit paths instead." }
```

## 7. Dead CI files — phantom gates and phantom owners

**The defect**: `.github/workflows/security.yml` was committed to enforce security gates. The
project's CI runs on Argo. The file never executed once. Three consequences: the architecture
doc documented controls that did not exist, compliance evidence for "security enforced in CI"
was false, and CODEOWNERS on `workflows/` added a phantom approval gate to unrelated PRs.

**Rule**: every CI config file in the repo must run on the CI system the project actually
uses. A gate that is not wired to the real runner is deleted, not kept "for documentation".

```bash
if [ -d .github/workflows ]; then
  echo "WARNING: .github/workflows/ present — confirm every file runs on the project's real CI"
  ls .github/workflows/
fi
```

Cross-check the architecture document's CI section against the runner in use. Same failure
across platforms: uninstantiated Argo `WorkflowTemplate`s, unreferenced CircleCI jobs,
GitLab jobs permanently `rules: never`, orphaned `Jenkinsfile` branches.

## 8. Enforcement must run locally, not only in CI

**The defect**: a moved file broke an import-boundary rule (`no-restricted-imports` requiring
barrel imports). CI caught it; the developer had not linted the new path locally. Every such
round-trip is a wasted CI cycle and a red branch.

**Rule**: staged files are linted pre-commit. Wire `lint-staged` via `husky` or
`simple-git-hooks`, running the same command CI runs:

```json
{ "lint-staged": { "src/**/*.{ts,tsx}": ["eslint --max-warnings 0"] } }
```

The pre-commit hook and CI must invoke the **same** lint command — a local hook with weaker
flags reproduces this class of defect instead of preventing it.

---

## Review flags — frontend hardening *(add to the language tables)*

| Issue | Severity |
|-------|----------|
| Regex on user input with overlapping adjacent character classes (ReDoS) | CRITICAL |
| Two config blocks with overlapping `files` globs declaring the same rule key | MAJOR |
| Any `security/*`, `no-secrets/*`, or `regexp/*` rule set to `warn` | MAJOR |
| Lint invoked without `--max-warnings 0` in any script or CI step | MAJOR |
| Test loop with an empty body, or a spy no `expect` ever reads | MAJOR |
| Validator/parser tested only on canonical format — no format-variant or real-caller row | MAJOR |
| `coverageConfigDefaults.exclude` filtered instead of extended | MAJOR |
| CI config file present for a CI system the project does not use | MAJOR |
| Architecture doc claims a CI gate that no runner executes | MAJOR |
| No pre-commit lint on staged files (`lint-staged` absent) | MINOR |
| Pre-commit lint command weaker than the CI lint command | MAJOR |

## Where each check lives

| Pattern | Pre-commit | CI gate | Review | Test Case row |
|---------|-----------|---------|--------|---------------|
| ReDoS regex | `eslint-plugin-regexp` | same | overlapping classes | regex passes `no-super-linear-backtracking` |
| Config shadowing | — | integration test that lints known-bad code | overlapping `files` globs | "each selector category fires" |
| Vacuous tests | `no-restricted-syntax` on test files | same | empty loop bodies, unread spies | "every spy reached by an `expect`" |
| Security rules at `warn` | `grep` check | assertion test | severity of every `security/*` | "all security rules = error" |
| Boundary formats | — | coverage delta | test matrix vs §4 table | raw · formatted · empty · off-by-one · real caller |
| Dead CI files | — | `ls .github/workflows/` | cross-ref architecture doc | "CI system matches file" |
| Coverage config | `no-restricted-syntax` on config | same | `.filter(coverageConfigDefaults` | — |
| Import boundary | `lint-staged` | CI eslint | import paths in moved files | — |
