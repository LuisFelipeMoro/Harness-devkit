# Output Format Reference

---

## Section Headers (inline / Claude.ai)

```
## 🗺️ Map — Codebase Map
## 📐 Plan — docs/plans/{slug}/plan.md
## 🔎 plan-reviewer — Plan Review  [Score: X/10]
## 💻 coder — Implementation + Specified Tests (falsified)
## 🧪 qa — Test Audit & Gates
## 🔍 reviewer — Code Review  [Score: X/10]
## 🔥 stress — Stress Report  [Score: X/10]
## 🏁 Verdict — Production Readiness
```

---

## Final Summary Table (append after every Verdict)

```markdown
---
## Run Summary

| Step | Role | Output | Score |
|------|------|--------|-------|
| Map | map | docs/plans/{slug}/codebase-map.md | — |
| Plan | plan author | docs/plans/{slug}/plan.md ({N} ACs, {N} Test Case rows, {N} tasks) | {score}/10 |
| Code | coder | impl + tests ({N} files, {N} rows, all falsified) | — |
| QA | qa | audited {N} tests, coverage {C}% | {score}/10 |
| Reviewer | Code Review | {N} issues ({X} critical) | {score}/10 |
| Stress | Chaos/Perf | {N} scenarios | {score}/10 |
| Verdict | Final Gate | {VERDICT} | {overall}/10 |

**Production Readiness: {VERDICT}**
**Overall Score: {X}/10**
**Security Gate: {PASS / FAIL — list unresolved CRITICAL security issues}**
**Coverage: {language} {C}% ({PASS/FAIL vs threshold})**

### Top 3 Action Items
1. {Most critical}
2. {Second}
3. {Third}
```

---

## API / HTML Artifact — Tab Labels

| Tab | Agent(s) | Content |
|-----|----------|---------|
| Map | map | codebase-map.md |
| Plan | plan author + plan-reviewer | plan.md + review log |
| Code | coder | Implementation + specified tests (falsified) |
| QA Audit | qa | Test audit + gates + coverage |
| Review | reviewer | Review + score |
| Stress | stress | Stress report + score |
| Verdict | verdict.sh + self-check | Final verdict + summary |

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
