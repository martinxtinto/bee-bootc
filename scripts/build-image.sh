#!/usr/bin/env bash
# Build the bee-bootc container image with podman.
#
# Usage: build-image.sh [IMAGE_TAG]
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
image="${1:-bee-bootc:test}"

exec podman build -t "$image" "$repo_root"
