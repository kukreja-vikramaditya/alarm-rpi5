#!/usr/bin/env bash
# src/doctor.sh — Diagnostics (--check) and preflight requirement verification

get_pkg_for_cmd() {
    case "$1" in
        parted) echo "sudo pacman -S parted" ;;
        mkfs.vfat) echo "sudo pacman -S dosfstools" ;;
        pacstrap | arch-chroot) echo "sudo pacman -S arch-install-scripts" ;;
        mkfs.ext4 | e2fsck | resize2fs | dumpe2fs | tune2fs) echo "sudo pacman -S e2fsprogs" ;;
        losetup) echo "sudo pacman -S util-linux" ;;
        xz) echo "sudo pacman -S xz" ;;
        truncate | numfmt) echo "sudo pacman -S coreutils" ;;
        *) echo "pacman -S package providing $1" ;;
    esac
}

check_environment() {
    log_phase "Host Environment Diagnostics"
    local issues=0

    # 1. Root / Privileges
    if [[ $EUID -eq 0 ]]; then
        printf '  %-32s %s\n' "Root execution" "$(format_badge OK)"
    elif sudo -n true 2>/dev/null; then
        printf '  %-32s %s (passwordless sudo active)\n' "Root execution" "$(format_badge OK)"
    else
        printf '  %-32s %s (requires sudo password when building)\n' "Root execution" "$(format_badge INFO)"
    fi

    # 2. Host Commands
    local cmd
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            printf '  %-32s %s (%s)\n' "Tool: ${cmd}" "$(format_badge OK)" "$(command -v "$cmd")"
        else
            printf '  %-32s %s -> install with: %s\n' "Tool: ${cmd}" "$(format_badge MISSING)" "$(get_pkg_for_cmd "$cmd")"
            ((issues++)) || true
        fi
    done

    # 3. Kernel binfmt_misc
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    if [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 || -f /proc/sys/fs/binfmt_misc/aarch64 || -f /proc/sys/fs/binfmt_misc/arm64 ]]; then
        printf '  %-32s %s\n' "binfmt: aarch64" "$(format_badge OK)"
    else
        printf '  %-32s %s -> enable with: sudo systemctl restart systemd-binfmt.service\n' \
            "binfmt: aarch64" "$(format_badge MISSING)"
        ((issues++)) || true
    fi

    # 4. QEMU static binary
    if [[ -x /usr/bin/qemu-aarch64-static ]]; then
        printf '  %-32s %s\n' "Binary: qemu-aarch64-static" "$(format_badge OK)"
    else
        printf '  %-32s %s -> install with: sudo pacman -S qemu-user-static qemu-user-static-binfmt\n' \
            "Binary: qemu-aarch64-static" "$(format_badge MISSING)"
        ((issues++)) || true
    fi

    # 5. Mirror connectivity
    local mirror_url="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"
    if curl --head --silent --fail --connect-timeout 5 "${mirror_url}" &>/dev/null; then
        printf '  %-32s %s (%s)\n' "ALARM mirror reachable" "$(format_badge OK)" "${mirror_url}"
    else
        printf '  %-32s %s (cannot connect to %s)\n' "ALARM mirror reachable" "$(format_badge WARN)" "${mirror_url}"
    fi

    # 6. Output directory writable
    local out_dir="${OUTPUT_DIR:-${SCRIPT_DIR:-.}/dist}"
    mkdir -p -- "$out_dir" 2>/dev/null || true
    if [[ -w "$out_dir" ]]; then
        printf '  %-32s %s (%s)\n' "Output dir writable" "$(format_badge OK)" "$out_dir"
    else
        printf '  %-32s %s (%s is not writable)\n' "Output dir writable" "$(format_badge MISSING)" "$out_dir"
        ((issues++)) || true
    fi

    echo ""
    if [[ $issues -eq 0 ]]; then
        "$GUM_BIN" style --foreground 42 --bold "✔ All prerequisites satisfied! Ready to build."
        return 0
    else
        "$GUM_BIN" style --foreground 214 --bold "⚠ ${issues} prerequisite(s) missing. Install missing packages before running the build."
        return 1
    fi
}

preflight() {
    log_phase "Preflight checks"

    # Enforce root
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (or via sudo)."
    fi

    # Clean any stale debris from past interrupted runs
    clean_stale_temp_files

    # Enforce host commands
    local -a missing=()
    local cmd
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required host commands: ${missing[*]}
Install them with:
  sudo pacman -S arch-install-scripts dosfstools e2fsprogs parted xz util-linux coreutils"
    fi

    # Enforce binfmt
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 && ! -f /proc/sys/fs/binfmt_misc/aarch64 && ! -f /proc/sys/fs/binfmt_misc/arm64 ]]; then
        die "binfmt_misc registration for aarch64 is missing.
Install and start it:
  sudo pacman -S qemu-user-static qemu-user-static-binfmt
  sudo systemctl restart systemd-binfmt.service"
    fi

    # Enforce qemu-aarch64-static binary
    if [[ ! -x /usr/bin/qemu-aarch64-static ]]; then
        die "qemu-aarch64-static binary not found at /usr/bin/qemu-aarch64-static.
Install it:
  sudo pacman -S qemu-user-static"
    fi

    log_info "Preflight checks passed (root, binfmt, tools, qemu)"
}
