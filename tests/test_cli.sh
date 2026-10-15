#!/usr/bin/env bash
# tests/test_cli.sh — Unit tests for src/cli.sh
set -euo pipefail

TEST_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
TEST_DIR="$(dirname -- "${TEST_PATH}")"
# shellcheck source=tests/test_helper.sh
source "${TEST_DIR}/test_helper.sh"

echo "=== Unit Tests: src/cli.sh ==="

# Syntax validation
if bash -n "${SRC_DIR}/cli.sh"; then
    assert_eq "0" "0" "src/cli.sh syntax validation (bash -n)"
else
    assert_eq "0" "1" "src/cli.sh syntax validation (bash -n)"
fi

# Source dependencies
# shellcheck source=src/terminal.sh
source "${SRC_DIR}/terminal.sh"
# shellcheck source=src/logger.sh
source "${SRC_DIR}/logger.sh"
# shellcheck source=src/cli.sh
source "${SRC_DIR}/cli.sh"

# Test 1: usage() output contains key documentation
usage_txt="$(SCRIPT_NAME="build.sh" usage)"
assert_contains "$usage_txt" "Usage: sudo ./build.sh [OPTIONS]" "usage lists correct command"
assert_contains "$usage_txt" "--check" "usage lists --check"
assert_contains "$usage_txt" "--interactive" "usage lists --interactive"
assert_contains "$usage_txt" "--non-interactive" "usage lists --non-interactive"
assert_contains "$usage_txt" "--output-dir" "usage lists --output-dir"
assert_contains "$usage_txt" "--version" "usage lists --version"
assert_contains "$usage_txt" "--img-size" "usage lists --img-size"
assert_contains "$usage_txt" "--hostname" "usage lists --hostname"
assert_contains "$usage_txt" "--no-compress" "usage lists --no-compress"

# Helper to reset cli arg globals before each test
reset_args() {
    _arg_check=""
    _arg_interactive=""
    _arg_non_interactive=""
    _arg_output_dir=""
    _arg_version=""
    _arg_img_size=""
    _arg_hostname=""
    _arg_user=""
    _arg_password=""
    _arg_root_user=""
    _arg_root_password=""
    _arg_no_compress=""
}

# Test 2: parse_cli flags
reset_args
parse_cli "--check"
assert_eq "1" "$_arg_check" "parse_cli sets _arg_check for --check"

reset_args
parse_cli "-c"
assert_eq "1" "$_arg_check" "parse_cli sets _arg_check for -c"

reset_args
parse_cli "--interactive"
assert_eq "1" "$_arg_interactive" "parse_cli sets _arg_interactive for --interactive"

reset_args
parse_cli "-i"
assert_eq "1" "$_arg_interactive" "parse_cli sets _arg_interactive for -i"

reset_args
parse_cli "--non-interactive"
assert_eq "1" "$_arg_non_interactive" "parse_cli sets _arg_non_interactive for --non-interactive"

reset_args
parse_cli "-y"
assert_eq "1" "$_arg_non_interactive" "parse_cli sets _arg_non_interactive for -y"

reset_args
parse_cli "--batch"
assert_eq "1" "$_arg_non_interactive" "parse_cli sets _arg_non_interactive for --batch"

reset_args
parse_cli "--output-dir" "/custom/dist"
assert_eq "/custom/dist" "$_arg_output_dir" "parse_cli sets _arg_output_dir for --output-dir"

reset_args
parse_cli "-o" "/custom/dist2"
assert_eq "/custom/dist2" "$_arg_output_dir" "parse_cli sets _arg_output_dir for -o"

reset_args
parse_cli "--version" "2.5.0"
assert_eq "2.5.0" "$_arg_version" "parse_cli sets _arg_version for --version"

reset_args
parse_cli "-v" "3.0.0"
assert_eq "3.0.0" "$_arg_version" "parse_cli sets _arg_version for -v"

reset_args
parse_cli "--img-size" "16G"
assert_eq "16G" "$_arg_img_size" "parse_cli sets _arg_img_size for --img-size"

reset_args
parse_cli "-s" "8G"
assert_eq "8G" "$_arg_img_size" "parse_cli sets _arg_img_size for -s"

reset_args
parse_cli "--hostname" "picluster"
assert_eq "picluster" "$_arg_hostname" "parse_cli sets _arg_hostname for --hostname"

reset_args
parse_cli "-u" "myuser"
assert_eq "myuser" "$_arg_user" "parse_cli sets _arg_user for -u"

reset_args
parse_cli "--user" "vikram"
assert_eq "vikram" "$_arg_user" "parse_cli sets _arg_user for --user"

reset_args
parse_cli "--username" "customuser"
assert_eq "customuser" "$_arg_user" "parse_cli sets _arg_user for --username"

reset_args
parse_cli "-p" "mypass123"
assert_eq "mypass123" "$_arg_password" "parse_cli sets _arg_password for -p"

reset_args
parse_cli "--password" "secretpwd"
assert_eq "secretpwd" "$_arg_password" "parse_cli sets _arg_password for --password"

reset_args
parse_cli "--root-user" "admin"
assert_eq "admin" "$_arg_root_user" "parse_cli sets _arg_root_user for --root-user"

reset_args
parse_cli "--root-password" "adminpass"
assert_eq "adminpass" "$_arg_root_password" "parse_cli sets _arg_root_password for --root-password"

reset_args
parse_cli "--no-compress"
assert_eq "1" "$_arg_no_compress" "parse_cli sets _arg_no_compress for --no-compress"

# Test 3: Multiple combined flags
reset_args
parse_cli -y -v 1.2.3 -s 8G --hostname node01 -u vikram -p pass123 --no-compress
assert_eq "1" "$_arg_non_interactive" "combined flags: -y"
assert_eq "1.2.3" "$_arg_version" "combined flags: -v"
assert_eq "8G" "$_arg_img_size" "combined flags: -s"
assert_eq "node01" "$_arg_hostname" "combined flags: --hostname"
assert_eq "vikram" "$_arg_user" "combined flags: -u"
assert_eq "pass123" "$_arg_password" "combined flags: -p"
assert_eq "1" "$_arg_no_compress" "combined flags: --no-compress"

# Test 4: Missing arguments
for opt in "-o" "--output-dir" "-v" "--version" "-s" "--img-size" "--hostname" "-u" "--user" "--username" "-p" "--password" "--root-user" "--root-password"; do
    set +e
    err_out="$(parse_cli "$opt" 2>&1)"
    code=$?
    set -e
    assert_eq "1" "$code" "missing arg for $opt exits with 1"
    assert_contains "$err_out" "Missing argument for $opt" "missing arg error message for $opt"
done

# Test 5: Unknown flag
set +e
err_out="$(parse_cli "--unknown-flag" 2>&1)"
code=$?
set -e
assert_eq "1" "$code" "unknown flag exits with 1"
assert_contains "$err_out" "Unknown option: --unknown-flag" "unknown flag error message"

# Test 6: Help flags exit 0
set +e
help_out="$(parse_cli --help 2>&1)"
help_code=$?
set -e
assert_eq "0" "$help_code" "parse_cli --help exits with 0"
assert_contains "$help_out" "Usage: sudo" "--help prints usage"

set +e
h_out="$(parse_cli -h 2>&1)"
h_code=$?
set -e
assert_eq "0" "$h_code" "parse_cli -h exits with 0"
assert_contains "$h_out" "Usage: sudo" "-h prints usage"

test_summary "src/cli.sh"
