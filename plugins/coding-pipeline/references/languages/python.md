# Python — Coding Standards + Review Flags

Loaded on demand by Coder and Reviewer when the story's `Language` is **Python**. Python is a
framework-neutral backend language in this harness; no framework, ORM, package manager, or sample
application is implied.

> **Test rule**: implement to the frozen Test Case table, then write exactly its tests and falsify
> each one. Coverage is a floor, not a target; tautological or unfalsified tests are blocking.
>
> **context7 rule**: verify current Ruff, mypy, pytest, and pip-audit behavior before applying
> tool-specific configuration or APIs.
>
> **Version policy**: use the project's pinned Python/tool versions when present; otherwise target
> the current stable release and record the assumption.

## Structure and Idiom *(authority: Python Developer's Guide → PEP 8/257 → Ruff/mypy conventions)*

| Rule | Requirement |
|---|---|
| Types | Annotate public functions and boundary data; avoid `Any` and untyped containers. |
| Errors | Raise specific exceptions, preserve context, and do not catch broad `Exception` without a deliberate boundary policy. |
| Resources | Use context managers for files, locks, and clients; close resources deterministically. |
| Tests | Use pytest fixtures and observable assertions; do not rely on mock-call-only tests. |
| Security | Validate external input and never interpolate untrusted data into shell, SQL, paths, or logs. |

## Required gates

```text
ruff format --check .
ruff check .
mypy .
pytest --cov --cov-fail-under=85
pip-audit
```

The root `pyproject.toml` is the explicit project marker for hook routing. Duplication is the
common repository gate: `jscpd --threshold 3`, once per pre-push run.

## Review flags

| Issue | Severity |
|---|---|
| Required Python gate is not enforced | BLOCK |
| Coverage below 85% | BLOCK |
| Unsafe shell interpolation, secret leakage, or unvalidated external input | CRITICAL |
| Broad exception handling that hides failures | MAJOR |
| Framework-specific guidance or sample application added out of scope | MAJOR |
| Missing public type annotations or non-idiomatic resource handling | MINOR |
