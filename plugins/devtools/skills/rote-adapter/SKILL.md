---
name: rote-adapter
description: 'Use when creating a NEW integration adapter from scratch — discovers the API, negotiates auth, scopes endpoints, builds, and verifies the adapter in 8 autonomous phases. Use /rote for running existing adapters/flows. Trigger phrases: "build adapter", "create integration", "new connector", "connect to X for the first time", "create rote adapter", "add new integration", "integrate with X".'
---

Dispatch the autonomous rote-adapter agent to build a new integration connector from scratch.

## Anti-patterns
- Don't read the agent definition directly — dispatch it as the `coding-pipeline:rote-adapter` sub-agent to keep the 8-phase discovery out of main context
- Don't use this for integrations that already have an adapter — use `/rote` instead
- Don't skip verification (Phase 6) — an adapter that doesn't verify is not complete

## Pre-flight — Choose the right skill

| Intent | Skill |
|--------|-------|
| Create a **new** adapter for a service never connected before | `/rote-adapter` (this skill) |
| Run, search, or reuse an **existing** adapter/flow | `/rote` |

If the user already has a working adapter and just wants to run it, redirect to `/rote`.

## Dispatch

Dispatch the `rote-adapter` sub-agent using the call template in `references/dispatch.md`. It runs Phase 0 → Phase 7 (Discovery → Analysis → Research → Auth → Scope → Creation → Verification → Crystallization), contract-first.

Show the result to the user. If verification failed, surface the exact error and manual steps.
