{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs@{ nixpkgs, ... }: {
    colmena = {
      meta = {
        specialArgs = {
          inherit inputs;
        };
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
        };
      };
    } // nixpkgs.lib.genAttrs [ "nah0" "air0" ] (name: {
      deployment =
        {
          targetHost = "${name}.lotust.xyz";
          keys."sops.key" = {
            keyFile = ./sops.key;
            destDir = "/run/keys";
            uploadAt = "pre-activation";
          };
        };
      imports = [ ./hosts/${name} ];
    });
  };
}
