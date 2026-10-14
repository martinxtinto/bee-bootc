{
  description = "bee-bootc - immutable Fedora bootc image with k0s, Tailscale and an ephemeral test VM";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};

    # bcvk is not packaged in nixpkgs yet, so we build it from source.
    # https://github.com/bootc-dev/bcvk
    bcvk = pkgs.rustPlatform.buildRustPackage rec {
      pname = "bcvk";
      version = "0.21.0";

      src = pkgs.fetchFromGitHub {
        owner = "bootc-dev";
        repo = "bcvk";
        rev = "v${version}";
        hash = "sha256-953dysh/oKBo7WNeHgqHPFRFpuswhjHJdL9Ym4KXZIo=";
      };

      cargoLock.lockFile = "${src}/Cargo.lock";
      cargoBuildFlags = ["--package" "bcvk"];

      nativeBuildInputs = with pkgs; [pkg-config];
      buildInputs = with pkgs; [openssl systemd];

      # Upstream tests need privileges and a container runtime.
      doCheck = false;

      meta = {
        description = "Bootc virtualization kit - run bootc containers as VMs";
        homepage = "https://github.com/bootc-dev/bcvk";
        license = pkgs.lib.licenses.asl20;
        mainProgram = "bcvk";
      };
    };

    # bcvk bundles qemu/virtiofsd lookups into a podman container; the shim
    # makes the nix store (and nix qemu/virtiofsd) visible inside it.
    podman-shim = pkgs.writeShellApplication {
      name = "podman";
      runtimeInputs = [pkgs.podman];
      text = builtins.readFile (pkgs.replaceVars ./scripts/podman-shim.sh {
        qemu = "${pkgs.qemu}/bin/qemu-system-x86_64";
        virtiofsd = "${pkgs.virtiofsd}/bin/virtiofsd";
        podman = "${pkgs.podman}/bin/podman";
      });
    };

    # bc vk looks for qemu/virtiofsd on the host; point it at the nixpkgs
    # copies so the flake is self-contained on any nix-enabled system.
    bcvk-wrapped = pkgs.writeShellApplication {
      name = "bcvk";
      runtimeInputs = [
        podman-shim
        pkgs.qemu
        pkgs.virtiofsd
        pkgs.openssh
        pkgs.util-linux
        pkgs.coreutils
        pkgs.iproute2
        pkgs.binutils
      ];
      text = ''
        export QEMU_BIN="''${QEMU_BIN:-${pkgs.qemu}/bin/qemu-system-x86_64}"
        export VIRTIOFSD_BIN="''${VIRTIOFSD_BIN:-${pkgs.virtiofsd}/bin/virtiofsd}"
        exec ${bcvk}/bin/bcvk "$@"
      '';
    };

    # Tools needed by the VM/ISO flows (and rootless podman in CI).
    vmTools = with pkgs; [
      podman
      fuse-overlayfs
      shadow
      slirp4netns
      qemu
      openssh
      skopeo
      util-linux
      coreutils
      iproute2
    ];

    lib = builtins.readFile ./scripts/lib.sh;
    withLib = text: lib + "\n" + text;

    buildImage = pkgs.writeShellApplication {
      name = "bee-bootc-build";
      runtimeInputs = with pkgs; [podman git];
      text = builtins.readFile ./scripts/build-image.sh;
    };

    testVm = pkgs.writeShellApplication {
      name = "bee-bootc-vm";
      runtimeInputs = [bcvk-wrapped] ++ vmTools;
      text = builtins.readFile ./scripts/test-vm.sh;
    };

    testVmDisk = pkgs.writeShellApplication {
      name = "bee-bootc-vm-disk";
      runtimeInputs = with pkgs; [git] ++ vmTools;
      text = withLib (builtins.readFile (pkgs.replaceVars ./scripts/test-vm-disk.sh {
        ovmf = "${pkgs.OVMF.fd}";
      }));
    };

    # On-demand installer ISO with a runtime-supplied kickstart (never
    # committed, never in the Nix store). Rootful podman required.
    buildIso = pkgs.writeShellApplication {
      name = "bee-bootc-iso";
      runtimeInputs = with pkgs; [podman git coreutils findutils];
      text = withLib (builtins.readFile ./scripts/build-iso.sh);
    };

    # On-demand disk image (QEMU qcow2 by default) with an optional runtime
    # blueprint for customizations and disk size. Rootful podman required.
    buildDisk = pkgs.writeShellApplication {
      name = "bee-bootc-disk";
      runtimeInputs = with pkgs; [podman git coreutils findutils];
      text = withLib (builtins.readFile ./scripts/build-disk.sh);
    };
  in {
    packages.${system} = {
      inherit bcvk;
      default = testVm;
      build = buildImage;
      vm = testVm;
      vm-disk = testVmDisk;
      iso = buildIso;
      disk = buildDisk;
    };

    apps.${system} = {
      build = {
        type = "app";
        program = "${buildImage}/bin/bee-bootc-build";
        meta.description = "Build the bee-bootc container image";
      };
      vm = {
        type = "app";
        program = "${testVm}/bin/bee-bootc-vm";
        meta.description = "Build bee-bootc and boot it as an ephemeral VM (bcvk)";
      };
      vm-disk = {
        type = "app";
        program = "${testVmDisk}/bin/bee-bootc-vm-disk";
        meta.description = "Build a qcow2 with image-builder and boot it under QEMU";
      };
      iso = {
        type = "app";
        program = "${buildIso}/bin/bee-bootc-iso";
        meta.description = "Build an installer ISO from a runtime-supplied kickstart";
      };
      disk = {
        type = "app";
        program = "${buildDisk}/bin/bee-bootc-disk";
        meta.description = "Build a disk image, optionally with a runtime blueprint";
      };
      default = {
        type = "app";
        program = "${testVm}/bin/bee-bootc-vm";
        meta.description = "Build bee-bootc and boot it as an ephemeral VM (bcvk)";
      };
    };

    checks.${system} = {
      inherit bcvk;
      build = buildImage;
      vm = testVm;
      vm-disk = testVmDisk;
      iso = buildIso;
      disk = buildDisk;
    };

    devShells.${system}.default = pkgs.mkShell {
      packages = [bcvk-wrapped] ++ vmTools ++ (with pkgs; [git]);
    };

    formatter.${system} = pkgs.alejandra;
  };
}
