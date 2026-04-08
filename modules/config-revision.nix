{ config, pkgs, lib, self, ... }:
{
  # Set the system's configuration revision using the flake's Git commit hash.
  # This allows for precise tracking of the configuration applied to the system.
  system.configurationRevision = self.rev or self.dirtyRev or null;
}
