{ lib, pkgs, ... }: {


  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Use Disko to format the disk
  disko.imageBuilder.extraRootModules = [ "btrfs" ];
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
              type = "EF02"; # For GRUB on BIOS systems
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/@root" = {
                    mountOptions = [ "compress=zstd" ];
                    mountpoint = "/";
                  };
                  "/@home" = {
                    mountOptions = [ "compress=zstd" ];
                    mountpoint = "/home";
                  };
                  "/@nix" = {
                    mountOptions = [ "compress=zstd" "noatime" ];
                    mountpoint = "/nix";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  swapDevices = [ ];

  # Expand root partition and filesystem on first boot.
  # Needed because diskoImages creates a minimal image (default 2G) that
  # must expand to fill the actual disk when dd'd to a larger device.
  # fdisk 'w' fixes the GPT backup header (moved to end of disk) but
  # cannot trigger kernel re-read on a mounted root partition.
  # growpart handles kernel notification and resizes the partition.
  systemd.services.expand-disk = {
    description = "Expand disk partition and filesystem on first boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionFirstBoot = "yes";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "expand-disk" ''
        set -eu
        echo -e "e\n2\n\nw" | ${pkgs.util-linux}/bin/fdisk /dev/vda
        ${pkgs.cloud-utils}/bin/growpart /dev/vda 2 || true
        ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /
      '';
    };
  };

  networking.useNetworkd = true;
  networking.useDHCP = false;

  # gravity relies on systemd.network
  systemd.network.networks = {
    ethernet = {
      matchConfig.Name = [
        "en*"
        "eth*"
      ];
      # Static config for current VPS provider (cloud-init, no DHCP)
      address = [
        "216.23.121.85/24"
        "2a0e:97c0:3f4:1::1a0c/64"
        "2a0e:97c0:3f4:1::1a0d/64"
        "2a0e:97c0:3f4:1::1a0e/64"
        "2a0e:97c0:3f4:1::1a0f/64"
        "2a0e:97c0:3f4:1::1a10/64"
        "2a0e:97c0:3f4:1::1a11/64"
        "2a0e:97c0:3f4:1::1a12/64"
        "2a0e:97c0:3f4:1::1a13/64"
        "2a0e:97c0:3f4:1::1a14/64"
        "2a0e:97c0:3f4:1::1a15/64"
        "2a0e:97c0:3f4:1::1a16/64"
        "2a0e:97c0:3f4:1::1a17/64"
        "2a0e:97c0:3f4:1::1a18/64"
        "2a0e:97c0:3f4:1::1a19/64"
        "2a0e:97c0:3f4:1::1a1a/64"
        "2a0e:97c0:3f4:1::1a1b/64"
      ];
      routes = [
        { Gateway = "216.23.121.1"; }
        { Gateway = "2a0e:97c0:3f4:1::1"; }
      ];
      dns = [
        "1.1.1.1"
        "2001:4860:4860::8888"
      ];
      networkConfig = {
        KeepConfiguration = "yes";
        IPv6PrivacyExtensions = "no";
      };
      # DHCP/RA config for providers that support it (uncomment if switching):
      # DHCP = "yes";
      # networkConfig = {
      #   KeepConfiguration = "yes";
      #   IPv6AcceptRA = "yes";
      #   IPv6PrivacyExtensions = "no";
      # };
    };
  };

  networking.usePredictableInterfaceNames = false;
}
