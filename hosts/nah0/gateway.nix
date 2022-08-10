{ pkgs, lib, config, ... }:
let cfg = config.services.web; in
with lib;
{
  options = {
    services.web = {
      enable = mkEnableOption "traefik api gateway";
    };
  };
  config = mkIf cfg.enable
    {
      services.traefik = {
        enable = true;
        staticConfigOptions = {
          experimental.http3 = true;
          entryPoints = {
            # http = {
            #   address = ":80";
            #   http.redirections.entryPoint = {
            #     to = "https";
            #     scheme = "https";
            #     permanent = false;
            #   };
            # };
            # https = {
            #   address = ":443";
            #   http.tls.certResolver = "le";
            #   http3 = { };
            # };
            mongo = {
              address = ":27017";
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
            routers = { };
            services = { };
            tcp = {
              routers = {
                mongo = {
                  rule = "HostSNI(`air0.${config.network.domain}`)";
                  entrypoints = "mongo";
                  tls = true;
                };
              };
              services = {
                mongo = {
                  loadbalancer = {
                    servers = [
                      { port = "27017"; }
                    ];
                  };
                };
              };
            };
          };
        };
      };
    };
}
