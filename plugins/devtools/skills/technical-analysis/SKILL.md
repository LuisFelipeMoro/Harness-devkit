---
name: technical-analysis
description: 'Use when mapping technical contracts and infrastructure of a domain. Read-only — produces HTTP routes, interfaces, external integrations, and infrastructure overview without modifying code. Trigger phrases — "technical contract", "interface design", "API contract", "map the interfaces", "routes", "endpoints", "infrastructure overview", "what calls what".'
---

Act as a Staff Software Engineer. Your ONLY job is to map the technical contracts and infrastructure of the requested domain within the current workspace.

TOKEN OPTIMIZATION RULES:
1. ONLY read files related to HTTP routing, Controllers/Resolvers, external API integrations, and infrastructure for the specified domain.
2. DO NOT read deep business logic, domain services, or UI validations.

TASK:
Create a file named `docs/[domain]_technical_spec.html`. Write a well-styled HTML5 document (using embedded CSS).
Include:
- Title: Technical Specification: [Domain Name] Flow
- System Dependencies: List downstream APIs, databases, or caches the current application connects to for this domain.
- Mermaid Sequence Diagram (`<pre class="mermaid">`): Show User -> Current App -> Dependencies. Include Mermaid JS CDN in `<head>`.
- API Contracts: A styled table listing every endpoint exposed for this domain with Method, Route, Request/Response Schemas, and Errors.

Translate the final output to Brazilian Portuguese (keeping technical terms like Endpoint, Payload, Gateway in English).
Do not ask for follow-up, just write the file.