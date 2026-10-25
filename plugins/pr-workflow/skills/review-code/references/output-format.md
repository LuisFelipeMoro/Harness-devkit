# PR Review Output & Posting Templates

## Step 1 — Fetch the PR diff

```bash
gh pr diff <PR_NUMBER>                                              # full diff
gh pr view <PR_NUMBER> --json title,body,baseRefName,headRefName    # metadata
gh pr checks <PR_NUMBER>                                            # CI status
gh pr list --state open                                            # if PR number unknown — pick current branch
```

## Finding line format

One finding per line: `path:line: <emoji> <SEVERITY>: [optional OWASP tag] message. Suggested fix.`

```text
path/to/file.go:42: 🔴 CRITICAL: [OWASP A03] SQL query built by string concat. Use parameterized query.
path/to/handler.go:17: 🟠 HIGH: Error returned without context wrap. Use fmt.Errorf("doing X: %w", err).
path/to/service.ts:88: 🟡 MEDIUM: No zod schema at HTTP boundary — raw req.body used directly.
path/to/util.go:5: 🔵 LOW: Commented-out code. Remove it.
```

Severity key: 🔴 CRITICAL · 🟠 HIGH · 🟡 MEDIUM · 🔵 LOW · ℹ️ INFO

The `reviewer` agent reports CRITICAL / MAJOR / MINOR / NIT; map them as CRITICAL → 🔴 CRITICAL, MAJOR → 🟠 HIGH, MINOR → 🟡 MEDIUM, NIT → 🔵 LOW.

## Posting a finding as an inline comment

```bash
gh pr review <PR_NUMBER> --comment --body "$(cat <<'EOF'
**[SEVERITY]** [description]

[explanation of why this is a problem]

Suggested fix:
\`\`\`go
// corrected code
\`\`\`
EOF
)"
```

## Setting the review verdict

```bash
# CRITICAL findings present:
gh pr review <PR_NUMBER> --request-changes --body "..."
# Non-blocking findings only:
gh pr review <PR_NUMBER> --comment --body "..."
# Clean PR:
gh pr review <PR_NUMBER> --approve --body "LGTM — no issues found."
```

## Two sections, side by side

Print the reviewer's findings under two headings, in its order — never merged, never reranked
across them. With no spec, the Spec section is one line.

```text
## Standards
internal/cart/store.go:42: 🟠 HIGH: [PE9] error returned without context. Wrap with fmt.Errorf("load cart: %w", err).
internal/cart/total.go:18: 🟡 MEDIUM: possible Feature Envy — Total() reads five Coupon fields. Move the calculation onto Coupon.

## Spec
internal/cart/total.go:31: 🟠 HIGH: AC2 "total never goes below zero" — implemented as a clamp after tax, so tax is computed on a negative subtotal. Clamp before tax.
```

## Summary block (printed last)

```text
PR #N Review Summary
CRITICAL: X  HIGH: Y  MEDIUM: Z  LOW: W
Standards: N findings · worst: {SEVERITY file:line — one line | none}
Spec:      N findings · worst: {SEVERITY file:line — one line | none | no spec available}
Size: N changed lines (target ≤200 · ceiling 800) — {reviewable | oversized, findings below are best-effort}
Duplication: introduced N% (limit 3%) · pre-existing debt M%
Action: [REQUEST CHANGES | APPROVED | COMMENTED]
```

## Gaps block (printed with the summary, when a plan is available)

Findings say what is wrong with the code that is there. Gaps say what is **missing** relative to
the plan — the class of defect an inline diff comment structurally cannot carry, because it has
no line to attach to. Post it as one general PR comment as well as printing it.

```text
Gaps vs. plan (docs/plans/{slug}/plan.md)
Unimplemented ACs:     {AC id — text — no code found}                    | none
Spec drift:            {where the code contracts differ from the plan's Design / api-spec.yaml} | none
Missing Test Case rows:{row name from the frozen table with no test}     | none
Reuse Map departures:  {component built new where the map said reuse/extend, file:line both sides} | none
Duplication:           {N}% (limit 3%) — {worst pair: file:line ↔ file:line}
Untraced changes:      {changed file/symbol matching no AC or Tasks row}  | none
```

With no plan available, print the block with `not available — no plan` and skip
the four plan-relative rows rather than guessing at intent.
