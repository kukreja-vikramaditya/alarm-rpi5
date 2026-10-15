#!/usr/bin/env bash
# shellcheck disable=SC2034 # Parsed CLI flags and USE_GUM are consumed by other modules
# src/cli.sh — Command line interface, usage, and argument parsing

usage() {
    local script_name="${SCRIPT_NAME:-build-alarm-rpi5.sh}"
    local script_dir="${SCRIPT_DIR:-.}"

    cat <<USAGE
Usage: sudo ./${script_name} [OPTIONS]

Build an Arch Linux ARM image for Raspberry Pi 5.
Runs in interactive wizard mode by default when attached to a terminal.

Options:
  -c, --check              Check host environment and dependencies without building
  -i, --interactive        Run interactive configuration wizard explicitly
  -y, --non-interactive,   Bypass interactive prompts and use defaults/flags
      --batch
  -o, --output-dir DIR     Output directory       (default: ${script_dir}/dist)
  -v, --version VER        Image version string   (default: 0.1.0)
  -s, --img-size SIZE      Raw image size         (default: 3G)
      --hostname NAME      Target hostname        (default: raspberrypi)
  -u, --user USER          Non-root username      (default: alarm)
  -p, --password PASS      Non-root user password (default: alarm)
      --root-user USER     Root username          (default: root)
      --root-password PASS Root password          (default: root)
      --no-compress        Skip xz compression
      --no-gum             Disable Gum styling and interactive elements
  -h, --help               Show this help

Environment overrides (lower precedence than flags):
  IMG_SIZE, VERSION, IMG_NAME, BOOT_SIZE_MIB, TARGET_HOSTNAME,
  ROOT_USER, ROOT_PASSWORD, ALARM_USER, NON_ROOT_USER, ALARM_PASSWORD,
  TIMEZONE, LOCALE, EXTRA_PACKAGES, ALARM_MIRROR, COMPRESS

Examples:
  ./${script_name} --check
  sudo ./${script_name}                  # interactive wizard by default
  sudo ./${script_name} -y               # build immediately with defaults
  sudo ./${script_name} -u vikram -p secret123
  sudo ./${script_name} -o /mnt/build -v 1.0.0
  EXTRA_PACKAGES="git htop" sudo ./${script_name}
USAGE
}

# Raw argument holders
_arg_check=""
_arg_interactive=""
_arg_non_interactive=""
_arg_output_dir=""
_arg_version=""
_arg_img_size=""
_arg_hostname=""
_arg_user=""
_arg_password=""
_arg_root_user=""
_arg_root_password=""
_arg_no_compress=""

parse_cli() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --check)
                _arg_check=1
                shift
                ;;
            -i | --interactive)
                _arg_interactive=1
                shift
                ;;
            -y | --non-interactive | --batch)
                _arg_non_interactive=1
                shift
                ;;
            --no-gum)
                USE_GUM=0
                shift
                ;;
            -o | --output-dir)
                [[ -n "${2:-}" ]] || die "Missing argument for $1"
                _arg_output_dir="$2"
                shift 2
                ;;
            -v | --version)
                [[ -n "${2:-}" ]] || die "Missing argument for $1"
                _arg_version="$2"
                shift 2
                ;;
            -s | --img-size)
                [[ -n "${2:-}" ]] || die "Missing argument for $1"
                _arg_img_size="$2"
                shift 2
                ;;
            --hostname)
                [[ -n "${2:-}" ]] || die "Missing argument for $1"
                _arg_hostname="$2"
                shift 2
                ;;
            -u | --user | --username)
                [[ -n "${2:-}" ]] || die "Missing argument for $1"
                _arg_user="$2"
                shift 2
                ;;
            -p | --password)
                [[ -n "${2:-}" ]] || die "Missing argument for $1"
                _arg_password="$2"
                shift 2
                ;;
            --root-user)
                [[ -n "${2:-}" ]] || die "Missing argument for $1"
                _arg_root_user="$2"
                shift 2
                ;;
            --root-password)
                [[ -n "${2:-}" ]] || die "Missing argument for $1"
                _arg_root_password="$2"
                shift 2
                ;;
            --no-compress)
                _arg_no_compress=1
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                die "Unknown option: $1 (see --help)"
                ;;
            *)
                die "Unexpected argument: $1 (see --help)"
                ;;
        esac
    done
}
