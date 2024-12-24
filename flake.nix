{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";  
    };
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, disko, sops-nix, ... }: {
    nixosModules = import ./modules;
    nixosConfigurations.svr1 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sops-nix.nixosModules.sops
        disko.nixosModules.disko
        ./hosts/svr1/configuration.nix
        ];
    };
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
    } // nixpkgs.lib.genAttrs [ "svr1" ] (name: {
      deployment =
        {
          targetHost = "${name}.rua.st";
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
