#!/usr/bin/env bash
# shellcheck disable=SC2317  # cleanup is invoked via trap, not direct call
#
# build-alarm-rpi5.sh — Build an Arch Linux ARM image for Raspberry Pi 5
#
# Produces a .img.xz file that can be flashed via:
#   - Raspberry Pi Imager → "Use custom"
#   - dd / balenaEtcher / any raw image flasher
#
# Requirements (x86_64 Arch Linux host):
#   sudo pacman -S qemu-user-static qemu-user-static-binfmt \
#     arch-install-scripts dosfstools e2fsprogs parted xz
#   sudo systemctl restart systemd-binfmt.service
#
# Usage:
#   sudo ./build-alarm-rpi5.sh [--output-dir DIR] [--version VER] [--no-compress]
#
# Sources:
#   - Rootfs:     archlinuxarm.org (community, FOSS packages)
#   - Kernel:     linux-rpi from ALARM repos (GPL, github.com/archlinuxarm/PKGBUILDs)
#   - Firmware:   raspberrypi-firmware from ALARM repos (Broadcom proprietary — hw requirement)
#   - Build tools: pacstrap, qemu-user-static (GPL)
#

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
# Resolve script directory — so this works when called from anywhere
# ──────────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"

# ──────────────────────────────────────────────────────────────────────
# Gum detection & UI styling (optional progressive enhancement)
# ──────────────────────────────────────────────────────────────────────
find_gum_binary() {
    if command -v gum &>/dev/null; then
        command -v gum
        return 0
    fi
    local candidates=(
        "/usr/bin/gum"
        "/usr/local/bin/gum"
    )
    if [[ -n "${SUDO_USER:-}" ]]; then
        candidates+=(
            "/home/${SUDO_USER}/.local/bin/gum"
            "/home/${SUDO_USER}/go/bin/gum"
        )
    fi
    candidates+=(
        "${HOME:-}/.local/bin/gum"
        "${HOME:-}/go/bin/gum"
    )
    for c in "${candidates[@]}"; do
        if [[ -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

GUM_BIN="$(find_gum_binary 2>/dev/null || true)"
USE_GUM=0
if [[ -n "${GUM_BIN}" && -t 1 ]]; then
    USE_GUM=1
fi

# ──────────────────────────────────────────────────────────────────────
# Logging (Plain text or Gum styled)
# ──────────────────────────────────────────────────────────────────────
_log()  { printf '[%s] [%-5s] %s\n' "$(date '+%H:%M:%S')" "$1" "$2"; }

log_info() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '  %s %s\n' "$("$GUM_BIN" style --foreground 39 "ℹ")" "$*"
    else
        _log "INFO" "$*"
    fi
}

log_warn() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '  %s %s\n' "$("$GUM_BIN" style --foreground 214 "⚠")" "$*" >&2
    else
        _log "WARN" "$*" >&2
    fi
}

log_error() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '  %s %s\n' "$("$GUM_BIN" style --foreground 196 --bold "✖")" "$*" >&2
    else
        _log "ERROR" "$*" >&2
    fi
}

log_phase() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        printf '\n'
        "$GUM_BIN" style --bold --foreground 212 "==> $*"
    else
        printf '\n[%s] === %s ===\n' "$(date '+%H:%M:%S')" "$*"
    fi
}

gum_banner() {
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        "$GUM_BIN" style \
            --border rounded \
            --border-foreground 212 \
            --padding "1 2" \
            --bold \
            "Arch Linux ARM for Raspberry Pi 5" \
            "Clean, Repeatable Image Builder"
        echo ""
    fi
}

run_spin() {
    local title="$1"; shift
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        "$GUM_BIN" spin --spinner dot --title "$title" -- "$@"
    else
        log_info "$title..."
        "$@"
    fi
}

die() {
    log_error "$@"
    exit 1
}

# ──────────────────────────────────────────────────────────────────────
# Usage / Help
# ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<USAGE
Usage: sudo ./${SCRIPT_NAME} [OPTIONS]

Build an Arch Linux ARM image for Raspberry Pi 5.
Runs in interactive wizard mode by default when attached to a terminal.

Options:
  -c, --check              Check host environment and dependencies without building
  -i, --interactive        Run interactive configuration wizard explicitly
  -y, --non-interactive    Bypass interactive prompts and use defaults/flags
  -o, --output-dir DIR     Output directory       (default: ${SCRIPT_DIR}/dist)
  -v, --version VER        Image version string   (default: 0.1.0)
  -s, --img-size SIZE      Raw image size         (default: 4G)
      --hostname NAME      Target hostname        (default: alarm-rpi5)
      --no-compress        Skip xz compression
      --no-gum             Disable Gum styling and interactive elements
  -h, --help               Show this help

