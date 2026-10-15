#!/usr/bin/env bash
# src/wizard.sh — Interactive configuration wizard (Gum & pure Bash fallback)

interactive_wizard_gum() {
    gum_banner
    "$GUM_BIN" style --bold --underline "🧙 Interactive Configuration Wizard"
    echo ""

    VERSION="$("$GUM_BIN" input --header "📦 Image Version" --value "${VERSION}")"
    VERSION="${VERSION:-0.1.0}"

    TARGET_HOSTNAME="$("$GUM_BIN" input --header "🏷️  Target Hostname" --value "${TARGET_HOSTNAME}")"
    TARGET_HOSTNAME="${TARGET_HOSTNAME:-raspberrypi}"

    # 1. Root Credentials
    ROOT_USER="$("$GUM_BIN" input --header "👑 Root Username" --value "${ROOT_USER:-root}")"
    ROOT_USER="${ROOT_USER:-root}"

    local new_root
    new_root="$("$GUM_BIN" input --password --header "🔑 Root Password (leave empty for default: ${ROOT_PASSWORD})")"
    [[ -n "$new_root" ]] && ROOT_PASSWORD="$new_root"

    # 2. Non-Root Credentials
    ALARM_USER="$("$GUM_BIN" input --header "👤 Non-Root Username" --value "${ALARM_USER}")"
    ALARM_USER="${ALARM_USER:-alarm}"

    local new_user
    new_user="$("$GUM_BIN" input --password --header "🔒 ${ALARM_USER} Password (leave empty for default: ${ALARM_PASSWORD})")"
    [[ -n "$new_user" ]] && ALARM_PASSWORD="$new_user"

    IMG_SIZE="$("$GUM_BIN" choose --header "💾 Raw disk size (3G fits on any SD card >=4GB):" "3G" "4G" "8G" "16G" "32G")"

    local comp_sel
    comp_sel="$("$GUM_BIN" choose --header "🗜️  XZ Compression:" "📦 Enabled (.img.xz - smaller, recommended)" "⚡ Disabled (.img - raw)")"
    if [[ "$comp_sel" == *"Disabled"* ]]; then
        COMPRESS=0
    else
        COMPRESS=1
    fi

    recompute_image_paths

    echo ""
    "$GUM_BIN" style --border normal --padding "1 2" \
        "📋 Build Summary:" \
        "  Version:       ${VERSION}" \
        "  Hostname:      ${TARGET_HOSTNAME}" \
        "  Root User:     ${ROOT_USER}" \
        "  Non-Root User: ${ALARM_USER}" \
        "  Image Size:    ${IMG_SIZE}" \
        "  Compressed:    $((COMPRESS ? 1 : 0)) (xz)" \
        "  Output Path:   ${OUTPUT_DIR}/"
    echo ""

    if ! "$GUM_BIN" confirm "🚀 Start building with these settings?"; then
        "$GUM_BIN" log -l warn "Build cancelled by user."
        exit 0
    fi
}

interactive_wizard_bash() {
    "$GUM_BIN" log -l info "=== 🧙 Interactive Configuration Wizard ==="

    local in_ver in_host in_root_user in_root_pw in_user in_user_pw in_size in_comp in_confirm

    read -r -p "📦 Image version [${VERSION}]: " in_ver
    [[ -n "$in_ver" ]] && VERSION="$in_ver"

    read -r -p "🏷️  Target hostname [${TARGET_HOSTNAME}]: " in_host
    [[ -n "$in_host" ]] && TARGET_HOSTNAME="$in_host"

    # 1. Root Credentials
    read -r -p "👑 Root username [${ROOT_USER:-root}]: " in_root_user
    [[ -n "$in_root_user" ]] && ROOT_USER="$in_root_user"

    read -r -s -p "🔑 Root password (press Enter for default): " in_root_pw
    echo ""
    [[ -n "$in_root_pw" ]] && ROOT_PASSWORD="$in_root_pw"

    # 2. Non-Root Credentials
    read -r -p "👤 Non-root username [${ALARM_USER}]: " in_user
    [[ -n "$in_user" ]] && ALARM_USER="$in_user"

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

    recompute_image_paths

    cat <<SUMMARY

📋 Build Summary:
  Version:       ${VERSION}
  Hostname:      ${TARGET_HOSTNAME}
  Root User:     ${ROOT_USER:-root}
  Non-Root User: ${ALARM_USER}
  Image Size:    ${IMG_SIZE}
  Compressed:    $((COMPRESS ? 1 : 0)) (xz)
  Output Path:   ${OUTPUT_DIR}/

SUMMARY

    read -r -p "🚀 Start building with these settings? (y/n) [y]: " in_confirm
    if [[ "$in_confirm" =~ ^[Nn] ]]; then
        "$GUM_BIN" log -l warn "Build cancelled by user."
        exit 0
    fi
}

interactive_wizard() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        if [[ -n "${_arg_interactive:-}" ]]; then
            die "Interactive mode requires an interactive terminal (stdin and stdout must be a tty)."
        fi
        return 0
    fi

    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        interactive_wizard_gum
    else
        interactive_wizard_bash
    fi
}
