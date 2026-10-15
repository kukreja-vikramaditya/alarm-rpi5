#!/usr/bin/env bash
# shellcheck disable=SC2034 # Configuration variables are shared across sourced modules
# src/config.sh — Defaults and environment configuration

# External required commands for building and packaging
readonly REQUIRED_CMDS=(
    parted mkfs.vfat mkfs.ext4 losetup
    pacstrap arch-chroot
    truncate e2fsck resize2fs dumpe2fs
    xz numfmt
)

# File creation mask: owner-only
umask 0077

# Defaults
BUILD_DATE="$(date +%Y%m%d)"
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-256}"
TIMEZONE="${TIMEZONE:-UTC}"
LOCALE="${LOCALE:-en_US.UTF-8}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"
ALARM_MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"
CUSTOM_IMG_NAME="${IMG_NAME:-}"
if [[ -z "${DATA_DIR:-}" ]]; then
    DATA_DIR="${SCRIPT_DIR:-.}/data"
fi

init_config() {
    IMG_SIZE="${_arg_img_size:-${IMG_SIZE:-4G}}"
    VERSION="${_arg_version:-${VERSION:-0.1.0}}"
    TARGET_HOSTNAME="${_arg_hostname:-${TARGET_HOSTNAME:-raspberrypi}}"
    ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
    ALARM_USER="${ALARM_USER:-alarm}"
    ALARM_PASSWORD="${ALARM_PASSWORD:-alarm}"

    local _output_dir="${_arg_output_dir:-${SCRIPT_DIR:-.}/dist}"
    _output_dir="$(mkdir -p -- "$_output_dir" && cd -- "$_output_dir" && pwd)"
    OUTPUT_DIR="$_output_dir"

    if [[ -n "${_arg_no_compress:-}" ]]; then
        COMPRESS=0
    else
        COMPRESS="${COMPRESS:-1}"
    fi

    recompute_image_paths
}

recompute_image_paths() {
    IMG_NAME="${CUSTOM_IMG_NAME:-alarm-rpi5-${VERSION}-${BUILD_DATE}}"
    IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"
}