Environment overrides (lower precedence than flags):
  IMG_SIZE, VERSION, IMG_NAME, BOOT_SIZE_MIB, TARGET_HOSTNAME,
  ROOT_PASSWORD, ALARM_USER, ALARM_PASSWORD, TIMEZONE, LOCALE,
  EXTRA_PACKAGES, ALARM_MIRROR, COMPRESS

Examples:
  ./${SCRIPT_NAME} --check
  sudo ./${SCRIPT_NAME}                  # interactive wizard by default
  sudo ./${SCRIPT_NAME} -y               # build immediately with defaults
  sudo ./${SCRIPT_NAME} -o /mnt/build -v 1.0.0
  EXTRA_PACKAGES="git htop" sudo ./${SCRIPT_NAME}
USAGE
}

# ──────────────────────────────────────────────────────────────────────
# Argument parsing
# ──────────────────────────────────────────────────────────────────────
_arg_check=""
_arg_interactive=""
_arg_non_interactive=""
_arg_output_dir=""
_arg_version=""
_arg_img_size=""
_arg_hostname=""
_arg_no_compress=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--check)
            _arg_check=1; shift ;;
        -i|--interactive)
            _arg_interactive=1; shift ;;
        -y|--non-interactive|--batch)
            _arg_non_interactive=1; shift ;;
        --no-gum)
            USE_GUM=0; shift ;;
        -o|--output-dir)
            [[ -n "${2:-}" ]] || die "Missing argument for $1"
            _arg_output_dir="$2"; shift 2 ;;
        -v|--version)
            [[ -n "${2:-}" ]] || die "Missing argument for $1"
            _arg_version="$2"; shift 2 ;;
        -s|--img-size)
            [[ -n "${2:-}" ]] || die "Missing argument for $1"
            _arg_img_size="$2"; shift 2 ;;
        --hostname)
            [[ -n "${2:-}" ]] || die "Missing argument for $1"
            _arg_hostname="$2"; shift 2 ;;
        --no-compress)
            _arg_no_compress=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift; break ;;
        -*)
            die "Unknown option: $1 (see --help)" ;;
        *)
            die "Unexpected argument: $1 (see --help)" ;;
    esac
done

# ──────────────────────────────────────────────────────────────────────
# Configuration — flags > environment > defaults
# ──────────────────────────────────────────────────────────────────────
IMG_SIZE="${_arg_img_size:-${IMG_SIZE:-4G}}"
VERSION="${_arg_version:-${VERSION:-0.1.0}}"
readonly BUILD_DATE="$(date +%Y%m%d)"
IMG_NAME="${IMG_NAME:-alarm-rpi5-${VERSION}-${BUILD_DATE}}"

_output_dir="${_arg_output_dir:-${SCRIPT_DIR}/dist}"
_output_dir="$(mkdir -p -- "$_output_dir" && cd -- "$_output_dir" && pwd)"
readonly OUTPUT_DIR="$_output_dir"
unset _output_dir

readonly BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-256}"
TARGET_HOSTNAME="${_arg_hostname:-${TARGET_HOSTNAME:-alarm-rpi5}}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
ALARM_USER="${ALARM_USER:-alarm}"
ALARM_PASSWORD="${ALARM_PASSWORD:-alarm}"
readonly TIMEZONE="${TIMEZONE:-UTC}"
readonly LOCALE="${LOCALE:-en_US.UTF-8}"
readonly EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"
readonly ALARM_MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"

if [[ -n "$_arg_no_compress" ]]; then
    COMPRESS=0
else
    COMPRESS="${COMPRESS:-1}"
fi

IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"
ROOTFS=""     # Set in main body; needs to be mutable for cleanup
PACMAN_CONF="" # Set in main body
LOOP=""        # Set in main body; loopback device, mutable

# Restrict file creation to owner-only
umask 0077

# ──────────────────────────────────────────────────────────────────────
# Required external commands
# ──────────────────────────────────────────────────────────────────────
readonly REQUIRED_CMDS=(
    parted mkfs.vfat mkfs.ext4 losetup
    pacstrap arch-chroot
    truncate e2fsck resize2fs dumpe2fs
    xz numfmt
)

