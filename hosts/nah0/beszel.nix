{ config, pkgs, lib, ... }:
let
  cfg = config.services.beszel.hub;
  seedKeyScript = pkgs.writeShellScript "beszel-hub-seed-key" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/install -d -m 750 "$STATE_DIRECTORY/beszel_data"
    ${pkgs.coreutils}/bin/install -m 600 "$CREDENTIALS_DIRECTORY/id_ed25519" "$STATE_DIRECTORY/beszel_data/id_ed25519"
  '';
  seedTokenScript = pkgs.writeShellScript "beszel-hub-seed-token" ''
    set -euo pipefail
    TOKEN=$(${pkgs.gnused}/bin/sed -n 's/^TOKEN=//p' "$CREDENTIALS_DIRECTORY/agent_env")
    [ -n "$TOKEN" ]
    BASE="http://${cfg.host}:${toString cfg.port}"
    ready=0
    for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
      if ${pkgs.curl}/bin/curl -sf "$BASE/api/health" >/dev/null; then
        ready=1
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.5
    done
    [ "$ready" -eq 1 ]
    AUTH_PAYLOAD=$(${pkgs.jq}/bin/jq -nc --arg id "$USER_EMAIL" --arg pw "$USER_PASSWORD" '{identity: $id, password: $pw}')
    JWT=$(${pkgs.curl}/bin/curl -sf -X POST "$BASE/api/collections/users/auth-with-password" \
      -H 'Content-Type: application/json' \
      -d "$AUTH_PAYLOAD" | ${pkgs.jq}/bin/jq -er '.token')
    RESP=$(${pkgs.curl}/bin/curl -sf -H "Authorization: $JWT" \
      "$BASE/api/beszel/universal-token?token=$TOKEN&enable=1&permanent=1")
    ${pkgs.jq}/bin/jq -e --arg t "$TOKEN" '.active == true and .permanent == true and .token == $t' <<<"$RESP" >/dev/null
  '';
in
{
  sops.secrets.beszel_hub_env = {
    sopsFile = ./secrets.yaml;
    restartUnits = [ "beszel-hub.service" ];
  };

  sops.secrets.beszel_hub_key = {
    sopsFile = ./secrets.yaml;
    restartUnits = [ "beszel-hub.service" ];
  };

  services.beszel.hub = {
    enable = true;
    environmentFile = config.sops.secrets.beszel_hub_env.path;
    environment = {
      APP_URL = "https://nah0.${config.networking.domain}";
    };
  };

  systemd.services.beszel-hub = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
    serviceConfig = {
      LoadCredential = [
        "id_ed25519:${config.sops.secrets.beszel_hub_key.path}"
        "agent_env:${config.sops.secrets.beszel_agent_env.path}"
      ];
      ExecStartPre = lib.mkBefore [ "${seedKeyScript}" ];
      ExecStartPost = [ "${seedTokenScript}" ];
    };
  };

  systemd.services.beszel-agent.after = [ "beszel-hub.service" ];
}
