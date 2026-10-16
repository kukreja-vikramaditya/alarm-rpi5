#!/usr/bin/env bash
# shellcheck disable=SC2034 # Configuration variables are shared across sourced modules
# src/config.sh — Defaults and environment configuration

# External required commands for building and packaging
if [[ -z "${REQUIRED_CMDS+x}" ]]; then
    readonly REQUIRED_CMDS=(
        parted mkfs.vfat mkfs.ext4 losetup
        pacstrap arch-chroot truncate
        xz numfmt gum
    )
fi

# Baseline host environment to distinguish bash internal variables from explicit overrides
_HOST_HOSTNAME="${HOSTNAME:-}"
_ENV_HOSTNAME="$(printenv HOSTNAME 2>/dev/null || true)"

# File creation mask: standard permissions (0755 dirs, 0644 files)
umask 0022

# Defaults and standard POSIX / UNIX environment overrides
BUILD_DATE="$(date +%Y%m%d)"
BOOT_SIZE="${BOOT_SIZE:-${BOOT_SIZE_MIB:-256}}"
BOOT_SIZE="${BOOT_SIZE%[Mm]}"
BOOT_SIZE_MIB="${BOOT_SIZE}"

TZ="${TZ:-${TIMEZONE:-Asia/Kolkata}}"
TIMEZONE="${TZ}"

LANG="${LANG:-${LOCALE:-en_US.UTF-8}}"
LOCALE="${LANG}"

PACKAGES="${PACKAGES:-${EXTRA_PACKAGES:-git curl wget vim neovim tmux zsh}}"
EXTRA_PACKAGES="${PACKAGES}"

MIRROR="${MIRROR:-${ALARM_MIRROR:-http://mirror.archlinuxarm.org}}"
ALARM_MIRROR="${MIRROR}"

if [[ -z "${_CONFIG_INITIALIZED:-}" ]]; then
    CUSTOM_IMG_NAME="${IMG_NAME:-}"
    _CONFIG_INITIALIZED=1
fi
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

# Synchronize aliases after optional alarm.conf source
BOOT_SIZE="${BOOT_SIZE:-${BOOT_SIZE_MIB:-256}}"
BOOT_SIZE="${BOOT_SIZE%[Mm]}"
BOOT_SIZE_MIB="${BOOT_SIZE}"

TZ="${TZ:-${TIMEZONE:-Asia/Kolkata}}"
TIMEZONE="${TZ}"

LANG="${LANG:-${LOCALE:-en_US.UTF-8}}"
LOCALE="${LANG}"

PACKAGES="${PACKAGES:-${EXTRA_PACKAGES:-git curl wget vim neovim tmux zsh}}"
EXTRA_PACKAGES="${PACKAGES}"

MIRROR="${MIRROR:-${ALARM_MIRROR:-http://mirror.archlinuxarm.org}}"
ALARM_MIRROR="${MIRROR}"

init_config() {
    IMAGE_SIZE="${_arg_img_size:-${IMAGE_SIZE:-${IMG_SIZE:-3G}}}"
    IMG_SIZE="${IMAGE_SIZE}"

    local default_ver="1.1.0-snapshot"
    if [[ -n "${SCRIPT_DIR:-}" && -f "${SCRIPT_DIR}/VERSION" ]]; then
        default_ver="$(tr -d ' \r\n' <"${SCRIPT_DIR}/VERSION")"
    elif [[ -f "./VERSION" ]]; then
        default_ver="$(tr -d ' \r\n' <"./VERSION")"
    fi
    VERSION="${_arg_version:-${VERSION:-${default_ver}}}"

    # Target hostname resolution:
    # CLI flag (--hostname) > TARGET_HOSTNAME > HOSTNAME (if set in alarm.conf or exported env) > default "raspberrypi"
    local resolved_hostname=""
    if [[ -n "${TARGET_HOSTNAME:-}" ]]; then
        resolved_hostname="${TARGET_HOSTNAME}"
    elif [[ -n "${_ENV_HOSTNAME}" ]]; then
        resolved_hostname="${_ENV_HOSTNAME}"
    elif [[ -n "${HOSTNAME:-}" && "${HOSTNAME:-}" != "${_HOST_HOSTNAME}" ]]; then
        resolved_hostname="${HOSTNAME}"
    fi
    TARGET_HOSTNAME="${_arg_hostname:-${resolved_hostname:-raspberrypi}}"
    HOSTNAME="${TARGET_HOSTNAME}"

    ROOT_USER="${_arg_root_user:-${ROOT_USER:-root}}"
    ROOT_PASSWORD="${_arg_root_password:-${ROOT_PASSWORD:-root}}"

    # Non-root username resolution:
    # CLI flag (-u/--user/--username) > USERNAME > ALARM_USER > NON_ROOT_USER > USER_NAME > default "alarm"
    USERNAME="${_arg_user:-${USERNAME:-${ALARM_USER:-${NON_ROOT_USER:-${USER_NAME:-alarm}}}}}"
    USERNAME="$(echo "${USERNAME}" | tr '[:upper:]' '[:lower:]')"
    ALARM_USER="${USERNAME}"

    PASSWORD="${_arg_password:-${PASSWORD:-${ALARM_PASSWORD:-${NON_ROOT_PASSWORD:-${USER_PASSWORD:-alarm}}}}}"
    ALARM_PASSWORD="${PASSWORD}"

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
    # If ALARM_USER was explicitly modified, honor it; otherwise use USERNAME
    if [[ -n "${ALARM_USER:-}" && "${ALARM_USER}" != "${USERNAME:-}" ]]; then
        USERNAME="${ALARM_USER}"
    fi
    # Normalize non-root username to lowercase (standard Linux convention)
    USERNAME="$(echo "${USERNAME:-${ALARM_USER:-alarm}}" | tr '[:upper:]' '[:lower:]')"
    ALARM_USER="${USERNAME}"

    if [[ -z "${USERNAME}" ]]; then
        die "Non-root username cannot be empty."
    fi

    if [[ "${USERNAME}" == "root" ]]; then
        die "Non-root username cannot be 'root'. Root credentials must be configured via ROOT_USER and ROOT_PASSWORD."
    fi

    if [[ ! "${USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        die "Invalid non-root username '${USERNAME}'. Usernames must start with a letter or underscore, and contain only lowercase letters, digits, underscores, or hyphens."
    fi
}

recompute_image_paths() {
    IMG_NAME="${CUSTOM_IMG_NAME:-alarm-rpi5-${VERSION}-${BUILD_DATE}}"
    IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"
}
