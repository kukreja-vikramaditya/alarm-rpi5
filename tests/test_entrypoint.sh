#!/usr/bin/env bash
# tests/test_entrypoint.sh — Unit & integration tests for root entry points
set -euo pipefail

TEST_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
TEST_DIR="$(dirname -- "${TEST_PATH}")"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

BIN="${SCRIPT_DIR}/build.sh"

echo "=== Unit Tests: Root Entry Point (build.sh) ==="

# Test 1: Bash syntax validation
if bash -n "$BIN"; then
    assert_eq "0" "0" "build.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "build.sh syntax validation (bash -n)"
fi

# Test 2: File permissions
assert_file_exists "$BIN" "build.sh exists"
if [[ -x "$BIN" ]]; then
    assert_eq "0" "0" "build.sh is executable"
else
    assert_eq "0" "1" "build.sh is executable"
fi

# Test 3: --help and -h flags
out="$("$BIN" --help 2>&1 || true)"
assert_contains "$out" "Usage: sudo ./build.sh" "Flag --help displays usage"
assert_contains "$out" "--check" "Flag --help lists --check"
assert_contains "$out" "--interactive" "Flag --help lists --interactive"
assert_contains "$out" "--non-interactive" "Flag --help lists --non-interactive"

out_h="$("$BIN" -h 2>&1 || true)"
assert_contains "$out_h" "Usage: sudo ./build.sh" "Flag -h displays usage"

# Test 4: Unknown flags exit 1
set +e
err_out="$("$BIN" --invalid-flag 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "unknown flag exits 1"
assert_contains "$err_out" "Unknown option: --invalid-flag" "unknown flag error message"

# Test 5: Missing arguments for options
for opt in "-o" "-v" "-s" "--hostname"; do
    set +e
    err_out="$("$BIN" "$opt" 2>&1)"
    code=$?
    set -e
    assert_eq "1" "$code" "missing arg for $opt exits 1"
    assert_contains "$err_out" "Missing argument for $opt" "missing arg error message"
done

# Test 6: Non-root invocation
set +e
out="$("$BIN" 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "non-root build attempt exits with code 1"
assert_contains "$out" "This script must be run as root" "non-root error message"

# Test 7: Non-tty interactive invocation
set +e
out="$("$BIN" --interactive 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "--interactive without tty exits with code 1"
assert_contains "$out" "requires an interactive terminal" "--interactive non-tty message"

# Test 8: Non-interactive batch flag (-y) without root
set +e
out="$("$BIN" -y 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "-y without root exits with code 1"
assert_contains "$out" "This script must be run as root" "-y non-root message"

# Test 9: --check diagnostics execution
set +e
out="$("$BIN" --check 2>&1)"
code=$?
set -e
assert_contains "$out" "Host Environment Diagnostics" "--check header present"
assert_contains "$out" "ALARM mirror reachable" "--check tests mirror connectivity"

# Test 10: Docker entrypoints
assert_file_exists "${SCRIPT_DIR}/Dockerfile" "Dockerfile exists"
assert_file_exists "${SCRIPT_DIR}/docker-build.sh" "docker-build.sh exists"
if [[ -x "${SCRIPT_DIR}/docker-build.sh" ]]; then
    assert_eq "0" "0" "docker-build.sh is executable"
else
    assert_eq "0" "1" "docker-build.sh is executable"
fi
if bash -n "${SCRIPT_DIR}/docker-build.sh"; then
    assert_eq "0" "0" "docker-build.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "docker-build.sh syntax validation (bash -n)"
fi

test_summary "Root Entry Points"
