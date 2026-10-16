#!/usr/bin/env bash
# Created for Arch Linux ARM Raspberry Pi 5 Image Builder
# Project: https://github.com/kukreja-vikramaditya/alarm-rpi5
#
# /usr/local/bin/alarm-expand-root.sh — Expand root partition and ext4 filesystem to 100% of disk
set -euo pipefail

ROOT_DEV="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
[[ -n "$ROOT_DEV" ]] || exit 0

ROOT_DISK="$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null || true)"
PART_NUM="$(lsblk -no PARTN "$ROOT_DEV" 2>/dev/null || true)"

if [[ -n "$ROOT_DISK" && -n "$PART_NUM" ]]; then
    # Fix backup GPT header to recognize all available disk space
    printf 'Fix\n' | parted ---pretend-input-tty "/dev/${ROOT_DISK}" print &>/dev/null || true

    # Expand partition to 100% of the drive
    parted -s "/dev/${ROOT_DISK}" resizepart "$PART_NUM" 100% &>/dev/null || true

    # Tell kernel about partition table changes
    partprobe "/dev/${ROOT_DISK}" 2>/dev/null || true

    # Resize ext4 filesystem online
    resize2fs "$ROOT_DEV" &>/dev/null || true
fi

touch /etc/alarm-root-expanded
