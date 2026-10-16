#!/usr/bin/env bash
# wizard.sh — Standalone Interactive Charm Gum TUI Command Builder
#
# Prompts for build configurations using Charm Gum and constructs the exact
# ./build.sh command to execute. Keeps interactive UI completely separate from
# core build logic.

set -euo pipefail

SCRIPT_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "${SCRIPT_PATH}")"
readonly SCRIPT_PATH
readonly SCRIPT_DIR

GUM_BIN="$(command -v gum 2>/dev/null || echo "gum")"
readonly GUM_BIN

FORCE_BASH=0
DRY_RUN=0

usage() {
    cat <<USAGE
Usage: ./wizard.sh [OPTIONS]

Interactive Charm Gum TUI wizard for Arch Linux ARM Raspberry Pi 5.
Prompts for configuration and generates the executable ./build.sh command.

Options:
  --bash       Force pure Bash fallback mode (no gum)
  --dry-run    Print generated command without executing
  -h, --help   Show this help message
USAGE
}

# Parse wizard flags
for arg in "$@"; do
    case "$arg" in
        --bash)
            FORCE_BASH=1
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "==> Error: Unknown option '$arg'" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Non-TTY guard: wizard requires an interactive terminal unless --bash mode is requested
if [[ "${FORCE_BASH}" -eq 0 && (! -t 0 || ! -t 1) ]]; then
    echo "==> Error: Interactive wizard requires an interactive terminal (stdin and stdout must be a tty)." >&2
    echo "    To run a build non-interactively, use: ./build.sh -y" >&2
    exit 1
fi

# Load initial configuration defaults from VERSION and alarm.conf
VERSION=""
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
    VERSION="$(tr -d '[:space:]' <"${SCRIPT_DIR}/VERSION")"
fi
VERSION="${VERSION:-1.1.0-snapshot}"
TARGET_HOSTNAME="raspberrypi"
ROOT_USER="root"
ROOT_PASSWORD="root"
ALARM_USER="alarm"
ALARM_PASSWORD="alarm"
IMG_SIZE="3G"
COMPRESS=1
OUTPUT_DIR="${SCRIPT_DIR}/dist"

