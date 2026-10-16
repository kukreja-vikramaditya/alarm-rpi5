#!/usr/bin/env bash
# shellcheck disable=SC1091 # Dynamic sourcing of modules and helpers during unit test runs
# tests/test_config.sh — Unit tests for src/config.sh
set -euo pipefail

TEST_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
TEST_DIR="$(dirname -- "${TEST_PATH}")"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/config.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/config.sh"; then
    assert_eq "0" "0" "src/config.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/config.sh syntax validation (bash -n)"
fi

# Source dependencies
# shellcheck source=src/terminal.sh
source "${SRC_DIR}/terminal.sh"
# shellcheck source=src/logger.sh
source "${SRC_DIR}/logger.sh"
# shellcheck source=src/config.sh
source "${SRC_DIR}/config.sh"

# Test 1: REQUIRED_CMDS array
assert_eq "10" "${#REQUIRED_CMDS[@]}" "REQUIRED_CMDS has 10 items"
for req in parted mkfs.vfat mkfs.ext4 losetup pacstrap arch-chroot truncate xz numfmt gum; do
    found=0
    for c in "${REQUIRED_CMDS[@]}"; do
        [[ "$c" == "$req" ]] && {
            found=1
            break
        }
    done
    assert_eq "1" "$found" "REQUIRED_CMDS contains $req"
done

# Test 2: init_config default values
_arg_img_size=""
_arg_version=""
_arg_hostname=""
_arg_output_dir=""
_arg_no_compress=""
init_config

expected_ver="$(tr -d ' \r\n' <"${SCRIPT_DIR}/VERSION")"
assert_eq "$expected_ver" "$VERSION" "init_config default VERSION tracks root VERSION file ($expected_ver)"
assert_eq "raspberrypi" "$TARGET_HOSTNAME" "init_config default TARGET_HOSTNAME is raspberrypi"
assert_eq "raspberrypi" "$HOSTNAME" "init_config default HOSTNAME is raspberrypi"
assert_eq "root" "$ROOT_USER" "init_config default ROOT_USER is root"
assert_eq "root" "$ROOT_PASSWORD" "init_config default ROOT_PASSWORD is root"
assert_eq "alarm" "$ALARM_USER" "init_config default ALARM_USER is alarm"
assert_eq "alarm" "$USERNAME" "init_config default USERNAME is alarm"
assert_eq "alarm" "$ALARM_PASSWORD" "init_config default ALARM_PASSWORD is alarm"
assert_eq "alarm" "$PASSWORD" "init_config default PASSWORD is alarm"
assert_eq "3G" "$IMG_SIZE" "init_config default IMG_SIZE is 3G"
assert_eq "3G" "$IMAGE_SIZE" "init_config default IMAGE_SIZE is 3G"
assert_eq "1" "$COMPRESS" "init_config default COMPRESS is 1"
assert_eq "256" "$BOOT_SIZE_MIB" "init_config default BOOT_SIZE_MIB is 256"
assert_eq "256" "$BOOT_SIZE" "init_config default BOOT_SIZE is 256"
assert_eq "Asia/Kolkata" "$TIMEZONE" "init_config default TIMEZONE is Asia/Kolkata"
assert_eq "Asia/Kolkata" "$TZ" "init_config default TZ is Asia/Kolkata"
assert_eq "en_US.UTF-8" "$LOCALE" "init_config default LOCALE is en_US.UTF-8"
assert_eq "en_US.UTF-8" "$LANG" "init_config default LANG is en_US.UTF-8"
assert_eq "http://mirror.archlinuxarm.org" "$ALARM_MIRROR" "init_config default ALARM_MIRROR is http://mirror.archlinuxarm.org"
assert_eq "http://mirror.archlinuxarm.org" "$MIRROR" "init_config default MIRROR is http://mirror.archlinuxarm.org"
assert_contains "$PACKAGES" "neovim" "PACKAGES contains default neovim"
assert_contains "$EXTRA_PACKAGES" "neovim" "EXTRA_PACKAGES alias contains default neovim"
assert_contains "$OUTPUT_DIR" "/dist" "init_config OUTPUT_DIR points to dist"
assert_contains "$IMG_FILE" "alarm-rpi5-${expected_ver}-" "init_config IMG_FILE contains version"
assert_contains "$DATA_DIR" "/data" "DATA_DIR points to data directory"
assert_file_exists "${DATA_DIR}/fstab" "DATA_DIR contains fstab"

