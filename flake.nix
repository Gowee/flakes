{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, ... }: {
    nixosModules = import ./modules;
    colmena = {
      meta = {
        specialArgs = {
          inherit inputs;
          inherit self;
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
            keyCommand = [ "sh" "-c" "cat $HOME/.config/sops/age/keys.txt || cat /tmp/sops.key" ];
            destDir = "/run/keys";
            uploadAt = "pre-activation";
          };
        };
      imports = [ ./hosts/${name} ];
    });
  };
}
