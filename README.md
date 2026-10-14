# bee-bootc

An immutable [bootc](https://containers.github.io/bootc/) image based on Fedora 43, shipping a
small home-server / edge Kubernetes stack. The image is built and published to GHCR by CI.

## What's included

| Area | Details |
|---|---|
| Base | `quay.io/fedora/fedora-bootc:43` |
| Repositories | RPM Fusion (free + nonfree) |
| Networking | Tailscale (installed and enabled; join the tailnet yourself) |
| Kubernetes | k0s host prerequisites; the cluster is installed/managed externally with [k0sctl](https://github.com/k0sproject/k0sctl) |
| Hardware | Intel CPU tools, VAAPI + QSV stack (`intel-media-driver`, `intel-compute-runtime`, `oneVPL-intel-gpu`) |
| Health | `smartmontools`, `lm_sensors` |
| Kernel | `kernel-devel`, `kernel-headers` |
| Remote access | `openssh-server` (SSH keys/users are provisioned at install time) |

Additional tuning:

- SELinux is disabled through bootc kernel args (`enforcing=0`, `audit=0`).
- `/opt` is a symlink to `/var/opt`, so anything written under `/opt` survives updates.
- `/var/cache/tailscale` and `/var/lib/dnf/repos` are declared in a tmpfiles config.
- `zram-generator-defaults` is removed and the k0s kernel modules/sysctls
  (`overlay`, `br_netfilter`, `ip_forward`, `bridge-nf-call-iptables`) are configured.

## k0s

The image does **not** ship the k0s binary. It only provides the host prerequisites
(`curl`, `hostname`, `iproute`, `shadow-utils`, `kmod`, modules/sysctls). k0s is installed and
managed from an admin machine with [k0sctl](https://github.com/k0sproject/k0sctl):

```bash
k0sctl apply --config k0sctl.yaml
```

Because k0s is not baked into the image, set `k0sInstallPath` in your k0sctl config to a
persistent, writable location (e.g. `/var/lib/k0s/bin/k0s`) — `/usr` is read-only on bootc.
k0sctl needs SSH access to the node as `root` or as a passwordless-`sudo` user.

## Build locally

```bash
podman build -t bee-bootc .
```

The build ends with `bootc container lint`, which fails the build on image problems.

## Local build & test VM (Nix)

A Nix flake wraps the build and an ephemeral test VM. New files must be `git add`ed for Nix to
see them.

```bash
nix develop                 # shell with podman, qemu, virtiofsd, bcvk
nix run .#build             # podman build -t bee-bootc:test
nix run .#vm                # build + boot an ephemeral VM and SSH in
```

`nix run .#vm` builds the image and runs it with [bc vk](https://github.com/bootc-dev/bcvk)
(`bcvk ephemeral run-ssh`). The VM boots directly from the image's filesystem over virtiofs, so
it starts fast and is discarded when you exit the SSH session. It requires podman and KVM on the
host. bc vk runs QEMU in a podman container that only mounts the host's `/usr`; the flake wraps
`bcvk` with a small `podman` shim that exposes the Nix store and points bc vk at the nixpkgs
qemu/virtiofsd, so it works on any nix-enabled host.

If bc vk still cannot work on your host, use the bootc-image-builder fallback, which builds a
qcow2 and boots it under QEMU:

```bash
nix run .#vm-bib            # requires rootful podman (sudo)
# then: ssh -i output/vm/id_ed25519 -p 2222 root@localhost
```

## Installer ISO (Nix, on demand)

`nix run .#iso` builds an Anaconda installer ISO for bee-bootc with a kickstart you supply at
runtime, using the newer [`image-builder`](https://github.com/osbuild/image-builder)
(`bootc-generic-iso`). The kickstart is read at runtime — it is **never committed to the repo and
never stored in the Nix store**.

```bash
nix run .#iso -- /path/to/install.ks      # requires rootful podman (sudo)
nix run .#iso -- --no-build /path/to/install.ks
```

By default the image is embedded in the ISO for offline installation
(`--bootc-installer-payload-ref`), and Anaconda reads the kickstart from the installer container's
`/usr/share/anaconda/interactive-defaults.ks`. The ISO is written under `output/`.

Because the payload is embedded, the kickstart should install from the local container store, e.g.:

```
bootc --source-imgref containers-storage:localhost/bee-bootc:test \
      --target-imgref localhost/bee-bootc:test
```

Pass `--online` to skip embedding the payload; the kickstart then has to reference the image from a
registry (smaller ISO).

## CI

`.github/workflows/build.yaml` installs Nix (`cachix/install-nix-action`), runs `nix flake check`,
builds the image with the flake, and pushes to GHCR:

- Every build is tagged `sha-<8>`.
- Pushes to `main` additionally get `latest`.
- Scheduled rebuilds (weekly, Saturday 03:00 UTC) additionally get an ISO-date tag (`YYYY-MM-DD`).
- Tags matching `v*` additionally get that tag name.
- Pull requests build but do not push.

## Layout

```
Containerfile                 # the image definition
files/                        # configs baked into the image
  10-disable-selinux.toml     # bootc kernel args
  90-custom-vardirs.conf      # tmpfiles.d entries
scripts/                      # helpers (invoked by the flake)
  build-image.sh
  test-vm.sh                  # bcvk ephemeral VM
  test-vm-bib.sh              # bootc-image-builder fallback
  build-iso.sh                # on-demand installer ISO
  podman-shim.sh              # exposes /nix to bcvk's qemu container
iso/                          # templates for the installer ISO (no secrets)
  Containerfile               # Anaconda installer container (kickstart supplied at runtime)
  iso.yaml                    # ISO label + grub2 menu entries
flake.nix                     # nix dev shell, apps, checks and the bcvk package
.github/workflows/build.yaml  # build + push pipeline
```
