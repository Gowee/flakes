{ config, lib, pkgs, ... }:
let
  cfg = config.keywa-sops;
in
{
  options.keywa-sops = {
    enable = lib.mkEnableOption "fetch sops age key from keywa at boot";

    keywaUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://keywa.${config.networking.domain}";
      description = "Base URL of the keywa instance.";
    };

    secretId = lib.mkOption {
      type = lib.types.str;
      example = "nium0-sops";
      description = "Secret ID registered in keywa for this host's sops age key.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.fetch-sops-key = {
      description = "Fetch sops age key from keywa";
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "fetch-sops-key" ''
          set -euo pipefail
          echo "Fetching sops key from ${cfg.keywaUrl}..."
          ${pkgs.curl}/bin/curl -4 -fsS \
            --max-time 28800 \
            --retry 9999 \
            --retry-delay 1 \
            "${cfg.keywaUrl}/secret/${cfg.secretId}?timeout=28801" \
            > /run/sops.key
          ${pkgs.coreutils}/bin/chmod 400 /run/sops.key
          echo "Sops key fetched successfully."
        '';
      };
    };

    systemd.services.sops-install-secrets = {
      after = [ "fetch-sops-key.service" ];
      requires = [ "fetch-sops-key.service" ];
    };
  };
}
