{ config, lib, pkgs, ... }:
{
  sops.secrets.shadowsocks-password = {
    sopsFile = ./secrets.yaml;
    restartUnits = [ "shadowsocks-libev.service" ];
  };

  services.shadowsocks = {
    enable = true;
    port = 8964;
    mode = "tcp_and_udp";
    fastOpen = true;
    passwordFile = config.sops.secrets.shadowsocks-password.path;
    encryptionMethod = "chacha20-ietf-poly1305";
  };

  nixpkgs.config.permittedInsecurePackages = [
    "mbedtls-2.28.10"
  ];
}
