{
  description = "Deployment for my server cluster";

  # For accessing `deploy-rs`'s utility Nix functions
  inputs.deploy-rs.url = "github:serokell/deploy-rs";

  outputs = { self, nixpkgs, deploy-rs }: {
    nixosConfigurations.nah0 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./nah0/configuration.nix ];
    };

    deploy.nodes.nah0 = {
        hostname = "nah0.lotust.xyz"
        profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nah0;
        };
    }

    # This is highly advised, and will prevent many possible mistakes
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
  };
}

