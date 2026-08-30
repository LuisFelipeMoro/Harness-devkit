# rote-adapter dispatch template

Dispatch the autonomous rote-adapter sub-agent with this call. The dispatched
subagent already carries its persona; do not read the agent file into the main
context. Use `subagent_type: "coding-pipeline:rote-adapter"` in a plugin install, or
`"rote-adapter"` in a flat `~/.claude/agents` install.

```text
Agent(
  description: "rote-adapter — autonomous adapter creation",
  subagent_type: "coding-pipeline:rote-adapter",
  model: "sonnet",
  prompt: """
You are the rote-adapter agent — follow your full 8-phase persona.

Integration target: [paste user's integration description — service name, what data/actions needed]
Working directory: [cwd]

Run your full Phase 0 → Phase 7 (Discovery → Analysis → Research → Auth → Scope → Creation → Verification → Crystallization).
Contract-first: define the Phase 8 acceptance test (which read-only tool you will call and what a valid response looks like) BEFORE the create command. The adapter is done only when that predefined test passes.

Return ONLY:
1. Adapter name + file path(s) created
2. Auth method used (API key / OAuth2 / Bearer / etc.)
3. Verification result: success output or failure with exact error
4. Crystallized flow name (what /rote can now call)
5. Any manual setup steps remaining for the user (API key env var, OAuth redirect URL, etc.)
"""
)
```
