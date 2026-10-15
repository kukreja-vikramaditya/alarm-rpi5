#!/usr/bin/env bash
# shellcheck disable=SC2317  # cleanup is invoked via trap, not direct call
# src/cleanup.sh — Safe, idempotent resource cleanup on EXIT, INT, TERM

# Tracked resources that must be released upon exit
ROOTFS=""         # Set when mounting rootfs in /tmp/alarm-rootfs.XXXXXX
PACMAN_CONF=""    # Set when creating temporary pacman.conf
LOOP=""           # Set when attaching /dev/loopX
FINAL_BUILT_FILE="" # Set on successful completion

clean_stale_temp_files() {
    [[ $EUID -eq 0 ]] || return 0

    local item
    for item in /tmp/alarm-rootfs.*; do
        [[ -e "$item" ]] || continue
        if mountpoint -q "${item}/boot" 2>/dev/null; then
            umount -l "${item}/boot" 2>/dev/null || true
        fi
        if mountpoint -q "${item}" 2>/dev/null; then
            umount -l "${item}" 2>/dev/null || true
        fi
        rm -rf -- "$item" 2>/dev/null || true
    done

    for item in /tmp/pacman-aarch64.*.conf; do
        [[ -f "$item" ]] || continue
        rm -f -- "$item" 2>/dev/null || true
    done
}

cleanup() {
    local exit_code=$?
    set +e  # Don't fail during cleanup

    # 1. Unmount and remove rootfs temporary directory
    if [[ -n "${ROOTFS}" ]]; then
        if mountpoint -q "${ROOTFS}/boot" 2>/dev/null; then
            umount -l "${ROOTFS}/boot" 2>/dev/null
        fi
        if mountpoint -q "${ROOTFS}" 2>/dev/null; then
            umount -l "${ROOTFS}" 2>/dev/null
        fi
        if [[ -d "${ROOTFS}" ]]; then
            rm -rf -- "${ROOTFS}"
        fi
        ROOTFS=""
    fi

    # 2. Detach loopback device
    if [[ -n "${LOOP}" ]]; then
        losetup -d "${LOOP}" 2>/dev/null
        LOOP=""
    fi

    # 3. Remove temporary pacman configuration
    if [[ -n "${PACMAN_CONF}" && -f "${PACMAN_CONF}" ]]; then
        rm -f -- "${PACMAN_CONF}"
        PACMAN_CONF=""
    fi

    # 4. Clean any residual temporary files from /tmp
    if [[ $EUID -eq 0 && -z "${_arg_check:-}" ]]; then
        clean_stale_temp_files
    fi

    # 5. Report failure if exit code is non-zero
    if [[ $exit_code -ne 0 && -z "${_arg_check:-}" ]]; then
        if [[ -n "${IMG_FILE:-}" && -f "${IMG_FILE}" ]]; then
            log_error "Build failed (exit code ${exit_code}). Partial artifacts may remain at: ${IMG_FILE}"
        fi
    fi

    return "$exit_code"
}

trap cleanup EXIT INT TERM
