{ config, lib, pkgs, ... }:
{
  # Automatic Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Automatically optimise the Nix store (deduplication)
  nix.settings.auto-optimise-store = true;

  # Limit boot loader generations to save disk space
  boot.loader.systemd-boot.configurationLimit = 3;
  boot.loader.grub.configurationLimit = 3;

  services.journald.extraConfig = ''
    SystemMaxUse=100M
    SystemKeepFree=500M
    RuntimeMaxUse=50M
    MaxRetentionSec=2weeks
  '';
}
