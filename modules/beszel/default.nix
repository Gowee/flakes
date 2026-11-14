{ config, ... }:
{
  sops.secrets.beszel_agent_env = {
    sopsFile = ./secrets.yaml;
    restartUnits = [ "beszel-agent.service" ];
  };

  services.beszel.agent = {
    enable = true;
    environmentFile = config.sops.secrets.beszel_agent_env.path;
    environment = {
      HUB_URL = "https://nah0.${config.networking.domain}";
      SYSTEM_NAME = config.networking.hostName;
    };
  };

  systemd.services.beszel-agent = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };
}
