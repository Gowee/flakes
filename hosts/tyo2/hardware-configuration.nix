{ config, lib, pkgs, ... }: {

  # ── Kernel modules for VPS ──────────────────────────────────────────────
  # virtio_pci: virtio bus driver (VPS disk/network)
  # virtio_net: virtio network device driver (initrd needs this for fetch-luks-key)
  # virtio_blk: virtio block device (virtio disk)
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_net"
    "virtio_blk"
  ];
  # Required by tayga (NAT64 for divi/nat64). Must be loaded at boot because
  # security.lockKernelModules prevents loading new modules after boot.
  boot.kernelModules = [ "tun" ];

  # ── Disko: GPT + BIOS + LUKS + btrfs ───────────────────────────────────
  # Disk layout (GPT + BIOS boot):
  #   /dev/vda1  1M    EF02     — BIOS boot partition (GRUB stage 1.5)
  #   /dev/vda2  256M  ext4     — /boot (unencrypted, stores GRUB + kernel + initrd)
  #   /dev/vda3  100%  LUKS     — encrypted root, btrfs inside
  #
  # btrfs subvolumes inside LUKS:
  #   @nix     → /nix       Nix store (noatime, compress=zstd)
  #   @persist → /persist   survives rollback (sops key, gravity, vnstat, SSH keys)
  disko.imageBuilder.extraRootModules = [ "btrfs" ];
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/vda";
        content = {
          type = "gpt";
          partitions = {
            # BIOS boot partition — GRUB stage 1.5 embedded here
            boot = {
              size = "1M";
              type = "EF02";
            };
            # /boot — unencrypted, stores GRUB config + kernel + initrd
            # 256M provides headroom for 2-3 kernel generations during upgrades
            # before garbage collection removes old ones
            bootfs = {
              size = "256M";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            # LUKS encrypted container — everything sensitive lives here
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";

                # ╔═════════════════════════════════════════════════════════════════╗
                # ║ LUKS key — read this before changing.                        ║
                # ║                                                                 ║
                # ║ settings.keyFile = "/tmp/luks-key" tells disko to pass        ║
                # ║ --key-file /tmp/luks-key to both cryptsetup luksFormat        ║
                # ║ (build time) and cryptsetup open (disko scripts).             ║
                # ║                                                                 ║
                # ║ Key is NEVER fetched inside disko — the QEMU VM has no NIC.   ║
                # ║ Instead, fetch on the build host and inject:                  ║
                # ║   curl -4 -fsS --cacert /etc/ssl/certs/ca-bundle.crt \        ║
                # ║     "https://keywa.rua.st/secret/tyo2-luks?timeout=901" \     ║
                # ║     | base64 -d > /tmp/luks-key                               ║
                # ║   ./result --pre-format-files /tmp/luks-key /tmp/luks-key      ║
                # ║                                                                 ║
                # ║ For colmena apply: keywa fetched via keywa-pin module's        ║
                # ║ fetch-luks-key.service in initrd (runtime).                    ║
                # ║                                                                 ║
                # ║ initrdUnlock = false: skip disko's auto-generated initrd LUKS  ║
                # ║ config. We define boot.initrd.luks.devices.cryptroot in       ║
                # ║ configuration.nix with the runtime keyFile path.              ║
                # ║                                                                 ║
                # ║ The LUKS "key" terminology is overloaded — both files contain ║
                # ║ the PASSPHRASE (sealing material), NOT the master key. LUKS    ║
                # ║ generates the master key internally from --cipher/--key-size. ║
                # ╚═════════════════════════════════════════════════════════════════╝
                initrdUnlock = false;

                # Key provided externally via --pre-format-files. Never in /nix/store.
                settings.keyFile = "/tmp/luks-key";

                # AES-XTS + PBKDF2 + SHA-512 — all hardware-accelerated on x86_64.
                # --pbkdf pbkdf2: explicitly force PBKDF2, avoiding argon2id
                #   (LUKS2 default) which is memory-hard and would spike on 1G RAM.
                # --iter-time 2000ms: sufficient since real entropy comes from
                #   keywa, not local passphrase brute-force resistance.
                extraFormatArgs = [ "--cipher" "aes-xts-plain64" "--key-size" "512" "--hash" "sha512" "--pbkdf" "pbkdf2" "--iter-time" "2000" ];
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    # Nix store — read-heavy, benefits from noatime.
                    # Not rolled back — Nix manages its own integrity.
                    "/@nix" = {
                      mountOptions = [ "compress=zstd" "noatime" ];
                      mountpoint = "/nix";
                    };
                    # Persistent state — survives root rollback.
                    # Only things that must survive reboots live here.
                    # neededForBoot=true: impermanence requires /persist
                    # available at boot for bind mounts.
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
  };

  # ── Root filesystem — tmpfs ─────────────────────────────────────────────
  # Ephemeral: everything resets on reboot. Persistent state lives on @persist.
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=512M" "mode=755" ];
  };

  # ── No disk swap — zramSwap configured in configuration.nix ────────────
  swapDevices = [ ];

  # ── /persist neededForBoot — impermanence requirement ──────────────────
  # disko doesn't expose neededForBoot on btrfs subvolumes, so we set it
  # manually. Required because impermanence bind-mounts from /persist.
  fileSystems."/persist".neededForBoot = true;

  # ── Expand LUKS partition on first boot ─────────────────────────────────
  # When dd-ing a 2G raw image to a 15G disk, the LUKS partition must be
  # resized to fill the disk. This runs once on first boot only.
  #
  # Steps: fix GPT backup header (fdisk 'w'), resize partition (growpart),
  # open LUKS (cryptsetup open), resize btrfs (filesystem resize max).
  # The LUKS passphrase is entered interactively at the console — the
  # operator is already present for dd, so this is acceptable.
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
        # LUKS is already open from initrd — just resize btrfs at /persist
        ${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /persist
      '';
    };
  };

  # ── Networking ──────────────────────────────────────────────────────────
  # Static config for current VPS provider (no DHCP/RA).
  # Initrd network is configured by modules/keywa-pin.
  networking.useNetworkd = true;
  networking.useDHCP = false;

  # ── Full network config — after pivot root ──────────────────────────────
  systemd.network.networks = {
    ethernet = {
      matchConfig.Name = [ "en*" "eth*" ];
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
