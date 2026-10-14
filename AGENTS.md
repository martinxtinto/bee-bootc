# AGENTS.md

## Project

`bee-bootc` builds an immutable Fedora 43 bootc image containing Tailscale, k0s host
prerequisites, and an Intel VAAPI/QSV stack. Everything lives in the `Containerfile` plus files
under `files/`. CI builds with podman and pushes to GHCR. A Nix flake provides a dev shell and an
ephemeral test VM.

## Key files

- `Containerfile` — the entire image definition. One `RUN` per concern, cleanup near the end,
  and `bootc container lint` as the final check.
- `files/10-disable-selinux.toml` — bootc kernel args (disables SELinux).
- `files/90-custom-vardirs.conf` — tmpfiles.d entries for writable directories.
- `flake.nix` — dev shell, `build`/`vm`/`vm-bib`/`iso` apps, `checks`, and the pinned `bcvk`
  package.
- `scripts/*.sh` — helpers invoked by the flake (`build-image.sh`, `test-vm.sh`,
  `test-vm-bib.sh`, `build-iso.sh`, `podman-shim.sh`).
- `iso/` — installer-ISO templates (`Containerfile`, `iso.yaml`). Never contains a kickstart.
- `.github/workflows/build.yaml` — Nix-based build/push pipeline.

## Conventions

- Use `dnf5` (the base image is Fedora 43). RPM Fusion must be installed before packages from it.
- Keep the build reproducible: pin from the official bootc base, no `:latest`. Pin the `bcvk`
  version and update its `hash` in `flake.nix` when bumping.
- Never bake secrets into the image. SSH keys/users are provisioned at install time; Tailscale
  and k0s are configured at runtime.
- k0s is **not** installed in the image and must not be. The image only carries host
  prerequisites (`curl`, `hostname`, `iproute`, `shadow-utils`, `kmod`) and loads the
  `overlay`/`br_netfilter` modules and k0s sysctls; `k0sctl` installs k0s on the node.
- Add a new `RUN` block for a new concern instead of expanding an unrelated one.
- When adding writable state, add a tmpfiles.d entry rather than writing to read-only paths.
- Scripts under `scripts/` use `set -euo pipefail` and are wrapped by `writeShellApplication`.
- Never commit a kickstart, and never read one at Nix evaluation time (no `builtins.readFile` /
  `import` / `path`). `scripts/build-iso.sh` reads it at runtime; keep it that way.

## Build and verify

```bash
podman build -t bee-bootc .
```

There is no separate test suite; `bootc container lint` runs at the end of the build and is the
primary verification. Run a local build after any `Containerfile` change.

## Testing (Nix)

```bash
nix develop              # podman, qemu, virtiofsd, bcvk
nix run .#build          # build the image
nix run .#vm             # build + boot an ephemeral VM (bcvk), SSH in
nix run .#vm-bib         # fallback: qcow2 via bootc-image-builder + qemu (needs sudo)
nix run .#iso -- ks      # on-demand installer ISO from a runtime kickstart (needs sudo)
nix flake check -L       # build all checks (bcvk, scripts)
```

- The image must keep `openssh-server`, `openssh-clients`, `mount` (util-linux) and `chroot`
  (coreutils): `bcvk ephemeral` requires `mount`, `chroot`, `systemctl`, `ssh` and `ssh-keygen`
  inside the target image.
- `bcvk` runs QEMU in a privileged podman container that bind-mounts the host's `/usr`. The
  `podman` shim in `scripts/podman-shim.sh` exposes the Nix store into that container and points
  bc vk at the nixpkgs qemu/virtiofsd, so the Nix-wrapped bcvk works on any nix host. If bc vk
  still fails, `scripts/test-vm-bib.sh` is the fallback.
- Flakes only see git-tracked files, so `git add` new scripts before running `nix run`.
- `nix run .#iso` builds an installer ISO with the newer `image-builder`
  (`ghcr.io/osbuild/image-builder-cli`, `bootc-generic-iso`). `iso/Containerfile` mirrors
  image-builder's generic-ISO example and `COPY`s the runtime kickstart to
  `/usr/share/anaconda/interactive-defaults.ks`. Never commit a kickstart; `build-iso.sh` copies it
  into a temporary build context.
- CI installs Nix (`cachix/install-nix-action`), runs `nix flake check`, then `nix run .#build`.
  It also runs weekly (Saturday 03:00 UTC), tagging an additional `YYYY-MM-DD` image tag. The ISO
  is not built in CI (on-demand only).
- CI relaxes `kernel.apparmor_restrict_unprivileged_userns` on the Ubuntu 24.04 runner before
  building: rootless podman (the nixpkgs one in the dev shell) otherwise fails with
  `failed to reexec: Permission denied`. A self-hosted runner image could bake this in instead.

## Gotchas

- SELinux is intentionally disabled via kargs. Do not "fix" this without being asked.
- `/opt` is a symlink to `/var/opt`; scripts that expect a real `/opt` directory will misbehave.
- `/usr/local` is a normal read-only directory (not a symlink to `/var/usrlocal`), so k0sctl must
  set `k0sInstallPath` to a `/var` path.
- The Tailscale package is installed and `tailscaled` is enabled, but nothing joins the tailnet
  automatically.
