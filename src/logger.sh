#!/usr/bin/env bash
# src/logger.sh — Structured logging, phases, and error handling

# Ensure terminal capabilities are loaded
if [[ -z "${GUM_INITIALIZED:-}" ]]; then
    LOGGER_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
    LOGGER_DIR="$(dirname -- "${LOGGER_PATH}")"
    # shellcheck source=src/terminal.sh
    source "${LOGGER_DIR}/terminal.sh"
fi

_log() { printf '[%s] [%-5s] %s\n' "$(date '+%H:%M:%S')" "$1" "$2"; }

# Format string substitution helper (Java String.format equivalent)
# Usage: format_string <var_name> <template> [args...]
format_string() {
    local _var_name="$1"
    local _fmt="$2"
    shift 2
    # shellcheck disable=SC2059
    printf -v "$_var_name" "$_fmt" "$@"
}

_format_log_msg() {
    if [[ $# -gt 1 ]]; then
        local fmt="$1"
        shift
        # shellcheck disable=SC2059
        printf -v _LOG_MSG "$fmt" "$@"
    else
        _LOG_MSG="${1:-}"
    fi
}

log_info() {
    local _LOG_MSG
    _format_log_msg "$@"
    "$GUM_BIN" log -l info "$_LOG_MSG"
}

log_warn() {
    local _LOG_MSG
    _format_log_msg "$@"
    "$GUM_BIN" log -l warn "$_LOG_MSG"
}

log_error() {
    local _LOG_MSG
    _format_log_msg "$@"
    "$GUM_BIN" log -l error "$_LOG_MSG"
}

log_phase() {
    local _LOG_MSG
    _format_log_msg "$@"
    printf '\n'
    "$GUM_BIN" style --bold --foreground 212 "==> $_LOG_MSG"
}

die() {
    log_error "$@"
    exit 1
}
