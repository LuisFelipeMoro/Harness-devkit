---
name: release-management
description: 'Cut a release from merged main: semver bump, CHANGELOG, tag, and a draft GitHub release. Usage: /release-management [args], e.g. "/release-management".'
disable-model-invocation: true
---

The version bump follows the conventional commits since the last tag, and the GitHub release stays a draft for the human to review before publishing — nothing publishes automatically.

> This skill is the step *after* a human has merged the PR: it tags an already-merged `main` and drafts the GitHub release. Run it on `main` after the merge — never on an unmerged feature branch, and never as a way to get work onto `main`.

## Contract
- Input: a repository on `main`, with the PR already merged, and conventional-commit history since the last tag.
- Output: an updated CHANGELOG.md, an annotated git tag pushed to origin, and a drafted GitHub release URL.
- Tool boundary: the draft release is never auto-published; version confirmation is requested from the user before tagging.
- Done when: the draft release URL prints for the user to review and publish.

## Steps
1. Determine the version bump: the git commands and the conventional-commit→semver table in `references/commands-and-templates.md` map commits since the last tag, where the highest-priority type wins.
2. Compute the new `vX.Y.Z` from the last tag, then confirm it with the user before tagging.
3. Update CHANGELOG.md from the Keep a Changelog template in `references/commands-and-templates.md`, grouping commits by type. Before writing the entries, run them past `coding-pipeline/references/prose-standards.md` on demand — an editorial pass, not a gate.
4. Tag and push with the git commands in `references/commands-and-templates.md`.
5. Draft the GitHub release with the `gh` command in `references/commands-and-templates.md`, then hand the resulting URL to the user.

## References
- `references/commands-and-templates.md` — git/gh commands, the semver mapping table, and the CHANGELOG template.
