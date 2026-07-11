{ config, lib, pkgs, ... }: {

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_net"
    "virtio_scsi"
  ];
  boot.kernelModules = [ "tun" ];

  disko.imageBuilder.extraRootModules = [ "btrfs" ];
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            bootfs = {
              size = "256M";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
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
  };

  swapDevices = [ ];

  disko.devices.nodev."/" = {
    fsType = "tmpfs";
    mountOptions = [ "size=1G" "mode=755" "nodev" "nosuid" ];
  };
  fileSystems."/persist".neededForBoot = true;

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
        echo -e "e\n3\n\nw" | ${pkgs.util-linux}/bin/fdisk /dev/sda
        ${pkgs.cloud-utils}/bin/growpart /dev/sda 3 || true
        ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /persist
      '';
    };
  };

  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.networks = {
    ethernet = {
      matchConfig.Name = [ "en*" "eth*" ];
      address = [
        "172.245.120.41/25"
        "2607:9d00:2000:39::3d5/64"
      ];
      routes = [
        { Gateway = "172.245.120.1"; }
        { Gateway = "2607:9d00:2000:39::1"; }
      ];
      dns = [
        "1.1.1.1"
        "2001:4860:4860::8888"
      ];
      networkConfig = {
        KeepConfiguration = "yes";
        IPv6PrivacyExtensions = "no";
      };
    };
  };

  networking.usePredictableInterfaceNames = false;
}