_arg_version="1.5.0"
_arg_img_size="8G"
_arg_hostname="alarm-host"
_arg_user="customuser"
_arg_password="custompass"
_arg_root_user="superuser"
_arg_root_password="superpass"
_arg_output_dir="/tmp/test-alarm-out"
_arg_no_compress="1"
init_config

assert_eq "1.5.0" "$VERSION" "_arg_version overrides default VERSION"
assert_eq "8G" "$IMG_SIZE" "_arg_img_size overrides default IMG_SIZE"
assert_eq "8G" "$IMAGE_SIZE" "_arg_img_size overrides default IMAGE_SIZE"
assert_eq "alarm-host" "$TARGET_HOSTNAME" "_arg_hostname overrides default TARGET_HOSTNAME"
assert_eq "alarm-host" "$HOSTNAME" "_arg_hostname overrides default HOSTNAME"
assert_eq "customuser" "$ALARM_USER" "_arg_user overrides default ALARM_USER"
assert_eq "customuser" "$USERNAME" "_arg_user overrides default USERNAME"
assert_eq "custompass" "$ALARM_PASSWORD" "_arg_password overrides default ALARM_PASSWORD"
assert_eq "custompass" "$PASSWORD" "_arg_password overrides default PASSWORD"
assert_eq "superuser" "$ROOT_USER" "_arg_root_user overrides default ROOT_USER"
assert_eq "superpass" "$ROOT_PASSWORD" "_arg_root_password overrides default ROOT_PASSWORD"
assert_eq "/tmp/test-alarm-out" "$OUTPUT_DIR" "_arg_output_dir overrides default OUTPUT_DIR"
assert_eq "0" "$COMPRESS" "_arg_no_compress sets COMPRESS to 0"
rmdir "/tmp/test-alarm-out" 2>/dev/null || true

# Test 3b: USERNAME & NON_ROOT_USER environment fallbacks
_arg_user=""
USERNAME="userfromenv"
init_config
assert_eq "userfromenv" "$ALARM_USER" "USERNAME env overrides default ALARM_USER"
assert_eq "userfromenv" "$USERNAME" "USERNAME is synchronized"
unset USERNAME ALARM_USER

NON_ROOT_USER="envuser"
init_config
assert_eq "envuser" "$ALARM_USER" "NON_ROOT_USER overrides default ALARM_USER"
assert_eq "envuser" "$USERNAME" "USERNAME tracks NON_ROOT_USER"
unset NON_ROOT_USER ALARM_USER USERNAME

# Test 3c: Standard POSIX environment variables and legacy alias synchronization
TZ="Europe/London"
TIMEZONE=""
source "${SRC_DIR}/config.sh"
assert_eq "Europe/London" "$TZ" "TZ env sets TZ"
assert_eq "Europe/London" "$TIMEZONE" "TZ env sets TIMEZONE alias"
unset TZ TIMEZONE

TIMEZONE="America/New_York"
TZ=""
source "${SRC_DIR}/config.sh"
assert_eq "America/New_York" "$TIMEZONE" "legacy TIMEZONE sets TIMEZONE"
assert_eq "America/New_York" "$TZ" "legacy TIMEZONE sets TZ"
unset TZ TIMEZONE

LANG="de_DE.UTF-8"
LOCALE=""
source "${SRC_DIR}/config.sh"
assert_eq "de_DE.UTF-8" "$LANG" "LANG env sets LANG"
assert_eq "de_DE.UTF-8" "$LOCALE" "LANG env sets LOCALE alias"
unset LANG LOCALE

LOCALE="fr_FR.UTF-8"
LANG=""
source "${SRC_DIR}/config.sh"
assert_eq "fr_FR.UTF-8" "$LOCALE" "legacy LOCALE sets LOCALE"
assert_eq "fr_FR.UTF-8" "$LANG" "legacy LOCALE sets LANG"
unset LANG LOCALE

