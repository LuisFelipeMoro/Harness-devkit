---
name: deps
description: Audit dependencies for outdated and vulnerable versions, read the changelogs for breaking changes, and apply the upgrade batches you pick one at a time with gates after each. Usage: /deps [audit | upgrade] [package...], e.g. "/deps upgrade".
disable-model-invocation: true
---

**Input**: the repo (all detected stacks); optional `audit` (report only, the default) or `upgrade`, optional package names to narrow it.
**Output**: a classified dependency table and proposed batches; with `upgrade`, the batches you picked applied, each with green gates.
**Boundary**: never applies an upgrade the user did not pick; one batch at a time; a major version is always its own batch. No dispatches. No push, no PR.

## Steps

1. **Detect stacks** from the manifests below; a monorepo gets every one present. Branch per `coding-pipeline/references/branching.md` before any edit.
2. **List outdated + vulnerable** (`rtk` prefix where available):

   | Stack | Outdated | Vulnerable |
   |---|---|---|
   | Go (`go.mod`) | `go list -m -u -json all` | `govulncheck ./...` |
   | Node (`package.json`) | `npm outdated --json` (pnpm/yarn equivalents) | `npm audit --json` |
   | Rust (`Cargo.toml`) | `cargo outdated --root-deps-only` | `cargo audit` |
   | Java (`pom.xml` / `build.gradle*`) | `mvn versions:display-dependency-updates` / `./gradlew dependencyUpdates` | `mvn dependency-check:check` |
   | PHP (`composer.json`) | `composer outdated --direct` | `composer audit` |
   | Python (`pyproject.toml` / `requirements*.txt`) | `pip list --outdated` | `pip-audit` |
   | Flutter (`pubspec.yaml`) | `flutter pub outdated` | — (check advisories via changelog) |

   A tool that is missing → report `unmeasured: install <tool>`, never "no findings".
3. **Classify** every direct dependency: `patch` · `minor` · `major` (semver; `0.x` minor bumps count as major) · `vuln` (with advisory id and severity). Indirect dependencies appear only when they carry a vulnerability.
4. **Read the changelogs** for every minor, major and vuln row: context7 first (`resolve-library-id`, then the docs for the target version), the project's release notes otherwise. Record breaking changes, deprecations the code uses (grep the call sites, cite `file:line`), and the new minimum runtime version.
5. **Propose batches**, printed as one table `| Batch | Packages (from → to) | Kind | Breaking changes hitting this code | Risk |`:
   vulnerability fixes first, then all patches together, then minors grouped by ecosystem, then **one batch per major**.
6. `audit` → stop here. `upgrade` → AskUserQuestion (`multiSelect: true`) over the batches.
7. **Apply one picked batch at a time**: bump the versions, regenerate the lockfile with the package manager (never hand-edit it), adapt the call sites the changelog named, then run the stack's gates from `coding-pipeline/references/quality-gate-reference.md` plus `bash ~/.claude/git-hooks/dup-gate.sh --worktree`. Gates red → fix within the batch or revert that batch's own edits and report; never carry a red batch into the next.
8. **Report**: per batch — versions, call sites changed, gate line, and anything deferred with its reason.

Next: `/validate-code` on the upgraded diff, then `/review-code`.
