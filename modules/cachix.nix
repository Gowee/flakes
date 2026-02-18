{ ... }:
{
  nix.settings = {
    substituters = [ "https://berry.cachix.org" ];
    trusted-public-keys = [ "berry.cachix.org-1:hDpfDwdw5hN3LJG6aDaYKqI3Mb222JBMcXkVPuOQBRc" ];
  };
}
