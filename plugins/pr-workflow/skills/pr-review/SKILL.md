---
name: pr-review
description: Review a GitHub pull request and post severity-tagged inline comments with file:line evidence. Use when asked to review a PR or code-review a diff, or when the post-push hook surfaces open PR comments. Produces an OWASP + language-standards + test-quality + change-discipline review and a verdict.
---

# PR Review

Fetch a PR diff, audit it against a fixed checklist, post severity-tagged inline comments, and print a verdict summary.

## Contract

**Inputs**: a PR number (or the current branch to resolve one); a repo with `gh` authenticated; **the delivery file, its Reuse Map, and the manifest when the PR came from a pipeline** — without them the plan-relative Gaps rows and the CD1/CD3/CD7 intent checks cannot be judged. Activated when the user asks to review a PR, or when `pr-review-responder.sh` hook output is present after a push.
**Outputs**: inline review comments posted via `gh pr review`; a printed summary block with severity counts, the duplication figure, and an action verdict; a **Gaps block** (unimplemented ACs · spec drift · missing Test Case rows · Reuse Map departures · duplication · untraced changes) printed and posted as one general comment.
**Boundary**: does NOT run the full 10-point OWASP audit (use `/security-review`); does NOT merge, close, or modify code; does NOT change CI config.

**Dependencies** (verify before starting):
- `gh` — GitHub CLI, authenticated; used to read the diff and post the review.
- `git` — to resolve the current branch when no PR number is supplied.

Machine-checkable behavior contract: `skill.spec.yml` (routes, dependencies, closure, trace).

## Steps

1. **Fetch** the PR diff, metadata, and CI status — commands in `references/output-format.md`. If the PR number is unknown, resolve it from the current branch.
2. **Analyse** the diff against `references/review-checklist.md`, in order: Security (OWASP) → Go/TypeScript standards → **reuse & duplication** (run `jscpd . --threshold 3 --min-lines 8 --reporters console` over the branch — this is the only review that sees the whole delivery as one diff, so it is the only one that can catch a helper written twice in two stories) → **design & durability** (the principal-engineer bar: correct → legible → durable → small; every finding names the future change it makes harder) → test quality (falsifiability) → change discipline (does every changed line trace to the request?) → general.
3. **Format** each issue as one finding per line per `references/output-format.md` (severity emoji + `path:line` + message + suggested fix).
4. **Post** findings as inline comments and set the review verdict (`--request-changes` if any CRITICAL, else `--comment`, or `--approve` if clean).
5. **Summarise**: print the summary block (severity counts, duplication %, action taken) and the **Gaps block** — what is missing relative to the plan, which no inline comment can carry because it has no line to attach to. Post the Gaps block as one general PR comment.

**Done when**: every finding is posted via `gh pr review`, the Gaps block is posted as a general comment, and the summary block (severity counts + duplication % + action) is printed. If no open PR resolves for the branch, stop and report that — do not improvise a review.

## References

- Fetch commands, finding line format, comment-posting templates, verdict commands, and the summary block: `references/output-format.md`.
- Checklist (OWASP + Go + TypeScript + reuse & duplication + design & durability + test quality + change discipline + general), with severity mapping: `references/review-checklist.md`.
- Change-discipline rows with worked ❌/✅ examples (single source of truth): `coding-pipeline/references/change-discipline.md`.
