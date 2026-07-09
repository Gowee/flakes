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
      url = "github:zhaofengli/colmena/v0.4.0";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, disko, sops-nix, colmena, impermanence, ... }:
    let
      # Single source of truth for the deployment domain. Used by:
      #   - Colmena targetHost
      #   - Each host's networking.domain (via specialArgs)
      #   - Cross-service URLs (keywa, hysteria, etc.)
      infraDomain = "rua.st";

      hosts = [ "svr1" "nah0" "tyo2" "nium0" /* "bud0" */ ];
      diskoHosts = [ "svr1" "tyo2" "nium0" ];

      nixosConfigurations = nixpkgs.lib.genAttrs hosts (name: nixpkgs.lib.nixosSystem {
        specialArgs = { inherit self inputs; inherit infraDomain; };
        system = "x86_64-linux";
        modules = [
          ./hosts/${name}
        ];
      });

      colmenaConfig = {
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
      } // nixpkgs.lib.genAttrs hosts (name: {
        deployment =
          {
            targetHost = "${name}.${infraDomain}";
            keys."sops.key" = {
              keyCommand = [ "sh" "-c" "cat $HOME/.config/sops/age/${name}-key.txt || cat $HOME/.config/sops/age/keys.txt" ];
              destDir = builtins.dirOf nixosConfigurations.${name}.config.sops.age.keyFile;
              uploadAt = "pre-activation";
            };
          };
        imports = [ ./hosts/${name} ];
      });
    in
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          build-image = name:
            let
              hostConfig = nixosConfigurations.${name}.config;
              hasKeywa = hostConfig.keywa-pin.enable or false;
              secretId = hostConfig.keywa-pin.secretId or "";
            in
            pkgs.writeShellScriptBin "build-${name}-image" ''
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
          legacyPackages.colmena = colmenaConfig;
          packages = nixpkgs.lib.listToAttrs (map
            (name: {
              name = "build-${name}-image";
              value = build-image name;
            })
            diskoHosts);
        }
      ) // {
      colmena = colmenaConfig;
      nixosModules = import ./modules;
      inherit nixosConfigurations;
    };
}
