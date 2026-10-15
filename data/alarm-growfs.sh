#!/usr/bin/env bash
# data/alarm-growfs.sh — Expand root partition and filesystem on first boot
set -euo pipefail

# Determine root filesystem device
root_part="$(findmnt -n -o SOURCE / || true)"
if [[ -z "${root_part}" ]]; then
    exit 0
fi

# Determine disk device and partition number
disk=""
part_num=""

if [[ "${root_part}" =~ ^(/dev/mmcblk[0-9]+|/dev/nvme[0-9]+n[0-9]+)p([0-9]+)$ ]]; then
    disk="${BASH_REMATCH[1]}"
    part_num="${BASH_REMATCH[2]}"
elif [[ "${root_part}" =~ ^(/dev/[a-z]+)([0-9]+)$ ]]; then
    disk="${BASH_REMATCH[1]}"
    part_num="${BASH_REMATCH[2]}"
else
    exit 0
fi

if [[ -z "${disk}" || -z "${part_num}" ]]; then
    exit 0
fi

# Expand partition to fill disk
if command -v parted &>/dev/null; then
    parted -s "${disk}" resizepart "${part_num}" 100% || true
elif command -v sfdisk &>/dev/null; then
    printf ',+\n' | sfdisk -N "${part_num}" --no-reread "${disk}" || true
fi

# Notify kernel of partition table change
partprobe "${disk}" 2>/dev/null || true
udevadm settle --timeout=5 2>/dev/null || sleep 1

# Online filesystem expansion
if command -v resize2fs &>/dev/null; then
    resize2fs "${root_part}" || true
fi

# Self-disable service after first boot completion
systemctl disable alarm-growfs.service 2>/dev/null || true
