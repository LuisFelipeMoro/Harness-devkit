# Security review — Scope Map sub-agent call

## Step 1 dispatch template

```text
Agent(
  subagent_type: "Explore",
  model: "haiku",
  prompt: "Map [target]. Return, each with file:line:
  1. Entry points (HTTP endpoints, CLI, queue consumers, file uploads)
  2. Auth/authz boundary files
  3. External integrations (APIs, DBs, caches, queues)
  4. Secret usage sites (env vars, vault, credential handling)
  5. Hardcoded API keys/passwords/tokens/connection strings/private keys (grep-based scan)
  6. Whether .env.example contains real values
  7. Whether AI/LLM components are present
  Raw observations only — no PASS/FAIL judgment, no fixes."
)
```

AI/LLM components present in the returned map → triggers Step 3 (LLM Top 10 audit).
