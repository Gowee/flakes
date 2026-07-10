{ config, lib, pkgs, infraDomain, ... }:

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║ tyo2 — "less trusted" VPS node                                        ║
# ║                                                                        ║
# ║ Threat model: VPS provider has physical/root access to the host.       ║
# ║ Full disk encryption ensures data confidentiality at rest.             ║
# ║ Impermanence (tmpfs root) reduces persistent attack surface.           ║
# ║ GRUB/kernel/systemd hardening mitigates VNC/console physical access.   ║
# ╚══════════════════════════════════════════════════════════════════════════╝

{
  # ── Host identity ─────────────────────────────────────────────────────
  networking.hostName = "tyo2";
  networking.domain = infraDomain;
  time.timeZone = "Asia/Taipei";
  system.stateVersion = "25.11";

  # ── Bootloader — GRUB on BIOS (GPT + EF02) ────────────────────────────
  # Hardened: no menu, no edit, no CLI, no waiting.
  # The operator never needs GRUB interactively — NixOS rollbacks are
  # handled via Colmena redeploy, not GRUB menu editing.
  #
  # noedit=1:  Prevent editing boot entries (blocks init=/bin/sh attacks)
  # nocli=1:   Prevent access to GRUB command line
  # timeout=0: Boot immediately, no menu visible
  boot.loader.grub = {
    enable = true;
    # device set automatically by disko from the disk layout
    extraConfig = ''
      set noedit=1
      set nocli=1
      set timeout=0
    '';
  };

  # ── Kernel hardening ───────────────────────────────────────────────────
  # panic=1:  Reboot on kernel panic after 1 second (don't hang for attacker)
  # sysrq=0:  Disable magic SysRq key — prevents VNC/console users from
  #           triggering sync/reboot/mount-raw to extract secrets or
  #           disrupt the running system
  boot.kernelParams = [ "panic=1" "sysrq=0" ];

  # ── Sysctl ─────────────────────────────────────────────────────────────
  # vm.swappiness=100: prefer swap (zram) over OOM kill.
  #   On zram systems, swap IS RAM-backed — high swappiness is beneficial.
  # rp_filter: strict reverse path filtering (anti-spoofing)
  # accept_redirects=0: reject ICMP redirects (anti-MitM)
  #
  # Physical-access hardening (less-trusted VPS):
  #   kexec_load_disabled: cannot replace running kernel from /dev/mem access
  #   kptr_restrict:        hide kernel pointers from non-CAP_SYSLOG
  #   dmesg_restrict:       unprivileged users can't read dmesg
  #   perf_event_paranoid:  restrict perf subsystem (kernel info leak)
  #   core_pattern:         disable core dumps (info leakage)
  # modules_disabled is set via security.lockKernelModules below (canonical).
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

  # Lock kernel module loading after boot — prevents live rootkit injection.
  # Already-loaded modules (network, fs, etc.) stay; new ones can't be loaded.
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
  # Module in modules/keywa-pin/ handles:
  #   - initrd fetch-luks-key.service (long-poll keywa, IP-gated, Telegram-approved)
  #   - initrd network config (static IP for keywa reachability)
  #   - initrd SSH (manual recovery fallback)
  #   - build-time key delivery via --pre-format-files (external to disko)
  #
  # Auth model: IP allowlist only (no token, no PSK). keywa's CIDRs must
  # include this host's egress IP. Telegram approval is required per fetch.
  #
  # Secret rotation: rotate keywa's secret AND rebuild the image. The LUKS
  # header is sealed by the build-time fetch; rebuilding reformats.
  #
  # Initrd LUKS unlock: defined here (NOT via disko) because disko's
  # initrdUnlock would spread settings.keyFile into this config. We want
  # the runtime path /tmp/luks-key (written by fetch-luks-key.service),
  # not the build-time path (same string, but populated at different times).
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    keyFile = "/tmp/luks-key";
    preLVM = true;
  };

  keywa-pin = {
    enable = true;
    keywaUrl = "https://keywa.${config.networking.domain}";
    secretId = "tyo2-luks";
    initrdInterface = "eth0";
    initrdAddress = "216.23.121.85/24";
    initrdGateway = "216.23.121.1";
    sshAuthorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
  };

  # ── IPSec key (dedicated for tyo2) ─────────────────────────────────────
  # Use dedicated IPSec key instead of shared one from modules/gravity,
  # as tyo2's server provider is less trusted.
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

  # Journald: persist to /var/log/journal (paired with impermanence above),
  # cap size to keep disk usage bounded on the 1GB VPS.
  # NixOS 26.x exposes only a few journald options; size caps via extraConfig.
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

  # ── Traffic limiter — 950 GiB/month cap ────────────────────────────────
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

  # ── Hysteria 2 ─────────────────────────────────────────────────────────
  services.hysteria2.listen = ":443";

  # ── Gravity ────────────────────────────────────────────────────────────
  services.gravity = {
    enable = true;
    reload.enable = true;
    divi = {
      enable = true;
      prefix = "2a0c:b641:69c:fb44:0:4::/96";
      oif = "eth0";
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
    address = [ "216.23.121.85/32" ];
  };

  # ── Systemd hardening — physical access mitigation ─────────────────────
  # If an attacker gains VNC/console access, they could try to interrupt
  # boot or access a rescue shell. These mitigations prevent that:
  #
  # 1. Mask serial/tty gettys — no login prompts on console
  # 2. Disable rescue/emergency shells — no root shell on boot failure
  # 3. Lock root account (!) — even if a shell appears, root login fails
  # 4. No GRUB edit/CLI — cannot modify boot params to add init=/bin/sh
  # 5. SysRq disabled — cannot trigger kernel debug commands via VNC
  # 6. Disable debug-shell — blocks 'SHELL' key-triggered root shell at boot
  systemd.services."serial-getty@ttyS0".enable = false;
  systemd.services."serial-getty@ttyS1".enable = false;
  systemd.services."serial-getty@ttyS2".enable = false;
  systemd.services."serial-getty@ttyS3".enable = false;
  systemd.services."getty@tty1".enable = false;
  systemd.services.rescue.enable = false;
  systemd.services.emergency.enable = false;
  systemd.services.systemd-sulogin.enable = false;
  # systemd-debug-generator: pressing SHELL key during early boot spawns
  # a root shell on tty9. With root locked and rootfs encrypted, this is
  # unnecessary and a potential physical-access escape hatch if the boot
  # is otherwise interrupted (BIOS, VNC console, etc.).
  systemd.services."debug-shell.service".enable = false;

  users.users.root.hashedPassword = "!";
  users.users.root.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVTLe5ElQ9zegq5F99LWvi4S5YlH5J0tut+Jxwp/FaNZmgSK6uEY7ySu4r/dKn+dwIwHEej152BMZO2/hGjhmw="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBDijuXohDJEgkv9izzEGJ1vLx/4sSs00aDq3RAI7bj"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKJtITC6SV5Og1+G9qNkqbAojHCtuxi+4GKRMMW+yHl"
  ];
  users.mutableUsers = false;

  # ── Impermanence — persistent state via bind mounts ────────────────────
  # tmpfs root. Only /persist survives.
  # Pair /var/log/journal with services.journald.storage = "persistent" below.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/gravity"
      "/var/lib/vnstat"
      "/var/lib/nixos" # NixOS user/group DB — keeps UIDs/GIDs stable across rollbacks
      "/var/log/journal" # journald logs (requires storage = "persistent")
    ];
    files = [
      "/etc/machine-id"
    ];
  };
}
