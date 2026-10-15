#!/usr/bin/env bash
# src/terminal.sh — Terminal styling, Charm Gum discovery, spinners, and status badges

# Find gum binary if available (checking PATH and user paths even under sudo)
find_gum_binary() {
    if command -v gum &>/dev/null; then
        command -v gum
        return 0
    fi
    local candidates=(
        "/usr/bin/gum"
        "/usr/local/bin/gum"
    )
    if [[ -n "${SUDO_USER:-}" ]]; then
        candidates+=(
            "/home/${SUDO_USER}/.local/bin/gum"
            "/home/${SUDO_USER}/go/bin/gum"
        )
    fi
    candidates+=(
        "${HOME:-}/.local/bin/gum"
        "${HOME:-}/go/bin/gum"
    )
    for c in "${candidates[@]}"; do
        if [[ -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

# Initialize Gum state
GUM_BIN="$(find_gum_binary 2>/dev/null || true)"
USE_GUM=0
if [[ -n "${GUM_BIN}" && -t 1 ]]; then
    USE_GUM=1
fi
# shellcheck disable=SC2034 # GUM_BIN, USE_GUM, and GUM_INITIALIZED are consumed across modules
GUM_INITIALIZED=1

gum_banner() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        "$GUM_BIN" style \
            --border rounded \
            --border-foreground 212 \
            --padding "1 2" \
            --bold \
            "🍓 Arch Linux ARM for Raspberry Pi 5" \
            "🛠️  Clean, Repeatable Image Builder"
        echo ""
    fi
}

run_spin() {
    local title="$1"
    shift
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        "$GUM_BIN" spin --spinner dot --title "$title" -- "$@"
    else
        log_info "$title..."
        "$@"
    fi
}

format_badge() {
    local type="$1"
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        case "$type" in
            OK) "$GUM_BIN" style --foreground 42 --bold "[  OK  ]" ;;
            MISSING) "$GUM_BIN" style --foreground 196 --bold "[MISSING]" ;;
            WARN) "$GUM_BIN" style --foreground 214 "[ WARN ]" ;;
            INFO) "$GUM_BIN" style --foreground 39 "[ INFO ]" ;;
            *) printf '[%s]' "$type" ;;
        esac
    else
        case "$type" in
            OK) printf '[  OK  ]' ;;
            MISSING) printf '[MISSING]' ;;
            WARN) printf '[ WARN ]' ;;
            INFO) printf '[ INFO ]' ;;
            *) printf '[%s]' "$type" ;;
        esac
    fi
}