# ──────────────────────────────────────────────────────────────────────
# Cleanup — safe, idempotent, handles partial failures
# ──────────────────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    set +e  # Don't fail during cleanup

    if [[ -n "${ROOTFS}" ]]; then
        if mountpoint -q "${ROOTFS}/boot" 2>/dev/null; then
            umount -l "${ROOTFS}/boot" 2>/dev/null
        fi
        if mountpoint -q "${ROOTFS}" 2>/dev/null; then
            umount -l "${ROOTFS}" 2>/dev/null
        fi
        rm -rf -- "${ROOTFS}"
    fi

    if [[ -n "${LOOP}" ]]; then
        losetup -d "${LOOP}" 2>/dev/null
        LOOP=""
    fi

    if [[ -n "${PACMAN_CONF}" && -f "${PACMAN_CONF}" ]]; then
        rm -f -- "${PACMAN_CONF}"
    fi

    if [[ $exit_code -ne 0 && -z "${_arg_check:-}" ]]; then
        if [[ -n "${IMG_FILE:-}" && -f "${IMG_FILE}" ]]; then
            log_error "Build failed (exit code ${exit_code}). Partial artifacts may remain at: ${IMG_FILE}"
        fi
    fi

    return "$exit_code"
}

trap cleanup EXIT INT TERM

# ──────────────────────────────────────────────────────────────────────
# Package mapping for diagnostics
# ──────────────────────────────────────────────────────────────────────
get_pkg_for_cmd() {
    case "$1" in
        parted)                              echo "sudo pacman -S parted" ;;
        mkfs.vfat)                          echo "sudo pacman -S dosfstools" ;;
        pacstrap|arch-chroot)               echo "sudo pacman -S arch-install-scripts" ;;
        mkfs.ext4|e2fsck|resize2fs|dumpe2fs) echo "sudo pacman -S e2fsprogs" ;;
        losetup)                            echo "sudo pacman -S util-linux" ;;
        xz)                                 echo "sudo pacman -S xz" ;;
        truncate|numfmt)                    echo "sudo pacman -S coreutils" ;;
        *)                                  echo "pacman -S package providing $1" ;;
    esac
}

format_badge() {
    local type="$1"
    if [[ "${USE_GUM:-0}" -eq 1 ]]; then
        case "$type" in
            OK)      "$GUM_BIN" style --foreground 42 --bold "[  OK  ]" ;;
            MISSING) "$GUM_BIN" style --foreground 196 --bold "[MISSING]" ;;
            WARN)    "$GUM_BIN" style --foreground 214 "[ WARN ]" ;;
            INFO)    "$GUM_BIN" style --foreground 39 "[ INFO ]" ;;
            *)       printf '[%s]' "$type" ;;
        esac
    else
        case "$type" in
            OK)      printf '[  OK  ]' ;;
            MISSING) printf '[MISSING]' ;;
            WARN)    printf '[ WARN ]' ;;
            INFO)    printf '[ INFO ]' ;;
            *)       printf '[%s]' "$type" ;;
        esac
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Interactive Wizard (Gum engine + pure Bash fallback)
# ──────────────────────────────────────────────────────────────────────
interactive_wizard_gum() {
    gum_banner
    "$GUM_BIN" style --bold --underline "Interactive Configuration Wizard"
    echo ""

    VERSION="$("$GUM_BIN" input --header "Image Version" --value "${VERSION}")"
    TARGET_HOSTNAME="$("$GUM_BIN" input --header "Target Hostname" --value "${TARGET_HOSTNAME}")"
    ALARM_USER="$("$GUM_BIN" input --header "Non-Root Username" --value "${ALARM_USER}")"

    local new_root
    new_root="$("$GUM_BIN" input --password --header "Root Password (leave empty for default: ${ROOT_PASSWORD})")"
    [[ -n "$new_root" ]] && ROOT_PASSWORD="$new_root"

    local new_user
    new_user="$("$GUM_BIN" input --password --header "${ALARM_USER} Password (leave empty for default: ${ALARM_PASSWORD})")"
    [[ -n "$new_user" ]] && ALARM_PASSWORD="$new_user"

    IMG_SIZE="$("$GUM_BIN" choose --header "Select raw disk image size:" "4G" "8G" "16G" "32G")"

    local comp_sel
    comp_sel="$("$GUM_BIN" choose --header "XZ Compression:" "Enabled (.img.xz - smaller, recommended)" "Disabled (.img - raw)")"
    if [[ "$comp_sel" == *"Disabled"* ]]; then
        COMPRESS=0
    else
        COMPRESS=1
    fi

    IMG_NAME="alarm-rpi5-${VERSION}-${BUILD_DATE}"
    IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"

    echo ""
    "$GUM_BIN" style --border normal --padding "1 2" \
        "Build Summary:" \
        "  Version:     ${VERSION}" \
        "  Hostname:    ${TARGET_HOSTNAME}" \
        "  User:        ${ALARM_USER}" \
        "  Image Size:  ${IMG_SIZE}" \
        "  Compressed:  $(( COMPRESS ? 1 : 0 )) (xz)" \
        "  Output Path: ${OUTPUT_DIR}/"
    echo ""

    if ! "$GUM_BIN" confirm "Start building with these settings?"; then
        echo "Build cancelled by user."
        exit 0
    fi
}

