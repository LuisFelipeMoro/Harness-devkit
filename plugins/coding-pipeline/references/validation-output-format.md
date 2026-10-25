# Validation Output Format — `/validate-code`

What `/validate-code` prints after its verdict (step 8). It is the verdict on the code itself —
gates, sensors, `qa` and `stress` — so it never carries a review score: the review is
`/review-code`'s own gate, with its own format (`pr-workflow/skills/review-code/references/output-format.md`).

---

## Section Headers (inline / Claude.ai)

```
## 🧪 qa — Test Audit & Gates  [Score: X/10]
## 🔥 stress — Stress Report  [Score: X/10]
## 🏁 Verdict — Code Verdict
```

Only the lenses the depth dispatched get a header: cosmetic none · light `qa` · standard/full `qa` + `stress`.

---

## Validation Summary (printed after the verdict)

```markdown
---
## Validation Summary — depth {cosmetic | light | standard | full}

| Step | Role | Output | Score |
|------|------|--------|-------|
| Gates | gates + sensors | {N} gates, {F} FAIL · coverage {C}% | — |
| QA | qa | audited {N} tests, coverage {C}% | {score}/10 |
| Stress | stress | {N} scenarios | {score}/10 |
| Verdict | verdict.sh + self-check | {VERDICT} | {overall}/10 |

**Code Verdict: {VERDICT}**
**Overall Score: {X}/10** (the line `verdict.sh` printed — `n/a (cosmetic — gates only)` at cosmetic)
**Security Gate: {PASS / FAIL — list unresolved CRITICAL security issues}**
**Coverage: {language} {C}% ({PASS/FAIL vs threshold})**

### Top 3 Action Items
1. {Most critical} — `file:line`
2. {Second} — `file:line`
3. {Third} — `file:line`
```

Rows for a lens the depth did not dispatch are omitted, never filled with a score nobody produced
(light: no Stress row; cosmetic: no QA or Stress row).

---

## API / HTML Artifact — Tab Labels

| Tab | Agent(s) | Content |
|-----|----------|---------|
| QA Audit | qa | Test audit + gates + coverage |
| Stress | stress | Stress report + score |
| Verdict | verdict.sh + self-check | Code verdict + summary |

---

## Agent Status Labels

| State | Label | Color |
|-------|-------|-------|
| Not started | Idle | Gray |
| Running | Running… | Blue (pulse) |
| Complete | Done ✓ | Green |
| Failed | Error | Red |

---

## File Extension Reference

| Language | Source | Test |
|----------|--------|------|
| Go | `.go` | `_test.go` |
| Java | `.java` | `Test.java` |
| JavaScript | `.js` | `.test.js` |
| TypeScript | `.ts` | `.test.ts` |
| PHP | `.php` | `Test.php` |
| Rust | `.rs` | `_test.rs` *(in `#[cfg(test)]` module)* |
| Kotlin | `.kt` | `Test.kt` *(JUnit5)* |
| Flutter/Dart | `.dart` | `_test.dart` |
| HTMX | `.html` + server | Playwright `.spec.ts` |
| Next.js | `.tsx` / `.ts` (App Router: `page.tsx`, `layout.tsx`, `route.ts`) | `.test.tsx` / `.spec.ts` |
