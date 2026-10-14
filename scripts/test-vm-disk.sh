#!/usr/bin/env bash
# Fallback test flow: build bee-bootc, generate a qcow2 with image-builder, and
# boot it as an ephemeral VM under QEMU.
#
# Use this when `bcvk ephemeral` cannot work on the host (for example when
# QEMU/virtiofsd are not visible in the host's /usr, which bcvk relies on).
# Requires rootful podman (sudo) and KVM.
#
# Usage: test-vm-disk.sh [--no-build] [--graphical] [--memory MiB] [--vcpus N] [--ssh-port PORT]
set -euo pipefail

repo_root="$(resolve_repo_root)"
output="$repo_root/output"
image_builder_mounts=()
memory=4096
vcpus=2
ssh_port=2222
build=1
graphical=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-build) build=0 ;;
        --graphical) graphical=1 ;;
        --memory)
            memory="$2"
            shift
            ;;
        --vcpus)
            vcpus="$2"
            shift
            ;;
        --ssh-port)
            ssh_port="$2"
            shift
            ;;
        *)
            echo "unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$build" -eq 1 ]; then
    build_payload "$repo_root"
fi

# Ephemeral SSH keypair, generated per checkout and never committed.
vm_dir="$output/vm"
mkdir -p "$vm_dir"
key="$vm_dir/id_ed25519"
if [ ! -f "$key" ]; then
    ssh-keygen -t ed25519 -N "" -C "bee-bootc-test" -f "$key"
fi
pubkey="$(cat "$key.pub")"

# Blueprint customizations: grant root (for k0sctl) and a wheel user SSH access
# using the ephemeral key. Written at runtime; never committed or stored.
cat >"$vm_dir/blueprint.toml" <<EOF
[[customizations.user]]
name = "root"
key = "$pubkey"

[[customizations.user]]
name = "core"
groups = ["wheel"]
key = "$pubkey"
EOF

mkdir -p "$output"
image_builder_mounts=(-v "$vm_dir/blueprint.toml:/blueprint.toml:ro")

run_image_builder "$output" \
    build \
    --bootc-ref "$payload_image" \
    --blueprint /blueprint.toml \
    --bootc-default-fs ext4 \
    --output-dir /output \
    --output-name bee-bootc \
    qcow2

disk="$output/bee-bootc.qcow2"
if [ ! -f "$disk" ]; then
    echo "expected disk image not found: $disk" >&2
    exit 1
fi

accel="$( [ -w /dev/kvm ] && echo kvm || echo tcg )"

echo
echo "Booting ephemeral VM (disk writes are discarded)."
echo "  SSH: ssh -i $key -p $ssh_port root@localhost"
echo

qemu_args=(
    -machine "q35,accel=$accel"
    -cpu host
    -smp "$vcpus"
    -m "$memory"
    -drive "if=pflash,format=raw,readonly=on,file=@ovmf@"
    -drive "file=$disk,if=virtio,format=qcow2,snapshot=on"
    -netdev "user,id=net0,hostfwd=tcp::$ssh_port-:22"
    -device "virtio-net-pci,netdev=net0"
)

if [ "$graphical" -eq 1 ]; then
    exec qemu-system-x86_64 "${qemu_args[@]}"
else
    exec qemu-system-x86_64 "${qemu_args[@]}" -nographic
fi