interactive_wizard_bash() {
    printf "\n=== Interactive Configuration Wizard ===\n\n"

    local in_ver in_host in_user in_root_pw in_user_pw in_size in_comp in_confirm

    read -r -p "Image version [${VERSION}]: " in_ver
    [[ -n "$in_ver" ]] && VERSION="$in_ver"

    read -r -p "Target hostname [${TARGET_HOSTNAME}]: " in_host
    [[ -n "$in_host" ]] && TARGET_HOSTNAME="$in_host"

    read -r -p "Non-root username [${ALARM_USER}]: " in_user
    [[ -n "$in_user" ]] && ALARM_USER="$in_user"

    read -r -s -p "Root password (press Enter for default): " in_root_pw
    echo ""
    [[ -n "$in_root_pw" ]] && ROOT_PASSWORD="$in_root_pw"

    read -r -s -p "${ALARM_USER} password (press Enter for default): " in_user_pw
    echo ""
    [[ -n "$in_user_pw" ]] && ALARM_PASSWORD="$in_user_pw"

    read -r -p "Raw image size (4G, 8G, 16G, 32G) [${IMG_SIZE}]: " in_size
    [[ -n "$in_size" ]] && IMG_SIZE="$in_size"

    read -r -p "Enable XZ compression? (y/n) [y]: " in_comp
    if [[ "$in_comp" =~ ^[Nn] ]]; then
        COMPRESS=0
    else
        COMPRESS=1
    fi

    IMG_NAME="alarm-rpi5-${VERSION}-${BUILD_DATE}"
    IMG_FILE="${OUTPUT_DIR}/${IMG_NAME}.img"

    cat <<SUMMARY

Build Summary:
  Version:     ${VERSION}
  Hostname:    ${TARGET_HOSTNAME}
  User:        ${ALARM_USER}
  Image Size:  ${IMG_SIZE}
  Compressed:  $(( COMPRESS ? 1 : 0 )) (xz)
  Output Path: ${OUTPUT_DIR}/

SUMMARY

    read -r -p "Start building with these settings? (y/n) [y]: " in_confirm
    if [[ "$in_confirm" =~ ^[Nn] ]]; then
        echo "Build cancelled by user."
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

# ──────────────────────────────────────────────────────────────────────
# Environment check / diagnostic mode (--check)
# ──────────────────────────────────────────────────────────────────────
check_environment() {
    log_phase "Host Environment Diagnostics"
    local issues=0

    # 1. Root / Privileges
    if [[ $EUID -eq 0 ]]; then
        printf '  %-32s %s\n' "Root execution" "$(format_badge OK)"
    elif sudo -n true 2>/dev/null; then
        printf '  %-32s %s (passwordless sudo available)\n' "Root execution" "$(format_badge OK)"
    else
        printf '  %-32s %s (requires sudo password when building)\n' "Root execution" "$(format_badge INFO)"
    fi

    # 2. Required external commands
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            printf '  %-32s %s (%s)\n' "Tool: $cmd" "$(format_badge OK)" "$(command -v "$cmd")"
        else
            printf '  %-32s %s -> install with: %s\n' "Tool: $cmd" "$(format_badge MISSING)" "$(get_pkg_for_cmd "$cmd")"
            ((issues++)) || true
        fi
    done

    # 3. binfmt_misc emulation
    if [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        printf '  %-32s %s\n' "binfmt: qemu-aarch64" "$(format_badge OK)"
    else
        printf '  %-32s %s -> enable with: sudo systemctl restart systemd-binfmt.service\n' "binfmt: qemu-aarch64" "$(format_badge MISSING)"
        ((issues++)) || true
    fi

    # 4. static qemu binary
    if [[ -f /usr/bin/qemu-aarch64-static ]]; then
        printf '  %-32s %s\n' "Binary: qemu-aarch64-static" "$(format_badge OK)"
    else
        printf '  %-32s %s -> install with: sudo pacman -S qemu-user-static qemu-user-static-binfmt\n' "Binary: qemu-aarch64-static" "$(format_badge MISSING)"
        ((issues++)) || true
    fi

    # 5. ALARM mirror reachable
    if command -v curl &>/dev/null; then
        if curl -sI --max-time 5 "${ALARM_MIRROR}" &>/dev/null; then
            printf '  %-32s %s (%s)\n' "ALARM mirror reachable" "$(format_badge OK)" "${ALARM_MIRROR}"
        else
            printf '  %-32s %s (%s unreachable)\n' "ALARM mirror reachable" "$(format_badge WARN)" "${ALARM_MIRROR}"
        fi
    fi

    # 6. Output directory writable
    if [[ -d "${OUTPUT_DIR}" && -w "${OUTPUT_DIR}" ]]; then
        printf '  %-32s %s (%s)\n' "Output dir writable" "$(format_badge OK)" "${OUTPUT_DIR}"
    else
        printf '  %-32s %s (%s)\n' "Output dir writable" "$(format_badge WARN)" "${OUTPUT_DIR}"
    fi

    # 7. Optional UI enhancement
    if [[ -n "${GUM_BIN}" ]]; then
        printf '  %-32s %s (%s)\n' "UI library: gum" "$(format_badge OK)" "${GUM_BIN}"
    else
        printf '  %-32s %s (optional for styled UI & wizard: sudo pacman -S gum)\n' "UI library: gum" "$(format_badge INFO)"
    fi

    echo ""
    if [[ $issues -eq 0 ]]; then
        log_info "All prerequisite checks passed. Environment is ready to build!"
        return 0
    else
        log_warn "${issues} prerequisite(s) missing. Install missing packages before running the build."
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Preflight checks
# ──────────────────────────────────────────────────────────────────────
preflight() {
    log_phase "Preflight checks"

    [[ $EUID -eq 0 ]] || die "This script must be run as root (or via sudo)."

    for cmd in "${REQUIRED_CMDS[@]}"; do
        command -v "$cmd" &>/dev/null \
            || die "'${cmd}' not found. Install required packages (see --help)."
    done

    [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] \
        || die "qemu-aarch64 binfmt not registered. Run: sudo systemctl restart systemd-binfmt.service"

    [[ -f /usr/bin/qemu-aarch64-static ]] \
        || die "/usr/bin/qemu-aarch64-static not found. Run: sudo pacman -S qemu-user-static qemu-user-static-binfmt"

    # Refuse to overwrite an existing image without explicit intent
    if [[ -f "${IMG_FILE}" || -f "${IMG_FILE}.xz" ]]; then
        die "Output already exists: ${IMG_FILE}(.xz). Remove it first or change --version."
    fi

    log_info "Output image: ${IMG_FILE}"
    log_info "Version:      ${VERSION}"
    log_info "Image size:   ${IMG_SIZE}"
    log_info "Hostname:     ${TARGET_HOSTNAME}"
    log_info "Compress:     $(( COMPRESS ? 1 : 0 )) (xz)"
}

# ──────────────────────────────────────────────────────────────────────
# Phase 1: Create disk image & partitions
# ──────────────────────────────────────────────────────────────────────
create_image() {
    log_phase "Phase 1/5 — Create disk image (${IMG_SIZE})"

    truncate -s "${IMG_SIZE}" -- "${IMG_FILE}"

    parted -s -- "${IMG_FILE}" mklabel msdos
    parted -s -- "${IMG_FILE}" mkpart primary fat32 1MiB "${BOOT_SIZE_MIB}MiB"
    parted -s -- "${IMG_FILE}" set 1 boot on
    parted -s -- "${IMG_FILE}" mkpart primary ext4 "${BOOT_SIZE_MIB}MiB" 100%

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

# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────
main() {
    if [[ -n "${_arg_check}" ]]; then
        check_environment
        return $?
    fi

    if [[ -z "${_arg_non_interactive}" ]]; then
        interactive_wizard
    fi

    gum_banner

    local start_time
    start_time="$(date +%s)"

    preflight
    create_image
    bootstrap_rootfs
    configure_boot
    configure_system
    finalize_image

    local elapsed=$(( $(date +%s) - start_time ))
    log_info "Total build time: $(( elapsed / 60 ))m $(( elapsed % 60 ))s"
}

main "$@"
