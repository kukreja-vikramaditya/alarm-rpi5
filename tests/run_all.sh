#!/usr/bin/env bash
# tests/run_all.sh — Master test runner for all unit and integration test suites
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

echo "═══════════════════════════════════════════════════════════════"
echo "  Running ALARM Raspberry Pi 5 Unit & Integration Test Suites   "
echo "═══════════════════════════════════════════════════════════════"
echo ""

SUITES=(
    "test_lint.sh"       # Linter and formatting validation
    "test_terminal.sh"   # src/terminal.sh
    "test_logger.sh"     # src/logger.sh
    "test_cleanup.sh"    # src/cleanup.sh
    "test_cli.sh"        # src/cli.sh
    "test_config.sh"     # src/config.sh
    "test_wizard.sh"     # src/wizard.sh
    "test_doctor.sh"     # src/doctor.sh
    "test_build.sh"      # src/build.sh
    "test_entrypoint.sh" # build-alarm-rpi5.sh & build.sh
)

for suite in "${SUITES[@]}"; do
    suite_path="${TEST_DIR}/${suite}"
    if [[ ! -x "$suite_path" ]]; then
        chmod +x "$suite_path"
    fi

    ((TOTAL_SUITES++)) || true
    set +e
    "$suite_path"
    code=$?
    set -e

    if [[ $code -eq 0 ]]; then
        ((PASSED_SUITES++)) || true
    else
        ((FAILED_SUITES++)) || true
        printf '\n  ✖ FAILED SUITE: %s (exit code %d)\n\n' "$suite" "$code"
    fi
    echo ""
done

echo "═══════════════════════════════════════════════════════════════"
echo "  TEST SUITES SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
printf "  Total Suites:  %d\n" "$TOTAL_SUITES"
printf "  Passed Suites: %d\n" "$PASSED_SUITES"
printf "  Failed Suites: %d\n" "$FAILED_SUITES"
echo "═══════════════════════════════════════════════════════════════"

if [[ $FAILED_SUITES -gt 0 ]]; then
    exit 1
fi
exit 0
