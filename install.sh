#!/usr/bin/env bash
# claude-devkit — machine bootstrap.
#
# One entry point that takes a bare machine to a fully configured Claude Code
# setup: detect the OS, install what is missing, put the devkit on disk, copy it
# into ~/.claude, and wire the hooks into settings.json so the guards are actually
# live rather than merely present.
#
# Re-running is the normal case. It compares the installed commit against the
# source commit and does nothing expensive when they match.
#
#   bash install.sh              # install or update
#   bash install.sh --check      # report only; never writes
#   bash install.sh --yes        # no prompts (CI, provisioning)
#   bash install.sh --no-deps    # skip package installation
#   bash install.sh --no-claude-mem   # skip the claude-mem memory layer
#   bash install.sh --dry-run    # print what would happen
#
# Deliberately does NOT pipe a downloaded script into a shell — the devkit's own
# destructive-guard blocks that shape, and an installer that breaks its own rule
# is not worth shipping. Anything downloaded is written to disk, its path shown,
# and executed only after confirmation.
set -euo pipefail

DEVKIT_REPO="${DEVKIT_REPO:-https://github.com/LuisFelipeMoro/claude-devkit.git}"
DEVKIT_HOME="${DEVKIT_HOME:-$HOME/.local/share/claude-devkit}"
TARGET_HOME="${TARGET_HOME:-$HOME}"
PLUGIN_NAME="coding-pipeline"

ASSUME_YES=0
CHECK_ONLY=0
SKIP_DEPS=0
DRY_RUN=0
SKIP_CLAUDE_MEM=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y)    ASSUME_YES=1 ;;
        --check)     CHECK_ONLY=1 ;;
        --no-deps)   SKIP_DEPS=1 ;;
        --no-claude-mem) SKIP_CLAUDE_MEM=1 ;;
        --dry-run)   DRY_RUN=1 ;;
        --home)      [ "$#" -ge 2 ] || { echo "--home needs a directory" >&2; exit 2; }
                     shift; TARGET_HOME="$1" ;;
        --home=*)    TARGET_HOME="${1#--home=}" ;;
        --help|-h)   sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

CLAUDE_DIR="$TARGET_HOME/.claude"
STATE_FILE="$CLAUDE_DIR/devkit/install-state.json"

# ── output ───────────────────────────────────────────────────────────────────
say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
die()  { printf '\n✗ %s\n' "$*" >&2; exit 1; }

confirm() {
    [ "$ASSUME_YES" = "1" ] && return 0
    [ -t 0 ] || return 1          # non-interactive and not --yes: decline
    printf '  %s [y/N] ' "$1"
    read -r reply
    case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ── platform ─────────────────────────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
        *)      echo unsupported ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) echo arm64 ;;
        x86_64|amd64)  echo x86_64 ;;
        *)             uname -m ;;
    esac
}

detect_distro() {
    [ -r /etc/os-release ] || { echo unknown; return; }
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}"
}

# Ordered so a machine with several managers picks the one that owns user-space
# packages: Homebrew on macOS, the system manager on Linux.
detect_pkg_manager() {
    if [ "$(detect_os)" = "macos" ]; then
        command -v brew >/dev/null 2>&1 && { echo brew; return; }
        echo none; return
    fi
    for pm in apt-get dnf yum pacman zypper apk brew; do
        command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return; }
    done
    echo none
}

pkg_install() {   # pkg_install <package>...
    local pm="$1"; shift
    [ "$#" -gt 0 ] || return 0
    if [ "$DRY_RUN" = "1" ]; then
        say "  would install with $pm: $*"
        return 0
    fi
    case "$pm" in
        brew)    brew install "$@" ;;
        apt-get) sudo apt-get update -qq && sudo apt-get install -y "$@" ;;
        dnf)     sudo dnf install -y "$@" ;;
        yum)     sudo yum install -y "$@" ;;
        pacman)  sudo pacman -S --noconfirm "$@" ;;
        zypper)  sudo zypper install -y "$@" ;;
        apk)     sudo apk add "$@" ;;
        *)       return 1 ;;
    esac
}

