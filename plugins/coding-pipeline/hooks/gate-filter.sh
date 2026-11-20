#!/usr/bin/env bash
# PreToolUse(Bash) — rewrite a simple gate command so only its failures and a short
# tail reach context. The full output is kept in a per-session file and named in
# the last line, so evidence stays restorable.
#
# Rewrites only a simple command that starts with a gate (DEVKIT_GATE_RE). Anything
# compound, commented, prefixed with rtk, or run while an rtk binary is on PATH is
# left alone. The rewrite never sets permissionDecision: the rewritten command goes
# through the normal permission flow. Every failure path exits 0 and prints nothing,
# so the command runs unfiltered rather than not at all.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./hook-lib.sh
. "$SCRIPT_DIR/hook-lib.sh"

devkit_hook_enabled "pre:bash:gate-filter" || exit 0
# Opt-in (G3): Claude Code cannot pre-check the rewritten compound command, so the filter
# needs a broad Bash allow (auto/bypass mode or the driver grant) before it adds no prompt.
[ "${DEVKIT_GATE_FILTER:-}" = 1 ] || exit 0
# rtk owns the output shaping when it is installed: two rewriters on one call is
# undocumented behaviour (ADR-1).
if command -v rtk >/dev/null 2>&1; then exit 0; fi

# One python3 start per Bash call (NFR-2) for the gate decision: it parses the payload,
# decides, creates the log file and emits the JSON. Any failure leaves stdout empty.
IFS= read -r -d '' GATE_FILTER_PY <<'PY' || true
import json, os, re, shutil, sys, time

gate_re, state = sys.argv[1], sys.argv[2]
if not gate_re or not state:
    sys.exit(0)  # no gate list or no state dir: rewrite nothing rather than everything

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tool_input = payload.get("tool_input") if isinstance(payload, dict) else None
cmd = tool_input.get("command") if isinstance(tool_input, dict) else None
if not isinstance(cmd, str) or not cmd:
    sys.exit(0)
if not os.path.isdir(state):
    sys.exit(0)

# AC1: a gate starts the command, followed by whitespace or end of string.
if not re.match(r"(?:" + gate_re + r")(?:[ \t]|\Z)", cmd):
    sys.exit(0)
# AC3: compound, redirected, commented or multi-line commands are left alone.
# Checked by plain substring on purpose: a quoted `|` still skips the rewrite.
for meta in ("|", ";", "&", "<", ">", "$(", "`", "#", "\n", "\r"):
    if meta in cmd:
        sys.exit(0)
if cmd.startswith("rtk"):
    sys.exit(0)

path = os.path.join(state, "gate-%d-%d.log" % (int(time.time()), os.getpid()))
# The path is spliced into a double-quoted echo, so refuse the characters that would
# expand there. Single quotes are escaped below and stay safe.
if any(c in path for c in '"$`\\'):
    sys.exit(0)
try:
    # Create it now: proves the state dir is writable before the command is rewritten
    # to redirect into it, and O_EXCL never reuses another run's log.
    os.close(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
except OSError:
    sys.exit(0)

q = "'" + path.replace("'", "'\\''") + "'"
rewritten = (
    "{ " + cmd + " ; } > " + q + " 2>&1; rc=$?; "
    "grep -nE -B2 -A6 'FAIL|ERROR|Error|error:|panic:|✗|×' " + q + " | head -n 150; "
    "tail -n 20 " + q + "; "
    'echo "[gate-filter] exit $rc · full output: ' + q + '"; '
    "(exit $rc)"
)
updated = dict(tool_input)
updated["command"] = rewritten
json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": updated}}, sys.stdout)
PY

# The state dir is the one rule every hook shares (hook-lib.sh devkit_state_dir). If it
# cannot be made, the command runs unfiltered: fail open (A05), never blocked.
payload="$(cat)"
state="$(devkit_state_dir "$payload")" || exit 0
[ -n "$state" ] || exit 0
# JSON is printed only when python exited 0 with output. Any other outcome — unparseable
# payload, unwritable log, python crash — leaves stdout empty and exits 0.
out=$(printf '%s' "$payload" | python3 -c "$GATE_FILTER_PY" "$DEVKIT_GATE_RE" "$state" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -n "$out" ] && printf '%s' "$out"
exit 0
