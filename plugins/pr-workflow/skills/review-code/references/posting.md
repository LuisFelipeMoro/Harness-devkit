# Posting a review

Resolve once: `OWNER=$(gh repo view --json owner --jq .owner.login)`, `REPO=$(gh repo view --json name --jq .name)`,
`SHA=$(gh pr view N --json headRefOid --jq .headRefOid)`.

## Language

Translate the finding text, never the code, identifiers, paths, severities or suggestion blocks.
Português (BR): natural Brazilian technical Portuguese — keep accepted English terms (`merge`, `deploy`, `endpoint`)
rather than forcing a translation. "Other": ask which language in plain text, once.

## Styles (one finding)

**Terse** — one line:
```text
🟠 MAJOR: error returned without context. Wrap with fmt.Errorf("load cart: %w", err).
```

**Detailed** — severity, why (the cost), and a GitHub suggestion block the author can apply:
````text
**🟠 MAJOR — error stripped of context**

Production logs cannot locate this failure: the caller only sees `sql: no rows`.

```suggestion
	return fmt.Errorf("load cart %s: %w", id, err)
```
````

**Conventional Comments** — `label (decorations): subject`, then the discussion:
```text
issue (blocking): error returned without context

Wrap it so production logs say what was attempted: `fmt.Errorf("load cart: %w", err)`.
```
Map severity → label: CRITICAL/MAJOR → `issue (blocking)`, MINOR → `suggestion (non-blocking)`, NIT → `nitpick (non-blocking)`, praise → `praise`.

## Inline comments (one review, many comments)

Write the payload to `$TMPDIR/review-N.json`, then send it in one call:
```json
{ "commit_id": "SHA", "event": "COMMENT", "body": "summary block",
  "comments": [ { "path": "internal/cart/store.go", "line": 42, "side": "RIGHT", "body": "..." } ] }
```
```bash
gh api "repos/$OWNER/$REPO/pulls/N/reviews" --method POST --input "$TMPDIR/review-N.json"
```
`event`: `REQUEST_CHANGES` if any CRITICAL or hard-gate FAIL, else `COMMENT`. Never `APPROVE` unless the user asks.
A finding whose line is not in the diff goes into `body`, not `comments` (the API rejects it).

## One summary comment

```bash
gh pr review N --comment --body-file "$TMPDIR/review-N.md"          # or --request-changes, same rule as above
```

## Summary block (top of `body`, also printed)

```text
Review — score {X}/10 · {recommendation}
CRITICAL {a} · MAJOR {b} · MINOR {c} · NIT {d}
Size: {N} changed lines (target ≤ 200 · ceiling 800)
Duplication: introduced {N}% (limit 3%) · Hard gates: {PASS | FAIL list}
Standards: worst {finding | none} · Spec: worst {finding | none | no spec available}
```

A summary comment keeps the `## Standards` and `## Spec` sections separate, as printed. Inline
comments carry their axis as a prefix — `[Standards]` / `[Spec]` — after the severity.