# Package names differ per manager; only the ones that actually differ are mapped.
pkg_name() {      # pkg_name <manager> <tool>
    case "$2:$1" in
        python3:pacman) echo python ;;
        python3:apk)    echo python3 ;;
        *)              echo "$2" ;;
    esac
}

# ── dependencies ─────────────────────────────────────────────────────────────
REQUIRED_TOOLS="git python3 curl"
RECOMMENDED_TOOLS="gh shellcheck rg"

tool_pkg() {      # some binaries are not named like their package
    case "$1" in
        rg) echo ripgrep ;;
        *)  echo "$1" ;;
    esac
}

missing_tools() {
    local out=""
    for t in $1; do
        command -v "$t" >/dev/null 2>&1 || out="$out $t"
    done
    printf '%s' "${out# }"
}

install_deps() {
    local pm missing_req missing_rec pkgs
    pm="$(detect_pkg_manager)"
    missing_req="$(missing_tools "$REQUIRED_TOOLS")"
    missing_rec="$(missing_tools "$RECOMMENDED_TOOLS")"

    if [ -z "$missing_req" ] && [ -z "$missing_rec" ]; then
        ok "all dependencies present"
        return 0
    fi

    if [ "$pm" = "none" ]; then
        [ -n "$missing_req" ] && die "missing required tools:$missing_req — no supported package manager found. Install them, then re-run."
        warn "no package manager found; optional tools not installed:$missing_rec"
        return 0
    fi

    pkgs=""
    for t in $missing_req $missing_rec; do
        pkgs="$pkgs $(pkg_name "$pm" "$(tool_pkg "$t")")"
    done
    # shellcheck disable=SC2086
    set -- $pkgs

    say "  missing:${missing_req:+ required:$missing_req}${missing_rec:+ optional:$missing_rec}"
    if confirm "install with $pm?"; then
        # shellcheck disable=SC2086
        pkg_install "$pm" "$@" || warn "package install reported an error; continuing"
    else
        [ -n "$missing_req" ] && die "required tools missing and install declined:$missing_req"
        warn "skipped optional tools:$missing_rec"
    fi
}

install_claude_code() {
    if command -v claude >/dev/null 2>&1; then
        ok "claude $(claude --version 2>/dev/null | head -1)"
        return 0
    fi
    warn "Claude Code CLI not found"
    if [ "$DRY_RUN" = "1" ]; then say "  would install Claude Code"; return 0; fi
    if command -v npm >/dev/null 2>&1; then
        if confirm "install Claude Code via npm?"; then
            npm install -g @anthropic-ai/claude-code || warn "npm install failed"
            return 0
        fi
    fi
    local installer="${TMPDIR:-/tmp}/claude-install.sh"
    if confirm "download the official installer to $installer for review?"; then
        curl -fsSL https://claude.ai/install.sh -o "$installer" || { warn "download failed"; return 0; }
        say "  downloaded. Review it, then run: bash $installer"
        if confirm "run it now?"; then bash "$installer" || warn "installer failed"; fi
    else
        warn "skipped — install Claude Code yourself, then re-run this script"
    fi
}

# claude-mem (github.com/thedotmack/claude-mem) persists context across sessions —
# the same Memory leg PROGRESS.md serves, but automatic and conversation-level.
# Optional and third-party, so it is opt-out and never fatal.
#
# Preflight is split from the install so the test suite can exercise the gating
# without a network call or a real install. Its upstream docs are explicit that a
# global npm install does not register the hooks; `npx claude-mem install` does.
claude_mem_preflight() {
    # Defaulted rather than bare: the test suite sources this file, and a shell
    # that scopes prefix assignments to the source command would leave it unset.
    if [ "${SKIP_CLAUDE_MEM:-0}" = "1" ]; then
        echo "skipped by --no-claude-mem"; return 1
    fi
    if ! command -v node >/dev/null 2>&1; then
        echo "needs Node.js (>= 20) — not found"; return 1
    fi
    local major
    major="$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
    case "$major" in
        ''|*[!0-9]*) echo "could not read the Node.js version"; return 1 ;;
    esac
    if [ "$major" -lt 20 ]; then
        echo "needs Node.js >= 20, found v$major"; return 1
    fi
    command -v npx >/dev/null 2>&1 || { echo "needs npx"; return 1; }
    return 0
}

