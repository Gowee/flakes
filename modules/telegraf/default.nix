{ config, pkgs, lib, ... }:
{
  sops.secrets.telegraf = {
    sopsFile = ./secrets.yaml;
    restartUnits = [ "telegraf.service" ];
  };

  services.telegraf.enable = true;
  services.telegraf.environmentFiles = [ config.sops.secrets.telegraf.path ];
  services.telegraf.extraConfig = {
    outputs.influxdb_v2 = {
      urls = [ "https://influxdb.${config.networking.domain}" ];
      organization = "berry";
      bucket = "bubble";
      token = "$INFLUXDB_TOKEN";
    };
    inputs = {
      cpu = {
        percpu = true;
        totalcpu = true;
        collect_cpu_time = false;
        report_active = false;
      };
      disk = {
        ignore_fs = [ "tmpfs" "devtmpfs" "devfs" "iso9660" "overlay" "aufs" "squashfs" ];
      };
      diskio = { };
      kernel = { };
      mem = { };
      processes = { };
      swap = { };
      system = { };
    };
  };
}
