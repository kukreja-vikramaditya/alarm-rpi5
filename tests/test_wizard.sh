#!/usr/bin/env bash
# tests/test_wizard.sh — Unit tests for src/wizard.sh
set -euo pipefail

TEST_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
TEST_DIR="$(dirname -- "${TEST_PATH}")"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/wizard.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/wizard.sh"; then
    assert_eq "0" "0" "src/wizard.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/wizard.sh syntax validation (bash -n)"
fi

# Source dependencies
# shellcheck source=src/terminal.sh
source "${SRC_DIR}/terminal.sh"
# shellcheck source=src/logger.sh
source "${SRC_DIR}/logger.sh"
# shellcheck source=src/config.sh
source "${SRC_DIR}/config.sh"
# shellcheck source=src/wizard.sh
source "${SRC_DIR}/wizard.sh"

init_config

# Test 1: interactive_wizard non-tty guard returns 0 when not explicit
_arg_interactive=""
set +e
interactive_wizard </dev/null
code=$?
set -e
assert_eq "0" "$code" "interactive_wizard returns 0 when not on a TTY and no explicit flag"

# Test 2: interactive_wizard non-tty guard dies when explicit --interactive is given
_arg_interactive="1"
set +e
err_out="$(interactive_wizard </dev/null 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "interactive_wizard dies when --interactive without TTY"
assert_contains "$err_out" "Interactive mode requires an interactive terminal" "correct non-tty error message"
_arg_interactive=""

# Test 3: interactive_wizard_bash processes inputs properly
VERSION="0.1.0"
TARGET_HOSTNAME="raspberrypi"
ROOT_USER="root"
ROOT_PASSWORD="root"
ALARM_USER="alarm"
ALARM_PASSWORD="alarm"
IMG_SIZE="4G"
COMPRESS=1

interactive_wizard_bash <<EOF >/dev/null
0.9.0
rpi5-test
rootadmin
root123
tester
user123
8G
y
y
EOF

assert_eq "0.9.0" "$VERSION" "wizard updates VERSION"
assert_eq "rpi5-test" "$TARGET_HOSTNAME" "wizard updates TARGET_HOSTNAME"
assert_eq "rootadmin" "$ROOT_USER" "wizard updates ROOT_USER"
assert_eq "root123" "$ROOT_PASSWORD" "wizard updates ROOT_PASSWORD"
assert_eq "tester" "$ALARM_USER" "wizard updates ALARM_USER"
assert_eq "user123" "$ALARM_PASSWORD" "wizard updates ALARM_PASSWORD"
assert_eq "8G" "$IMG_SIZE" "wizard updates IMG_SIZE"
assert_eq "1" "$COMPRESS" "wizard sets COMPRESS to 1 on 'y'"

# Test 4: interactive_wizard_bash handles compression disabled
COMPRESS=1
interactive_wizard_bash <<EOF >/dev/null







n
y
EOF
assert_eq "0" "$COMPRESS" "wizard sets COMPRESS to 0 on 'n'"

# Test 5: interactive_wizard_bash cancellation when user declines confirmation
set +e
cancel_out="$( (
    interactive_wizard_bash <<EOF
0.1.0
raspberrypi
root

alarm

4G
y
n
EOF
) 2>&1)"
cancel_code=$?
set -e
assert_eq "0" "$cancel_code" "wizard exits 0 when cancelled"
assert_contains "$cancel_out" "Build cancelled by user" "wizard prints cancellation message"
assert_contains "$cancel_out" "Executable Command:" "wizard summary includes Executable Command"
assert_contains "$cancel_out" "sudo ./build.sh -y" "wizard summary includes executable CLI command"

test_summary "src/wizard.sh"
