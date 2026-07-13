{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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
      url = "github:nix-community/colmena/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
    swan-updown = {
      url = "github:Gowee/swan-updown";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, disko, sops-nix, colmena, impermanence, ... }:
    let
      # Single source of truth for the deployment domain. Used by:
      #   - Colmena targetHost
      #   - Each host's networking.domain (via specialArgs)
      #   - Cross-service URLs (keywa, hysteria, etc.)
      infraDomain = "rua.st";

      hostNames = [ "nah0" "tyo2" "nium0" "tyo3" /* "bud0" "svr1" */ ];
      luksHosts = [ "tyo2" ];

      # ── Colmena 0.4 hive (colmenaHive = colmena.lib.makeHive { ... }) ─────
      # `deployment.keys.<name>.destDir` derives from each host's
      # `sops.age.keyFile` parent directory so the contract between Colmena
      # upload path and sops-nix read path is a single source of truth
      # (the keyFile option in the host's configuration.nix).
      #
      # The self-reference `self.colmenaHive.nodes.${name}.config.sops.age.keyFile`
      # resolves via Nix lazy evaluation + memoization: destDir forces only the
      # keyFile option (set in static config.nix), not the full deployment block.
      # This is safe, tested, and avoids duplicating the keyFile path.
      colmenaHive = inputs.colmena.lib.makeHive (
        {
          meta = {
            nixpkgs = import nixpkgs {
              system = "x86_64-linux";
            };
            specialArgs = {
              inherit inputs;
              inherit self;
              inherit infraDomain;
            };
          };
        } // nixpkgs.lib.genAttrs hostNames (name: { ... }: {
          deployment =
            {
              targetHost = "${name}.${infraDomain}";
              keys."sops.key" = {
                keyCommand = [ "sh" "-c" "cat $HOME/.config/sops/age/${name}-key.txt || cat $HOME/.config/sops/age/keys.txt" ];
                destDir = builtins.dirOf self.colmenaHive.nodes.${name}.config.sops.age.keyFile;
                uploadAt = "pre-activation";
              };
            };
          imports = [ ./hosts/${name} ];
        })
      );
    in
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          build-image = name:
            let
              hostConfig = self.colmenaHive.nodes.${name}.config;
              hasKeywa = hostConfig.keywa-pin.enable or false;
              secretId = hostConfig.keywa-pin.secretId or "";
            in
            pkgs.writeShellScriptBin "build-luks-${name}-image" ''
              set -euo pipefail
              HOST="${name}"

              DISK_ARGS=()

              ${nixpkgs.lib.optionalString hasKeywa ''
              KEY_FILE="''${TMPDIR:-/tmp}/$HOST-luks-key"
              cleanup() { ${pkgs.coreutils}/bin/rm -f "$KEY_FILE"; }
              trap cleanup EXIT
              echo "==> Fetching LUKS key from keywa (Telegram approval)..."
              ${pkgs.curl}/bin/curl -4 -fsS --max-time 900 \
                "https://keywa.rua.st/secret/${secretId}?timeout=901" \
                | ${pkgs.coreutils}/bin/base64 -d > "$KEY_FILE"
              ${pkgs.coreutils}/bin/chmod 600 "$KEY_FILE"
              DISK_ARGS+=(--pre-format-files "$KEY_FILE" /tmp/luks-key)
              ''}

              SOPS_KEY="''${SOPS_KEY:-$HOME/.config/sops/age/$HOST-key.txt}"
              if [ -f "$SOPS_KEY" ]; then
                DISK_ARGS+=(--post-format-files "$SOPS_KEY" /persist/var/lib/sops.key)
                echo "==> Baking sops.key from $SOPS_KEY"
              fi

              echo "==> Building disko image script..."
              DISKO_SCRIPT="$(nix build --no-link --print-out-paths \
                .#nixosConfigurations.$HOST.config.system.build.diskoImagesScript)"

              echo "==> Building disk image for $HOST..."
              "$DISKO_SCRIPT" "''${DISK_ARGS[@]}"
              echo "==> Done: $PWD/main.raw"
            '';
        in
        {
          packages = nixpkgs.lib.listToAttrs (map
            (name: {
              name = "build-luks-${name}-image";
              value = build-image name;
            })
            luksHosts);
        }
      ) // {
      colmenaHive = colmenaHive;
      nixosModules = import ./modules;
      nixosConfigurations = self.colmenaHive.nodes;
    };
}
