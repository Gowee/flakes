{ config, lib, pkgs, infraDomain, ... }:

{
  networking.hostName = "nium0";
  networking.domain = infraDomain;
  time.timeZone = "Asia/Taipei";
  system.stateVersion = "25.11";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  boot.kernelParams = [ "panic=1" "sysrq=0" ];

  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "net.ipv4.tcp_syncookies" = true;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "kernel.kexec_load_disabled" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.perf_event_paranoid" = 3;
    "kernel.core_pattern" = "|/bin/false";
  };

  security.lockKernelModules = true;

  sops = {
    defaultSopsFile = ./secrets.yaml;
    age = {
      keyFile = "/run/sops.key";
      generateKey = false;
    };
    useSystemdActivation = true;
  };

  keywa-sops = {
    enable = true;
    secretId = "nium0-sops";
  };

  # Sops ordering — ensures services wait for sops-install-secrets before starting
  systemd.services.gravity-ipsec.after = [ "sops-install-secrets.service" ];
  systemd.services.gravity-ipsec.wants = [ "sops-install-secrets.service" ];
  systemd.services.gravity-registry.after = [ "sops-install-secrets.service" ];
  systemd.services.gravity-registry.wants = [ "sops-install-secrets.service" ];
  systemd.services.hysteria2.after = [ "sops-install-secrets.service" ];
  systemd.services.hysteria2.wants = [ "sops-install-secrets.service" ];
  systemd.services.shadowsocks-libev.after = [ "sops-install-secrets.service" ];
  systemd.services.shadowsocks-libev.wants = [ "sops-install-secrets.service" ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
    priority = 100;
  };

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

  services.vnstat.enable = true;

  services.journald = {
    storage = "persistent";
    extraConfig = ''
      SystemMaxUse=200M
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

  systemd.services.traffic-limiter = {
    description = "Traffic Limiter";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "traffic-limiter" ''
        #!/bin/sh
        LIMIT_KIB=996147200
        TOTAL_KIB=$(vnstat -i eth0 --json m 1 | ${pkgs.jq}/bin/jq '.interfaces[0].traffic.months[0].total')
        if [ "$TOTAL_KIB" -gt "$LIMIT_KIB" ]; then
          ${pkgs.systemd}/bin/shutdown now
        fi
      '';
    };
  };

  systemd.timers.traffic-limiter = {
    description = "Run traffic limiter every hour";
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    wantedBy = [ "timers.target" ];
  };

  services.hysteria2.listen = ":443";

  services.gravity = {
    enable = true;
    reload.enable = true;
    divi = {
      enable = true;
      prefix = "2a0c:b641:69c:fb54:0:4::/96";
      oif = "eth0";
    };
    srv6 = {
      enable = true;
      prefix = "2a0c:b641:69c:fb5";
    };
    address = [ "2a0c:b641:69c:fb50::1/128" ];
    bird = {
      enable = true;
      prefix = "2a0c:b641:69c:fb50::/60";
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

  networking.firewall.enable = false;
  systemd.network.enable = true;
  systemd.network.networks.lo = {
    matchConfig.Name = "lo";
    address = [ "172.245.120.41/32" ];
  };

  systemd.services."serial-getty@ttyS0".enable = false;
  systemd.services."serial-getty@ttyS1".enable = false;
  systemd.services."serial-getty@ttyS2".enable = false;
  systemd.services."serial-getty@ttyS3".enable = false;
  systemd.services."getty@tty1".enable = false;
  systemd.services.rescue.enable = false;
  systemd.services.emergency.enable = false;
  systemd.services.systemd-sulogin.enable = false;
  systemd.services."debug-shell.service".enable = false;

  users.users.root.hashedPassword = "!";
  users.users.root.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVTLe5ElQ9zegq5F99LWvi4S5YlH5J0tut+Jxwp/FaNZmgSK6uEY7ySu4r/dKn+dwIwHEej152BMZO2/hGjhmw="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBDijuXohDJEgkv9izzEGJ1vLx/4sSs00aDq3RAI7bj"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKJtITC6SV5Og1+G9qNkqbAojHCtuxi+4GKRMMW+yHl"
  ];
  users.mutableUsers = false;

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
