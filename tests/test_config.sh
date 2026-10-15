#!/usr/bin/env bash
# tests/test_config.sh — Unit tests for src/config.sh
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
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
# shellcheck source=src/ui.sh
source "${SRC_DIR}/ui.sh"
# shellcheck source=src/config.sh
source "${SRC_DIR}/config.sh"

# Test 1: REQUIRED_CMDS array
assert_eq "12" "${#REQUIRED_CMDS[@]}" "REQUIRED_CMDS has 12 items"
for req in parted mkfs.vfat mkfs.ext4 losetup pacstrap arch-chroot truncate e2fsck resize2fs dumpe2fs xz numfmt; do
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

assert_eq "0.1.0" "$VERSION" "init_config default VERSION is 0.1.0"
assert_eq "raspberrypi" "$TARGET_HOSTNAME" "init_config default TARGET_HOSTNAME is raspberrypi"
assert_eq "root" "$ROOT_PASSWORD" "init_config default ROOT_PASSWORD is root"
assert_eq "alarm" "$ALARM_USER" "init_config default ALARM_USER is alarm"
assert_eq "alarm" "$ALARM_PASSWORD" "init_config default ALARM_PASSWORD is alarm"
assert_eq "4G" "$IMG_SIZE" "init_config default IMG_SIZE is 4G"
assert_eq "1" "$COMPRESS" "init_config default COMPRESS is 1"
assert_eq "256" "$BOOT_SIZE_MIB" "init_config default BOOT_SIZE_MIB is 256"
assert_contains "$OUTPUT_DIR" "/dist" "init_config OUTPUT_DIR points to dist"
assert_contains "$IMG_FILE" "alarm-rpi5-0.1.0-" "init_config IMG_FILE contains version"
assert_contains "$DATA_DIR" "/data" "DATA_DIR points to data directory"
assert_file_exists "${DATA_DIR}/fstab" "DATA_DIR contains fstab"

# Test 3: CLI arguments override defaults
_arg_version="1.5.0"
_arg_img_size="8G"
_arg_hostname="alarm-host"
_arg_output_dir="/tmp/test-alarm-out"
_arg_no_compress="1"
init_config

assert_eq "1.5.0" "$VERSION" "_arg_version overrides default VERSION"
assert_eq "8G" "$IMG_SIZE" "_arg_img_size overrides default IMG_SIZE"
assert_eq "alarm-host" "$TARGET_HOSTNAME" "_arg_hostname overrides default TARGET_HOSTNAME"
assert_eq "/tmp/test-alarm-out" "$OUTPUT_DIR" "_arg_output_dir overrides default OUTPUT_DIR"
assert_eq "0" "$COMPRESS" "_arg_no_compress sets COMPRESS to 0"
rmdir "/tmp/test-alarm-out" 2>/dev/null || true

# Test 4: recompute_image_paths updates paths when VERSION changes
VERSION="2.0.0"
recompute_image_paths
assert_contains "$IMG_FILE" "alarm-rpi5-2.0.0-" "recompute_image_paths reflects new VERSION"

test_summary "src/config.sh"
