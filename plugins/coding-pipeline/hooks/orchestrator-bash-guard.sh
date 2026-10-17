#!/usr/bin/env bash
# PreToolUse(Bash) for agents/orchestrator.md — the thin main session.
#
# The orchestrator keeps Bash only for gates and git. Every read, search or edit
# it could do through Bash would grow its own context, which is the cost this
# session exists to remove. So the guard admits a short list of command shapes
# and blocks everything else. It is a cost-discipline sensor, not a security
# boundary: destructive-guard.sh still applies to the same session.
#
# Structure is checked, not substrings: heredoc bodies are dropped first (commit
# messages and PROGRESS entries carry arbitrary text), then the command is split
# on every separator, and each segment must start with an allowed word.
set -uf
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "pre:bash:orchestrator-guard" || exit 0

input=$(cat)
cmd="$(devkit_field "$input" command)"
[ -n "$cmd" ] || exit 0

block() {
    echo "BLOCKED: orchestrator runs gates and git only — dispatch an agent for reads, searches and edits."
    exit 2
}

# Heredoc bodies are removed, and the one allowed command substitution (the
# commit-message form) is rewritten to an empty string. Python is used because
# the quoting of heredoc terminators is not expressible reliably in sed.
clean=$(python3 -c '
import re, sys
cmd = sys.argv[1]
opener = re.compile(r"<<-?[ \t]*(\x27|\")?([A-Za-z_][A-Za-z0-9_]*)\1")
commit = re.compile(r"\"\$\(cat[ \t]*<<-?[ \t]*(\x27|\")?[A-Za-z_][A-Za-z0-9_]*\1")
out = []
word = None
for line in cmd.split("\n"):
    if word is not None:
        if line == word:
            word = None
        continue
    m = opener.search(line)
    if m:
        word = m.group(2)
    line = commit.sub("\"\"", line)
    out.append(opener.sub("", line))
sys.stdout.write("\n".join(out))
' "$cmd" 2>/dev/null) || exit 0

# Command substitution and backticks run arbitrary commands inside an argument,
# which would let `git status $(cat x)` read a file. The commit form was rewritten above.
# shellcheck disable=SC2016 # the literal `$(` text is the pattern, not an expansion
case "$clean" in
    *'$('*|*'`'*) block ;;
esac
# A remaining `<` is an input redirect, which reads a file into a command.
case "$clean" in
    *'<'*) block ;;
esac

# Split on every command separator. The `||`, `&&` and `&` forms are replaced
# before the single-character ones so `||` is not read as two pipes.
segs=$(printf '%s' "$clean" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/[;&|]/\
/g')

while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [ -n "$seg" ] || continue
    # Closing fragments of a commit-message substitution run nothing.
    if [ -z "$(printf '%s' "$seg" | tr -d ")\"'")" ]; then
        continue
    fi

    # Output redirects are allowed only into PROGRESS.md.
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        case "$target" in
            PROGRESS.md) ;;
            *) block ;;
        esac
    done <<EOF_TARGETS
$(printf '%s' "$seg" | grep -oE '>>?[[:space:]]*[^[:space:]]*' | sed -E 's/^>>?[[:space:]]*//')
EOF_TARGETS
    # A bare `>` with no target is malformed and blocked the same way.
    if printf '%s' "$seg" | grep -qE '>[[:space:]]*($|[;&|])'; then
        block
    fi

    rest=$(printf '%s' "$seg" | sed -E 's/>>?[[:space:]]*PROGRESS\.md//g; s/^[[:space:]]+//; s/[[:space:]]+$//')
    first="${rest%%[[:space:]]*}"
    args="${rest#"$first"}"
    args="${args#"${args%%[![:space:]]*}"}"

    case "$first" in
        git|gh|cd|test|echo) ;;
        bash)
            target="${args%%[[:space:]]*}"
            case "$target" in
                */scripts/verify/*.sh|*/git-hooks/dup-gate.sh|.github/scripts/*.sh|install.sh|*/install.sh|*/scripts/delivery-state.sh) ;;
                *) block ;;
            esac ;;
        python3)
            target="${args%%[[:space:]]*}"
            case "$target" in
                .github/scripts/*.py|*/scripts/bench-context.py) ;;
                *) block ;;
            esac ;;
        cat)
            # cat is allowed only as the body feeder of a PROGRESS.md append.
            case "$seg" in *PROGRESS.md*) ;; *) block ;; esac
            [ "$rest" = "cat" ] || block ;;
        *) block ;;
    esac
done <<EOF_SEGS
$segs
EOF_SEGS

exit 0
