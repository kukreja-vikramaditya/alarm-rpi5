#!/usr/bin/env bash
# shellcheck disable=SC2317
#
# build.sh — Entry point for Arch Linux ARM Raspberry Pi 5 Image Builder
#
# Produces a clean, bootable .img.xz file flashable via Raspberry Pi Imager.
#
# Usage:
#   sudo ./build.sh [OPTIONS]
#

set -euo pipefail

# Script location resolution (works when invoked from any working directory)
SCRIPT_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "${SCRIPT_PATH}")"
readonly SCRIPT_PATH
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename -- "${SCRIPT_PATH}")"
readonly SCRIPT_NAME
readonly SRC_DIR="${SCRIPT_DIR}/src"
readonly DATA_DIR="${SCRIPT_DIR}/data"

# Source modular components
# shellcheck source=src/terminal.sh
source "${SRC_DIR}/terminal.sh"
# shellcheck source=src/logger.sh
source "${SRC_DIR}/logger.sh"
# shellcheck source=src/cleanup.sh
source "${SRC_DIR}/cleanup.sh"
# shellcheck source=src/cli.sh
source "${SRC_DIR}/cli.sh"
# shellcheck source=src/config.sh
source "${SRC_DIR}/config.sh"
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

    # 2. Host-to-Container Bridge
    # Docker is mandatory. Unless already inside the container (/.dockerenv / ALARM_INTERNAL_BUILD),
    # build seamlessly inside the Arch Linux container image.
    if [[ "${ALARM_FORCE_HOST_MODE:-0}" -eq 1 ]] || [[ ! -f /.dockerenv && -z "${ALARM_INTERNAL_BUILD:-}" ]]; then
        if [[ -n "${_arg_check:-}" ]]; then
            log_phase "Host Docker Environment Diagnostics"
            if command -v docker &>/dev/null; then
                log_info "Docker CLI: installed ($(command -v docker))"
                if docker info &>/dev/null 2>&1; then
                    log_info "Docker daemon: running and accessible"
                else
                    log_warn "Docker daemon: not accessible or requires sudo"
                fi
            else
                log_error "Docker CLI: not found in PATH"
            fi
            return 0
        fi

        if [[ "${MOCK_DOCKER_MISSING:-0}" -eq 1 ]] || ! command -v docker &>/dev/null || ! docker --version &>/dev/null; then
            die "Docker is required to build Arch Linux ARM images.
Please install Docker and ensure the Docker daemon is running.
If using Docker Desktop on Windows with WSL 2, enable WSL Integration in:
  Docker Desktop -> Settings -> Resources -> WSL Integration"
        fi

        log_info "Ensuring Arch Linux builder image (alarm-rpi5-builder) is up to date..."
        docker build -t alarm-rpi5-builder -f "${SCRIPT_DIR}/Dockerfile" "${SCRIPT_DIR}"

        mkdir -p "${SCRIPT_DIR}/dist"

        local -a tty_flags=()
        if [[ -t 0 && -t 1 ]]; then
            tty_flags+=("-it")
        fi

        log_info "Running build inside isolated Arch Linux container..."
        exec docker run --rm --privileged "${tty_flags[@]}" \
            -e "ALARM_INTERNAL_BUILD=1" \
            -v /dev:/dev \
            -v /sys:/sys \
            -v "${SCRIPT_DIR}:/workspace" \
            -w /workspace \
            alarm-rpi5-builder "$@"
    fi

    # 3. Diagnostic mode (--check) runs without root
    if [[ -n "${_arg_check}" ]]; then
        init_config
        check_environment
        return $?
    fi

    # 4. Interactive mode delegation:
    # Explicit --interactive flag without a TTY fails early; with a TTY, it launches wizard.sh
    if [[ -n "${_arg_interactive:-}" ]]; then
        if [[ ! -t 0 || ! -t 1 ]]; then
            die "Interactive mode requires an interactive terminal (stdin and stdout must be a tty)."
        fi
        exec "${SCRIPT_DIR}/wizard.sh"
    fi

    # Running build.sh interactively with zero arguments delegates to the standalone wizard
    if [[ $# -eq 0 && -z "${_arg_non_interactive:-}" && -t 0 && -t 1 ]]; then
        exec "${SCRIPT_DIR}/wizard.sh"
    fi

    # 5. IMMEDIATE ROOT/SUDO CHECK — Required for loop device, partitioning, and pacstrap
    if [[ "${MOCK_EUID:-$EUID}" -ne 0 ]]; then
        if [[ -t 0 && -t 1 ]]; then
            log_warn "Root privileges are required to build disk images (mount, losetup, pacstrap)."
            log_info "Prompting for sudo password..."
            exec sudo -- "$0" "$@"
        else
            die "This script must be run as root (or via sudo)."
        fi
    fi

    # 6. Clean up any lingering resources from previous runs BEFORE setup begins
    cleanup_previous_run

    # 7. Initialize configuration (flags > env > defaults)
    init_config

    # 8. Preflight checks (tools, binfmt, qemu)
    preflight

    # 9. Validate configuration values (hostname, usernames, etc.)
    validate_config

    # 10. Check if previous run left output artifacts
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
                        if [[ -n "$ldev" ]]; then
                            losetup -d "$ldev" 2>/dev/null || true
                        fi
                    done < <(losetup -j "${IMG_FILE}" 2>/dev/null | cut -d: -f1)
                fi
                rm -f -- "${IMG_FILE}" "${IMG_FILE}.xz"
            else
                log_warn "Build cancelled by user (will not overwrite existing output)."
                exit 0
            fi
        else
            die "Output already exists: ${existing_target}. Remove it first or change --version."
        fi
    fi

    gum_banner

    local start_time
    start_time="$(date +%s)"

    # 10. Execute 5-phase build pipeline
    log_info "Initiating 5-phase build pipeline (with automatic cleanup of previous installation attempts)..."
    create_image
    bootstrap_rootfs
    configure_boot
    configure_system
    finalize_image

    local elapsed=$(($(date +%s) - start_time))
    log_info "Total build time: $((elapsed / 60))m $((elapsed % 60))s"

    echo ""
    "$GUM_BIN" style \
        --border rounded \
        --border-foreground 42 \
        --padding "1 2" \
        --bold \
        "🎉 Build Complete!" \
        "📦 Built image: ${FINAL_BUILT_FILE}"
    echo ""
}

main "$@"
