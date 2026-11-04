#!/usr/bin/env bash
# install-opencode.sh — CLI wrapper around generate-opencode.py (the OpenCode flavour of the devkit).
# Validates flags and the mandatory model tiers first, so a bad configuration writes nothing.
# Never reads, creates, or modifies the operator's opencode.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATOR="$SCRIPT_DIR/generate-opencode.py"

# ── output ───────────────────────────────────────────────────────────────────
say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die()  { printf 'install-opencode.sh: %s\n' "$*" >&2; exit 1; }
usage_die() { printf 'install-opencode.sh: %s (try --help)\n' "$*" >&2; exit 2; }

usage() {
    cat <<'EOF'
Usage: install-opencode.sh [options]

Generates the OpenCode flavour of the devkit into a target directory.
Never reads, creates, or modifies opencode.json.

Target (at most one; default is the global OpenCode config directory):
  --project [DIR]      install into DIR/.opencode (DIR defaults to the current directory)
  --target DIR         install into DIR exactly
  (neither)            ${XDG_CONFIG_HOME:-$HOME/.config}/opencode

Model tiers (all three mandatory, each in provider/model form):
  --model-cheap VALUE      or DEVKIT_OPENCODE_MODEL_CHEAP
  --model-standard VALUE   or DEVKIT_OPENCODE_MODEL_STANDARD
  --model-deep VALUE       or DEVKIT_OPENCODE_MODEL_DEEP
  A command-line flag wins over the matching environment variable.

Other options:
  --check              validate flags and model tiers, write nothing
  --dry-run            same contract as --check
  --yes, -y            skip confirmation prompts
  --no-git-hooks       do not wire git hooks into the current repository
  --help, -h           show this help
EOF
}

# ── flag parsing ─────────────────────────────────────────────────────────────
PROJECT_SET=0
PROJECT_DIR=""
TARGET_SET=0
TARGET_ARG=""
CHECK_ONLY=0
DRY_RUN=0
ASSUME_YES=0
NO_GIT_HOOKS=0
CLI_CHEAP_SET=0
CLI_CHEAP=""
CLI_STANDARD_SET=0
CLI_STANDARD=""
CLI_DEEP_SET=0
CLI_DEEP=""

need_value() { [ "$#" -ge 2 ] || usage_die "$1 needs a value"; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --project)
            PROJECT_SET=1
            if [ "$#" -ge 2 ]; then
                case "$2" in
                    -*) ;;
                    *)  [ -n "$2" ] || usage_die "--project DIR must not be empty"
                        PROJECT_DIR="$2"; shift ;;
                esac
            fi
            ;;
        --target)
            need_value "$@"
            [ -n "$2" ] || usage_die "--target DIR must not be empty"
            TARGET_SET=1; TARGET_ARG="$2"; shift
            ;;
        --model-cheap)    need_value "$@"; CLI_CHEAP_SET=1;    CLI_CHEAP="$2";    shift ;;
        --model-standard) need_value "$@"; CLI_STANDARD_SET=1; CLI_STANDARD="$2"; shift ;;
        --model-deep)     need_value "$@"; CLI_DEEP_SET=1;     CLI_DEEP="$2";     shift ;;
        --check)          CHECK_ONLY=1 ;;
        --dry-run)        DRY_RUN=1 ;;
        --yes|-y)         ASSUME_YES=1 ;;
        --no-git-hooks)   NO_GIT_HOOKS=1 ;;
        --help|-h)        usage; exit 0 ;;
        *)                usage_die "unknown argument: $1" ;;
    esac
    shift
done

# Mutual exclusion is a flag-parse-stage error: it must fire before model-tier validation.
if [ "$PROJECT_SET" = 1 ] && [ "$TARGET_SET" = 1 ]; then
    usage_die "--project and --target are mutually exclusive"
fi

# ── model tiers (AC4) ────────────────────────────────────────────────────────
if [ "$CLI_CHEAP_SET" = 1 ];    then CHEAP="$CLI_CHEAP";       else CHEAP="${DEVKIT_OPENCODE_MODEL_CHEAP:-}"; fi
if [ "$CLI_STANDARD_SET" = 1 ]; then STANDARD="$CLI_STANDARD"; else STANDARD="${DEVKIT_OPENCODE_MODEL_STANDARD:-}"; fi
if [ "$CLI_DEEP_SET" = 1 ];     then DEEP="$CLI_DEEP";         else DEEP="${DEVKIT_OPENCODE_MODEL_DEEP:-}"; fi