PACKAGES="htop tmux"
EXTRA_PACKAGES=""
source "${SRC_DIR}/config.sh"
assert_eq "htop tmux" "$PACKAGES" "PACKAGES env sets PACKAGES"
assert_eq "htop tmux" "$EXTRA_PACKAGES" "PACKAGES env sets EXTRA_PACKAGES alias"
unset PACKAGES EXTRA_PACKAGES

BOOT_SIZE="512M"
BOOT_SIZE_MIB=""
source "${SRC_DIR}/config.sh"
assert_eq "512" "$BOOT_SIZE" "BOOT_SIZE with trailing M trims unit"
assert_eq "512" "$BOOT_SIZE_MIB" "BOOT_SIZE sets BOOT_SIZE_MIB alias"
unset BOOT_SIZE BOOT_SIZE_MIB

MIRROR="https://custom.mirror.org"
ALARM_MIRROR=""
source "${SRC_DIR}/config.sh"
assert_eq "https://custom.mirror.org" "$MIRROR" "MIRROR env sets MIRROR"
assert_eq "https://custom.mirror.org" "$ALARM_MIRROR" "MIRROR env sets ALARM_MIRROR alias"
unset MIRROR ALARM_MIRROR

# Test 3d: Simulated Docker container environment does not corrupt default TARGET_HOSTNAME, ALARM_USER, or LOCALE
(
    export HOSTNAME="container-hash-789abc"
    export USERNAME="root"
    export LANG="C.UTF-8"
    unset TARGET_HOSTNAME ALARM_USER LOCALE _arg_hostname _arg_user
    source "${SRC_DIR}/config.sh"
    init_config
    assert_eq "raspberrypi" "$TARGET_HOSTNAME" "container HOSTNAME env does not override default TARGET_HOSTNAME"
    assert_eq "raspberrypi" "$HOSTNAME" "container HOSTNAME env does not override default HOSTNAME"
    assert_eq "alarm" "$ALARM_USER" "root USERNAME env does not override default ALARM_USER"
    assert_eq "alarm" "$USERNAME" "root USERNAME env does not override default USERNAME"
    assert_eq "en_US.UTF-8" "$LOCALE" "container LANG=C.UTF-8 env does not override default LOCALE"
    assert_eq "en_US.UTF-8" "$LANG" "container LANG=C.UTF-8 env does not override default LANG"
)

# Restore clean defaults for remaining tests
source "${SRC_DIR}/config.sh"
_arg_user=""
_arg_password=""
_arg_hostname=""
_arg_img_size=""
_arg_version=""
_arg_output_dir=""
_arg_no_compress=""
init_config

# Test 4: recompute_image_paths updates paths when VERSION changes
VERSION="2.0.0"
recompute_image_paths
assert_contains "$IMG_FILE" "alarm-rpi5-2.0.0-" "recompute_image_paths reflects new VERSION"

# Test 5: Username normalization and validation
_arg_user="CustomPi"
init_config
assert_eq "custompi" "$ALARM_USER" "init_config normalizes non-root username to lowercase"

# validate_config accepts valid custom usernames
ALARM_USER="pi"
assert_eq "0" "$(validate_config && echo 0 || echo 1)" "validate_config accepts 'pi'"

ALARM_USER="developer"
assert_eq "0" "$(validate_config && echo 0 || echo 1)" "validate_config accepts 'developer'"

ALARM_USER="my_user-1"
assert_eq "0" "$(validate_config && echo 0 || echo 1)" "validate_config accepts 'my_user-1'"

# validate_config rejects 'root' as non-root username
set +e
err_root="$( (
    ALARM_USER="root"
    validate_config
) 2>&1)"
code_root=$?
set -e
assert_eq "1" "$code_root" "validate_config rejects 'root' as non-root user"
assert_contains "$err_root" "cannot be 'root'" "validate_config error mentions root cannot be non-root user"

# validate_config rejects invalid username formats
set +e
err_invalid="$( (
    ALARM_USER="user@invalid"
    validate_config
) 2>&1)"
code_invalid=$?
set -e
assert_eq "1" "$code_invalid" "validate_config rejects invalid username format"
assert_contains "$err_invalid" "Invalid non-root username" "validate_config error mentions invalid username"

test_summary "src/config.sh"
