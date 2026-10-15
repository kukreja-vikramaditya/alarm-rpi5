#!/usr/bin/env bash
# tests/test_logger.sh — Unit tests for src/logger.sh
set -euo pipefail

TEST_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
TEST_DIR="$(dirname -- "${TEST_PATH}")"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/logger.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/logger.sh"; then
    assert_eq "0" "0" "src/logger.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/logger.sh syntax validation (bash -n)"
fi

# Source logger module
# shellcheck source=src/logger.sh
source "${SRC_DIR}/logger.sh"

# Test 1: Logging functions
info_out="$(log_info "hello info" 2>&1)"
assert_contains "$info_out" "hello info" "log_info prints message"

warn_out="$(log_warn "hello warn" 2>&1)"
assert_contains "$warn_out" "hello warn" "log_warn prints message"

error_out="$(log_error "hello error" 2>&1)"
assert_contains "$error_out" "hello error" "log_error prints message"

phase_out="$(log_phase "Phase Test" 2>&1)"
assert_contains "$phase_out" "Phase Test" "log_phase prints phase header"

# Test 2: Plain text _log output format
raw_log="$(_log "TEST" "message content")"
assert_contains "$raw_log" "[TEST ] message content" "_log formats level and message"

# Test 3: die function exits with status 1 and error output
set +e
die_out="$( (die "fatal failure message") 2>&1)"
die_code=$?
set -e
assert_eq "1" "$die_code" "die exits with code 1"
assert_contains "$die_out" "fatal failure message" "die outputs error message"

# Test 4: Format string substitution (Java String.format equivalent)
formatted_str=""
format_string formatted_str "User '%s' executed step %d of %d (status: %s)" "alarm" 2 5 "success"
assert_eq "User 'alarm' executed step 2 of 5 (status: success)" "$formatted_str" "format_string substitutes template variables"

# Test 5: Template-based logging functions
tpl_info="$(log_info "Sparse image allocated: %s (size: %s)" "/tmp/img.raw" "3G" 2>&1)"
assert_contains "$tpl_info" "Sparse image allocated: /tmp/img.raw (size: 3G)" "log_info supports template formatting"

tpl_warn="$(log_warn "Device %s has %d bad blocks" "/dev/sda" 0 2>&1)"
assert_contains "$tpl_warn" "Device /dev/sda has 0 bad blocks" "log_warn supports template formatting"

tpl_err="$(log_error "Connection failed to %s on port %d" "archlinuxarm.org" 443 2>&1)"
assert_contains "$tpl_err" "Connection failed to archlinuxarm.org on port 443" "log_error supports template formatting"

tpl_phase="$(log_phase "Phase %d/%d — %s" 1 5 "Setup" 2>&1)"
assert_contains "$tpl_phase" "Phase 1/5 — Setup" "log_phase supports template formatting"

set +e
tpl_die="$( (die "Critical error code %d: %s" 404 "Not Found") 2>&1)"
tpl_die_code=$?
set -e
assert_eq "1" "$tpl_die_code" "die with template exits with code 1"
assert_contains "$tpl_die" "Critical error code 404: Not Found" "die supports template formatting"

test_summary "src/logger.sh"
