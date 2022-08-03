{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = { nixpkgs, ... }: {
    colmena = {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
        };
      };
    } // inputs.nixpkgs.lib.genAttrs [ "nah0" "air0" ] (name: {
      deployment =
        {
          targetHost = "${name}.lotust.xyz";
        }
          imports = [ ./hosts/${name} ];
    });
  };
}
