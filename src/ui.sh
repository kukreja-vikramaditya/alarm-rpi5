#!/usr/bin/env bash
# src/ui.sh — Terminal UI styling, Gum progressive enhancement, and logging

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

_log()  { printf '[%s] [%-5s] %s\n' "$(date '+%H:%M:%S')" "$1" "$2"; }

log_info() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '  %s %s\n' "$("$GUM_BIN" style --foreground 39 "ℹ")" "$*"
    else
        _log "INFO" "$*"
    fi
}

log_warn() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '  %s %s\n' "$("$GUM_BIN" style --foreground 214 "⚠")" "$*" >&2
    else
        _log "WARN" "$*" >&2
    fi
}

log_error() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '  %s %s\n' "$("$GUM_BIN" style --foreground 196 --bold "✖")" "$*" >&2
    else
        _log "ERROR" "$*" >&2
    fi
}

log_phase() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '\n'
        "$GUM_BIN" style --bold --foreground 212 "==> $*"
    else
        printf '\n[%s] === %s ===\n' "$(date '+%H:%M:%S')" "$*"
    fi
}

gum_banner() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        "$GUM_BIN" style \
            --border rounded \
            --border-foreground 212 \
            --padding "1 2" \
            --bold \
            "Arch Linux ARM for Raspberry Pi 5" \
            "Clean, Repeatable Image Builder"
        echo ""
    fi
}

run_spin() {
    local title="$1"; shift
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        "$GUM_BIN" spin --spinner dot --title "$title" -- "$@"
    else
        log_info "$title..."
        "$@"
    fi
}

die() {
    log_error "$@"
    exit 1
}

format_badge() {
    local type="$1"
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        case "$type" in
            OK)      "$GUM_BIN" style --foreground 42 --bold "[  OK  ]" ;;
            MISSING) "$GUM_BIN" style --foreground 196 --bold "[MISSING]" ;;
            WARN)    "$GUM_BIN" style --foreground 214 "[ WARN ]" ;;
            INFO)    "$GUM_BIN" style --foreground 39 "[ INFO ]" ;;
            *)       printf '[%s]' "$type" ;;
        esac
    else
        case "$type" in
            OK)      printf '[  OK  ]' ;;
            MISSING) printf '[MISSING]' ;;
            WARN)    printf '[ WARN ]' ;;
            INFO)    printf '[ INFO ]' ;;
            *)       printf '[%s]' "$type" ;;
        esac
    fi
}
