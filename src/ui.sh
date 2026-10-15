#!/usr/bin/env bash
# src/ui.sh — Facade combining terminal styling and structured logging

UI_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=src/terminal.sh
source "${UI_SCRIPT_DIR}/terminal.sh"
# shellcheck source=src/logger.sh
source "${UI_SCRIPT_DIR}/logger.sh"
