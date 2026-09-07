---
name: grill-me
description: 'Use when stress-testing a plan, design, or architectural decision before committing to it. Asks one hard question at a time with a concrete recommendation. Stops when user says "done" or "enough". Trigger phrases: "grill me", "challenge this", "stress-test", "poke holes", "pick this apart", "interview me about", "find gaps in my plan", "what am I missing", "red team this".'
---

Interview relentlessly about every aspect of this plan until reaching shared understanding. Walk down each branch of the decision tree, resolving dependencies one by one. For each question, provide a concrete recommendation.

Ask one question at a time.

If a question can be answered by exploring the codebase, explore instead of asking.

## Rules

- State the assumption being challenged, then the consequence if it's wrong
- One question max per turn. One recommendation per question.
- No softening ("just wondering"), no multi-part questions, no praise before critique
- Don't ask about things the user already addressed

## Ending

When user says "done", "enough", "ship it", or "next": list the 3 unresolved risks in order of severity, one line each.
