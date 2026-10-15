#!/usr/bin/env bash
# ==============================================================================
# docker-build.sh — Build ALARM Raspberry Pi 5 Image inside isolated Docker container
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG="alarm-rpi5-builder:latest"

# Check docker availability
if ! command -v docker &>/dev/null; then
    echo "ERROR: 'docker' command not found." >&2
    echo "Please ensure Docker is installed and running." >&2
    echo "If using Docker Desktop on Windows with WSL 2, enable WSL Integration in:" >&2
    echo "  Docker Desktop -> Settings -> Resources -> WSL Integration" >&2
    exit 1
fi

mkdir -p "${SCRIPT_DIR}/dist"

echo "==> Building Docker container: ${IMAGE_TAG}..."
docker build -t "${IMAGE_TAG}" -f "${SCRIPT_DIR}/Dockerfile" "${SCRIPT_DIR}"

echo "==> Running build inside isolated container..."
# Privileged mode is required for loop device creation and partition mounting
docker run --rm --privileged \
    -v /dev:/dev \
    -v /sys:/sys \
    -v "${SCRIPT_DIR}:/workspace" \
    -w /workspace \
    "${IMAGE_TAG}" "$@"

echo "==> Docker build finished. Generated artifacts are in '${SCRIPT_DIR}/dist/'."
