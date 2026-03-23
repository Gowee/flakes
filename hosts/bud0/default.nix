{ config, pkgs, lib, specialArgs, ... }:
{
  imports = with specialArgs;[
    ./configuration.nix
    self.nixosModules.cachix
    self.nixosModules.hysteria2
    self.nixosModules.nix-maintenance
    self.nixosModules.telegraf
    self.nixosModules.shadowsocks
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
  ];
}
