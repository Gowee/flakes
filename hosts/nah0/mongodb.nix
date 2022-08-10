{ config, lib, pkgs, ... }:
{
  config = {
    services.mongodb.enable = true;
    services.mongodb.enableAuth = true;
    services.mongodb.initialRootPassword = "root"
  };
}
