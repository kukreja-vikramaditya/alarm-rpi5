#!/usr/bin/env bash
# tests/test_terminal.sh — Unit tests for src/terminal.sh
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/terminal.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/terminal.sh"; then
    assert_eq "0" "0" "src/terminal.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/terminal.sh syntax validation (bash -n)"
fi

# Source terminal module
# shellcheck source=src/terminal.sh
source "${SRC_DIR}/terminal.sh"

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

# Test 2: run_spin executes command successfully
spin_out="$(run_spin "Running echo test" echo "spin_success")"
assert_contains "$spin_out" "spin_success" "run_spin executes passed command"

# Test 3: find_gum_binary returns path or fails cleanly
set +e
gum_path="$(find_gum_binary 2>/dev/null)"
gum_code=$?
set -e
if [[ $gum_code -eq 0 ]]; then
    assert_contains "$gum_path" "gum" "find_gum_binary returns path containing gum"
else
    assert_eq "1" "$gum_code" "find_gum_binary returns 1 when gum not found"
fi

# Test 4: GUM_INITIALIZED flag is set
assert_eq "1" "${GUM_INITIALIZED:-0}" "GUM_INITIALIZED flag is set"

test_summary "src/terminal.sh"
