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

    # Base packages for a working RPi 5 system
    local -a packages=(
        base
        linux-rpi
        firmware-raspberrypi
        raspberrypi-bootloader
        archlinuxarm-keyring
        openssh
        sudo
        nano
        networkmanager
        iwd
        e2fsprogs
        parted
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

    # Install first-boot auto-expand service
    mkdir -p -- "${ROOTFS}/usr/local/bin" "${ROOTFS}/etc/systemd/system"
    cp -- "${DATA_DIR}/alarm-growfs.sh" "${ROOTFS}/usr/local/bin/alarm-growfs"
    chmod 755 "${ROOTFS}/usr/local/bin/alarm-growfs"
    cp -- "${DATA_DIR}/alarm-growfs.service" "${ROOTFS}/etc/systemd/system/alarm-growfs.service"
    chmod 644 "${ROOTFS}/etc/systemd/system/alarm-growfs.service"

    # Ensure system config files have standard read permissions
    chmod 644 "${ROOTFS}/etc/hostname" "${ROOTFS}/etc/hosts" "${ROOTFS}/etc/locale.conf" "${ROOTFS}/etc/locale.gen" "${ROOTFS}/etc/pacman.conf" "${ROOTFS}/etc/fstab"

    # Execute system setup inside chroot
    arch-chroot "${ROOTFS}" /bin/bash <<-CHROOT
	set -euo pipefail

	# Pacman keyring
	pacman-key --init
	pacman-key --populate archlinuxarm

	# Timezone
	ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime

	# Locale
	locale-gen

	# Enable services
	systemctl enable sshd.service
	systemctl enable NetworkManager.service
	systemctl enable alarm-growfs.service

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

    # ── Shrink ext4 filesystem to minimum ────────────────────────────
    LOOP="$(losetup --find --show --partscan -- "${IMG_FILE}")"
    ensure_loop_partitions "${LOOP}"
    # shellcheck disable=SC2016 # Expression is intentional parameter for bash -c subshell
    run_spin "Checking filesystem integrity" bash -c 'e2fsck -f -y "$1" >/dev/null 2>&1 || true' _ "${LOOP}p2"
    # Reduce ext4 reserved block ratio to 1% so non-root users have immediate space
    tune2fs -m 1 "${LOOP}p2" >/dev/null 2>&1 || true
    # shellcheck disable=SC2016 # Expression is intentional parameter for bash -c subshell
    run_spin "Shrinking ext4 filesystem to minimum" bash -c 'resize2fs -M "$1" >/dev/null 2>&1' _ "${LOOP}p2"

    # Calculate new partition boundaries (+64MiB margin for non-root headroom)
    local block_count block_size fs_size_bytes part2_start part2_end truncate_size
    block_count="$(dumpe2fs -h "${LOOP}p2" 2>/dev/null | awk '/^Block count:/{print $3}')"
    block_size="$(dumpe2fs -h "${LOOP}p2" 2>/dev/null | awk '/^Block size:/{print $3}')"
    fs_size_bytes=$((block_count * block_size + 64 * 1024 * 1024)) # +64MiB margin
    part2_start="$(parted -s -- "${IMG_FILE}" unit B print | awk '/^ 2/{print $2}' | tr -d 'B')"
    part2_end=$((part2_start + fs_size_bytes))

    losetup -d "${LOOP}"
    LOOP=""

    # Truncate image to shrunk size + 1MiB alignment padding
    truncate_size=$((part2_end + 1024 * 1024))
    truncate -s "${truncate_size}" -- "${IMG_FILE}"

    # Fix partition table to match truncated image
    parted -s -- "${IMG_FILE}" resizepart 2 "${part2_end}B" 2>/dev/null || true

    # Re-attach with partition scan to verify integrity and expand filesystem to boundary
    LOOP="$(losetup --find --show --partscan -- "${IMG_FILE}")"
    ensure_loop_partitions "${LOOP}"
    udevadm settle --timeout=5 2>/dev/null || sleep 1
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
