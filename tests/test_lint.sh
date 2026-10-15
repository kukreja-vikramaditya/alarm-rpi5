#!/usr/bin/env bash
# tests/test_lint.sh — Linter and code formatting validation suite

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=tests/test_helper.sh
source "${SCRIPT_DIR}/test_helper.sh"

echo "=== Unit Tests: Shell Linting & Formatting ==="

TARGET_SCRIPTS=(
    "${SCRIPT_DIR}/build-alarm-rpi5.sh"
    "${SRC_DIR}/"*.sh
    "${SCRIPT_DIR}/tests/"*.sh
)

# Test 1: ShellCheck validation
if command -v shellcheck &>/dev/null; then
    sc_out="$(shellcheck -x "${TARGET_SCRIPTS[@]}" 2>&1 || true)"
    if [[ -z "$sc_out" ]]; then
        assert_eq "0" "0" "shellcheck passes cleanly on all scripts"
    else
        echo "$sc_out"
        assert_eq "0" "1" "shellcheck passes cleanly on all scripts"
    fi
else
    echo "    [SKIP] shellcheck not found in PATH"
fi

# Test 2: shfmt formatting validation
if command -v shfmt &>/dev/null; then
    fmt_diff="$(shfmt -d -i 4 -ci "${TARGET_SCRIPTS[@]}" 2>&1 || true)"
    if [[ -z "$fmt_diff" ]]; then
        assert_eq "0" "0" "shfmt -i 4 -ci formatting is consistent on all scripts"
    else
        echo "$fmt_diff"
        assert_eq "0" "1" "shfmt -i 4 -ci formatting is consistent on all scripts"
    fi
else
    echo "    [SKIP] shfmt not found in PATH"
fi

test_summary "Linting & Formatting"