if [[ -f "${SCRIPT_DIR}/alarm.conf" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/alarm.conf"
    VERSION="${VERSION:-1.1.0-snapshot}"
    TARGET_HOSTNAME="${TARGET_HOSTNAME:-raspberrypi}"
    ROOT_USER="${ROOT_USER:-root}"
    ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
    ALARM_USER="${ALARM_USER:-alarm}"
    ALARM_PASSWORD="${ALARM_PASSWORD:-alarm}"
    IMG_SIZE="${IMG_SIZE:-3G}"
    COMPRESS="${COMPRESS:-1}"
    OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/dist}"
fi

wizard_gum() {
    "$GUM_BIN" style \
        --border rounded \
        --border-foreground 212 \
        --padding "1 2" \
        --bold \
        "🍓 Arch Linux ARM for Raspberry Pi 5" \
        "🧙 Interactive Command Generator"
    echo ""

    VERSION="$("$GUM_BIN" input --header "📦 Image Version" --value "${VERSION}")"
    VERSION="${VERSION:-1.1.0-snapshot}"
    "$GUM_BIN" style --foreground 212 "  ✓ Image Version:     ${VERSION}"

    TARGET_HOSTNAME="$("$GUM_BIN" input --header "🏷️  Target Hostname" --value "${TARGET_HOSTNAME}")"
    TARGET_HOSTNAME="${TARGET_HOSTNAME:-raspberrypi}"
    "$GUM_BIN" style --foreground 212 "  ✓ Target Hostname:   ${TARGET_HOSTNAME}"

    # 1. Root Credentials
    ROOT_USER="$("$GUM_BIN" input --header "👑 Root Username" --value "${ROOT_USER}")"
    ROOT_USER="${ROOT_USER:-root}"
    "$GUM_BIN" style --foreground 212 "  ✓ Root Username:     ${ROOT_USER}"

    local new_root
    new_root="$("$GUM_BIN" input --password --header "🔑 Root Password (leave empty for default: ${ROOT_PASSWORD})")"
    [[ -n "$new_root" ]] && ROOT_PASSWORD="$new_root"
    "$GUM_BIN" style --foreground 212 "  ✓ Root Password:     ********"

    # 2. Non-Root Credentials
    ALARM_USER="$("$GUM_BIN" input --header "👤 Non-Root Username" --value "${ALARM_USER}")"
    ALARM_USER="${ALARM_USER:-alarm}"
    ALARM_USER="$(echo "${ALARM_USER}" | tr '[:upper:]' '[:lower:]')"
    while [[ ! "${ALARM_USER}" =~ ^[a-z_][a-z0-9_-]*$ || "${ALARM_USER}" == "root" ]]; do
        "$GUM_BIN" log -l error "Invalid username '${ALARM_USER}'. Must start with a letter/underscore and contain only lowercase letters, digits, underscores, or hyphens (cannot be 'root')."
        ALARM_USER="$("$GUM_BIN" input --header "👤 Non-Root Username" --value "alarm")"
        ALARM_USER="${ALARM_USER:-alarm}"
        ALARM_USER="$(echo "${ALARM_USER}" | tr '[:upper:]' '[:lower:]')"
    done
    "$GUM_BIN" style --foreground 212 "  ✓ Non-Root Username: ${ALARM_USER}"

    local new_user
    new_user="$("$GUM_BIN" input --password --header "🔒 ${ALARM_USER} Password (leave empty for default: ${ALARM_PASSWORD})")"
    [[ -n "$new_user" ]] && ALARM_PASSWORD="$new_user"
    "$GUM_BIN" style --foreground 212 "  ✓ User Password:     ********"

    IMG_SIZE="$("$GUM_BIN" choose --header "💾 Raw disk size (3G fits on any SD card >=4GB):" "3G" "4G" "8G" "16G" "32G")"
    IMG_SIZE="${IMG_SIZE:-3G}"
    "$GUM_BIN" style --foreground 212 "  ✓ Raw Disk Size:     ${IMG_SIZE}"

    local comp_sel
    comp_sel="$("$GUM_BIN" choose --header "🗜️  XZ Compression:" "📦 Enabled (.img.xz - smaller, recommended)" "⚡ Disabled (.img - raw)")"
    if [[ "$comp_sel" == *"Disabled"* ]]; then
        COMPRESS=0
        "$GUM_BIN" style --foreground 212 "  ✓ XZ Compression:    Disabled (.img)"
    else
        COMPRESS=1
        "$GUM_BIN" style --foreground 212 "  ✓ XZ Compression:    Enabled (.img.xz)"
    fi

    local -a cmd_args=("${SCRIPT_DIR}/build.sh" "-y" "-v" "${VERSION}" "--hostname" "${TARGET_HOSTNAME}" "--root-user" "${ROOT_USER}" "-u" "${ALARM_USER}" "-s" "${IMG_SIZE}")
    if [[ "${ROOT_PASSWORD}" != "root" ]]; then
        cmd_args+=("--root-password" "${ROOT_PASSWORD}")
    fi
    if [[ "${ALARM_PASSWORD}" != "alarm" ]]; then
        cmd_args+=("-p" "${ALARM_PASSWORD}")
    fi
    if [[ "${COMPRESS}" -eq 0 ]]; then
        cmd_args+=("--no-compress")
    fi
    if [[ -n "${OUTPUT_DIR:-}" && "${OUTPUT_DIR}" != "${SCRIPT_DIR}/dist" && "${OUTPUT_DIR}" != "./dist" ]]; then
        cmd_args+=("-o" "${OUTPUT_DIR}")
    fi

    local display_cmd
    display_cmd="./build.sh -y -v \"${VERSION}\" --hostname \"${TARGET_HOSTNAME}\" --root-user \"${ROOT_USER}\" -u \"${ALARM_USER}\" -s \"${IMG_SIZE}\""
    if [[ "${ROOT_PASSWORD}" != "root" ]]; then
        display_cmd+=" --root-password \"********\""
    fi
    if [[ "${ALARM_PASSWORD}" != "alarm" ]]; then
        display_cmd+=" -p \"********\""
    fi
    if [[ "${COMPRESS}" -eq 0 ]]; then
        display_cmd+=" --no-compress"
    fi
    if [[ -n "${OUTPUT_DIR:-}" && "${OUTPUT_DIR}" != "${SCRIPT_DIR}/dist" && "${OUTPUT_DIR}" != "./dist" ]]; then
        display_cmd+=" -o \"${OUTPUT_DIR}\""
    fi

    echo ""
    "$GUM_BIN" style --border normal --padding "1 2" \
        "📋 Build Summary:" \
        "  Version:          ${VERSION}" \
        "  Hostname:         ${TARGET_HOSTNAME}" \
        "  Root User:        ${ROOT_USER}" \
        "  Non-Root User:    ${ALARM_USER}" \
        "  Image Size:       ${IMG_SIZE}" \
        "  Compressed:       $((COMPRESS ? 1 : 0)) (xz)" \
        "  Output Path:      ${OUTPUT_DIR}/" \
        "" \
        "💻 Executable Command:" \
        "  ${display_cmd}"
    echo ""

    if ! "$GUM_BIN" confirm "🚀 Start building with these settings?"; then
        "$GUM_BIN" log -l warn "Build cancelled by user."
        echo ""
        echo "You can run this command directly whenever you're ready:"
        echo "  ${display_cmd}"
        exit 0
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Dry run enabled. Executable command:"
        echo "  ${display_cmd}"
        exit 0
    fi

    exec "${cmd_args[@]}"
}

wizard_bash() {
    echo "=== 🧙 Interactive Command Generator ==="

    local in_ver in_host in_root_user in_root_pw in_user in_user_pw in_size in_comp in_confirm

    read -r -p "📦 Image version [${VERSION}]: " in_ver
    [[ -n "$in_ver" ]] && VERSION="$in_ver"

    read -r -p "🏷️  Target hostname [${TARGET_HOSTNAME}]: " in_host
    [[ -n "$in_host" ]] && TARGET_HOSTNAME="$in_host"

    # 1. Root Credentials
    read -r -p "👑 Root username [${ROOT_USER}]: " in_root_user
    [[ -n "$in_root_user" ]] && ROOT_USER="$in_root_user"

    read -r -s -p "🔑 Root password (press Enter for default): " in_root_pw
    echo ""
    [[ -n "$in_root_pw" ]] && ROOT_PASSWORD="$in_root_pw"

    # 2. Non-Root Credentials
    read -r -p "👤 Non-root username [${ALARM_USER}]: " in_user
    [[ -n "$in_user" ]] && ALARM_USER="$in_user"
    ALARM_USER="$(echo "${ALARM_USER}" | tr '[:upper:]' '[:lower:]')"

    read -r -s -p "🔒 ${ALARM_USER} password (press Enter for default): " in_user_pw
    echo ""
    [[ -n "$in_user_pw" ]] && ALARM_PASSWORD="$in_user_pw"

    read -r -p "💾 Raw disk size (3G fits on any SD card >=4GB) [${IMG_SIZE}]: " in_size
    [[ -n "$in_size" ]] && IMG_SIZE="$in_size"

    read -r -p "🗜️  Enable XZ compression? (y/n) [y]: " in_comp
    if [[ "$in_comp" =~ ^[Nn] ]]; then
        COMPRESS=0
    else
        COMPRESS=1
    fi

    local -a cmd_args=("${SCRIPT_DIR}/build.sh" "-y" "-v" "${VERSION}" "--hostname" "${TARGET_HOSTNAME}" "--root-user" "${ROOT_USER}" "-u" "${ALARM_USER}" "-s" "${IMG_SIZE}")
    if [[ "${ROOT_PASSWORD}" != "root" ]]; then
        cmd_args+=("--root-password" "${ROOT_PASSWORD}")
    fi
    if [[ "${ALARM_PASSWORD}" != "alarm" ]]; then
        cmd_args+=("-p" "${ALARM_PASSWORD}")
    fi
    if [[ "${COMPRESS}" -eq 0 ]]; then
        cmd_args+=("--no-compress")
    fi
    if [[ -n "${OUTPUT_DIR:-}" && "${OUTPUT_DIR}" != "${SCRIPT_DIR}/dist" && "${OUTPUT_DIR}" != "./dist" ]]; then
        cmd_args+=("-o" "${OUTPUT_DIR}")
    fi

    local display_cmd
    display_cmd="./build.sh -y -v \"${VERSION}\" --hostname \"${TARGET_HOSTNAME}\" --root-user \"${ROOT_USER}\" -u \"${ALARM_USER}\" -s \"${IMG_SIZE}\""
    if [[ "${ROOT_PASSWORD}" != "root" ]]; then
        display_cmd+=" --root-password \"********\""
    fi
    if [[ "${ALARM_PASSWORD}" != "alarm" ]]; then
        display_cmd+=" -p \"********\""
    fi
    if [[ "${COMPRESS}" -eq 0 ]]; then
        display_cmd+=" --no-compress"
    fi
    if [[ -n "${OUTPUT_DIR:-}" && "${OUTPUT_DIR}" != "${SCRIPT_DIR}/dist" && "${OUTPUT_DIR}" != "./dist" ]]; then
        display_cmd+=" -o \"${OUTPUT_DIR}\""
    fi

    cat <<SUMMARY

📋 Build Summary:
  Version:          ${VERSION}
  Hostname:         ${TARGET_HOSTNAME}
  Root User:        ${ROOT_USER}
  Non-Root User:    ${ALARM_USER}
  Image Size:       ${IMG_SIZE}
  Compressed:       $((COMPRESS ? 1 : 0)) (xz)
  Output Path:      ${OUTPUT_DIR}/

💻 Executable Command:
  ${display_cmd}

SUMMARY

    read -r -p "🚀 Start building with these settings? (y/n) [y]: " in_confirm
    if [[ "$in_confirm" =~ ^[Nn] ]]; then
        echo "==> Build cancelled by user."
        echo ""
        echo "You can run this command directly whenever you're ready:"
        echo "  ${display_cmd}"
        exit 0
    fi

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Dry run enabled. Executable command:"
        echo "  ${display_cmd}"
        exit 0
    fi

    exec "${cmd_args[@]}"
}

if [[ "${FORCE_BASH}" -eq 0 && -n "$(command -v gum 2>/dev/null)" ]]; then
    wizard_gum
else
    wizard_bash
fi
