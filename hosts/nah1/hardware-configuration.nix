{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # ── Kernel & OCI Virtio SCSI modules ────────────────────────────────────
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "tcp_bbr" ];
  boot.extraModulePackages = [ ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "cake";
  };

  # ── Disko: GPT + UEFI ESP + btrfs + tmpfs impermanence ──────────────────
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        imageSize = "4G";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/@nix" = {
                    mountOptions = [ "compress=zstd" "noatime" ];
                    mountpoint = "/nix";
                  };
                  "/@persist" = {
                    mountOptions = [ "compress=zstd" ];
                    mountpoint = "/persist";
                  };
                };
              };
            };
          };
        };
      };
    };
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [ "size=384M" "mode=755" "nodev" "nosuid" ];
    };
  };

  # ── No disk swap — zramSwap configured in configuration.nix ────────────
  swapDevices = [ ];

  # ── /persist neededForBoot — impermanence requirement ──────────────────
  fileSystems."/persist".neededForBoot = true;

  # ── Expand btrfs partition on first boot ────────────────────────────────
  systemd.services.expand-disk = {
    description = "Expand btrfs partition and filesystem on first boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionFirstBoot = "yes";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "expand-disk" ''
        set -eu
        ${pkgs.cloud-utils}/bin/growpart /dev/sda 2 || true
        ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /persist
      '';
    };
  };

  # ── Networking ──────────────────────────────────────────────────────────
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.networks = {
    ethernet = {
      matchConfig.Name = [
        "en*"
        "eth*"
      ];
      DHCP = "yes";
      networkConfig = {
        KeepConfiguration = "yes";
        IPv6AcceptRA = "yes";
        IPv6PrivacyExtensions = "no";
      };
      linkConfig.RequiredForOnline = true;
    };
  };

  networking.usePredictableInterfaceNames = false;
}
