#!/usr/bin/env bash
# shellcheck disable=SC2034 # GUM_BIN, USE_GUM, and GUM_INITIALIZED are consumed across sourced modules
# src/terminal.sh — Terminal styling, Charm Gum discovery, spinners, and status badges

# Require gum to be available on PATH; early quit if not found
if ! command -v gum &>/dev/null; then
    echo "==> Error: 'gum' is required but not found in PATH." >&2
    echo "    Please install charmbracelet/gum to continue (e.g. 'sudo pacman -S gum' or 'brew install gum')." >&2
    exit 1
fi

# shellcheck disable=SC2034 # GUM_BIN, USE_GUM, and GUM_INITIALIZED are consumed across modules
GUM_BIN="$(command -v gum)"
readonly GUM_BIN
export GUM_BIN
USE_GUM=1
GUM_INITIALIZED=1

gum_banner() {
    "$GUM_BIN" style \
        --border rounded \
        --border-foreground 212 \
        --padding "1 2" \
        --bold \
        "🍓 Arch Linux ARM for Raspberry Pi 5" \
        "🛠️  Clean, Repeatable Image Builder"
    echo ""
}

run_spin() {
    local title="$1"
    shift
    "$GUM_BIN" spin --spinner dot --title "$title" -- "$@"
}

format_badge() {
    local type="$1"
    case "$type" in
        OK) "$GUM_BIN" style --foreground 42 --bold "[  OK  ]" ;;
        MISSING) "$GUM_BIN" style --foreground 196 --bold "[MISSING]" ;;
        WARN) "$GUM_BIN" style --foreground 214 "[ WARN ]" ;;
        INFO) "$GUM_BIN" style --foreground 39 "[ INFO ]" ;;
        *) printf '[%s]' "$type" ;;
    esac
}
