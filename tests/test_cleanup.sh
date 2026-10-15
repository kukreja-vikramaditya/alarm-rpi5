#!/usr/bin/env bash
# tests/test_cleanup.sh — Unit tests for src/cleanup.sh
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/cleanup.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/cleanup.sh"; then
    assert_eq "0" "0" "src/cleanup.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/cleanup.sh syntax validation (bash -n)"
fi

# Source dependencies and module
# shellcheck source=src/ui.sh
source "${SRC_DIR}/ui.sh"
# shellcheck source=src/cleanup.sh
source "${SRC_DIR}/cleanup.sh"

# Test 1: cleanup removes ROOTFS directory
test_rootfs="$(mktemp -d /tmp/alarm-rootfs.unitXXXXXX)"
ROOTFS="$test_rootfs"
assert_file_exists "$test_rootfs" "temporary test ROOTFS directory created"
cleanup
assert_file_not_exists "$test_rootfs" "cleanup removes ROOTFS directory"
assert_eq "" "$ROOTFS" "cleanup resets ROOTFS variable to empty"

# Test 2: cleanup removes PACMAN_CONF file
test_conf="$(mktemp /tmp/pacman-aarch64.unitXXXXXX.conf)"
PACMAN_CONF="$test_conf"
assert_file_exists "$test_conf" "temporary test PACMAN_CONF file created"
cleanup
assert_file_not_exists "$test_conf" "cleanup removes PACMAN_CONF file"
assert_eq "" "$PACMAN_CONF" "cleanup resets PACMAN_CONF variable to empty"

# Test 3: cleanup is idempotent when called multiple times
set +e
cleanup
first_code=$?
cleanup
second_code=$?
set -e
assert_eq "0" "$first_code" "cleanup runs safely first time"
assert_eq "0" "$second_code" "cleanup runs idempotently second time"

# Test 4: cleanup_previous_run cleans orphaned directories in /tmp
stale_dir1="$(mktemp -d /tmp/alarm-rootfs.stale1XXXXXX)"
stale_dir2="$(mktemp -d /tmp/alarm-rootfs.stale2XXXXXX)"
assert_file_exists "$stale_dir1" "stale dir 1 created"
assert_file_exists "$stale_dir2" "stale dir 2 created"
cleanup_previous_run
assert_file_not_exists "$stale_dir1" "cleanup_previous_run deletes stale dir 1"
assert_file_not_exists "$stale_dir2" "cleanup_previous_run deletes stale dir 2"

# Test 5: cleanup_previous_run cleans orphaned pacman configs in /tmp
stale_conf1="$(mktemp /tmp/pacman-aarch64.stale1XXXXXX.conf)"
stale_conf2="$(mktemp /tmp/pacman-aarch64.stale2XXXXXX.conf)"
assert_file_exists "$stale_conf1" "stale conf 1 created"
assert_file_exists "$stale_conf2" "stale conf 2 created"
cleanup_previous_run
assert_file_not_exists "$stale_conf1" "cleanup_previous_run deletes stale conf 1"
assert_file_not_exists "$stale_conf2" "cleanup_previous_run deletes stale conf 2"

# Test 6: clean_stale_temp_files backwards compatibility alias
stale_alias="$(mktemp /tmp/pacman-aarch64.aliasXXXXXX.conf)"
assert_file_exists "$stale_alias" "alias test conf created"
clean_stale_temp_files
assert_file_not_exists "$stale_alias" "clean_stale_temp_files alias works"

test_summary "src/cleanup.sh"
