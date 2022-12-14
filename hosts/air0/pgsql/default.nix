{ config, lib, pkgs, ... }:
{
  config = {
    services.postgresql.enable = true;
    services.postgresql.port = 15432;
    services.postgresql.ensureUsers = [
      {
        name = "lamp";
        ensurePermissions = {
          "DATABASE lamp" = "ALL PRIVILEGES";
        };
      }
    ];
    services.postgresql.ensureDatabases = [
      "lamp"
    ];


    sops.secrets.pgadmin-password = {
      sopsFile = ./secrets.yaml;
      mode = "0440";
      owner = config.users.users.pgadmin.name;
      group = config.users.users.pgadmin.group;
      restartUnits = [ "pgadmin.service" ];
    };


    services.pgadmin.enable = true;
    services.pgadmin.settings = {
      SCRIPT_NAME = "/pgadmin";
    };
    services.pgadmin.initialEmail = "admin@${config.networking.domain}";
    services.pgadmin.initialPasswordFile = config.sops.secrets.pgadmin-password.path;
  };
}
