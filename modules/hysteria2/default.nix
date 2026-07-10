{ config, pkgs, lib, ... }:
let
  cfg = config.services.hysteria2;
  checkPasswordScript = pkgs.writeShellScript "hysteria2-check-password" ''
    PASSWORD_FILE="${config.sops.secrets.hysteria2-password.path}"
    EXPECTED=$(cat "$PASSWORD_FILE")
    if [ "$1" = "$EXPECTED" ]; then
      echo "ok"
    else
      echo "reject"
      exit 1
    fi
  '';
  configFile = pkgs.writeText "hysteria2-server.yaml" ''
    listen: ${cfg.listen}
    acme:
      domains:
        - ${config.networking.hostName}.${config.networking.domain}
      email: admin@${config.networking.domain}
    auth:
      type: command
      command: ${checkPasswordScript}
    masquerade:
      type: proxy
      proxy:
        url: https://news.ycombinator.com/
        rewriteHost: true
  '';
in
{
  options.services.hysteria2 = {
    listen = lib.mkOption {
      type = lib.types.str;
      default = ":4433";
      description = "Address and port to listen on";
    };
  };

  config = {
    sops.secrets.hysteria2-password = {
      sopsFile = ./secrets.yaml;
      restartUnits = [ "hysteria2.service" ];
    };

    systemd.services.hysteria2 = {
      description = "Hysteria2 Server";
      after = [ "network.target" "sops-nix.service" "sops-install-secrets.service" ];
      wants = [ "network.target" "sops-install-secrets.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hysteria}/bin/hysteria server --config ${configFile}";
        Restart = "on-failure";
        RestartSec = "5s";
        DynamicUser = true;
        # ACME cert dir needs to be writable
        StateDirectory = "hysteria2";
        WorkingDirectory = "/var/lib/hysteria2";
        # Allow binding to port 443 (or any privileged port if needed, though 4433 is > 1024)
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
      };
    };
  };
}
