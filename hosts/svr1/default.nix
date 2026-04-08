{ config, pkgs, lib, specialArgs, ... }:
{
  imports = with specialArgs;[
    ./configuration.nix
    ./gateway
    ./influxdb2.nix
    ./tut-pod
    # ./pgsql
    self.nixosModules.cachix
    self.nixosModules.hysteria2
    self.nixosModules.nix-maintenance
    self.nixosModules.telegraf
    self.nixosModules.shadowsocks
    self.nixosModules.gravity
    self.nixosModules.common
    # self.nixosModules.vultr
    # self.nixosModules.v2ray
    # self.nixosModules.cloud.common
    # {
    #   nixpkgs.overlays = [
    #     self.overlays.default
    #     (final: prev: {
    #       ranet = inputs.ranet.packages.${pkgs.system}.default;
    #       bird = prev.bird-babel-rtt;
    #     })
    #   ];
    # }
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    # inputs.impermanence.nixosModules.impermanence
    self.nixosModules.config-revision
  ];
}
