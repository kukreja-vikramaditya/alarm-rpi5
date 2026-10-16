#!/usr/bin/env bash
# wizard.sh — Entry point for Standalone Interactive Command Generator
#
# Prompts for build configurations using Charm Gum (or Bash fallback)
# and constructs the exact ./build.sh command to execute. Keeps interactive UI
# completely separate from core build logic.

set -euo pipefail

SCRIPT_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "${SCRIPT_PATH}")"
readonly SCRIPT_PATH
readonly SCRIPT_DIR
readonly WIZARD_DIR="${SCRIPT_DIR}/wizard"

GUM_BIN="$(command -v gum 2>/dev/null || echo "gum")"
readonly GUM_BIN

FORCE_BASH=0
DRY_RUN=0
VERSION="${VERSION:-0.0.0-snapshot}"

# Source modular wizard components
# shellcheck source=wizard/config.sh
source "${WIZARD_DIR}/config.sh"
# shellcheck source=wizard/gum.sh
source "${WIZARD_DIR}/gum.sh"
# shellcheck source=wizard/bash.sh
source "${WIZARD_DIR}/bash.sh"

main() {
    # 1. Parse CLI arguments (--bash, --dry-run, --help)
    parse_wizard_cli "$@"

    # 2. Load configuration defaults from VERSION and alarm.conf
    load_wizard_defaults

    # 3. Launch interactive prompt flow
    if [[ "${FORCE_BASH}" -eq 0 && -n "$(command -v gum 2>/dev/null)" ]]; then
        wizard_gum
    else
        wizard_bash
    fi
}

main "$@"
