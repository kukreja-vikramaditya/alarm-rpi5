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

    # 5. Clean up any lingering resources from previous runs BEFORE setup begins
    cleanup_previous_run

    # 6. Initialize configuration (flags > env > defaults)
    init_config

    # 7. Preflight checks (tools, binfmt, qemu)
    preflight

    # 8. Interactive wizard (only runs once root and tools are verified!)
    if [[ -z "${_arg_non_interactive}" ]]; then
        interactive_wizard
    fi

    # 9. Check if previous run left output artifacts
    local existing_target=""
    if [[ -f "${IMG_FILE}.xz" ]]; then
        existing_target="${IMG_FILE}.xz"
    elif [[ -f "${IMG_FILE}" ]]; then
        existing_target="${IMG_FILE}"
    fi

    if [[ -n "${existing_target}" ]]; then
        if [[ -t 0 && -t 1 && -z "${_arg_non_interactive:-}" ]]; then
            log_warn "Output artifact from a previous run exists: ${existing_target}"
            local overwrite_confirm=0
            if [[ "${USE_GUM:-0}" -eq 1 ]]; then
                if "$GUM_BIN" confirm "Overwrite previous build artifact?"; then
                    overwrite_confirm=1
                fi
            else
                local reply
                read -r -p "Overwrite previous build artifact? (y/n) [n]: " reply
                if [[ "$reply" =~ ^[Yy] ]]; then
                    overwrite_confirm=1
                fi
            fi

            if [[ $overwrite_confirm -eq 1 ]]; then
                log_info "Removing previous build artifact: ${existing_target}"
                if command -v losetup &>/dev/null; then
                    local ldev
                    while read -r ldev; do
                        [[ -n "$ldev" ]] && losetup -d "$ldev" 2>/dev/null || true
                    done < <(losetup -j "${IMG_FILE}" 2>/dev/null | cut -d: -f1)
                fi
                rm -f -- "${IMG_FILE}" "${IMG_FILE}.xz"
            else
                echo "Build cancelled by user (will not overwrite existing output)."
                exit 0
            fi
        else
            die "Output already exists: ${existing_target}. Remove it first or change --version."
        fi
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
