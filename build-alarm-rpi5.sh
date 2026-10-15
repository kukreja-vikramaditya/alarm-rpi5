#!/usr/bin/env bash
# shellcheck disable=SC2317
#
# build-alarm-rpi5.sh — Entry point for Arch Linux ARM Raspberry Pi 5 Image Builder
#
# Produces a clean, bootable .img.xz file flashable via Raspberry Pi Imager.
#
# Usage:
#   sudo ./build-alarm-rpi5.sh [OPTIONS]
#

set -euo pipefail

# Script location resolution (works when invoked from any working directory)
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
readonly SRC_DIR="${SCRIPT_DIR}/src"

# Source modular components
# shellcheck source=src/ui.sh
source "${SRC_DIR}/ui.sh"
# shellcheck source=src/cleanup.sh
source "${SRC_DIR}/cleanup.sh"
# shellcheck source=src/cli.sh
source "${SRC_DIR}/cli.sh"
# shellcheck source=src/config.sh
source "${SRC_DIR}/config.sh"
# shellcheck source=src/wizard.sh
source "${SRC_DIR}/wizard.sh"
# shellcheck source=src/doctor.sh
source "${SRC_DIR}/doctor.sh"
# shellcheck source=src/build.sh
source "${SRC_DIR}/build.sh"

# ──────────────────────────────────────────────────────────────────────
# Main Entry Point
# ──────────────────────────────────────────────────────────────────────
main() {
    # 1. Parse CLI arguments
    parse_cli "$@"

    # 2. Diagnostic mode (--check) runs without root
    if [[ -n "${_arg_check}" ]]; then
        init_config
        check_environment
        return $?
    fi

    # 3. Explicit interactive mode without a tty fails early
    if [[ -n "${_arg_interactive:-}" && ( ! -t 0 || ! -t 1 ) ]]; then
        die "Interactive mode requires an interactive terminal (stdin and stdout must be a tty)."
    fi

    # 4. IMMEDIATE ROOT/SUDO CHECK — RUNS BEFORE ANY WIZARD QUESTIONS
    if [[ $EUID -ne 0 ]]; then
        if [[ -t 0 && -t 1 ]]; then
            log_warn "Root privileges are required to build disk images (mount, losetup, pacstrap)."
            log_info "Prompting for sudo password..."
            exec sudo -- "$0" "$@"
        else
            die "This script must be run as root (or via sudo)."
        fi
    fi

    # 5. Initialize configuration (flags > env > defaults)
    init_config

    # 6. Preflight checks (tools, binfmt, qemu)
    preflight

    # 7. Interactive wizard (only runs once root and tools are verified!)
    if [[ -z "${_arg_non_interactive}" ]]; then
        interactive_wizard
    fi

    # 8. Overwrite guard for configured output file
    if [[ -f "${IMG_FILE}" || -f "${IMG_FILE}.xz" ]]; then
        die "Output already exists: ${IMG_FILE}(.xz). Remove it first or change --version."
    fi

    gum_banner

    local start_time
    start_time="$(date +%s)"

    # 9. Execute 5-phase build pipeline
    create_image
    bootstrap_rootfs
    configure_boot
    configure_system
    finalize_image

    local elapsed=$(( $(date +%s) - start_time ))
    log_info "Total build time: $(( elapsed / 60 ))m $(( elapsed % 60 ))s"

    echo ""
    echo "================================================================"
    echo "BUILT IMAGE PATH:"
    echo "${FINAL_BUILT_FILE}"
    echo "================================================================"
    echo ""
}

main "$@"
