# Posting a review

Resolve once: `OWNER=$(gh repo view --json owner --jq .owner.login)`, `REPO=$(gh repo view --json name --jq .name)`,
`SHA=$(gh pr view N --json headRefOid --jq .headRefOid)`.

## Language

Translate the comment text, never the code, identifiers, paths or suggestion blocks.
Português (BR): natural Brazilian technical Portuguese — keep accepted English terms (`merge`, `deploy`, `endpoint`)
rather than forcing a translation. "Other": ask which language in plain text, once.

## Voice (every posted comment, in every language and style)

Severity, the two axes and the score decide the outcome in the terminal. They never appear in posted text.

- Start with what actually breaks, then say how to fix it.
- Talk to the author directly, in one to three sentences, with one point per comment.
- No severity label, emoji, axis name, OWASP tag or finding code. A security finding names the attack in plain words.
- Seriousness comes through the wording. CRITICAL or MAJOR: "this needs to change before merge because…". MINOR: "worth changing because…". NIT: "small one: …".
- No filler or praise in inline comments.

## Styles (one finding)

**Short** — a sentence or two:
```text
This returns `sql: no rows` with no context, so the logs can't say which cart failed. This needs to change before merge: wrap it with `fmt.Errorf("load cart %s: %w", id, err)`.
```

**With suggestions** — the same comment, plus a GitHub suggestion block when the fix is a concrete edit. Without a concrete edit, it stays as Short:
````text
This returns `sql: no rows` with no context, so the logs can't say which cart failed. This needs to change before merge, and this wrap fixes it:

```suggestion
	return fmt.Errorf("load cart %s: %w", id, err)
```
````

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
A finding whose line is not in the diff goes into `body`, naming its `file:line`, not `comments` (the API rejects it).

## One summary comment

```bash
gh pr review N --comment --body-file "$TMPDIR/review-N.md"          # or --request-changes, same rule as above
```

The summary paragraph comes first, then one short paragraph per finding with its `file:line`, what has to change before what is worth a look. No axis headings.

## Summary (top of `body`)

A short paragraph: what has to change, what is worth a look, and what couldn't be checked. Leave out any part with nothing to say, except that a sensor that did not run or a review with no spec is always stated. No score, severity counts or gate table; those stay in the terminal.

```text
The retry loop needs to change before merge, because it can charge a customer twice. The cart total is worth a look too. I couldn't run the security scan here, so that part is unchecked.
```

## Gaps

What the Gaps block found goes out as one general comment in this voice: a short paragraph saying what the plan asked for and the code doesn't do yet. Nothing missing means no comment.
