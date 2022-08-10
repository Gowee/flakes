{ config, lib, pkgs, ... }:
{
  sops.secrets.mongo-init-script = {
    sopsFile = ./secrets.yaml;
    restartUnits = [ "mongodb.service" ];
  };

  services.mongodb = {
    enable = true;
    enableAuth = true;
    initialRootPassword = "root";
    initialScript = config.sops.secrets.mongo-init-script.path;
  };
}
