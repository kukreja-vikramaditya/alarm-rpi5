#!/usr/bin/env bash
#
# tests/test_cli.sh — Test suite for build-alarm-rpi5.sh CLI interface and diagnostics
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
BIN="${SCRIPT_DIR}/build-alarm-rpi5.sh"

PASSED=0
FAILED=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  [PASS] %s\n' "$test_name"
        ((PASSED++)) || true
    else
        printf '  [FAIL] %s: expected "%s", got "%s"\n' "$test_name" "$expected" "$actual"
        ((FAILED++)) || true
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  [PASS] %s\n' "$test_name"
        ((PASSED++)) || true
    else
        printf '  [FAIL] %s: expected to contain "%s"\n' "$test_name" "$needle"
        ((FAILED++)) || true
    fi
}

echo "=== Running ALARM RPi 5 Builder Tests ==="
echo ""

# Test 1: Bash syntax check on all entry points and modules
if bash -n "$BIN"; then
    printf '  [PASS] Entry script syntax validation (bash -n)\n'
    ((PASSED++)) || true
else
    printf '  [FAIL] Entry script syntax validation failed\n'
    ((FAILED++)) || true
fi

for mod in "${SCRIPT_DIR}"/src/*.sh; do
    mod_name="$(basename "$mod")"
    if bash -n "$mod"; then
        printf '  [PASS] Module syntax: src/%s (bash -n)\n' "$mod_name"
        ((PASSED++)) || true
    else
        printf '  [FAIL] Module syntax failed: src/%s\n' "$mod_name"
        ((FAILED++)) || true
    fi
done

# Test 2: --help flag exits 0 and displays usage
output="$("$BIN" --help 2>&1 || true)"
assert_contains "$output" "Usage: sudo ./build-alarm-rpi5.sh" "Flag --help displays usage"
assert_contains "$output" "--check" "Flag --help lists --check"
assert_contains "$output" "--interactive" "Flag --help lists --interactive"
assert_contains "$output" "--non-interactive" "Flag --help lists --non-interactive"
assert_contains "$output" "--no-gum" "Flag --help lists --no-gum"

# Test 3: -h flag behaves identically
output="$("$BIN" -h 2>&1 || true)"
assert_contains "$output" "Usage: sudo ./build-alarm-rpi5.sh" "Flag -h displays usage"

# Test 4: Unknown option exits with error
set +e
output="$("$BIN" --bogus-option 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "Unknown flag returns exit code 1"
assert_contains "$output" "Unknown option: --bogus-option" "Unknown flag error message"

# Test 5: Missing argument for options
for opt in "-o" "-v" "-s" "--hostname"; do
    set +e
    output="$("$BIN" "$opt" 2>&1)"
    code=$?
    set -e
    assert_eq "1" "$code" "Missing argument for $opt returns exit code 1"
    assert_contains "$output" "Missing argument for $opt" "Missing argument error for $opt"
done

# Test 6: Running build without root fails at preflight
set +e
output="$("$BIN" 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "Non-root build attempt exits with code 1"
assert_contains "$output" "This script must be run as root" "Non-root error message"

# Test 7: --check diagnostics run without root and report status
set +e
output="$("$BIN" --check 2>&1)"
code=$?
set -e
assert_contains "$output" "Host Environment Diagnostics" "--check header present"
assert_contains "$output" "ALARM mirror reachable" "--check tests mirror connectivity"

# Test 8: --no-gum flag functions correctly in check mode
set +e
output="$("$BIN" --check --no-gum 2>&1)"
code=$?
set -e
assert_contains "$output" "Host Environment Diagnostics" "--no-gum check executes"
assert_contains "$output" "UI library: gum" "--no-gum check displays UI info"

# Test 9: --interactive without a terminal exits cleanly with message
set +e
output="$("$BIN" --interactive 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "--interactive without tty exits with code 1"
assert_contains "$output" "requires an interactive terminal" "--interactive non-tty message"

# Test 10: -y / --non-interactive flag bypasses wizard and proceeds to preflight
set +e
output="$("$BIN" -y 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "-y without root exits at preflight"
assert_contains "$output" "This script must be run as root" "-y preflight message"

# Test 11: Repository structure and modular architecture checks
[[ -f "${SCRIPT_DIR}/README.md" ]] && assert_eq "0" "0" "README.md exists" || assert_eq "0" "1" "README.md exists"
[[ -f "${SCRIPT_DIR}/LICENSE" ]] && assert_eq "0" "0" "LICENSE exists" || assert_eq "0" "1" "LICENSE exists"
[[ -x "$BIN" ]] && assert_eq "0" "0" "build script is executable" || assert_eq "0" "1" "build script is executable"
[[ -L "${SCRIPT_DIR}/build.sh" || -f "${SCRIPT_DIR}/build.sh" ]] && assert_eq "0" "0" "build.sh entry point exists" || assert_eq "0" "1" "build.sh entry point exists"

for mod_name in ui.sh cleanup.sh cli.sh config.sh wizard.sh doctor.sh build.sh; do
    [[ -f "${SCRIPT_DIR}/src/${mod_name}" ]] && assert_eq "0" "0" "src/${mod_name} exists" || assert_eq "0" "1" "src/${mod_name} exists"
done

echo ""
printf "Summary: %d passed, %d failed\n" "$PASSED" "$FAILED"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
