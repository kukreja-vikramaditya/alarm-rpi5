#!/usr/bin/env bash
# src/build.sh — Core 5-phase Arch Linux ARM Raspberry Pi 5 build pipeline

# ──────────────────────────────────────────────────────────────────────
# Phase 1: Create disk image & partitions
# ──────────────────────────────────────────────────────────────────────
create_image() {
    log_phase "Phase 1/5 — Create disk image (${IMG_SIZE})"

    # Allocate sparse file
    truncate -s "${IMG_SIZE}" "${IMG_FILE}"
    log_info "Sparse disk image allocated: ${IMG_FILE}"

    # Partition table: GPT
    #   p1: FAT32, ${BOOT_SIZE_MIB}MiB, bootable, type ESP/boot
    #   p2: ext4,   fills remainder
    local boot_end=$(( BOOT_SIZE_MIB + 1 ))  # 1MiB alignment offset
    parted -s -- "${IMG_FILE}" \
        mklabel gpt \
        mkpart "boot" fat32 1MiB "${boot_end}MiB" \
        set 1 boot on \
        set 1 esp on \
        mkpart "root" ext4 "${boot_end}MiB" 100%

    # Attach loopback with partition scanning
    LOOP="$(losetup --find --show --partscan -- "${IMG_FILE}")"
    log_info "Loopback device: ${LOOP}"

    # Wait for partition device nodes to appear
    udevadm settle --timeout=5 2>/dev/null || sleep 2

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

    # Write pacman config for aarch64 / ALARM repos
    PACMAN_CONF="$(mktemp -- /tmp/pacman-aarch64.XXXXXX.conf)"
    cat > "${PACMAN_CONF}" <<-EOF
	[options]
	HoldPkg     = pacman glibc
	Architecture = aarch64
	CheckSpace
	SigLevel    = Never

	[core]
	Server = ${ALARM_MIRROR}/\$arch/\$repo

	[extra]
	Server = ${ALARM_MIRROR}/\$arch/\$repo

	[alarm]
	Server = ${ALARM_MIRROR}/\$arch/\$repo

	[aur]
	Server = ${ALARM_MIRROR}/\$arch/\$repo
	EOF

    # Base packages for a working RPi 5 system
    local -a packages=(
        base
        linux-rpi
        raspberrypi-firmware
        archlinuxarm-keyring
        openssh
        sudo
        nano
        networkmanager
        iwd
    )

    # Append user-specified extra packages
    if [[ -n "${EXTRA_PACKAGES}" ]]; then
        local -a extras
        IFS=' ' read -ra extras <<< "${EXTRA_PACKAGES}"
        packages+=("${extras[@]}")
    fi

    log_info "Installing packages: ${packages[*]}"
    pacstrap -M -G -C "${PACMAN_CONF}" "${ROOTFS}" "${packages[@]}"
}

# ──────────────────────────────────────────────────────────────────────
# Phase 3: Configure boot
# ──────────────────────────────────────────────────────────────────────
configure_boot() {
    log_phase "Phase 3/5 — Configure boot"

    # fstab
    cat > "${ROOTFS}/etc/fstab" <<-'EOF'
	# <device>             <dir>    <type>  <options>          <dump> <pass>
	/dev/mmcblk0p1         /boot    vfat    defaults           0      2
	/dev/mmcblk0p2         /        ext4    defaults,noatime   0      1
	EOF

    # Kernel command line
    printf '%s\n' "root=/dev/mmcblk0p2 rw rootwait console=tty1 console=ttyAMA10,115200" \
        > "${ROOTFS}/boot/cmdline.txt"

    # Pi 5 config.txt
    cat > "${ROOTFS}/boot/config.txt" <<-'EOF'
	# Arch Linux ARM — Raspberry Pi 5
	# This file is read by the Pi firmware before the kernel boots.

	arm_64bit=1
	enable_uart=1

	# KMS video driver (standard for Pi 4/5)
	dtoverlay=vc4-kms-v3d

	# Uncomment to overclock (requires adequate cooling)
	#arm_freq=2800
	#over_voltage=6

	# Uncomment for USB boot (NVMe via M.2 HAT)
	#BOOT_ORDER=0xf416
	EOF

    log_info "Boot config written (config.txt, cmdline.txt, fstab)"
}

