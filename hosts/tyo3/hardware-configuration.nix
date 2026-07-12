{ config, lib, pkgs, ... }: {

  # ── Kernel modules for VPS ──────────────────────────────────────────────
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_net"
    "virtio_blk"
  ];
  boot.kernelModules = [ "tun" ];

  # ── Disko: GPT + BIOS + btrfs (no LUKS) ────────────────────────────────
  # Single btrfs partition with subvolumes. @boot has no compression
  # (GRUB can't read zstd). EF02 partition for GRUB stage 1.5.
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/vda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/@boot" = {
                    mountOptions = [ ];
                    mountpoint = "/boot";
                  };
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
  # Image built with disko may be smaller than target disk. Resize partition
  # 2 (btrfs root) to fill the disk, then resize btrfs.
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
        ${pkgs.cloud-utils}/bin/growpart /dev/vda 2 || true
        ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /persist
      '';
    };
  };

  # ── Networking ──────────────────────────────────────────────────────────
  # IPv4 DHCP only. IPv6 explicitly disabled (kernel stack stays for gravity overlay).
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.networks = {
    ethernet = {
      matchConfig.Name = [ "en*" "eth*" ];
      # IPv4 DHCP only — no DHCPv6, no Router Advertisement.
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
      linkConfig.RequiredForOnline = true;
    };
  };

  networking.usePredictableInterfaceNames = false;
}
