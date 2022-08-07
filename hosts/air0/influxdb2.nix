{ config, lib, pkgs, ... }:
{
  config = {
    services.influxdb2.enable = true;
    services.influxdb2.settings = {
      http-bind-address = "127.0.0.1:8086";
      # query-concurrency = 20;
      # query-queue-size = 15;
      # session-length = 120;
      # tls-cert = /path/to/influxdb.crt;
      # tls-key = /path/to/influxdb.key;
    };
  };
}