TIER_ERRORS=0

# Argument: tier name, value, env var name. Never echoes the value itself.
validate_tier() {
    local name="$1" value="$2" envname="$3" stripped slashes
    if [ -z "$value" ]; then
        printf 'install-opencode.sh: model tier "%s" is not set (use --model-%s or %s)\n' \
            "$name" "$name" "$envname" >&2
        TIER_ERRORS=1
        return 0
    fi
    stripped="${value//\//}"
    slashes=$(( ${#value} - ${#stripped} ))
    local provider="${value%%/*}" model="${value#*/}" ok=1
    [ "$slashes" -eq 1 ] || ok=0
    [ -n "$provider" ] || ok=0
    [ -n "$model" ] || ok=0
    case "$value" in
        -*|*[[:space:]]*) ok=0 ;;
    esac
    if [ "$ok" = 0 ]; then
        printf 'install-opencode.sh: model tier "%s" is malformed: expected provider/model (exactly one "/", non-empty on both sides, no whitespace)\n' \
            "$name" >&2
        TIER_ERRORS=1
    fi
}

validate_tier cheap    "$CHEAP"    DEVKIT_OPENCODE_MODEL_CHEAP
validate_tier standard "$STANDARD" DEVKIT_OPENCODE_MODEL_STANDARD
validate_tier deep     "$DEEP"     DEVKIT_OPENCODE_MODEL_DEEP
if [ "$TIER_ERRORS" -ne 0 ]; then
    exit 2
fi

# ── target resolution ────────────────────────────────────────────────────────
# Every symlink check (SEC-8/SEC-9) runs in generate-opencode.py on the one resolved TARGET below,
# so --target, --project and the default path are covered by the same code.
if [ "$PROJECT_SET" = 1 ]; then
    TARGET="${PROJECT_DIR:-$PWD}/.opencode"
elif [ "$TARGET_SET" = 1 ]; then
    TARGET="$TARGET_ARG"
else
    TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
fi
case "$TARGET" in
    /*) ;;
    *)  TARGET="$PWD/$TARGET" ;;
esac

# ── check / dry-run: validated, nothing written, generator and git-hooks never reached ──
if [ "$CHECK_ONLY" = 1 ] || [ "$DRY_RUN" = 1 ]; then
    MODE="--check"
    [ "$DRY_RUN" = 1 ] && MODE="--dry-run"
    [ -f "$GENERATOR" ] || die "generator not found: $GENERATOR"
    command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"
    say "install-opencode.sh: $MODE ok — target: $TARGET — model tiers valid — no files written"
    exit 0
fi

# ── generate ─────────────────────────────────────────────────────────────────
[ -f "$GENERATOR" ] || die "generator not found: $GENERATOR"
command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"

# Arguments use the --flag=value form so no value is ever parsed as an option.
GEN_RC=0
python3 "$GENERATOR" \
    --target="$TARGET" \
    --model-cheap="$CHEAP" \
    --model-standard="$STANDARD" \
    --model-deep="$DEEP" || GEN_RC=$?
[ "$GEN_RC" -eq 0 ] || exit "$GEN_RC"

# ── git hooks ────────────────────────────────────────────────────────────────
# Templates reach the target via the generator (devkit/git-hooks/); this step only wires the current repository.
wire_git_hooks() {
    step "Git hooks"
    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        say "  ! not inside a git repository — git hooks not wired"
        return 0
    fi
    if [ "$ASSUME_YES" = 0 ]; then
        if [ ! -t 0 ]; then
            say "  ! non-interactive and no --yes — git hooks not wired"
            return 0
        fi
        printf '  Wire git hooks into the current repository? [y/N] '
        local reply
        read -r reply
        case "$reply" in
            [yY]*) ;;
            *) say "  ! git hooks not wired"; return 0 ;;
        esac
    fi
    bash "$PLUGIN/git-hooks/install.sh"
}

if [ "$NO_GIT_HOOKS" = 0 ]; then
    wire_git_hooks
fi

# ── hand-mergeable command snippet (D1: written by the generator, also printed here) ──
SAMPLE="$TARGET/devkit/commands.json.sample"
[ -f "$SAMPLE" ] || die "generator did not write $SAMPLE"
step "devkit/commands.json.sample — merge by hand into your opencode.json; never merged automatically"
cat "$SAMPLE"
