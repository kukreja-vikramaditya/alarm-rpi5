#!/usr/bin/env bash
# src/build.sh — Core 5-phase Arch Linux ARM Raspberry Pi 5 build pipeline

ensure_loop_partitions() {
    local ldev="$1"
    local devname
    devname="$(basename "$ldev")"
    partprobe "${ldev}" 2>/dev/null || partx -u "${ldev}" 2>/dev/null || true
    udevadm settle --timeout=5 2>/dev/null || sleep 1
    local p
    for p in 1 2; do
        if [[ ! -b "${ldev}p${p}" ]]; then
            local sys_dev=""
            if [[ -f "/sys/class/block/${devname}p${p}/dev" ]]; then
                sys_dev="/sys/class/block/${devname}p${p}/dev"
            elif [[ -f "/sys/block/${devname}/${devname}p${p}/dev" ]]; then
                sys_dev="/sys/block/${devname}/${devname}p${p}/dev"
            fi
            if [[ -n "$sys_dev" && -f "$sys_dev" ]]; then
                local maj min
                IFS=: read -r maj min <"$sys_dev"
                mknod -m 660 "${ldev}p${p}" b "$maj" "$min" 2>/dev/null || true
            fi
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────
# Phase 1: Create disk image & partitions
# ──────────────────────────────────────────────────────────────────────
create_image() {
    log_phase "Phase 1/5 — Clean previous attempts & create disk image (${IMG_SIZE})"

    # Clean up lingering resources from any previous installation attempts
    cleanup_previous_run

    # Ensure /dev/loop-control and loop device nodes exist in minimal container environments
    if [[ ! -c /dev/loop-control ]]; then
        mknod -m 660 /dev/loop-control c 10 237 2>/dev/null || true
    fi
    local i
    for i in $(seq 0 15); do
        if [[ ! -b "/dev/loop${i}" ]]; then
            mknod -m 660 "/dev/loop${i}" b 7 "$i" 2>/dev/null || true
        fi
    done

    mkdir -p -- "${OUTPUT_DIR}"

    # Detach any loopback device already associated with this image file
    if command -v losetup &>/dev/null && [[ -f "${IMG_FILE}" ]]; then
        local ldev
        while read -r ldev; do
            if [[ -n "$ldev" ]]; then
                losetup -d "$ldev" 2>/dev/null || true
            fi
        done < <(losetup -j "${IMG_FILE}" 2>/dev/null | cut -d: -f1)
    fi

    # Allocate sparse file
    truncate -s "${IMG_SIZE}" "${IMG_FILE}"
    log_info "Sparse disk image allocated: ${IMG_FILE}"

    # Partition table: GPT
    #   p1: FAT32, ${BOOT_SIZE_MIB}MiB, bootable, type ESP/boot
    #   p2: ext4,   fills remainder
    local boot_end=$((BOOT_SIZE_MIB + 1)) # 1MiB alignment offset
    parted -s -- "${IMG_FILE}" \
        mklabel gpt \
        mkpart "boot" fat32 1MiB "${boot_end}MiB" \
        set 1 boot on \
        set 1 esp on \
        mkpart "root" ext4 "${boot_end}MiB" 100%

    # Attach loopback with partition scanning
    LOOP="$(losetup --find --show --partscan -- "${IMG_FILE}")"
    log_info "Loopback device: ${LOOP}"
    ensure_loop_partitions "${LOOP}"

    # Wait for partition device nodes to appear
    udevadm settle --timeout=5 2>/dev/null || sleep 1

    run_spin "Formatting boot partition (FAT32)" mkfs.vfat -F32 -n BOOT "${LOOP}p1"
    run_spin "Formatting root partition (ext4)" mkfs.ext4 -L ROOT -F -q "${LOOP}p2"

    log_info "Partitions created: ${BOOT_SIZE_MIB}MiB FAT32 boot + ext4 root"
}

# ──────────────────────────────────────────────────────────────────────
# Phase 2: Mount & pacstrap
# ──────────────────────────────────────────────────────────────────────
bootstrap_rootfs() {
    log_phase "Phase 2/5 — Bootstrap aarch64 rootfs"

    ROOTFS="$(mktemp -d -- /tmp/alarm-rootfs.XXXXXX)"

    mount -- "${LOOP}p2" "${ROOTFS}"
    mkdir -p -- "${ROOTFS}/boot"
    mount -- "${LOOP}p1" "${ROOTFS}/boot"

    # Inject qemu-aarch64-static so pacstrap can run aarch64 package scriptlets
    mkdir -p -- "${ROOTFS}/usr/bin"
    cp -- /usr/bin/qemu-aarch64-static "${ROOTFS}/usr/bin/"

    # Write pacman config for aarch64 / ALARM repos from data/ template
    PACMAN_CONF="$(mktemp -- /tmp/pacman-aarch64.XXXXXX.conf)"
    sed "s|@ALARM_MIRROR@|${ALARM_MIRROR}|g" "${DATA_DIR}/pacman-bootstrap.conf" >"${PACMAN_CONF}"

    # Base packages for a working RPi 5 system + conveniences
    local -a packages=(
        base
        linux-rpi
        firmware-raspberrypi
        raspberrypi-bootloader
        archlinuxarm-keyring
        openssh
        sudo
        nano
        e2fsprogs
        parted
        git
        tmux
        zsh
        curl
        wget
        unzip
    )

    # Append user-specified extra packages
    if [[ -n "${EXTRA_PACKAGES}" ]]; then
        local -a extras
        IFS=' ' read -ra extras <<<"${EXTRA_PACKAGES}"
        packages+=("${extras[@]}")
    fi

    log_info "Installing packages: ${packages[*]}"
    pacstrap -M -G -C "${PACMAN_CONF}" "${ROOTFS}" "${packages[@]}"

    # Clean up temporary pacstrap config immediately
    if [[ -n "${PACMAN_CONF}" && -f "${PACMAN_CONF}" ]]; then
        rm -f -- "${PACMAN_CONF}"
        PACMAN_CONF=""
        log_info "Cleaned up temporary pacstrap config"
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Phase 3: Configure boot
# ──────────────────────────────────────────────────────────────────────
configure_boot() {
    log_phase "Phase 3/5 — Configure boot"

    mkdir -p -- "${ROOTFS}/etc" "${ROOTFS}/boot"
    cp -- "${DATA_DIR}/fstab" "${ROOTFS}/etc/fstab"
    cp -- "${DATA_DIR}/cmdline.txt" "${ROOTFS}/boot/cmdline.txt"
    cp -- "${DATA_DIR}/config.txt" "${ROOTFS}/boot/config.txt"

    log_info "Boot config written (config.txt, cmdline.txt, fstab from data/)"
}

# ──────────────────────────────────────────────────────────────────────
# Phase 4: In-chroot configuration
# ──────────────────────────────────────────────────────────────────────
configure_system() {
    log_phase "Phase 4/5 — Configure system (chroot)"

    # Deploy system configuration files from data/ templates
    sed "s|@LOCALE@|${LOCALE}|g" "${DATA_DIR}/locale.gen" >"${ROOTFS}/etc/locale.gen"
    sed "s|@LOCALE@|${LOCALE}|g" "${DATA_DIR}/locale.conf" >"${ROOTFS}/etc/locale.conf"
    sed "s|@TARGET_HOSTNAME@|${TARGET_HOSTNAME}|g" "${DATA_DIR}/hosts" >"${ROOTFS}/etc/hosts"
    printf '%s\n' "${TARGET_HOSTNAME}" >"${ROOTFS}/etc/hostname"

    mkdir -p -- "${ROOTFS}/etc/sudoers.d"
    cp -- "${DATA_DIR}/sudoers-wheel" "${ROOTFS}/etc/sudoers.d/wheel"
    chmod 440 "${ROOTFS}/etc/sudoers.d/wheel"

    sed "s|@ALARM_MIRROR@|${ALARM_MIRROR}|g" "${DATA_DIR}/pacman-runtime.conf" >"${ROOTFS}/etc/pacman.conf"

    # Pre-configure native systemd-networkd for automatic wired DHCP on any ethernet interface
    mkdir -p -- "${ROOTFS}/etc/systemd/network"
    cp -- "${DATA_DIR}/20-wired.network" "${ROOTFS}/etc/systemd/network/20-wired.network"

    # Deploy first-boot automatic root expansion service
    mkdir -p -- "${ROOTFS}/usr/local/bin" "${ROOTFS}/etc/systemd/system"
    cp -- "${DATA_DIR}/alarm-expand-root.sh" "${ROOTFS}/usr/local/bin/alarm-expand-root.sh"
    chmod 755 "${ROOTFS}/usr/local/bin/alarm-expand-root.sh"
    cp -- "${DATA_DIR}/alarm-expand-root.service" "${ROOTFS}/etc/systemd/system/alarm-expand-root.service"
    chmod 644 "${ROOTFS}/etc/systemd/system/alarm-expand-root.service"

    # Deploy automated desktop environment (UI) installer script
    cp -- "${DATA_DIR}/install-ui.sh" "${ROOTFS}/usr/local/bin/install-ui"
    chmod 755 "${ROOTFS}/usr/local/bin/install-ui"
    ln -sf -- install-ui "${ROOTFS}/usr/local/bin/install-ui.sh"

    # Pre-configure Xorg OutputClass for Raspberry Pi 5 vc4 KMS driver
    mkdir -p -- "${ROOTFS}/etc/X11/xorg.conf.d"
    cp -- "${DATA_DIR}/99-vc4.conf" "${ROOTFS}/etc/X11/xorg.conf.d/99-vc4.conf"
    chmod 644 "${ROOTFS}/etc/X11/xorg.conf.d/99-vc4.conf"

    # Ensure system config files have standard read permissions
    chmod 644 "${ROOTFS}/etc/hostname" "${ROOTFS}/etc/hosts" "${ROOTFS}/etc/locale.conf" "${ROOTFS}/etc/locale.gen" "${ROOTFS}/etc/pacman.conf" "${ROOTFS}/etc/fstab" "${ROOTFS}/etc/systemd/network/20-wired.network"

    # Execute system setup inside chroot
    arch-chroot "${ROOTFS}" /bin/bash <<-CHROOT
	set -euo pipefail

	# Initialize machine-id
	systemd-machine-id-setup

	# Pacman keyring
	pacman-key --init
	pacman-key --populate archlinuxarm

	# Timezone & Locale
	ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
	locale-gen

	# Enable native systemd networking (zero external dependencies)
	systemctl enable systemd-networkd.service
	systemctl enable systemd-resolved.service

	# Enable first-boot root partition auto-expansion to 100% of disk
	systemctl enable alarm-expand-root.service

	# Enable SSH
	systemctl enable sshd.service

	# Root password
	printf '%s\n' "${ROOT_USER:-root}:${ROOT_PASSWORD}" | chpasswd

	# Ensure /home has standard 755 permissions and create non-root user
	chmod 755 /home
	useradd -m -G wheel -s /bin/bash "${ALARM_USER}"
	printf '%s\n' "${ALARM_USER}:${ALARM_PASSWORD}" | chpasswd
	chown -R "${ALARM_USER}:${ALARM_USER}" "/home/${ALARM_USER}"
	chmod 700 "/home/${ALARM_USER}"

	# Clean pacman cache to reduce image size
	pacman -Scc --noconfirm
CHROOT

    # Configure resolv.conf symlink for systemd-resolved (done outside chroot as arch-chroot bind-mounts host resolv.conf)
    rm -f -- "${ROOTFS}/etc/resolv.conf"
    ln -sf -- /run/systemd/resolve/stub-resolv.conf "${ROOTFS}/etc/resolv.conf"

    log_info "System configuration complete"
}

# ──────────────────────────────────────────────────────────────────────
# Phase 5: Finalize & package
# ──────────────────────────────────────────────────────────────────────
finalize_image() {
    log_phase "Phase 5/5 — Finalize image & clean up temporary installation files"

    # Remove qemu binary (not needed on real hardware)
    if [[ -n "${ROOTFS:-}" && -f "${ROOTFS}/usr/bin/qemu-aarch64-static" ]]; then
        rm -f -- "${ROOTFS}/usr/bin/qemu-aarch64-static"
    fi

    # Sync and unmount cleanly with fallback
    sync
    if mountpoint -q "${ROOTFS}/boot" 2>/dev/null; then
        umount -- "${ROOTFS}/boot" 2>/dev/null || umount -l "${ROOTFS}/boot" 2>/dev/null
    fi
    if mountpoint -q "${ROOTFS}" 2>/dev/null; then
        umount -- "${ROOTFS}" 2>/dev/null || umount -l "${ROOTFS}" 2>/dev/null
    fi
    if [[ -d "${ROOTFS}" ]]; then
        rm -rf -- "${ROOTFS}"
        log_info "Cleaned up temporary rootfs mount directory"
    fi
    ROOTFS=""

    if [[ -n "${LOOP}" ]]; then
        losetup -d "${LOOP}" 2>/dev/null || true
        LOOP=""
    fi

    local raw_size final_file
    raw_size="$(stat --format=%s -- "${IMG_FILE}")"
    log_info "Image size (raw): $(numfmt --to=iec-i --suffix=B -- "${raw_size}")"

    # ── Compress ─────────────────────────────────────────────────────
    if [[ "${COMPRESS}" -eq 1 ]]; then
        run_spin "Compressing image with xz (multi-threaded, level 9)" xz -9 -T0 -f -- "${IMG_FILE}"
        final_file="${IMG_FILE}.xz"
        local xz_size
        xz_size="$(stat --format=%s -- "${final_file}")"
        log_info "Compressed size:  $(numfmt --to=iec-i --suffix=B -- "${xz_size}")"
    else
        final_file="${IMG_FILE}"
    fi

    # shellcheck disable=SC2034 # Global variable read by build-alarm-rpi5.sh entrypoint
    FINAL_BUILT_FILE="${final_file}"

    # Ensure output files are accessible to host users
    chmod -R a+rX "${OUTPUT_DIR}" 2>/dev/null || true
    chmod 644 "${final_file}" 2>/dev/null || true

    # ── Verify temporary cleanup ─────────────────────────────────────
    clean_stale_temp_files
    log_info "All temporary build files and mounts in /tmp cleaned up"

    # ── Summary ──────────────────────────────────────────────────────
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '\n'
        "$GUM_BIN" style \
            --border double \
            --border-foreground 42 \
            --padding "1 2" \
            --bold \
            "✔ BUILD COMPLETE" \
            "" \
            "Image:       ${final_file}" \
            "Version:     ${VERSION}" \
            "Built:       $(date '+%Y-%m-%d %H:%M:%S %Z')" \
            "" \
            "Flash via Raspberry Pi Imager:" \
            "  1. Choose OS → Use custom → select ${final_file}" \
            "  2. Choose storage → Write" \
            "" \
            "Default credentials:" \
            "  root  / ${ROOT_PASSWORD}" \
            "  ${ALARM_USER} / ${ALARM_PASSWORD}" \
            "" \
            "First boot: connect Ethernet, SSH in, then:" \
            "  sudo pacman -Syu"
        printf '\n'
    else
        cat <<-SUMMARY

	═══════════════════════════════════════════════════════════════
	  BUILD COMPLETE
	═══════════════════════════════════════════════════════════════
	  Image:       ${final_file}
	  Version:     ${VERSION}
	  Built:       $(date '+%Y-%m-%d %H:%M:%S %Z')
	
	  Flash via Raspberry Pi Imager:
	    1. Choose OS → Use custom → select the image
	    2. Choose storage → Write
	
	  Default credentials:
	    root  / ${ROOT_PASSWORD}
	    ${ALARM_USER} / ${ALARM_PASSWORD}
	
	  First boot: connect Ethernet, SSH in, then:
	    sudo pacman -Syu
	═══════════════════════════════════════════════════════════════
	SUMMARY
    fi
}
