#!/usr/bin/env bash
# Build bee-bootc and boot it as an ephemeral VM using bcvk.
#
# Everything is throwaway: the VM boots straight from the image's root
# filesystem over virtiofs and disappears when you exit the SSH session.
#
# Usage: test-vm.sh [--no-build] [bcvk ephemeral run-ssh options...]
#
#   --no-build   Reuse an already-built bee-bootc:test image.
#
# Any other arguments are forwarded to `bcvk ephemeral run-ssh`
# (for example --memory 8G --vcpus 4).
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
image="bee-bootc:test"
build=1
passthru=()

for arg in "$@"; do
    case "$arg" in
        --no-build) build=0 ;;
        *) passthru+=("$arg") ;;
    esac
done

if [ "$build" -eq 1 ]; then
    podman build -t "$image" "$repo_root"
fi

exec bcvk ephemeral run-ssh "${passthru[@]}" "$image"
