{ config, pkgs, lib, specialArgs, ... }:
{
  imports = with specialArgs;[
    ./configuration.nix
    ./hardware-configuration.nix
    self.nixosModules.cachix
    self.nixosModules.hysteria2
    self.nixosModules.shadowsocks
    self.nixosModules.gravity
    self.nixosModules.common
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    self.nixosModules.config-revision
  ];
}
