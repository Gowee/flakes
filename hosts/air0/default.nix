{ config, pkgs, lib, ... }:
{
  imports = [
    ./configuration.nix
    ./web.nix
    ./influxdb2.nix
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
    # inputs.sops-nix.nixosModules.sops
    # inputs.impermanence.nixosModules.impermanence
  ];
}