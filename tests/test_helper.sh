#!/usr/bin/env bash
# shellcheck disable=SC2034 # SRC_DIR and test stats are shared with test suites
# tests/test_helper.sh — Shared test assertion helpers and reporting

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
readonly SCRIPT_DIR
readonly SRC_DIR="${SCRIPT_DIR}/src"

PASSED=0
FAILED=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '    [PASS] %s\n' "$test_name"
        ((PASSED++)) || true
    else
        printf '    [FAIL] %s: expected "%s", got "%s"\n' "$test_name" "$expected" "$actual"
        ((FAILED++)) || true
    fi
}

assert_ne() {
    local unexpected="$1"
    local actual="$2"
    local test_name="$3"
    if [[ "$unexpected" != "$actual" ]]; then
        printf '    [PASS] %s\n' "$test_name"
        ((PASSED++)) || true
    else
        printf '    [FAIL] %s: expected not to equal "%s"\n' "$test_name" "$unexpected"
        ((FAILED++)) || true
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '    [PASS] %s\n' "$test_name"
        ((PASSED++)) || true
    else
        printf '    [FAIL] %s: expected to contain "%s"\n' "$test_name" "$needle"
        ((FAILED++)) || true
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf '    [PASS] %s\n' "$test_name"
        ((PASSED++)) || true
    else
        printf '    [FAIL] %s: expected NOT to contain "%s"\n' "$test_name" "$needle"
        ((FAILED++)) || true
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    if [[ -f "$file" || -d "$file" || -L "$file" ]]; then
        printf '    [PASS] %s\n' "$test_name"
        ((PASSED++)) || true
    else
        printf '    [FAIL] %s: file "%s" does not exist\n' "$test_name" "$file"
        ((FAILED++)) || true
    fi
}

assert_file_not_exists() {
    local file="$1"
    local test_name="$2"
    if [[ ! -e "$file" && ! -L "$file" ]]; then
        printf '    [PASS] %s\n' "$test_name"
        ((PASSED++)) || true
    else
        printf '    [FAIL] %s: file "%s" unexpectedly exists\n' "$test_name" "$file"
        ((FAILED++)) || true
    fi
}

test_summary() {
    local suite_name="$1"
    echo ""
    printf '  Results for %s: %d passed, %d failed\n' "$suite_name" "$PASSED" "$FAILED"
    if [[ $FAILED -gt 0 ]]; then
        return 1
    fi
    return 0
}