# ──────────────────────────────────────────────────────────────────────
# Phase 4: In-chroot configuration
# ──────────────────────────────────────────────────────────────────────
configure_system() {
    log_phase "Phase 4/5 — Configure system (chroot)"

    arch-chroot "${ROOTFS}" /bin/bash <<-CHROOT
	set -euo pipefail

	# Pacman keyring
	pacman-key --init
	pacman-key --populate archlinuxarm

	# Timezone
	ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime

	# Locale
	printf '%s\n' "${LOCALE} UTF-8" > /etc/locale.gen
	locale-gen
	printf '%s\n' "LANG=${LOCALE}" > /etc/locale.conf

	# Hostname
	printf '%s\n' "${TARGET_HOSTNAME}" > /etc/hostname
	cat > /etc/hosts <<-HOSTS
	127.0.0.1   localhost
	::1         localhost
	127.0.1.1   ${TARGET_HOSTNAME}
	HOSTS

	# Enable services
	systemctl enable sshd.service
	systemctl enable NetworkManager.service

	# Root password
	printf '%s\n' "root:${ROOT_PASSWORD}" | chpasswd

	# Create user
	useradd -m -G wheel -s /bin/bash "${ALARM_USER}"
	printf '%s\n' "${ALARM_USER}:${ALARM_PASSWORD}" | chpasswd
	printf '%s\n' "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel

	# Write runtime pacman.conf (with signature verification)
	cat > /etc/pacman.conf <<-'PACCONF'
	[options]
	HoldPkg     = pacman glibc
	Architecture = aarch64
	CheckSpace
	SigLevel    = Required DatabaseOptional
	LocalFileSigLevel = Optional

	[core]
	Server = http://mirror.archlinuxarm.org/\$arch/\$repo

	[extra]
	Server = http://mirror.archlinuxarm.org/\$arch/\$repo

	[alarm]
	Server = http://mirror.archlinuxarm.org/\$arch/\$repo

	[aur]
	Server = http://mirror.archlinuxarm.org/\$arch/\$repo
	PACCONF

	# Clean pacman cache to reduce image size
	pacman -Scc --noconfirm
	CHROOT

    log_info "System configuration complete"
}

# ──────────────────────────────────────────────────────────────────────
# Phase 5: Finalize & package
# ──────────────────────────────────────────────────────────────────────
finalize_image() {
    log_phase "Phase 5/5 — Finalize image"

    # Remove qemu binary (not needed on real hardware)
    rm -f -- "${ROOTFS}/usr/bin/qemu-aarch64-static"

    # Sync and unmount
    sync
    umount -- "${ROOTFS}/boot"
    umount -- "${ROOTFS}"
    rm -rf -- "${ROOTFS}"
    ROOTFS=""

    losetup -d "${LOOP}"
    LOOP=""

    # ── Shrink ext4 filesystem to minimum ────────────────────────────
    LOOP="$(losetup --find --show --partscan -- "${IMG_FILE}")"
    run_spin "Checking filesystem integrity" bash -c 'e2fsck -f -y "$1" >/dev/null 2>&1 || true' _ "${LOOP}p2"
    run_spin "Shrinking ext4 filesystem to minimum" bash -c 'resize2fs -M "$1" >/dev/null 2>&1' _ "${LOOP}p2"

    # Calculate new partition boundaries
    local block_count block_size fs_size_bytes part2_start part2_end truncate_size
    block_count="$(dumpe2fs -h "${LOOP}p2" 2>/dev/null | awk '/^Block count:/{print $3}')"
    block_size="$(dumpe2fs -h "${LOOP}p2" 2>/dev/null | awk '/^Block size:/{print $3}')"
    fs_size_bytes=$(( block_count * block_size + 16 * 1024 * 1024 ))  # +16MiB margin
    part2_start="$(parted -s -- "${IMG_FILE}" unit B print | awk '/^ 2/{print $2}' | tr -d 'B')"
    part2_end=$(( part2_start + fs_size_bytes ))

    losetup -d "${LOOP}"
    LOOP=""

    # Truncate image to shrunk size + 1MiB alignment padding
    truncate_size=$(( part2_end + 1024 * 1024 ))
    truncate -s "${truncate_size}" -- "${IMG_FILE}"

    # Re-attach and fix partition table to match truncated image
    LOOP="$(losetup --find --show --partscan -- "${IMG_FILE}")"
    parted -s -- "${IMG_FILE}" resizepart 2 "${part2_end}B" 2>/dev/null || true
    e2fsck -f -y "${LOOP}p2" >/dev/null 2>&1 || true
    resize2fs "${LOOP}p2" >/dev/null 2>&1 || true
    losetup -d "${LOOP}"
    LOOP=""

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

    FINAL_BUILT_FILE="${final_file}"

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
