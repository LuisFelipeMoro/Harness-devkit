---
name: pr-review
description: Review a GitHub pull request and post severity-tagged inline comments with file:line evidence. Use when asked to review a PR or code-review a diff, or when the post-push hook surfaces open PR comments. Produces an OWASP + language-standards + test-quality + change-discipline review and a verdict.
---

# PR Review

Fetch a PR diff, audit it against a fixed checklist, post severity-tagged inline comments, and print a verdict summary.

## Contract

**Inputs**: a PR number (or the current branch to resolve one); a repo with `gh` authenticated. Activated when the user asks to review a PR, or when `pr-review-responder.sh` hook output is present after a push.
**Outputs**: inline review comments posted via `gh pr review`; a printed summary block with severity counts and an action verdict.
**Boundary**: does NOT run the full 10-point OWASP audit (use `/security-review`); does NOT merge, close, or modify code; does NOT change CI config.

**Dependencies** (verify before starting):
- `gh` — GitHub CLI, authenticated; used to read the diff and post the review.
- `git` — to resolve the current branch when no PR number is supplied.

Machine-checkable behavior contract: `skill.spec.yml` (routes, dependencies, closure, trace).

## Steps

1. **Fetch** the PR diff, metadata, and CI status — commands in `references/output-format.md`. If the PR number is unknown, resolve it from the current branch.
2. **Analyse** the diff against `references/review-checklist.md`, in order: Security (OWASP) → Go/TypeScript standards → test quality (falsifiability) → change discipline (does every changed line trace to the request?) → general.
3. **Format** each issue as one finding per line per `references/output-format.md` (severity emoji + `path:line` + message + suggested fix).
4. **Post** findings as inline comments and set the review verdict (`--request-changes` if any CRITICAL, else `--comment`, or `--approve` if clean).
5. **Summarise**: print the summary block with severity counts and the action taken.

**Done when**: every finding is posted via `gh pr review` and the summary block (severity counts + action) is printed. If no open PR resolves for the branch, stop and report that — do not improvise a review.

## References

- Fetch commands, finding line format, comment-posting templates, verdict commands, and the summary block: `references/output-format.md`.
- Checklist (OWASP + Go + TypeScript + test quality + change discipline + general), with severity mapping: `references/review-checklist.md`.
- Change-discipline rows with worked ❌/✅ examples (single source of truth): `coding-pipeline/references/change-discipline.md`.
