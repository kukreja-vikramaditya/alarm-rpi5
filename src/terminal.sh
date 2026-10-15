#!/usr/bin/env bash
# shellcheck disable=SC2034 # GUM_BIN, USE_GUM, and GUM_INITIALIZED are consumed across sourced modules
# src/terminal.sh — Terminal styling, Charm Gum discovery, spinners, and status badges

# Gum is pre-installed in the Arch Linux builder container
GUM_BIN="$(command -v gum 2>/dev/null || echo "gum")"
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
        *) "$GUM_BIN" style "[$type]" ;;
    esac
}
