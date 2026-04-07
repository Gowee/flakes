{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "nodev";


  networking.hostName = "tyo2";
  time.timeZone = "Asia/Shanghai";

  networking.firewall.enable = false;
  networking.domain = "rua.st";

  users.mutableUsers = false;
  # users.users.admin = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # Enable ‘sudo’
  #   openssh.authorizedKeys.keys = [
  #     "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVTLe5ElQ9zegq5F99LWvi4S5YlH5J0tut+Jxwp/FaNZmgSK6uEY7ySu4r/dKn+dwIwHEej152BMZO2/hGjhmw="
  #     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBDijuXohDJEgkv9izzEGJ1vLx/4sSs00aDq3RAI7bj"
  #     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKJtITC6SV5Og1+G9qNkqbAojHCtuxi+4GKRMMW+yHl"
  #   ];
  # };
  users.users.root.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVTLe5ElQ9zegq5F99LWvi4S5YlH5J0tut+Jxwp/FaNZmgSK6uEY7ySu4r/dKn+dwIwHEej152BMZO2/hGjhmw="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBDijuXohDJEgkv9izzEGJ1vLx/4sSs00aDq3RAI7bj"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKJtITC6SV5Og1+G9qNkqbAojHCtuxi+4GKRMMW+yHl"
  ];
  users.users.root.initialHashedPassword = "";


  environment.systemPackages = with pkgs; [
    vim
    tmux
    bandwhich
    iperf3
    tcpdump
    mtr
    jq
  ];

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Bandwidth Monitoring
  services.vnstat = {
    enable = true;
  };

  systemd.services.traffic-limiter = {
    description = "Traffic Limiter";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "traffic-limiter" ''
        #!/bin/sh
        # 950GiB in KiB
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

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
    priority = 100;
  };

  services.hysteria2.listen = ":443";

  services.gravity = {
    enable = true;
    reload.enable = true;
    divi = {
      enable = true;
      prefix = "2a0c:b641:69c:fb44:0:4::/96";
      oif = "wg-warp";
    };
    srv6 = {
      enable = true;
      prefix = "2a0c:b641:69c:fb4";
    };
    address = [ "2a0c:b641:69c:fb40::1/128" ];
    bird = {
      enable = true;
      prefix = "2a0c:b641:69c:fb40::/60";
    };

    ipsec = {
      enable = true;
      organization = "lotust";
      commonName = config.networking.hostName;
      port = 13000;
      interfaces = [ "eth0" ];
      endpoints = [
        {
          serialNumber = "0";
          addressFamily = "ip4";
        }
        {
          serialNumber = "1";
          addressFamily = "ip6";
        }
      ];
    };
  };

  sops.secrets.warp_private_key = { };

  systemd.network.netdevs."10-wg-warp" = {
    netdevConfig = {
      Kind = "wireguard";
      Name = "wg-warp";
      MTUBytes = "1280";
    };
    wireguardConfig = {
      PrivateKeyFile = config.sops.secrets.warp_private_key.path;
      RouteTable = false;
    };
    wireguardPeers = [{
      wireguardPeerConfig = {
        PublicKey = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";
        Endpoint = "engage.cloudflareclient.com:2408";
        AllowedIPs = [
          "0.0.0.0/0"
          "::/0"
        ];
      };
    }];
  };

  systemd.network.networks."10-wg-warp" = {
    name = "wg-warp";
    # These addresses are assigned by Cloudflare Warp during registration
    address = [
      "172.16.0.2/32"
      "fd01:5ca1:ab1e::1/128"
    ];
    routes = [
      {
        Destination = "0.0.0.0/0";
        Table = 1000;
      }
      {
        Destination = "::/0";
        Table = 1000;
      }
    ];
    linkConfig.RequiredForOnline = false;
  };

  systemd.network.networks.divi.routingPolicyRules = [{
    From = "10.200.0.0/16";
    Table = 1000;
    Priority = 1000;
  }];

  systemd.network.networks.nat64.routingPolicyRules = [{
    From = "10.201.0.0/16";
    Table = 1000;
    Priority = 1000;
  }];

  system.stateVersion = "25.11";

  sops = {
    defaultSopsFile = ./secrets.yaml;
    age = {
      keyFile = "/var/lib/sops.key";
      generateKey = false;
    };
  };
}
