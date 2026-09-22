# Security review checklist — single source

The eight sections the Reviewer and `/pr-review` both evaluate. They used to be restated in
`agents/reviewer.md` and `pr-workflow/.../review-checklist.md` in different words, which is how
two reviewers of the same diff came to apply two checklists.

**Run `scripts/verify/security-scan.sh <changed-paths>` first.** It greps the literal shapes —
injection, XSS, SSRF, weak crypto, hardcoded secrets, unsafe deserialization, secrets in logs,
route surface — and returns `file:line` candidates. Adjudicate those; do not re-read every file
hunting for them. What the scan cannot see is absence: a missing authz check matches no pattern,
so the sections below are still walked, with the scan's route list as the starting point.

**Emit ONLY violations (✗) and inapplicable items with a brief reason.** A clean section is one
line: `[Section name]: clean`. Whole checklist clean: `Security checklist: clean — no violations`.
A 50-line ✓ list is noise; only failures carry signal.

**Auth & Sessions**: protected routes require valid auth token · validated cryptographically (signature + expiry, not just presence) · tokens short-lived with refresh rotation · session IDs regenerated on privilege change · logout invalidates server-side session/token

**Authorization**: every data access checks ownership (IDOR prevention) · role checks at service layer, not only UI/controller · default deny — access granted explicitly, not by absence of restriction

**Input Handling**: all inputs validated (type, length, format, range, allowed chars) at system boundary · file uploads: magic-byte type check, size limited, stored outside webroot · redirects use allowlist — no open redirect via user-controlled URL

**Output & Encoding**: HTML output escaped for context · JSON responses set `Content-Type: application/json` · SQL uses parameterized queries — zero string concatenation · shell commands avoid user input; if unavoidable, allowlist + shell-escape

**Cryptography**: passwords bcrypt/argon2 work-factor ≥ 12 (not MD5/SHA1/SHA256 alone) · tokens/nonces from CSPRNG (`crypto.randomBytes`/`SecureRandom`/`random_bytes`/`crypto/rand`) · TLS 1.2+ on all external connections; `InsecureSkipVerify` absent · authenticated encryption (AES-GCM, ChaCha20-Poly1305) — not ECB/CBC-no-MAC

**Secrets & Config**: no secrets in source, committed config, or `.env` · secrets from env/vault at runtime · no secrets in logs, error messages, or HTTP responses

**HTTP Security Headers**: `Content-Security-Policy` · `X-Content-Type-Options: nosniff` · `X-Frame-Options: DENY`/`SAMEORIGIN` · HSTS for HTTPS · CORS: origin allowlist, not `*` for authenticated endpoints

**Dependency & Supply Chain**: no libraries with known critical CVEs · versions pinned (lockfile committed) · no `eval()`, dynamic `require()`/`import()`, or RCE patterns
