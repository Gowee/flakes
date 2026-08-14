{ config, pkgs, lib, specialArgs, ... }:
{
  imports = with specialArgs; [
    ./configuration.nix
    ./gateway.nix
    ./tut-pod
    ./monitoring.nix
    #./mongodb
    self.nixosModules.cachix
    self.nixosModules.hysteria2
    self.nixosModules.nix-maintenance
    self.nixosModules.shadowsocks
    self.nixosModules.common
    self.nixosModules.node-exporter
    self.nixosModules.prometheus-server
    # ./influxdb2.nix
    self.nixosModules.gravity
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
    # inputs.impermanence.nixosModules.impermanence
    self.nixosModules.config-revision
  ];
}
