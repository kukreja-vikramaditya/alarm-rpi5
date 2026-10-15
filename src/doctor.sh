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
        "$GUM_BIN" log -l info "Root execution"
    elif sudo -n true 2>/dev/null; then
        "$GUM_BIN" log -l info "Root execution (passwordless sudo active)"
    else
        "$GUM_BIN" log -l warn "Root execution (requires sudo password when building)"
    fi

    # 2. Host Commands
    local cmd
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            "$GUM_BIN" log -l info "Tool: ${cmd} ($(command -v "$cmd"))"
        else
            "$GUM_BIN" log -l error "Tool: ${cmd} -> install with: $(get_pkg_for_cmd "$cmd")"
            ((issues++)) || true
        fi
    done

    # 3. Kernel binfmt_misc
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    if [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 || -f /proc/sys/fs/binfmt_misc/aarch64 || -f /proc/sys/fs/binfmt_misc/arm64 ]]; then
        "$GUM_BIN" log -l info "binfmt: aarch64"
    else
        "$GUM_BIN" log -l error "binfmt: aarch64 -> enable with: sudo systemctl restart systemd-binfmt.service"
        ((issues++)) || true
    fi

    # 4. QEMU static binary
    if [[ -x /usr/bin/qemu-aarch64-static ]]; then
        "$GUM_BIN" log -l info "Binary: qemu-aarch64-static"
    else
        "$GUM_BIN" log -l error "Binary: qemu-aarch64-static -> install with: sudo pacman -S qemu-user-static qemu-user-static-binfmt"
        ((issues++)) || true
    fi

    # 5. Mirror connectivity
    local mirror_url="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"
    if curl --head --silent --fail --connect-timeout 5 "${mirror_url}" &>/dev/null; then
        "$GUM_BIN" log -l info "ALARM mirror reachable (${mirror_url})"
    else
        "$GUM_BIN" log -l warn "ALARM mirror reachable (cannot connect to ${mirror_url})"
    fi

    # 6. Output directory writable
    local out_dir="${OUTPUT_DIR:-${SCRIPT_DIR:-.}/dist}"
    mkdir -p -- "$out_dir" 2>/dev/null || true
    if [[ -w "$out_dir" ]]; then
        "$GUM_BIN" log -l info "Output dir writable (${out_dir})"
    else
        "$GUM_BIN" log -l error "Output dir writable (${out_dir} is not writable)"
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
