#!/usr/bin/env bash
# Build a QEMU (or other hypervisor) disk image for bee-bootc, using the newer
# `image-builder` on demand.
#
# An optional blueprint (users, SSH keys, hostname, ...) is read at runtime: it
# is never committed to the repository and never stored in the Nix store. The
# disk size is set through the blueprint's root filesystem minimum size.
#
# Requires rootful podman (sudo) and network access.
#
# Usage: build-disk.sh [OPTIONS]
#
#   --no-build          Reuse an already-built localhost/bee-bootc:test image.
#   --format FORMAT     Image format (default: qcow2). One of:
#                       qcow2, raw, vmdk, vhd, ova, pxe-tar-xz.
#   --size SIZE         Root filesystem minimum size, e.g. 20G or "20 GiB".
#                       Sets the effective disk image size.
#   --blueprint FILE    Blueprint (TOML) with customizations. Optional.
#   --fs FS             Default filesystem when building (default: ext4).
#   --name NAME         Output basename (default: bee-bootc).
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: build-disk.sh [OPTIONS]

Build a disk image for bee-bootc with image-builder. Requires rootful podman.

  --no-build          Reuse an already-built localhost/bee-bootc:test image.
  --format FORMAT     qcow2 (default), raw, vmdk, vhd, ova or pxe-tar-xz.
  --size SIZE         Root filesystem minimum size, e.g. 20G or "20 GiB".
  --blueprint FILE    Blueprint (TOML) with customizations (optional).
  --fs FS             Default filesystem when building (default: ext4).
  --name NAME         Output basename (default: bee-bootc).
EOF
}

allowed_formats=(qcow2 raw vmdk vhd ova pxe-tar-xz)

build=1
format="qcow2"
size=""
blueprint=""
fs="ext4"
name="bee-bootc"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-build) build=0 ;;
        --format)
            format="$2"
            shift
            ;;
        --size)
            size="$2"
            shift
            ;;
        --blueprint)
            blueprint="$2"
            shift
            ;;
        --fs)
            fs="$2"
            shift
            ;;
        --name)
            name="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            echo "unexpected argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if ! printf '%s\n' "${allowed_formats[@]}" | grep -qx "$format"; then
    echo "unsupported format: $format (expected one of: ${allowed_formats[*]})" >&2
    exit 2
fi

if [ -n "$blueprint" ] && [ ! -f "$blueprint" ]; then
    echo "blueprint file not found: $blueprint" >&2
    exit 1
fi

repo_root="$(resolve_repo_root)"
output="$repo_root/output"
image_builder_mounts=()

if [ "$build" -eq 1 ]; then
    build_payload "$repo_root"
fi

# Assemble the runtime blueprint in a temp dir. The blueprint (and the size
# derived from it) live only here, never in the repository or the Nix store.
ctx="$(mktemp -d)"
trap 'rm -rf "$ctx"' EXIT

blueprint_file="$ctx/blueprint.toml"
if [ -n "$blueprint" ]; then
    cp "$blueprint" "$blueprint_file"
else
    : >"$blueprint_file"
fi
if [ -n "$size" ]; then
    append_root_minsize "$blueprint_file" "$size"
fi

blueprint_args=()
if [ -s "$blueprint_file" ]; then
    image_builder_mounts+=(-v "$blueprint_file:/blueprint.toml:ro")
    blueprint_args+=(--blueprint /blueprint.toml)
fi

mkdir -p "$output"

run_image_builder "$output" \
    build \
    --bootc-ref "$payload_image" \
    "${blueprint_args[@]}" \
    --bootc-default-fs "$fs" \
    --output-dir /output \
    --output-name "$name" \
    "$format"

echo
echo "Image(s) written under: $output"
find "$output" -maxdepth 2 -type f -print 2>/dev/null || true
