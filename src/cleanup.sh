#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2034  # cleanup is invoked via trap; resources are shared across modules
# src/cleanup.sh — Safe, idempotent resource cleanup before setup and on EXIT/INT/TERM

# Tracked resources that must be released upon exit
ROOTFS=""           # Set when mounting rootfs in /tmp/alarm-rootfs.XXXXXX
PACMAN_CONF=""      # Set when creating temporary pacman.conf
LOOP=""             # Set when attaching /dev/loopX
FINAL_BUILT_FILE="" # Set on successful completion

# ──────────────────────────────────────────────────────────────────────
# Clean up lingering resources from any previous interrupted runs
# ──────────────────────────────────────────────────────────────────────
cleanup_previous_run() {
    # 1. Unmount any stale mounts inside /tmp/alarm-rootfs* (root only, unmount nested /boot first)
    if [[ $EUID -eq 0 && -f /proc/mounts ]] && grep -q "/tmp/alarm-rootfs" /proc/mounts 2>/dev/null; then
        local mp
        while read -r mp; do
            [[ -n "$mp" ]] || continue
            umount -l "$mp" 2>/dev/null || true
        done < <(grep "/tmp/alarm-rootfs" /proc/mounts 2>/dev/null | awk '{print $2}' | sort -r)
    fi

    # 2. Detach any lingering loopback devices associated with alarm-rpi5 or alarm-rootfs (root only)
    if [[ $EUID -eq 0 ]] && command -v losetup &>/dev/null; then
        local ldev
        while read -r ldev; do
            [[ -n "$ldev" ]] || continue
            losetup -d "$ldev" 2>/dev/null || true
        done < <(losetup -a 2>/dev/null | grep -E "alarm-rpi5|alarm-rootfs" | cut -d: -f1)
    fi

    # 3. Clean any stale temporary directories in /tmp
    local item
    for item in /tmp/alarm-rootfs.*; do
        [[ -e "$item" ]] || continue
        if [[ $EUID -eq 0 ]] && mountpoint -q "${item}/boot" 2>/dev/null; then
            umount -l "${item}/boot" 2>/dev/null || true
        fi
        if [[ $EUID -eq 0 ]] && mountpoint -q "${item}" 2>/dev/null; then
            umount -l "${item}" 2>/dev/null || true
        fi
        rm -rf -- "$item" 2>/dev/null || true
    done

    # 4. Clean any stale pacman configurations in /tmp
    for item in /tmp/pacman-aarch64.*.conf; do
        [[ -f "$item" ]] || continue
        rm -f -- "$item" 2>/dev/null || true
    done
}

# Alias for backwards compatibility with any direct callers
clean_stale_temp_files() {
    cleanup_previous_run
}

# ──────────────────────────────────────────────────────────────────────
# Trap exit handler
# ──────────────────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    set +e # Don't fail during cleanup

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
        cleanup_previous_run
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