install_claude_mem() {
    local reason
    if ! reason="$(claude_mem_preflight)"; then
        warn "claude-mem: $reason"
        return 0
    fi
    if [ -d "$HOME/.claude-mem" ]; then
        ok "claude-mem already installed"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then say "  would run: npx --yes claude-mem install"; return 0; fi
    if confirm "install claude-mem (persists context across sessions)?"; then
        npx --yes claude-mem install || warn "claude-mem install failed — continuing without it"
    else
        warn "claude-mem skipped"
    fi
}

# ── source tree ──────────────────────────────────────────────────────────────
# Running from inside a clone uses that clone; otherwise the repo is fetched to
# DEVKIT_HOME. Either way SOURCE_DIR ends up pointing at a checkout.
resolve_source() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/.claude-plugin/marketplace.json" ]; then
        SOURCE_DIR="$script_dir"
        SOURCE_KIND="local checkout"
        return 0
    fi
    SOURCE_DIR="$DEVKIT_HOME"
    SOURCE_KIND="managed clone"
    if [ -d "$DEVKIT_HOME/.git" ]; then
        [ "$DRY_RUN" = "1" ] && { say "  would fetch updates in $DEVKIT_HOME"; return 0; }
        git -C "$DEVKIT_HOME" fetch --quiet origin || warn "fetch failed; using the checkout as-is"
    else
        [ "$DRY_RUN" = "1" ] && { say "  would clone $DEVKIT_REPO into $DEVKIT_HOME"; return 0; }
        mkdir -p "$(dirname "$DEVKIT_HOME")"
        git clone --quiet "$DEVKIT_REPO" "$DEVKIT_HOME" || die "clone failed: $DEVKIT_REPO"
    fi
}

source_sha() {
    git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || echo unknown
}

# Reports whether the checkout is behind its remote. Never rewrites history and
# never touches a dirty or diverged tree — that is the operator's call.
sync_source() {
    git -C "$SOURCE_DIR" rev-parse --git-dir >/dev/null 2>&1 || { warn "source is not a git checkout; using files as-is"; return 0; }
    local branch upstream behind ahead dirty
    branch="$(git -C "$SOURCE_DIR" rev-parse --abbrev-ref HEAD)"
    upstream="$(git -C "$SOURCE_DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
    [ -n "$upstream" ] || { ok "on $branch (no upstream to compare)"; return 0; }
    dirty="$(git -C "$SOURCE_DIR" status --porcelain | wc -l | tr -d ' ')"
    behind="$(git -C "$SOURCE_DIR" rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
    ahead="$(git -C "$SOURCE_DIR" rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)"

    if [ "$behind" = "0" ]; then
        ok "source up to date with $upstream"
        return 0
    fi
    if [ "$dirty" != "0" ] || [ "$ahead" != "0" ]; then
        warn "source is $behind commit(s) behind $upstream but has local work (dirty=$dirty ahead=$ahead) — not touching it"
        return 0
    fi
    if [ "$SOURCE_KIND" = "managed clone" ] || confirm "fast-forward $branch to $upstream ($behind behind)?"; then
        [ "$DRY_RUN" = "1" ] && { say "  would fast-forward $branch"; return 0; }
        git -C "$SOURCE_DIR" merge --ff-only "$upstream" --quiet && ok "fast-forwarded $branch to $upstream"
    else
        warn "left $branch $behind commit(s) behind"
    fi
}

# Staging the hook scripts and wiring settings.json are separate steps, and
# install-global.sh owns the wiring. This proves it happened: a machine with every
# guard on disk and none referenced by settings.json is the silent failure here.
verify_wiring() {   # verify_wiring <plugin-dir> <home>
    python3 - "$1" "$2" <<'PYCHECK'
import json, os, sys
plugin, home = sys.argv[1], sys.argv[2]
hooks_dir = os.path.join(plugin, "hooks")
shipped = {f for f in os.listdir(hooks_dir)
           if f.endswith(".sh") and f != "hook-lib.sh"}
settings_path = os.path.join(home, ".claude", "settings.json")
try:
    with open(settings_path, encoding="utf-8") as fh:
        settings = json.load(fh)
except (OSError, json.JSONDecodeError) as exc:
    print("  ! cannot read %s: %s" % (settings_path, exc))
    sys.exit(1)
wired = json.dumps(settings.get("hooks", {}))
missing = sorted(n for n in shipped if n not in wired)
if missing:
    print("  ! not referenced by settings.json: " + ", ".join(missing))
    sys.exit(1)
print("  \u2713 all %d hooks referenced by settings.json" % len(shipped))
PYCHECK
}

