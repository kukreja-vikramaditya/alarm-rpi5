#!/usr/bin/env bash
# tests/test_logger.sh — Unit tests for src/logger.sh
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
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

test_summary "src/logger.sh"
