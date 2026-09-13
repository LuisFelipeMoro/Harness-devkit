# Phase 1 specification: Python harness contract

**Oracle plan:** ora-2  
**Source:** `feat/python-harness-contract`  
**Base:** `main`  
**Freeze date:** 2026-09-13  
**Status:** frozen durable contract; validation owner is the parent orchestrator. The independent
oracle gate runs after the forward merges.

## Scope and non-goals

Phase 1 adds first-class, framework-neutral Python recognition and quality-gate wiring to the
Harness. A root `pyproject.toml` is the explicit project marker. The required toolchain is Ruff
format/check, mypy, pytest-cov with an inclusive 85% floor, pip-audit, and the existing common
jscpd duplication gate.

This phase does **not** add a Python application, package manager, lockfile, virtual environment,
framework, ORM, OpenAPI generator, Python-specific CI matrix, generic hook refactor, changed
thresholds for existing languages, or a second duplication gate. It does not claim that the
developer tools are installed on every machine; the hook tests stub external tools.

## Acceptance criteria

- **AC-1:** Python is selectable through the language-routing index and has a self-contained
  language reference.
- **AC-2:** The canonical and standalone quality-gate references agree on the Python commands and
  the inclusive 85% coverage floor.
- **AC-3:** A project with `pyproject.toml` runs pre-commit `ruff format --check .`, `ruff check .`,
  and `mypy .`; a failing selected gate blocks.
- **AC-4:** A project with `pyproject.toml` runs pre-push `pytest --cov --cov-fail-under=85` and
  `pip-audit`; failures block, including coverage below 85%, while exactly 85% is accepted.
- **AC-5:** A project without `pyproject.toml` does not enter either Python hook branch.
- **AC-6:** The common duplication gate is invoked once per pre-push run and remains stack-agnostic.
- **AC-7:** Pipeline roles, artifact guidance, DevOps/stress/public documentation, and the
  standalone quality-gate plugin recognize Python consistently.
- **AC-8:** Existing hook, installation, duplication-attribution, wiring, and shell sensors remain
  valid.

## Frozen test table

The rows below are the Phase-1 test contract. Each row names an observable result and a concrete
mutation that must make that result fail; a mutation is applied only for falsification and then
restored.

| ID / test | Preconditions | Observable result | AC | Falsified by |
|---|---|---|---|---|
| **P1-01 Python pre-commit routing** | Fixture contains `pyproject.toml`; local Ruff and mypy stubs record argv and succeed. | Pre-commit exits 0 and records exactly `ruff format --check .`, `ruff check .`, and `mypy .`. | AC-3 | Remove the `pyproject.toml` pre-commit branch (or omit one command); the recorded-call assertion fails. |
| **P1-02 Python pre-commit failure propagation** | Fixture contains `pyproject.toml`; one selected fast-gate stub exits 1. | Pre-commit exits non-zero. | AC-3 | Change the Python branch to append `|| true`; the exit-code assertion fails. |
| **P1-03 Non-Python pre-commit isolation** | Fixture has no `pyproject.toml`; Python stubs fail if invoked. | Pre-commit exits 0 and no Python stub is called. | AC-5 | Change the marker guard to an unconditional branch; the no-call/exit assertion fails. |
| **P1-04 Python pre-push routing and exact threshold** | Fixture contains `pyproject.toml`; pytest and pip-audit stubs record argv and succeed; common jscpd is stubbed. | Pre-push records `pytest --cov --cov-fail-under=85` and `pip-audit`, and reaches the common duplication gate once. | AC-4, AC-6 | Remove `--cov-fail-under=85` or the Python pre-push branch; the exact-argv assertion fails. |
| **P1-05 Python test failure propagation** | Python fixture; pytest stub exits 1. | Pre-push exits non-zero and does not report a successful completion. | AC-4 | Add `|| true` to pytest invocation; the exit assertion fails. |
| **P1-06 Coverage below floor** | Python fixture; pytest stub rejects the `--cov-fail-under=85` invocation as an 84% result. | Pre-push exits non-zero. | AC-4 | Change the threshold argument to `84`; the below-floor fixture no longer fails and the assertion fails. |
| **P1-07 Coverage at floor** | Python fixture; pytest accepts the exact `--cov-fail-under=85` threshold and pip-audit succeeds. | Pre-push exits 0. | AC-4 | Change the threshold argument to `86`; the inclusive-boundary assertion fails. |
| **P1-08 Python audit failure propagation** | Python fixture; pytest succeeds and pip-audit exits 1. | Pre-push exits non-zero. | AC-4 | Add `|| true` to pip-audit; the audit failure assertion fails. |
| **P1-09 Common duplication exactly once** | Python fixture is a git repository with a baseline; jscpd stub counts invocations and attribution returns a known result. | Pre-push invokes jscpd once, applies the common attribution result, and blocks an introduced duplicate. | AC-6 | Add a second Python-specific jscpd invocation or bypass attribution; the count/result assertion fails. |
| **P1-10 Wiring and regressions** | Final merged tree; repository fixtures and shell scripts are available. | `test-git-hooks.sh`, `test-hooks.sh`, `test-dup-attribution.sh`, `test-install.sh`, `validate-wiring.py`, `bash -n` for both hooks, and error-level shellcheck exit 0. | AC-1, AC-2, AC-7, AC-8 | Move/remove a referenced Python anchor or break a hook syntax/fixture path; the relevant validation command exits non-zero. |

## Validation commands

The parent orchestrator owns execution and result reporting. Run from the repository root:

```bash
bash .github/scripts/test-git-hooks.sh
bash .github/scripts/test-hooks.sh
bash .github/scripts/test-dup-attribution.sh
bash .github/scripts/test-install.sh
python3 .github/scripts/validate-wiring.py
bash -n plugins/coding-pipeline/git-hooks/pre-commit
bash -n plugins/coding-pipeline/git-hooks/pre-push
shellcheck --severity=error plugins/coding-pipeline/git-hooks/pre-commit plugins/coding-pipeline/git-hooks/pre-push
git diff --check
```

## Falsification evidence observed during implementation

This is local evidence from the implementation work, not raw logs, CI output, or a claim of a
remote check. The hook fixture suite was exercised with the Python marker present and absent,
failing Ruff/pytest/pip-audit stubs, the 84/85 boundary stubs, and a counted common-jscpd stub;
the corresponding routing, failure, boundary, isolation, attribution, and once-only assertions
were observed to fail when their covered hook path was temporarily removed or altered, then the
implementation was restored. Existing non-Python routing cases remained in the same local fixture
suite. Final merged-tree validation and the independent oracle gate are intentionally left to the
parent orchestrator; this document does not claim those results.
