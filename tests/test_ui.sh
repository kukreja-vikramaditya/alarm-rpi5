#!/usr/bin/env bash
# tests/test_ui.sh — Unit tests for src/ui.sh
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/ui.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/ui.sh"; then
    assert_eq "0" "0" "src/ui.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/ui.sh syntax validation (bash -n)"
fi

# Source ui module
# shellcheck source=src/ui.sh
source "${SRC_DIR}/ui.sh"

# Test 1: format_badge outputs
badge_ok="$(format_badge OK)"
assert_contains "$badge_ok" "OK" "format_badge OK contains OK"

badge_missing="$(format_badge MISSING)"
assert_contains "$badge_missing" "MISSING" "format_badge MISSING contains MISSING"

badge_warn="$(format_badge WARN)"
assert_contains "$badge_warn" "WARN" "format_badge WARN contains WARN"

badge_info="$(format_badge INFO)"
assert_contains "$badge_info" "INFO" "format_badge INFO contains INFO"

badge_custom="$(format_badge CUSTOM)"
assert_contains "$badge_custom" "CUSTOM" "format_badge fallback formats correctly"

# Test 2: Logging functions
info_out="$(log_info "hello info" 2>&1)"
assert_contains "$info_out" "hello info" "log_info prints message"

warn_out="$(log_warn "hello warn" 2>&1)"
assert_contains "$warn_out" "hello warn" "log_warn prints message"

error_out="$(log_error "hello error" 2>&1)"
assert_contains "$error_out" "hello error" "log_error prints message"

phase_out="$(log_phase "Phase Test" 2>&1)"
assert_contains "$phase_out" "Phase Test" "log_phase prints phase header"

# Test 3: Plain text _log output format
raw_log="$(_log "TEST" "message content")"
assert_contains "$raw_log" "[TEST ] message content" "_log formats level and message"

# Test 4: run_spin executes command successfully
spin_out="$(run_spin "Running echo test" echo "spin_success")"
assert_contains "$spin_out" "spin_success" "run_spin executes passed command"

# Test 5: die function exits with status 1 and error output
set +e
die_out="$( (die "fatal failure message") 2>&1)"
die_code=$?
set -e
assert_eq "1" "$die_code" "die exits with code 1"
assert_contains "$die_out" "fatal failure message" "die outputs error message"

# Test 6: find_gum_binary returns path or fails cleanly
set +e
gum_path="$(find_gum_binary 2>/dev/null)"
gum_code=$?
set -e
if [[ $gum_code -eq 0 ]]; then
    assert_contains "$gum_path" "gum" "find_gum_binary returns path containing gum"
else
    assert_eq "1" "$gum_code" "find_gum_binary returns 1 when gum not found"
fi

test_summary "src/ui.sh"
