{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.keywa-pin;

  # The fetch-luks-key script. Bound to a name so we can both reference
  # it from the service's ExecStart AND add it to storePaths (which
  # actually copies the file into the initrd CPIO).
  fetchLukSKeyScript = pkgs.writeShellScript "fetch-luks-key" ''
    set -eu
    set -o pipefail
    echo "Fetching LUKS key from ${cfg.keywaUrl}..."
    # -4: force IPv4 (initrd only has IPv4 configured)
    # --max-time: total budget across retries
    # --retry 9999: essentially infinite retries (until max-time hits)
    # keywa returns base64-encoded secret; decode to plaintext.
    /bin/curl -4 -fsS \
      --cacert /etc/ssl/certs/ca-bundle.crt \
      --max-time ${toString cfg.initrdFetchTimeout} \
      --retry 9999 \
      "${cfg.keywaUrl}/secret/${cfg.secretId}" \
      | base64 -d > /tmp/luks-key
    chmod 400 /tmp/luks-key
    echo "LUKS key fetched successfully."
  '';

  # The initrd-ssh-fingerprint script. Bound to a name so we can add it
  # to storePaths (which copies it into the initrd CPIO).
  initrdSshFingerprintScript = pkgs.writeShellScript "initrd-ssh-fingerprint" ''
    echo ""
    echo "============================================================"
    echo "  INITRD SSH HOST KEY FINGERPRINT (verify before connecting)"
    echo "============================================================"
    ${pkgs.openssh}/bin/ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
    echo "  Key is stable per image — regenerate to change."
    echo "============================================================"
    echo ""
  '';

  # Build-time initrd SSH host key. Baked into /nix/store and copied into
  # the initrd via boot.initrd.secrets. Stable per image — operator verifies
  # fingerprint once per image (printed to console by initrd-ssh-fingerprint).
  #
  # Security note: This key lives in /nix/store, same as any other build-time
  # secret. Low risk — it's only for ephemeral recovery access during initrd,
  # not the LUKS volume or persistent data.
  initrdSshHostKey = pkgs.runCommand "${cfg.secretId}-initrd-ssh-host-key"
    {
      nativeBuildInputs = [ pkgs.openssh ];
    } ''
    ssh-keygen -t ed25519 -f $out -N ""
  '';
in
{
  options.keywa-pin = {
    enable = lib.mkEnableOption "LUKS auto-unlock via keywa (IP allowlist + Telegram approval)";

    keywaUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://keywa.${config.networking.domain}";
      description = "Base URL of the keywa instance.";
    };

    secretId = lib.mkOption {
      type = lib.types.str;
      example = "tyo2-luks";
      description = "Secret ID registered in keywa for this host's LUKS passphrase.";
    };

    sshAuthorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys authorized to log in via initrd SSH (manual recovery).";
    };

    initrdInterface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "Initrd network interface (glob pattern matched by systemd-networkd).";
    };

    initrdDHCP = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use DHCP for initrd networking instead of static IP.";
    };

    initrdAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "216.23.121.85/24";
      description = "Static IPv4 address for initrd (must be in keywa's CIDR allowlist). Unused when initrdDHCP = true.";
    };

    initrdGateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "216.23.121.1";
      description = "IPv4 gateway for initrd network. Unused when initrdDHCP = true.";
    };

    initrdDns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" ];
      description = "DNS servers for initrd (needed to resolve keywaUrl).";
    };

    initrdFetchTimeout = lib.mkOption {
      type = lib.types.int;
      default = 28800;
      description = ''
        Max seconds for initrd curl --max-time. Allows long Telegram approval waits.
        Default 8h. Each retry cycle consumes one MAX_TIMEOUT_SECONDS window from keywa.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.initrdDHCP || (cfg.initrdAddress != null && cfg.initrdGateway != null);
        message = "keywa-pin: initrdAddress and initrdGateway must be set when initrdDHCP is false";
      }
    ];
    # ── initrd binaries ──────────────────────────────────────────────
    # cacert is added via boot.initrd.systemd.contents below (not initrdBin
    # which only exposes /bin). curl is the only binary fetch-luks-key needs.
    boot.initrd.systemd.initrdBin = with pkgs; [
      curl
    ];

    # ╔═════════════════════════════════════════════════════════════════╗
    # ║ RUNTIME: initrd fetch-luks-key.service                        ║
    # ║                                                                 ║
    # ║ Long-poll keywa with infinite retries and 8h budget.           ║
    # ║ Auth: IP allowlist only (no token, no PSK).                    ║
    # ║ Each retry triggers a fresh Telegram notification.             ║
    # ║ Result written to /tmp/luks-key, consumed by cryptsetup open.   ║
    # ╚═════════════════════════════════════════════════════════════════╝
    # Copy the CA bundle into the initrd so curl can verify keywa's TLS cert.
    # initrdBin only exposes /bin; the cert at cacert/etc/ssl/certs/ is NOT
    # copied. We must use boot.initrd.systemd.contents to place the file at
    # /etc/ssl/certs/ca-bundle.crt (curl's default SSL_CERT_FILE location).
    boot.initrd.systemd.contents."/etc/ssl/certs/ca-bundle.crt".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

    # The fetch-luks-key shell script (produced by pkgs.writeShellScript)
    # lives at a /nix/store path. initrdBin only exposes /bin; the script
    # is NOT automatically copied into the initrd. We must add it to
    # storePaths so the unit file's ExecStart path actually exists in
    # the initrd CPIO.

    # cryptsetup@cryptroot.service fires on the udev block-device event
    # (/dev/disk/by-partlabel/disk-main-root appears), which happens
    # BEFORE initrd.target is reached. Triggering via wantedBy=initrd.target
    # is too late — cryptsetup runs first, finds no key, fails, and
    # initrd.target is never reached (deadlock).
    #
    # Fix: wantedBy=cryptsetup.target makes fetch-luks-key a dependency of
    # cryptsetup.target. cryptsetup-pre.target runs fetch-luks-key before
    # cryptsetup services. The Before=cryptsetup-pre.target ensures the
    # order within the target graph. After=network-online.target makes
    # the service wait for network before running.
    boot.initrd.systemd.services.fetch-luks-key = {
      description = "Fetch LUKS key from keywa (IP allowlist, Telegram-approved)";
      wantedBy = [ "cryptsetup.target" ];
      before = [ "cryptsetup-pre.target" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
      # DefaultDependencies=yes adds implicit After=sysinit.target, creating ordering cycle:
      # fetch-luks-key → sysinit.target → cryptsetup.target → systemd-cryptsetup@cryptroot → fetch-luks-key
      # All real deps are explicit above; no need for default ordering.
      unitConfig.DefaultDependencies = false;
      # storePaths below copies the actual script into the initrd CPIO.
      # Without this, the unit's ExecStart path is a /nix/store path
      # that doesn't exist in the initrd, and the service fails with
      # status=203/EXEC ("No such file or directory").
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${fetchLukSKeyScript}";
      };
    };
    # Drop-in override for systemd-cryptsetup@cryptroot.service.
    # Without this, udev fires cryptsetup immediately when the block device
    # appears — BEFORE network is up and BEFORE fetch-luks-key writes the key.
    # The drop-in adds After=fetch-luks-key.service so cryptsetup waits.
    boot.initrd.systemd.services."systemd-cryptsetup@cryptroot" = {
      overrideStrategy = "asDropin";
      after = [ "fetch-luks-key.service" ];
      requires = [ "fetch-luks-key.service" ];
    };
    # Copy the fetch-luks-key script into the initrd CPIO. Without this,
    # the unit's ExecStart path doesn't exist at runtime.
    boot.initrd.systemd.storePaths = [ fetchLukSKeyScript initrdSshFingerprintScript pkgs.openssh ];

    # ╔═════════════════════════════════════════════════════════════════╗
    # ║ RUNTIME: initrd network                                       ║
    # ║                                                                 ║
    # ║ Brings up the management interface during initrd so fetch-    ║
    # ║ luks-key can reach keywa. Static IP or DHCP based on config.  ║
    # ║ Address must be in keywa's CIDR allowlist if using static IP. ║
    # ╚═════════════════════════════════════════════════════════════════╝
    boot.initrd.systemd.network = {
      enable = true;
      networks."10-initrd-eth" = {
        matchConfig.Name = [ cfg.initrdInterface ];
        dns = cfg.initrdDns;
        networkConfig = {
          KeepConfiguration = "yes";
        } // lib.optionalAttrs cfg.initrdDHCP {
          DHCP = "yes";
        };
      } // lib.optionalAttrs (!cfg.initrdDHCP) {
        address = [ cfg.initrdAddress ];
        routes = [{ Gateway = cfg.initrdGateway; }];
      };
    };

    # ╔═════════════════════════════════════════════════════════════════╗
    # ║ RUNTIME: initrd SSH (manual fallback)                         ║
    # ║                                                                 ║
    # ║ Allows operator SSH access during initrd for manual recovery  ║
    # ║ (e.g., Telegram unavailable, network down). Lands in /bin/sh. ║
    # ║                                                                 ║
    # ║ Host key: STABLE PER IMAGE, generated at build time and       ║
    # ║ baked into /nix/store. Copied into initrd via                 ║
    # ║ boot.initrd.secrets. Per-image TOFU — operator verifies       ║
    # ║ fingerprint once per image (printed to console).              ║
    # ║                                                                 ║
    # ║ NOT random per boot (we tried — NixOS now requires pre-       ║
    # ║ generated host keys for initrd SSH).                           ║
    # ║                                                                 ║
    # ║ Rescue/emergency services in initrd are NOT disabled here —  ║
    # ║ SSH is the primary fallback path, but emergency.target        ║
    # ║ still works for kernel/initrd debugging.                      ║
    # ╚═════════════════════════════════════════════════════════════════╝
    boot.initrd.systemd.services.initrd-ssh-fingerprint = {
      description = "Print initrd SSH host key fingerprint";
      wantedBy = [ "sshd.service" ];
      after = [ "sshd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${initrdSshFingerprintScript}";
      };
    };
    # initrd SSH host key: stable per image, generated at build time.
    # The key is in /nix/store (same as any build-time secret). Low risk —
    # initrd SSH is ephemeral recovery access only, not the LUKS volume.
    boot.initrd.network.ssh = {
      enable = true;
      port = 22;
      authorizedKeys = cfg.sshAuthorizedKeys;
      hostKeys = [ initrdSshHostKey ];
    };
    boot.initrd.systemd.services."emergency.service".enable = false;
    boot.initrd.systemd.services."rescue.service".enable = false;
  };
}
