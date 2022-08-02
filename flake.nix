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

      nah0 = {
        deployment = {
          targetHost = "nah0.lotust.xyz";
          # targetPort = 22;
          # targetUser = "root";
        };
        imports = [ ./hosts/nah0 ];
        # boot.isContainer = true;
        # time.timeZone = "America/Los_Angeles";
      };
    };
  };
}