installed_sha() {
    [ -f "$STATE_FILE" ] || { echo none; return; }
    python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('commit','none'))" "$STATE_FILE" 2>/dev/null || echo none
}

write_state() {
    [ "$DRY_RUN" = "1" ] && return 0
    mkdir -p "$(dirname "$STATE_FILE")"
    python3 - "$STATE_FILE" "$(source_sha)" "$SOURCE_DIR" <<'PY'
import json, sys, time
path, commit, source = sys.argv[1], sys.argv[2], sys.argv[3]
json.dump({"commit": commit, "source": source,
           "installed_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")},
          open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
}

# The test suite sources this file to exercise the detection helpers without
# running an install. Nothing else sets DEVKIT_LIB_ONLY.
if [ "${DEVKIT_LIB_ONLY:-0}" = "1" ]; then
    return 0
fi

# ── main ─────────────────────────────────────────────────────────────────────
OS="$(detect_os)"
ARCH="$(detect_arch)"
[ "$OS" = "unsupported" ] && die "unsupported OS: $(uname -s). This installer covers macOS, Linux, and WSL."

step "claude-devkit installer"
say "  os: $OS/$ARCH$([ "$OS" != macos ] && printf ' (%s)' "$(detect_distro)")   package manager: $(detect_pkg_manager)"
say "  target: $CLAUDE_DIR"

step "1/5  source"
resolve_source
say "  $SOURCE_KIND: $SOURCE_DIR"
[ "$DRY_RUN" = "1" ] || sync_source
SRC_SHA="$(source_sha)"
CUR_SHA="$(installed_sha)"
if [ "$CUR_SHA" = "none" ]; then
    say "  installed: nothing yet"
elif [ "$CUR_SHA" = "$SRC_SHA" ]; then
    ok "already installed at ${SRC_SHA:0:8} — up to date"
else
    say "  installed ${CUR_SHA:0:8} → source ${SRC_SHA:0:8}"
fi

if [ "$CHECK_ONLY" = "1" ]; then
    step "2/5  dependencies (check only)"
    for t in $REQUIRED_TOOLS $RECOMMENDED_TOOLS claude; do
        if command -v "$t" >/dev/null 2>&1; then ok "$t"; else warn "$t missing"; fi
    done
    if [ -d "$HOME/.claude-mem" ]; then
        ok "claude-mem"
    else
        reason="$(claude_mem_preflight)" && warn "claude-mem not installed (eligible)" \
            || warn "claude-mem not installed ($reason)"
    fi
    say ""
    say "--check made no changes."
    exit 0
fi

step "2/5  dependencies"
if [ "$SKIP_DEPS" = "1" ]; then
    warn "--no-deps: skipping package installation"
else
    install_deps
    install_claude_code
    install_claude_mem
fi

step "3/5  devkit files → $CLAUDE_DIR"
if [ "$DRY_RUN" = "1" ]; then
    say "  would run install-global.sh against $CLAUDE_DIR"
else
    HOME="$TARGET_HOME" bash "$SOURCE_DIR/plugins/$PLUGIN_NAME/scripts/install-global.sh"
fi

step "4/5  verify wiring"
if [ "$DRY_RUN" = "1" ]; then
    say "  would verify every shipped hook is referenced by settings.json"
else
    verify_wiring "$SOURCE_DIR/plugins/$PLUGIN_NAME" "$TARGET_HOME" \
        || die "hooks are staged but not active — see the message above"
fi

step "5/5  record state"
write_state
ok "installed commit ${SRC_SHA:0:8}"

step "done"
say "  Restart Claude Code so it re-reads ~/.claude/settings.json."
say "  Verify any time with: bash $SOURCE_DIR/install.sh --check"
say "  Wire git hooks into a repo: bash $CLAUDE_DIR/git-hooks/install.sh"
