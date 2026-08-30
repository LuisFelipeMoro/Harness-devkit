# Architecture document — required sections

Produce all ten sections in order. Skip none. No pseudocode — real interfaces/types only.

### 1. Context
One paragraph: what this solves and why it exists.

### 2. Tech Stack
| Component | Technology | Version | Rationale | Rejected Alternatives |

### 3. Security Architecture — MANDATORY, never skip
OWASP Web Top 10 threat matrix for this domain:
| A01–A10 | Mitigation | Implementation |

If AI/LLM components present: also OWASP LLM Top 10 (2025) matrix.
Secrets strategy (env/vault/KMS). Auth/authz model.

### 4. Component Design
Per component:
- **Interface** (language-idiomatic — Go `interface`, TS `interface`, etc.)
- **Responsibility** (one sentence — if more is needed, split the component)
- **Dependencies** (what it calls; direction must flow inward)
- **Testable seam** (how it is verified: dependencies behind interfaces, I/O injectable/mockable, pure logic separable from side effects — so each Test Case row can assert an observable result and be falsified by a named break in this component)

Clean Architecture layers (outermost → innermost):
`transport` → `application` → `domain` ← `infrastructure`

### 5. Data Model
Key domain types/structs/schemas. No ORM annotations in domain layer.

### 6. API Contracts
| Method | Route | Request | Response | Errors |
Must match component interface definitions above.

### 7. Data Flow
Mermaid sequence diagram — happy path, all component interactions. Template and rules: [data-flow-example.md](data-flow-example.md).

### 8. Error Handling Strategy
How errors propagate: infra → domain → application → transport.

### 9. Observability
| Signal | What | Why |
Key metrics, log events, trace spans to instrument.

### 10. ADRs — per non-obvious design choice
- **Context**: why a decision was needed
- **Decision**: what was chosen
- **Consequences**: trade-offs accepted
- **Rejected alternatives**: what was considered and why rejected
