---
name: business-analysis
description: 'Use when mapping business rules, constraints, and presentation logic of a domain. Produces user capability map, validation rules, presentation rules, and external integrations in Brazilian Portuguese. Trigger phrases — "business rules", "business logic", "domain rules", "what does the business require", "validation rules", "domain model", "use cases".'
---

# Business Analysis

Act as a Product Manager and Technical Writer. Map the business rules, constraints, and presentation logic of a domain.

## Rules
- Output in Brazilian Portuguese
- No implementation details — business rules only
- Every validation must include the user-facing error message
- Implicit rules: mark as `[IMPLÍCITO]`

## Invocation
`/business-analysis [domain]`

## Output: `docs/[domain]_business_rules.html`

Produce a styled HTML5 document in Brazilian Portuguese with:

### 1. User Capabilities
Bulleted list. One capability per bullet. Action-oriented: "Usuário pode adicionar itens ao carrinho."

### 2. Validation Rules
Table: Field · Constraint · Error Message
Include: required fields, length limits, format rules, allowed values, cross-field dependencies.

### 3. Presentation Rules
Currency formatting, date formats, conditional rendering, calculated fields, sorting/ordering.

### 4. External Integrations
Per integration: system name · data in/out · when called · failure behavior.
