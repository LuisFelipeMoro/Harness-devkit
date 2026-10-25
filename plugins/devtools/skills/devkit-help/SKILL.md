---
name: devkit-help
description: Show what the devkit has — every skill grouped by job, the typical flows, and what is enforced — read live from the installed standards so it never drifts from the real skill set; or one skill's usage, contract and next step. Usage: /devkit-help [skill | flows], e.g. "/devkit-help validate-code".
disable-model-invocation: true
---

**Input**: nothing, a skill name (with or without the leading `/`), or `flows`.
**Output**: printed only — the grouped skill list, the flows, or one skill's summary.
**Boundary**: read-only, Bash and Read only, zero dispatches; never starts the skill it describes and loads no reference file. The skill list is read from the files every time, never written from memory: a skill that is not in the table is not listed, and one in the table is never hidden.

## Steps

1. **Pick the mode.** No argument → step 2. `flows` → step 3 only. Anything else → step 4.
2. **Skills.** Read the `## Skills (invoke manually)` table — up to the next `## ` heading — from `~/.claude/devkit/CLAUDE.md`, falling back to `plugins/coding-pipeline/CLAUDE.md` in the repo. Neither readable → say which paths were tried and stop. Print each row (`/skill` — its Need cell) under these groups, in this order, a group printed only when it has a row:

   | Group | Skills |
   |---|---|
   | Plan & build | `planning`, `map`, `code` |
   | Check | `validate-code`, `review-code`, `security-review` |
   | Ship & PR | `pr`, `pr-fix`, `release-management` |
   | Fix | `bugfix`, `performance-profiling`, `deps` |
   | Design & docs | `grill-me`, `improve-codebase-architecture`, `business-analysis`, `technical-analysis`, `database-migration`, `observability` |
   | Session | `handoff`, `retro` |
   | Integrations | `rote`, `rote-adapter` |
   | Meta | `write-a-skill`, `devkit-help` |

   A table row whose skill is in no group goes under **Other**, so nothing is hidden; a group name with no row in the table is skipped silently. Then step 3, then one line: what is enforced (spec-first tests proven by falsification, CD1–CD7, quality gates, security defaults, the 80% context ceiling) lives in the same `CLAUDE.md` — give the path that was read.
3. **Flows.** Print:
   ```
   Feature:      /planning → /code → /validate-code → /review-code → /pr → /pr-fix
   Bug:          /bugfix → /validate-code → /review-code → /pr
   Small change: /code "..." → /validate-code
   ```
   and that every skill is started by the user and only suggests the next one.
4. **One skill.** Strip a leading `/`. Read `~/.claude/skills/<name>/SKILL.md`, falling back to `plugins/*/skills/<name>/SKILL.md` in the repo. Not found → say so, list the table's skill names from step 2's file, and stop. Print only: its `description` (with the `Usage:` example), its `**Input**`, `**Output**` and `**Boundary**` lines, and its `Next:` line (or `Next: none` when it has none). Never its steps or any reference file.

Next: start any skill the list names, e.g. `/planning` or `/code "..."`.
