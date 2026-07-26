{ config, lib, pkgs, infraDomain, ... }:

{
  # ── Host identity ─────────────────────────────────────────────────────
  networking.hostName = "fra0";
  networking.domain = infraDomain;
  time.timeZone = "Asia/Taipei";
  system.stateVersion = "25.11";

  # ── Bootloader — GRUB on BIOS (GPT + EF02) ────────────────────────────
  boot.loader.grub = {
    enable = true;
    extraConfig = ''
      set noedit=1
      set nocli=1
      set timeout=0
    '';
  };

  # ── Kernel hardening ───────────────────────────────────────────────────
  boot.kernelParams = [ "panic=1" ];

  # ── Sysctl ─────────────────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "net.ipv4.tcp_syncookies" = true;
  };

  security.lockKernelModules = true;

  # ── SOPS — secret management ───────────────────────────────────────────
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age = {
      keyFile = "/persist/var/lib/sops.key";
      generateKey = false;
    };
  };

  # ── keywa-pin: LUKS auto-unlock via keywa ─────────────────────────────
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    keyFile = "/tmp/luks-key";
    preLVM = true;
  };

  keywa-pin = {
    enable = true;
    keywaUrl = "https://keywa.${config.networking.domain}";
    secretId = "fra0-luks";
    initrdInterface = "eth0";
    initrdAddress = "193.168.200.131/24";
    initrdGateway = "193.168.200.1";
    sshAuthorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
  };

  # ── IPSec key (dedicated for fra0) ─────────────────────────────────────
  sops.secrets.ipsec = lib.mkForce {
    sopsFile = ./secrets.yaml;
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
    vim
    tmux
    htop
    curl
    git
    ldns
    bandwhich
    iperf3
    tcpdump
    mtr
    jq
  ];

  # ── Services ───────────────────────────────────────────────────────────
  services.vnstat.enable = true;

  services.journald = {
    storage = "persistent";
    extraConfig = lib.mkForce ''
      SystemMaxUse=100M
      SystemKeepFree=100M
      RuntimeMaxUse=50M
      MaxRetentionSec=2weeks
    '';
  };
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
      prefix = "2a0c:b641:69c:fb74:0:4::/96";
      oif = "eth0";
    };
    srv6 = {
      enable = true;
      prefix = "2a0c:b641:69c:fb7";
    };
    address = [ "2a0c:b641:69c:fb70::1/128" ];
    bird = {
      enable = true;
      prefix = "2a0c:b641:69c:fb70::/60";
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

  # ── Network ────────────────────────────────────────────────────────────
  networking.firewall.enable = false;
  systemd.network.enable = true;
  systemd.network.networks.lo = {
    matchConfig.Name = "lo";
    address = [ "193.168.200.131/32" ];
  };

  users.users.root.hashedPassword = "!";
  users.users.root.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVTLe5ElQ9zegq5F99LWvi4S5YlH5J0tut+Jxwp/FaNZmgSK6uEY7ySu4r/dKn+dwIwHEej152BMZO2/hGjhmw="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBDijuXohDJEgkv9izzEGJ1vLx/4sSs00aDq3RAI7bj"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKJtITC6SV5Og1+G9qNkqbAojHCtuxi+4GKRMMW+yHl"
  ];
  users.mutableUsers = false;

  # ── Low-resource 1C1G tuning ──────────────────────────────────────────
  documentation.enable = false;
  fonts.fontconfig.enable = false;
  programs.command-not-found.enable = false;
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];

  nix.settings = {
    max-jobs = 0;
    "min-free" = 200 * 1024 * 1024;
  };
  nix.gc.options = lib.mkForce "--delete-older-than 7d";

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
