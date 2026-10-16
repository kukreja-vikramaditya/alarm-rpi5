#!/usr/bin/env bash
# shellcheck disable=SC2034 # Wizard settings are consumed by gum.sh and bash.sh
# wizard/config.sh — Argument parsing, usage, and configuration defaults for wizard

usage() {
    cat <<USAGE
Usage: ./wizard.sh [OPTIONS]

Interactive Charm Gum TUI wizard for Arch Linux ARM Raspberry Pi 5.
Prompts for configuration and generates the executable ./build.sh command.

Options:
  --bash       Force pure Bash fallback mode (no gum)
  --dry-run    Print generated command without executing
  -h, --help   Show this help message
USAGE
}

parse_wizard_cli() {
    for arg in "$@"; do
        case "$arg" in
            --bash)
                FORCE_BASH=1
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                echo "==> Error: Unknown option '$arg'" >&2
                usage >&2
                exit 1
                ;;
        esac
    done

    # Non-TTY guard: wizard requires an interactive terminal unless --bash mode is requested
    if [[ "${FORCE_BASH}" -eq 0 && (! -t 0 || ! -t 1) ]]; then
        echo "==> Error: Interactive wizard requires an interactive terminal (stdin and stdout must be a tty)." >&2
        echo "    To run a build non-interactively, use: ./build.sh -y" >&2
        exit 1
    fi
}

load_wizard_defaults() {
    VERSION=""
    if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
        VERSION="$(tr -d '[:space:]' <"${SCRIPT_DIR}/VERSION")"
    fi
    VERSION="${VERSION:-0.0.0-snapshot}"
    TARGET_HOSTNAME="raspberrypi"
    ROOT_USER="root"
    ROOT_PASSWORD="root"
    ALARM_USER="alarm"
    ALARM_PASSWORD="alarm"
    IMG_SIZE="3G"
    COMPRESS=1
    OUTPUT_DIR="${SCRIPT_DIR}/dist"

    if [[ -f "${SCRIPT_DIR}/alarm.conf" ]]; then
        # shellcheck source=/dev/null
        source "${SCRIPT_DIR}/alarm.conf"
        VERSION="${VERSION:-0.0.0-snapshot}"
        TARGET_HOSTNAME="${HOSTNAME:-${TARGET_HOSTNAME:-raspberrypi}}"
        ROOT_USER="${ROOT_USER:-root}"
        ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
        ALARM_USER="${USERNAME:-${ALARM_USER:-alarm}}"
        ALARM_PASSWORD="${PASSWORD:-${ALARM_PASSWORD:-alarm}}"
        IMG_SIZE="${IMAGE_SIZE:-${IMG_SIZE:-3G}}"
        COMPRESS="${COMPRESS:-1}"
        OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/dist}"
    fi
}
