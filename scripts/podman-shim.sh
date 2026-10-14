#!/usr/bin/env bash
# podman shim used only inside the bcvk wrapper.
#
# `bcvk ephemeral` runs QEMU inside a podman container whose "hybrid root" is
# the target image plus a read-only bind mount of the host's /usr. A
# nix-built bcvk (and nix-built qemu/virtiofsd) therefore cannot run inside
# that container, because their interpreter and libraries live in /nix/store.
#
# This shim transparently exposes the nix store inside the container's hybrid
# root and points bcvk at the nix-built qemu/virtiofsd, so bcvk works on any
# host that has nix, podman and KVM.
set -euo pipefail

args=("$@")

# Find the podman subcommand (the first argument that is not a global flag).
sub=-1
for i in "${!args[@]}"; do
    case "${args[$i]}" in
        -*) continue ;;
        *)
            sub=$i
            break
            ;;
    esac
done

if [ "$sub" -ge 0 ]; then
    case "${args[$sub]}" in
        run | create)
            inject=()
            if [ -d /nix ]; then
                # /run/tmproot becomes the container's chroot, so this ends up
                # as /nix inside the VM's container root.
                inject+=(-v "/nix:/run/tmproot/nix:ro")
            fi
            inject+=(
                -e "QEMU_BIN=@qemu@"
                -e "VIRTIOFSD_BIN=@virtiofsd@"
            )
            args=("${args[@]:0:$((sub + 1))}" "${inject[@]}" "${args[@]:$((sub + 1))}")
            ;;
    esac
fi

exec @podman@ "${args[@]}"
