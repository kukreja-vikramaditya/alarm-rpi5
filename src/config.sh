#!/usr/bin/env bash
# shellcheck disable=SC2034 # Configuration variables are shared across sourced modules
# src/config.sh — Defaults and environment configuration

# External required commands for building and packaging
readonly REQUIRED_CMDS=(
    parted mkfs.vfat mkfs.ext4 losetup
    pacstrap arch-chroot truncate
    xz numfmt gum
)

# File creation mask: standard permissions (0755 dirs, 0644 files)
umask 0022

# Defaults
BUILD_DATE="$(date +%Y%m%d)"
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-256}"
TIMEZONE="${TIMEZONE:-Asia/Kolkata}"
LOCALE="${LOCALE:-en_US.UTF-8}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-git curl wget vim neovim tmux zsh}"
ALARM_MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"
CUSTOM_IMG_NAME="${IMG_NAME:-}"
if [[ -z "${DATA_DIR:-}" ]]; then
    DATA_DIR="${SCRIPT_DIR:-.}/data"
fi

# Optional configuration file override (alarm.conf)
if [[ -n "${SCRIPT_DIR:-}" && -f "${SCRIPT_DIR}/alarm.conf" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/alarm.conf"
elif [[ -f "./alarm.conf" ]]; then
    # shellcheck source=/dev/null
    source "./alarm.conf"
fi

init_config() {
    IMG_SIZE="${_arg_img_size:-${IMG_SIZE:-3G}}"
    local default_ver="1.1.0-snapshot"
    if [[ -n "${SCRIPT_DIR:-}" && -f "${SCRIPT_DIR}/VERSION" ]]; then
        default_ver="$(tr -d ' \r\n' <"${SCRIPT_DIR}/VERSION")"
    elif [[ -f "./VERSION" ]]; then
        default_ver="$(tr -d ' \r\n' <"./VERSION")"
    fi
    VERSION="${_arg_version:-${VERSION:-${default_ver}}}"
    TARGET_HOSTNAME="${_arg_hostname:-${TARGET_HOSTNAME:-raspberrypi}}"
    ROOT_USER="${_arg_root_user:-${ROOT_USER:-root}}"
    ROOT_PASSWORD="${_arg_root_password:-${ROOT_PASSWORD:-root}}"
    ALARM_USER="${_arg_user:-${NON_ROOT_USER:-${USER_NAME:-${ALARM_USER:-alarm}}}}"
    ALARM_USER="$(echo "${ALARM_USER}" | tr '[:upper:]' '[:lower:]')"
    ALARM_PASSWORD="${_arg_password:-${NON_ROOT_PASSWORD:-${USER_PASSWORD:-${ALARM_PASSWORD:-alarm}}}}"

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

validate_config() {
    # Normalize non-root username to lowercase (standard Linux convention)
    ALARM_USER="$(echo "${ALARM_USER:-alarm}" | tr '[:upper:]' '[:lower:]')"

    if [[ -z "${ALARM_USER}" ]]; then
        die "Non-root username cannot be empty."
    fi

    if [[ "${ALARM_USER}" == "root" ]]; then
        die "Non-root username cannot be 'root'. Root credentials must be configured via ROOT_USER and ROOT_PASSWORD."
    fi

    if [[ ! "${ALARM_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        die "Invalid non-root username '${ALARM_USER}'. Usernames must start with a letter or underscore, and contain only lowercase letters, digits, underscores, or hyphens."
    fi
}

recompute_image_paths() {
    IMG_NAME="${CUSTOM_IMG_NAME:-alarm-rpi5-${VERSION}-${BUILD_DATE}}"
    IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"
}
