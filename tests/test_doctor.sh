#!/usr/bin/env bash
# tests/test_doctor.sh — Unit tests for src/doctor.sh
set -euo pipefail

TEST_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
TEST_DIR="$(dirname -- "${TEST_PATH}")"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/doctor.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/doctor.sh"; then
    assert_eq "0" "0" "src/doctor.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/doctor.sh syntax validation (bash -n)"
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
# shellcheck source=src/doctor.sh
source "${SRC_DIR}/doctor.sh"

init_config

# Test 1: get_pkg_for_cmd mappings
assert_eq "sudo pacman -S parted" "$(get_pkg_for_cmd parted)" "package mapping for parted"
assert_eq "sudo pacman -S dosfstools" "$(get_pkg_for_cmd mkfs.vfat)" "package mapping for mkfs.vfat"
assert_eq "sudo pacman -S arch-install-scripts" "$(get_pkg_for_cmd pacstrap)" "package mapping for pacstrap"
assert_eq "sudo pacman -S arch-install-scripts" "$(get_pkg_for_cmd arch-chroot)" "package mapping for arch-chroot"
assert_eq "sudo pacman -S e2fsprogs" "$(get_pkg_for_cmd mkfs.ext4)" "package mapping for mkfs.ext4"
assert_eq "sudo pacman -S e2fsprogs" "$(get_pkg_for_cmd tune2fs)" "package mapping for tune2fs"
assert_eq "sudo pacman -S util-linux" "$(get_pkg_for_cmd losetup)" "package mapping for losetup"
assert_eq "sudo pacman -S xz" "$(get_pkg_for_cmd xz)" "package mapping for xz"
assert_eq "sudo pacman -S coreutils" "$(get_pkg_for_cmd truncate)" "package mapping for truncate"
assert_contains "$(get_pkg_for_cmd randomcmd)" "package providing randomcmd" "fallback package mapping"

# Test 2: check_environment executes and checks mirror & tools
set +e
check_out="$(check_environment 2>&1)"
check_code=$?
set -e
assert_eq "0" "$((check_code == 0 || check_code == 1 ? 0 : check_code))" "check_environment returns valid exit code (0 or 1)"
assert_contains "$check_out" "Host Environment Diagnostics" "check_environment prints header"
assert_contains "$check_out" "Tool:" "check_environment inspects tools"
assert_contains "$check_out" "ALARM mirror reachable" "check_environment tests mirror"
assert_contains "$check_out" "Output dir writable" "check_environment checks output dir"

# Test 3: preflight enforces root privileges
set +e
pre_out="$(MOCK_EUID=1000 preflight 2>&1)"
pre_code=$?
set -e
assert_eq "1" "$pre_code" "preflight exits 1 when non-root"
assert_contains "$pre_out" "This script must be run as root" "preflight root error message"

test_summary "src/doctor.sh"
