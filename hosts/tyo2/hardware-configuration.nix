{ lib, pkgs, ... }: {


  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Use Disko to format the disk
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

  networking.useNetworkd = true;
  networking.useDHCP = false;

  # gravity relies on systemd.network
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
    };
  };

  networking.usePredictableInterfaceNames = false;
}
