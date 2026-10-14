# shellcheck shell=bash
#
# Shared helpers for the image-builder based scripts (build-iso.sh,
# build-disk.sh, test-vm-disk.sh). flake.nix concatenates this file ahead of
# each script body, so it must not contain a shebang or `set` options.

image_builder_ref="ghcr.io/osbuild/image-builder-cli:latest"
payload_image="localhost/bee-bootc:test"

# Extra bind mounts for run_image_builder, e.g. a runtime blueprint. Scripts may
# replace this with their own array before calling run_image_builder.
image_builder_mounts=()

resolve_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

# build_payload REPO_ROOT
build_payload() {
    sudo podman build -t "$payload_image" "$1"
}

# run_image_builder OUTPUT ARGS...
#
# Runs the image-builder container (rootful podman) with OUTPUT bind-mounted at
# /output plus any extra mounts in image_builder_mounts, passing ARGS through.
run_image_builder() {
    local output="$1"
    shift
    sudo podman run --rm --privileged --pull=newer \
        --security-opt label=type:unconfined_t \
        -v "$output:/output" \
        "${image_builder_mounts[@]}" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "$image_builder_ref" "$@"
}

# append_root_minsize BLUEPRINT SIZE
#
# Appends a filesystem customization setting the minimum size of the root
# filesystem, which (since the root partition grows to fill the disk) sets the
# effective image size. SIZE accepts units, e.g. "20 GiB" or "20G".
append_root_minsize() {
    local file="$1"
    local size="$2"
    {
        printf '\n[[customizations.filesystem]]\n'
        printf 'mountpoint = "/"\n'
        printf 'minsize = "%s"\n' "$size"
    } >>"$file"
}
