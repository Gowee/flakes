{ config, lib, pkgs, ... }: {

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_net"
    "virtio_blk"
  ];


  # ── Disko: GPT + BIOS + LUKS + btrfs ───────────────────────────────────
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
                type = "luks";
                name = "cryptroot";
                initrdUnlock = false;
                settings.keyFile = "/tmp/luks-key";
                # Standard PBKDF2 for low-memory 1C1G node (identical to tyo2)
                extraFormatArgs = [ "--cipher" "aes-xts-plain64" "--key-size" "512" "--hash" "sha512" "--pbkdf" "pbkdf2" "--iter-time" "2000" ];
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
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [ "size=512M" "mode=755" "nodev" "nosuid" ];
    };
  };

  swapDevices = [ ];
  fileSystems."/persist".neededForBoot = true;

  # Expand partition on first boot
  systemd.services.expand-disk = {
    description = "Expand LUKS partition and btrfs filesystem on first boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionFirstBoot = "yes";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "expand-disk" ''
        set -eu
        echo -e "e\n3\n\nw" | ${pkgs.util-linux}/bin/fdisk /dev/vda
        ${pkgs.cloud-utils}/bin/growpart /dev/vda 3 || true
        ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /persist
      '';
    };
  };

  # ── Networking ──────────────────────────────────────────────────────────
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.networks = {
    ethernet = {
      matchConfig.Name = [ "en*" "eth*" ];
      address = [
        "193.168.200.131/24"
        "2a0e:97c0:3f6::1bb/64"
        "2a0e:97c0:3f6::1bc/64"
        "2a0e:97c0:3f6::3c8/64"
        "2a0e:97c0:3f6::3c9/64"
        "2a0e:97c0:3f6::3ca/64"
        "2a0e:97c0:3f6::3cb/64"
        "2a0e:97c0:3f6::3cc/64"
        "2a0e:97c0:3f6::3cd/64"
        "2a0e:97c0:3f6::3ce/64"
        "2a0e:97c0:3f6::3cf/64"
        "2a0e:97c0:3f6::3d0/64"
        "2a0e:97c0:3f6::3d1/64"
        "2a0e:97c0:3f6::3d2/64"
        "2a0e:97c0:3f6::3d3/64"
        "2a0e:97c0:3f6::3d4/64"
        "2a0e:97c0:3f6::3d5/64"
      ];
      routes = [
        { Gateway = "193.168.200.1"; }
        {
          Gateway = "2a0e:97c0:3f6::1";
          PreferredSource = "2a0e:97c0:3f6::1bb";
        }
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
