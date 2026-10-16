#!/usr/bin/env bash
# wizard/bash.sh — Fallback pure Bash interactive command builder flow

wizard_bash() {
    echo "=== 🧙 Interactive Command Generator ==="

    local in_ver in_host in_root_user in_root_pw in_user in_user_pw in_size in_comp in_confirm

    read -r -p "📦 Image version [${VERSION}]: " in_ver
    [[ -n "$in_ver" ]] && VERSION="$in_ver"
    VERSION="${VERSION:-0.0.0-snapshot}"

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
