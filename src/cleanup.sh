#!/usr/bin/env bash
# shellcheck disable=SC2317  # cleanup is invoked via trap, not direct call
# src/cleanup.sh — Safe, idempotent resource cleanup on EXIT, INT, TERM

# Tracked resources that must be released upon exit
ROOTFS=""         # Set when mounting rootfs in /tmp/alarm-rootfs.XXXXXX
PACMAN_CONF=""    # Set when creating temporary pacman.conf
LOOP=""           # Set when attaching /dev/loopX
FINAL_BUILT_FILE="" # Set on successful completion

cleanup() {
    local exit_code=$?
    set +e  # Don't fail during cleanup

    if [[ -n "${ROOTFS}" ]]; then
        if mountpoint -q "${ROOTFS}/boot" 2>/dev/null; then
            umount -l "${ROOTFS}/boot" 2>/dev/null
        fi
        if mountpoint -q "${ROOTFS}" 2>/dev/null; then
            umount -l "${ROOTFS}" 2>/dev/null
        fi
        rm -rf -- "${ROOTFS}"
        ROOTFS=""
    fi

    if [[ -n "${LOOP}" ]]; then
        losetup -d "${LOOP}" 2>/dev/null
        LOOP=""
    fi

    if [[ -n "${PACMAN_CONF}" && -f "${PACMAN_CONF}" ]]; then
        rm -f -- "${PACMAN_CONF}"
        PACMAN_CONF=""
    fi

    if [[ $exit_code -ne 0 && -z "${_arg_check:-}" ]]; then
        if [[ -n "${IMG_FILE:-}" && -f "${IMG_FILE}" ]]; then
            log_error "Build failed (exit code ${exit_code}). Partial artifacts may remain at: ${IMG_FILE}"
        fi
    fi

    return "$exit_code"
}

trap cleanup EXIT INT TERM
