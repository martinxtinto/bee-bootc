#!/usr/bin/env bash
# Build an installer ISO for bee-bootc with a user-supplied kickstart embedded,
# using the newer `image-builder` and its `bootc-generic-iso` image type.
#
# The kickstart is read at runtime: it is never committed to the repository and
# never stored in the Nix store. Anaconda consumes it from the installer
# container's /usr/share/anaconda/interactive-defaults.ks.
#
# Requires rootful podman (sudo) and network access.
#
# Usage: build-iso.sh [--no-build] [--online] KICKSTART
#
#   --no-build   Reuse an already-built bee-bootc:test image.
#   --online     Do not embed the payload image; the kickstart must reference
#                the image from a registry (smaller ISO).
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
output="$repo_root/output"
payload_image="localhost/bee-bootc:test"
iso_builder_image="bee-bootc-iso:test"
image_builder_ref="ghcr.io/osbuild/image-builder-cli:latest"

build=1
online=0
kickstart=""

usage() {
    cat <<'EOF'
Usage: build-iso.sh [--no-build] [--online] KICKSTART

Build an installer ISO for bee-bootc with a user-supplied kickstart embedded,
using image-builder's bootc-generic-iso image type. Requires rootful podman.

  --no-build   Reuse an already-built bee-bootc:test image.
  --online     Do not embed the payload image; the kickstart must reference
               the image from a registry (smaller ISO).
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-build) build=0 ;;
        --online) online=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *) kickstart="$1" ;;
    esac
    shift
done

if [ -z "$kickstart" ]; then
    usage >&2
    exit 2
fi
if [ ! -f "$kickstart" ]; then
    echo "kickstart file not found: $kickstart" >&2
    exit 1
fi
kickstart="$(readlink -f "$kickstart")"

if [ "$build" -eq 1 ]; then
    sudo podman build -t "$payload_image" "$repo_root"
fi

# Build context for the installer container. The kickstart is copied here and
# nowhere else persistent.
ctx="$(mktemp -d)"
trap 'rm -rf "$ctx"' EXIT

cp "$repo_root/iso/Containerfile" "$ctx/Containerfile"
cp "$repo_root/iso/iso.yaml" "$ctx/iso.yaml"
cp "$kickstart" "$ctx/install.ks"

sudo podman build -t "$iso_builder_image" "$ctx"

mkdir -p "$output"

payload_args=()
if [ "$online" -eq 0 ]; then
    payload_args+=(--bootc-installer-payload-ref "$payload_image")
fi

sudo podman run --rm --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "$output:/output" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    "$image_builder_ref" \
    build \
    --bootc-ref "localhost/$iso_builder_image" \
    "${payload_args[@]}" \
    --bootc-default-fs ext4 \
    --output-dir /output \
    bootc-generic-iso

echo
echo "ISO(s) written under: $output"
find "$output" -maxdepth 3 -name '*.iso' -print 2>/dev/null || true
