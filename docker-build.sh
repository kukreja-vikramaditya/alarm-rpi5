#!/usr/bin/env bash
# ==============================================================================
# docker-build.sh — Convenience alias for ./build.sh
# ==============================================================================
set -euo pipefail

SCRIPT_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "${SCRIPT_PATH}")"

exec "${SCRIPT_DIR}/build.sh" "$@"
