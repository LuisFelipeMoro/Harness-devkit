---
name: security-review
description: Use when auditing code for security issues. Runs OWASP Web Top 10 (2025) checklist and — if AI/GenAI components present — OWASP LLM Top 10 (2025). Produces severity-tagged findings with file:line evidence.
---

# Security Review

Act as a Staff Security Engineer. Perform a thorough security audit covering OWASP Web Top 10 (2025) + OWASP LLM Top 10 (2025) where AI/GenAI components are present.

## Contract
- **Input**: a target — file path, domain name, or "current branch" (ask if not provided).
- **Output**: a severity-tagged findings report (CRITICAL/HIGH/MEDIUM/LOW) with file:line evidence, plus an OWASP Web coverage table and an LLM coverage table when applicable.
- **Boundary**: read-only audit — never modifies code; CRITICAL always blocks deployment, no exceptions.
- **Done when**: the Output Format report prints with both coverage tables filled (LLM table only if AI/LLM components were found) and a top 3–5 summary.

## Rules (apply throughout)
- If cannot verify PASS → emit FAIL with note
- All evidence must be file:line references

## Invocation
`/security-review [target]` — file path, domain name, or "current branch"

## Process

### Step 1 — Scope Map + Secrets Scan (1 Explore sub-agent, model: haiku)
Multi-file, codebase-wide grunt work — keep it out of main context. Dispatch one read-only Explore sub-agent using the call template in `references/scope-map-reference.md`.

### Step 2 — OWASP Web Top 10 (2025)
Emit PASS / FAIL / N/A with file:line evidence for each:

| ID | Check |
|----|-------|
| A01 Broken Access Control | All endpoints authenticated? IDOR? Privilege escalation? Admin routes guarded? |
| A02 Cryptographic Failures | Secrets in env/vault only? TLS enforced? No weak algorithms (MD5/SHA1/DES/RC4)? |
| A03 Injection | SQL parameterized? No exec with user input? Template injection? |
| A04 Insecure Design | Rate limiting? Business logic abuse paths? Threat model? |
| A05 Security Misconfiguration | Debug off? Stack traces hidden? CORS restrictive? Security headers present? |
| A06 Vulnerable Components | `govulncheck`/`npm audit` clean? Deps pinned? |
| A07 Auth Failures | Brute-force protection? Session fixation prevented? Token expiry? Refresh rotation? |
| A08 Software Integrity | Deps from trusted sources? CI tamper-resistant? |
| A09 Logging/Monitoring | Auth failures logged? No PII in logs? Anomaly detection? |
| A10 SSRF | Outbound URLs allowlisted? DNS rebinding protection? |

### Step 3 — OWASP LLM Top 10 (2025) — run only if AI/LLM components present

| ID | Check |
|----|-------|
| LLM01 Prompt Injection | User input sanitized before LLM? Instructions separated from data? Output validated before acting? |
| LLM02 Sensitive Info Disclosure | PII/secrets filterable from output? RAG corpus access-controlled? |
| LLM03 Supply Chain | Model provider audited? Version pinned? Fine-tuning data verified? |
| LLM04 Data/Model Poisoning | Fine-tuning dataset validated? Output drift monitored? |
| LLM05 Improper Output Handling | LLM output treated as untrusted? Sanitized before render/exec/SQL? |
| LLM06 Excessive Agency | Tool permissions scoped? Human-in-loop for irreversible? All actions logged? |
| LLM07 System Prompt Leakage | Security doesn't depend on prompt secrecy? Defence-in-depth applied? |
| LLM08 Vector/Embedding Weaknesses | Retrieval results validated? Access control on vector store? |
| LLM09 Misinformation | Human review gates for high-stakes? Grounded in verified sources? |
| LLM10 Unbounded Consumption | Rate limits per tenant? Token budgets enforced? Circuit breakers? |

### Step 4 — Auth/AuthZ Deep Dive
- Every authenticated route has middleware guard?
- Authorization at resource level (not just route)?
- No IDOR — users cannot access other users' data?

### Step 5 — Input Validation
- All external inputs validated before use (body, query, headers, files, path params)?
- Length limits enforced?
- Error responses safe (no stack traces, no internal paths, no raw DB errors)?

## Output Format

```text
## Security Audit: [target]  Date: YYYY-MM-DD

### CRITICAL — fix before any deployment
- [finding]: [file:line evidence] → [recommended fix]

### HIGH — fix before next release
- [finding]: [file:line evidence] → [recommended fix]

### MEDIUM — fix within current sprint
- [finding]: [file:line evidence] → [recommended fix]

### LOW / INFORMATIONAL
- [finding]: [evidence]

### OWASP Web Coverage
| A01 | A02 | A03 | A04 | A05 | A06 | A07 | A08 | A09 | A10 |
|-----|-----|-----|-----|-----|-----|-----|-----|-----|-----|
| PASS/FAIL/N/A × 10 |

### OWASP LLM Coverage (if applicable)
| LLM01 | LLM02 | LLM03 | LLM04 | LLM05 | LLM06 | LLM07 | LLM08 | LLM09 | LLM10 |
|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|
| PASS/FAIL/N/A × 10 |

### Summary — top 3–5 recommendations by risk
```

## References
- `references/scope-map-reference.md` — Step 1 sub-agent dispatch template.
