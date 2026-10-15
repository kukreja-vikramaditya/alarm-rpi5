#!/usr/bin/env bash
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
assert_eq "root" "$ROOT_USER" "init_config default ROOT_USER is root"
assert_eq "root" "$ROOT_PASSWORD" "init_config default ROOT_PASSWORD is root"
assert_eq "alarm" "$ALARM_USER" "init_config default ALARM_USER is alarm"
assert_eq "alarm" "$ALARM_PASSWORD" "init_config default ALARM_PASSWORD is alarm"
assert_eq "3G" "$IMG_SIZE" "init_config default IMG_SIZE is 3G"
assert_eq "1" "$COMPRESS" "init_config default COMPRESS is 1"
assert_eq "256" "$BOOT_SIZE_MIB" "init_config default BOOT_SIZE_MIB is 256"
assert_eq "Asia/Kolkata" "$TIMEZONE" "init_config default TIMEZONE is Asia/Kolkata"
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
assert_eq "alarm-host" "$TARGET_HOSTNAME" "_arg_hostname overrides default TARGET_HOSTNAME"
assert_eq "customuser" "$ALARM_USER" "_arg_user overrides default ALARM_USER"
assert_eq "custompass" "$ALARM_PASSWORD" "_arg_password overrides default ALARM_PASSWORD"
assert_eq "superuser" "$ROOT_USER" "_arg_root_user overrides default ROOT_USER"
assert_eq "superpass" "$ROOT_PASSWORD" "_arg_root_password overrides default ROOT_PASSWORD"
assert_eq "/tmp/test-alarm-out" "$OUTPUT_DIR" "_arg_output_dir overrides default OUTPUT_DIR"
assert_eq "0" "$COMPRESS" "_arg_no_compress sets COMPRESS to 0"
rmdir "/tmp/test-alarm-out" 2>/dev/null || true

# Test 3b: NON_ROOT_USER environment fallback
_arg_user=""
NON_ROOT_USER="envuser"
init_config
assert_eq "envuser" "$ALARM_USER" "NON_ROOT_USER overrides default ALARM_USER"
unset NON_ROOT_USER

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
