{ config, lib, pkgs, infraDomain, ... }:

{
  # ── Host identity ──────────────────────────────────────────────────────
  networking.hostName = "nah1";
  networking.domain = infraDomain;
  time.timeZone = "Asia/Taipei";
  system.stateVersion = "26.05";

  # ── Bootloader — systemd-boot on UEFI (GPT + EF00 ESP) ─────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Sysctl ─────────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "net.ipv4.tcp_syncookies" = true;
  };

  # ── SOPS — secret management ───────────────────────────────────────────
  sops.age = {
    keyFile = "/persist/var/lib/sops.key";
    generateKey = false;
  };

  # ── Zram swap — no disk swap ───────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
    priority = 100;
  };

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

  # ── Gravity ────────────────────────────────────────────────────────────
  services.gravity = {
    enable = true;
    reload.enable = true;
    divi = {
      enable = true;
      prefix = "2a0c:b641:69c:fb84:0:4::/96";
      oif = "eth0";
    };
    srv6 = {
      enable = true;
      prefix = "2a0c:b641:69c:fb8";
    };
    address = [ "2a0c:b641:69c:fb80::1/128" ];
    bird = {
      enable = true;
      prefix = "2a0c:b641:69c:fb80::/60";
    };
    ipsec = {
      enable = true;
      organization = "gowee";
      commonName = config.networking.hostName;
      port = 13000;
      interfaces = [ "eth0" ];
      endpoints = [
        { serialNumber = "0"; addressFamily = "ip4"; }
        { serialNumber = "1"; addressFamily = "ip6"; }
      ];
    };
  };

  # ── Network ────────────────────────────────────────────────────────────
  networking.firewall.enable = false;
  systemd.network.enable = true;

  # ── Low-resource tuning (1 GiB RAM) ────────────────────────────────────
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
