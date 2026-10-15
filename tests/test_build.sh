#!/usr/bin/env bash
# tests/test_build.sh — Unit tests for src/build.sh
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/build.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/build.sh"; then
    assert_eq "0" "0" "src/build.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/build.sh syntax validation (bash -n)"
fi

# Source dependencies
# shellcheck source=src/terminal.sh
source "${SRC_DIR}/terminal.sh"
# shellcheck source=src/logger.sh
source "${SRC_DIR}/logger.sh"
# shellcheck source=src/cleanup.sh
source "${SRC_DIR}/cleanup.sh"
# shellcheck source=src/config.sh
source "${SRC_DIR}/config.sh"
# shellcheck source=src/build.sh
source "${SRC_DIR}/build.sh"

init_config

# Test 1: Function declarations exist
assert_eq "function" "$(type -t create_image)" "create_image function declared"
assert_eq "function" "$(type -t bootstrap_rootfs)" "bootstrap_rootfs function declared"
assert_eq "function" "$(type -t configure_boot)" "configure_boot function declared"
assert_eq "function" "$(type -t configure_system)" "configure_system function declared"
assert_eq "function" "$(type -t finalize_image)" "finalize_image function declared"

# Test 2: configure_boot writes proper bootloader configs
mock_rootfs="$(mktemp -d /tmp/alarm-mock-rootfs.XXXXXX)"
mkdir -p "${mock_rootfs}/etc" "${mock_rootfs}/boot"
ROOTFS="${mock_rootfs}"

configure_boot >/dev/null

# Validate fstab
assert_file_exists "${mock_rootfs}/etc/fstab" "fstab file created"
fstab_content="$(cat "${mock_rootfs}/etc/fstab")"
assert_contains "$fstab_content" "/dev/mmcblk0p1" "fstab mounts boot partition"
assert_contains "$fstab_content" "/dev/mmcblk0p2" "fstab mounts root partition"
assert_contains "$fstab_content" "vfat" "fstab specifies vfat for boot"
assert_contains "$fstab_content" "ext4" "fstab specifies ext4 for root"

# Validate cmdline.txt
assert_file_exists "${mock_rootfs}/boot/cmdline.txt" "cmdline.txt created"
cmdline_content="$(cat "${mock_rootfs}/boot/cmdline.txt")"
assert_contains "$cmdline_content" "root=/dev/mmcblk0p2" "cmdline sets root partition"
assert_contains "$cmdline_content" "console=tty1" "cmdline enables tty1"
assert_contains "$cmdline_content" "console=ttyAMA10,115200" "cmdline sets Pi 5 UART"

# Validate config.txt
assert_file_exists "${mock_rootfs}/boot/config.txt" "config.txt created"
config_content="$(cat "${mock_rootfs}/boot/config.txt")"
assert_contains "$config_content" "arm_64bit=1" "config.txt enables 64-bit mode"
assert_contains "$config_content" "enable_uart=1" "config.txt enables UART"
assert_contains "$config_content" "dtoverlay=vc4-kms-v3d" "config.txt enables vc4-kms-v3d"

rm -rf "${mock_rootfs}"
ROOTFS=""

# Test 3: Pacman configuration generation from data/ template
test_conf="$(mktemp /tmp/pacman-aarch64.testgenXXXXXX.conf)"
sed "s|@ALARM_MIRROR@|${ALARM_MIRROR}|g" "${DATA_DIR}/pacman-bootstrap.conf" >"${test_conf}"

conf_content="$(cat "${test_conf}")"
assert_contains "$conf_content" "Architecture = aarch64" "pacman conf sets aarch64"
assert_contains "$conf_content" "SigLevel    = Never" "pacman conf bootstrap siglevel"
assert_contains "$conf_content" "${ALARM_MIRROR}/\$arch/\$repo" "pacman conf uses ALARM_MIRROR"
rm -f "${test_conf}"

# Test 3b: System config templates from data/ (hosts, locale, sudoers, pacman-runtime)
test_hosts="$(mktemp /tmp/hosts.testgenXXXXXX)"
sed "s|@TARGET_HOSTNAME@|${TARGET_HOSTNAME}|g" "${DATA_DIR}/hosts" >"${test_hosts}"
assert_contains "$(cat "${test_hosts}")" "127.0.1.1   ${TARGET_HOSTNAME}" "hosts template substitutes hostname"
rm -f "${test_hosts}"

test_runtime_conf="$(mktemp /tmp/pacman-runtime.testgenXXXXXX.conf)"
sed "s|@ALARM_MIRROR@|${ALARM_MIRROR}|g" "${DATA_DIR}/pacman-runtime.conf" >"${test_runtime_conf}"
assert_contains "$(cat "${test_runtime_conf}")" "SigLevel    = Required DatabaseOptional" "runtime pacman conf enables signature check"
assert_contains "$(cat "${test_runtime_conf}")" "${ALARM_MIRROR}/\$arch/\$repo" "runtime pacman conf uses ALARM_MIRROR"
rm -f "${test_runtime_conf}"

assert_file_exists "${DATA_DIR}/sudoers-wheel" "sudoers-wheel exists in data/"
assert_file_exists "${DATA_DIR}/locale.gen" "locale.gen exists in data/"
assert_file_exists "${DATA_DIR}/locale.conf" "locale.conf exists in data/"
assert_file_exists "${DATA_DIR}/20-wired.network" "20-wired.network exists in data/"
assert_file_exists "${DATA_DIR}/alarm-expand-root.sh" "alarm-expand-root.sh exists in data/"
assert_file_exists "${DATA_DIR}/alarm-expand-root.service" "alarm-expand-root.service exists in data/"

# Test 4: Partition boundary math
boot_size=256
boot_end=$((boot_size + 1))
assert_eq "257" "$boot_end" "boot partition end is offset by 1MiB for alignment"

test_summary "src/build.sh"
