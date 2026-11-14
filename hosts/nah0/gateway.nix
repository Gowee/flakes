{ pkgs, lib, config, ... }:
let cfg = config.services.gateway; in
with lib;
{
  options = {
    services.gateway = {
      enable = mkEnableOption "traefik api gateway";
    };
  };
  config = mkIf cfg.enable
    {
      services.traefik = {
        enable = true;
        staticConfigOptions = {
          entryPoints = {
            http = {
              address = ":80";
              http.redirections.entryPoint = {
                to = "https";
                scheme = "https";
                permanent = false;
              };
            };
            https = {
              address = ":443";
              http.tls.certResolver = "le";
              http3 = { };
            };
          };
          certificatesResolvers.le.acme = {
            email = "whygowe@gmail.com";
            storage = config.services.traefik.dataDir + "/acme.json";
            keyType = "EC256";
            tlsChallenge = { };
          };
          # ping = {
          #   manualRouting = true;
          # };
          # metrics = {
          #   prometheus = {
          #     addRoutersLabels = true;
          #     manualRouting = true;
          #   };
          # };
        };
        dynamicConfigOptions = {
          tls.options.default = {
            minVersion = "VersionTLS13";
            sniStrict = true;
          };
          http = {
            routers = {
              beszel = {
                rule = "Host(`nah0.${config.networking.domain}`)";
                entryPoints = [ "https" ];
                service = "beszel";
              };
            };
            services = {
              beszel = {
                loadBalancer = {
                  servers = [
                    { url = "http://${config.services.beszel.hub.host}:${toString config.services.beszel.hub.port}"; }
                  ];
                };
              };
            };
          };
        };
      };
    };
}
