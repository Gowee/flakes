{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ranet-ipsec = {
      url = "github:NickCao/ranet";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    colmena = {
      url = "github:zhaofengli/colmena/v0.4.0";
    };
  };

  outputs = inputs@{ self, nixpkgs, disko, sops-nix, colmena, ... }: {
    nixosModules = import ./modules;
    nixosConfigurations = nixpkgs.lib.genAttrs [ "svr1" "bud0" ] (name: nixpkgs.lib.nixosSystem {
      specialArgs = { inherit self inputs; };
      system = "x86_64-linux";
      modules = [
        ./hosts/${name}
      ];
    });
    colmenaHive = {
      meta = {
        specialArgs = {
          inherit inputs;
          inherit self;
        };
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
        };
      };
    } // nixpkgs.lib.genAttrs [ "svr1" "bud0" "nah0" ] (name: {
      deployment =
        {
          targetHost = "${name}.rua.st";
          keys."sops.key" = {
            keyCommand = [ "sh" "-c" "cat $HOME/.config/sops/age/keys.txt || cat /tmp/sops.key" ];
            destDir = "/var/lib";
            uploadAt = "pre-activation";
          };
        };
      imports = [ ./hosts/${name} ];
    });
  };
}
