# Output Format Reference

---

## Section Headers (inline / Claude.ai)

```
## 📋 Mary (Analyst) — Product Brief
## 📄 John (PM) — PRD
## 🏗️ Winston (Architect) — Architecture
## 📝 Bob (SM) — Story File
## 💻 Amelia (Coder) — Implementation + Specified Tests (falsified)
## 🧪 Quinn (QA) — Test Audit & Gates
## 🔍 Reviewer — Code Review  [Score: X/10]
## 🔥 Stress Tester — Stress Report  [Score: X/10]
## 🏁 Verdict — Production Readiness
```

---

## Final Summary Table (append after every Verdict)

```markdown
---
## Pipeline Summary

| Agent | Role | Output | Score |
|-------|------|--------|-------|
| Mary | Analyst | {key}/product-brief.md | — |
| John | PM | {key}/PRD.md ({N} FRs, {M} NFRs) | — |
| Winston | Architect | delivery-{slug}-{key}.md ({N} ADRs) | — |
| Bob | SM | story-{slug}.md | — |
| Amelia | Coder | impl + tests ({N} files, {N} rows, all falsified) | — |
| Quinn | QA | audited {N} tests, coverage {C}% | — |
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
| Analysis | Mary + John | {key}/product-brief.md + {key}/PRD.md |
| Planning | Winston | delivery file + manifest |
| Stories | Bob | story-{slug}.md files |
| Code | Amelia | Implementation + specified tests (falsified) |
| QA Audit | Quinn | Test audit + gates + coverage |
| Review | Reviewer | Review + score |
| Stress | Stress Tester | Stress report + score |
| Verdict | Verdict Agent | Final verdict + summary |

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
