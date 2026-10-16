#!/usr/bin/env bash
# tests/test_wizard.sh — Unit tests for standalone wizard.sh
set -euo pipefail

TEST_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
TEST_DIR="$(dirname -- "${TEST_PATH}")"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

WIZARD_BIN="${SCRIPT_DIR}/wizard.sh"

echo "=== Unit Tests: Standalone Interactive TUI (wizard.sh) ==="

# Test 1: Syntax validation
if bash -n "$WIZARD_BIN"; then
    assert_eq "0" "0" "wizard.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "wizard.sh syntax validation (bash -n)"
fi

for mod in config.sh gum.sh bash.sh; do
    mod_path="${SCRIPT_DIR}/wizard/${mod}"
    assert_file_exists "$mod_path" "wizard/${mod} exists"
    if bash -n "$mod_path"; then
        assert_eq "0" "0" "wizard/${mod} syntax validation (bash -n)"
    else
        assert_eq "0" "1" "wizard/${mod} syntax validation (bash -n)"
    fi
done

# Test 2: File exists and permissions
assert_file_exists "$WIZARD_BIN" "wizard.sh exists"
if [[ -x "$WIZARD_BIN" ]]; then
    assert_eq "0" "0" "wizard.sh is executable"
else
    assert_eq "0" "1" "wizard.sh is executable"
fi

# Test 3: Help flags
help_out="$("$WIZARD_BIN" --help)"
assert_contains "$help_out" "Usage: ./wizard.sh" "wizard.sh --help displays usage"
assert_contains "$help_out" "--bash" "wizard.sh lists --bash option"
assert_contains "$help_out" "--dry-run" "wizard.sh lists --dry-run option"

h_out="$("$WIZARD_BIN" -h)"
assert_contains "$h_out" "Usage: ./wizard.sh" "wizard.sh -h displays usage"

# Test 4: Unknown flag exits with error
set +e
err_flag="$("$WIZARD_BIN" --unknown-option 2>&1)"
flag_code=$?
set -e
assert_eq "1" "$flag_code" "unknown option exits 1"
assert_contains "$err_flag" "Unknown option" "unknown option error message"

# Test 5: Non-TTY guard
set +e
err_out="$("$WIZARD_BIN" </dev/null 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "wizard.sh dies when invoked without interactive terminal"
assert_contains "$err_out" "requires an interactive terminal" "correct non-tty error message"

# Test 6: Bash fallback mode processes inputs and builds executable command
set +e
out="$( (
    "$WIZARD_BIN" --bash --dry-run <<EOF
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
) 2>&1)"
dry_code=$?
set -e
assert_eq "0" "$dry_code" "wizard.sh --bash --dry-run exits with 0 on confirmation"
assert_contains "$out" "Version:          0.9.0" "wizard summary updates VERSION"
assert_contains "$out" "Hostname:         rpi5-test" "wizard summary updates TARGET_HOSTNAME"
assert_contains "$out" "Root User:        rootadmin" "wizard summary updates ROOT_USER"
assert_contains "$out" "Non-Root User:    tester" "wizard summary updates ALARM_USER"
assert_contains "$out" "Image Size:       8G" "wizard summary updates IMG_SIZE"
assert_contains "$out" "Compressed:       1 (xz)" "wizard summary sets COMPRESS to 1 on 'y'"
assert_contains "$out" "Executable Command:" "wizard summary includes Executable Command"
assert_contains "$out" "./build.sh -y -v \"0.9.0\" --hostname \"rpi5-test\" --root-user \"rootadmin\" -u \"tester\" -s \"8G\"" "command includes customized inputs"
assert_contains "$out" "Dry run enabled. Executable command:" "dry run message printed"

# Test 7: Compression disabled handling
set +e
no_comp_out="$( (
    "$WIZARD_BIN" --bash --dry-run <<EOF







n
y
EOF
) 2>&1)"
no_comp_code=$?
set -e
assert_eq "0" "$no_comp_code" "wizard handles disabled compression cleanly"
assert_contains "$no_comp_out" "Compressed:       0 (xz)" "wizard summary sets COMPRESS to 0 on 'n'"
assert_contains "$no_comp_out" "--no-compress" "executable command includes --no-compress"

# Test 8: Cancellation when user declines confirmation
set +e
cancel_out="$( (
    "$WIZARD_BIN" --bash <<EOF
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
assert_contains "$cancel_out" "./build.sh -y" "wizard summary includes executable CLI command"

test_summary "wizard.sh"
