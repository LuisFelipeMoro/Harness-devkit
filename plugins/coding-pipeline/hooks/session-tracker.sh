#!/usr/bin/env bash
# PostToolUse(Bash|Write|Edit|MultiEdit) — record what this session actually did.
#
# Deterministic evidence only: which source files were written, and whether a
# gate command was ever run. delivery-gate.sh reads this at Stop. Nothing here
# blocks and nothing is inferred from prose — the point is that "gates passed"
# stops being a claim the model makes about itself.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "post:session-tracker" || exit 0

input=$(cat)
state="$(devkit_state_dir "$input")" || exit 0

file="$(devkit_field "$input" file_path path)"
case "$file" in
    *.go|*.ts|*.tsx|*.js|*.jsx|*.py|*.rs|*.java|*.kt|*.kts|*.php|*.dart|*.sql|*.sh|*.rb|*.cs)
        printf '%s\n' "$file" >> "$state/edits" ;;
esac

cmd="$(devkit_field "$input" command)"
if [ -n "$cmd" ]; then
    # A gate is a command that can fail the build: test runners, linters, type
    # checkers, vulnerability scanners. Formatters alone do not count.
    if printf '%s' "$cmd" | grep -qE '(go test|golangci-lint|go vet|govulncheck|npm (run )?test|pnpm (run )?test|yarn test|vitest|jest|tsc |eslint|pytest|ruff check|cargo test|cargo clippy|mvn test|gradle test|phpunit|phpstan|flutter test|dart analyze)'; then
        printf '%s\n' "$cmd" >> "$state/gates"
    fi
fi
exit 0
