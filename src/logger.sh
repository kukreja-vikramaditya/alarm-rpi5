#!/usr/bin/env bash
# src/logger.sh — Structured logging, phases, and error handling

# Ensure terminal capabilities are loaded
if [[ -z "${GUM_INITIALIZED:-}" ]]; then
    LOGGER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    # shellcheck source=src/terminal.sh
    source "${LOGGER_DIR}/terminal.sh"
fi

_log() { printf '[%s] [%-5s] %s\n' "$(date '+%H:%M:%S')" "$1" "$2"; }

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

die() {
    log_error "$@"
    exit 1
}
