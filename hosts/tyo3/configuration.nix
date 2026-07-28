{ config, lib, pkgs, infraDomain, ... }:

{
  # ── Host identity ─────────────────────────────────────────────────────
  networking.hostName = "tyo3";
  networking.domain = infraDomain;
  time.timeZone = "Asia/Taipei";
  system.stateVersion = "25.11";

  # ── Bootloader — GRUB on BIOS (GPT + EF02) ────────────────────────────
  boot.loader.grub.enable = true;

  # ── Sysctl ─────────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "net.ipv4.tcp_syncookies" = true;
  };

  # ── SOPS — secret management ───────────────────────────────────────────
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age = {
      keyFile = "/persist/var/lib/sops.key";
      generateKey = false;
    };
  };

  # ── Zram swap — no disk swap ───────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
    priority = 100;
  };

  # ── Packages ───────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # future host-specific packages
  ];

  # ── Services ───────────────────────────────────────────────────────────
  services.vnstat.enable = true;

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        type = "rsa";
        bits = 4096;
        path = "/persist/etc/ssh/ssh_host_rsa_key";
      }
      {
        type = "ed25519";
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
      }
    ];
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # ── Hysteria 2 ─────────────────────────────────────────────────────────
  services.hysteria2.listen = ":443";

  # ── Gravity IPSec key (dedicated for tyo2) ─────────────────────────────────────
  # Use dedicated IPSec key instead of shared one from modules/gravity,
  # as tyo2's server provider is less trusted.
  sops.secrets.ipsec = lib.mkForce {
    sopsFile = ./secrets.yaml;
  };

  # ── Gravity ────────────────────────────────────────────────────────────
  services.gravity = {
    enable = true;
    reload.enable = true;
    divi = {
      enable = true;
      prefix = "2a0c:b641:69c:fb64:0:4::/96";
      oif = "eth0";
    };
    srv6 = {
      enable = true;
      prefix = "2a0c:b641:69c:fb6";
    };
    address = [ "2a0c:b641:69c:fb60::1/128" ];
    bird = {
      enable = true;
      prefix = "2a0c:b641:69c:fb60::/60";
    };
    ipsec = {
      enable = true;
      organization = "gowee-isolated";
      commonName = config.networking.hostName;
      port = 13000;
      interfaces = [ "eth0" ];
      endpoints = [
        { serialNumber = "0"; addressFamily = "ip4"; }
        { serialNumber = "1"; addressFamily = "ip6"; }
      ];
    };
  };

  systemd.services.traffic-cap = {
    description = "Traffic Cap";
    after = [ "vnstat.service" ];
    wants = [ "vnstat.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "traffic-cap" ''
        #!/bin/sh
        set -euo pipefail
        # Plan: 220GiB/mo free, 2000Mbps port. Cap = 190GiB to leave headroom.
        # vnstat JSON returns bytes.
        LIMIT_GIB=190
        LIMIT_BYTES=$((LIMIT_GIB * 1024 * 1024 * 1024))

        # Fail-safe: if measurement fails, block conservatively.
        if ! TOTAL_BYTES=$(${pkgs.vnstat}/bin/vnstat -i eth0 --json m 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '[.interfaces[0].traffic.month[-1].rx, .interfaces[0].traffic.month[-1].tx] | add' 2>/dev/null); then
          echo "WARN: traffic measurement failed, blocking eth0 conservatively"
          ${pkgs.iproute2}/bin/ip link set eth0 down
          exit 0
        fi

        # Numeric guard against schema drift / garbage.
        case "$TOTAL_BYTES" in
          ""|*[!0-9]*) echo "WARN: non-numeric traffic value: $TOTAL_BYTES, blocking eth0 conservatively"
            ${pkgs.iproute2}/bin/ip link set eth0 down
            exit 0
            ;;
        esac

        MIB=$(( TOTAL_BYTES / 1024 / 1024 ))
        PERCENT=$(( TOTAL_BYTES * 100 / LIMIT_BYTES ))
        echo "traffic: ''${TOTAL_BYTES} bytes (''${MIB} MiB), ''${PERCENT}% of ''${LIMIT_GIB}GiB cap"
        if [ "$TOTAL_BYTES" -gt "$LIMIT_BYTES" ]; then
          ${pkgs.iproute2}/bin/ip link set eth0 down && echo "eth0 DOWN"
        else
          ${pkgs.iproute2}/bin/ip link set eth0 up && echo "eth0 UP"
        fi
      '';
    };
  };

  systemd.timers.traffic-cap = {
    description = "Run traffic cap check every 15 seconds";
    after = [ "vnstat.service" ];
    wants = [ "vnstat.service" ];
    timerConfig = {
      OnBootSec = "0";
      OnUnitActiveSec = "15s";
      AccuracySec = "1s";
      RandomizedDelaySec = 0;
    };
    wantedBy = [ "timers.target" ];
  };

  # ── Network ────────────────────────────────────────────────────────────
  networking.firewall.enable = false;
  systemd.network.enable = true;

  # ── 2G disk tuning ──────────────────────────────────────────────────
  documentation.enable = false;
  fonts.fontconfig.enable = false;
  programs.command-not-found.enable = false;
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];

  nix.settings = {
    max-jobs = 0;
    "min-free" = 200 * 1024 * 1024;
  };

  services.journald = {
    storage = "persistent";
    extraConfig = lib.mkForce ''
      SystemMaxUse=100M
      SystemKeepFree=100M
      RuntimeMaxUse=50M
      MaxRetentionSec=2weeks
    '';
  };

  nix.gc.options = lib.mkForce "--delete-older-than 7d";

  # ── User ───────────────────────────────────────────────────────────────
  users.users.root.hashedPassword = "$6$sHUuTusLRCigrGWD$.JpdnLij7uXpkZ0ORWP3urxfiOdgZD9I.kXJxMnGjLJrz49Bav9npRw.iO64HXbU8f3OX.S7eZ9lrubmyPTUW.";
  users.users.root.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVTLe5ElQ9zegq5F99LWvi4S5YlH5J0tut+Jxwp/FaNZmgSK6uEY7ySu4r/dKn+dwIwHEej152BMZO2/hGjhmw="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBDijuXohDJEgkv9izzEGJ1vLx/4sSs00aDq3RAI7bj"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKJtITC6SV5Og1+G9qNkqbAojHCtuxi+4GKRMMW+yHl"
  ];
  users.mutableUsers = false;

  # ── Impermanence — persistent state via bind mounts ────────────────────
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/gravity"
      "/var/lib/vnstat"
      "/var/lib/nixos"
      "/var/log/journal"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
}
