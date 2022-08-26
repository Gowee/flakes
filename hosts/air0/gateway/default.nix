{ pkgs, lib, config, ... }:
let cfg = config.services.gateway; in
with lib;{
  options = {
    services.gateway = {
      enable = mkEnableOption "traefik api gateway";
    };
  };
  config = mkIf cfg.enable {
    sops.secrets.traefik-credentials = {
      sopsFile = ./secrets.yaml;
      restartUnits = [ "traefik.service" ];
      owner = "traefik";
      group = "traefik";
    };

    services.traefik = {
      enable = true;
      staticConfigOptions = {
        api = {
          dashboard = true;
        };
        experimental.http3 = true;
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
          pgsql = {
            address = ":5432";
          };
        };
        certificatesResolvers.le.acme = {
          email = "whygowe@gmail.com";
          storage = config.services.traefik.dataDir + "/acme.json";
          keyType = "EC256";
          tlsChallenge = { };
        };
        ping = {
          manualRouting = true;
        };
        metrics = {
          prometheus = {
            addRoutersLabels = true;
            manualRouting = true;
          };
        };
      };
      dynamicConfigOptions = {
        tls.options.default = {
          minVersion = "VersionTLS13";
          sniStrict = true;
        };
        http = {
          middlewares = {
            pgadminHeader = {
              headers = {
                customrequestheaders = {
                  X-Script-Name = "/pgadmin";
                };
              };
            };
            dashboardAuth = {
              basicauth = {
                usersfile = config.sops.secrets.traefik-credentials.path;
              };
            };
          };
          routers = {
            ception = {
              rule = "Host(`${config.networking.fqdn}`)";
              entryPoints = [ "https" ];
              service = "api@internal";
              middlewares = [ "dashboardAuth" ];
            };
            # ping = {
            #   rule = "Host(`${config.networking.fqdn}`) && Path(`/`)";
            #   entryPoints = [ "https" ];
            #   service = "ping@internal";
            # };
            # traefik = {
            #   rule = "Host(`${config.networking.fqdn}`) && Path(`/traefik`)";
            #   entryPoints = [ "https" ];
            #   service = "prometheus@internal";
            # };
            pgadmin = {
              rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/pgadmin`)";
              entryPoints = [ "https" ];
              service = "pgadmin";
              middlewares = [ "pgadminHeader" ];
            };
            influxdb = {
              rule = "Host(`influxdb.${config.networking.domain}`)";
              entrypoints = [ "https" ];
              service = "influxdb";
            };
            grafana = {
              rule = "Host(`grafana.${config.networking.domain}`)";
              entrypoints = [ "https" ];
              service = "grafana";
            };
          };
          services = {
            influxdb = {
              loadBalancer = {
                servers = [
                  { url = "http://localhost:8086"; }
                ];
              };
            };
            grafana = {
              loadBalancer = {
                servers = [
                  { url = "http://localhost:3000"; }
                ];
              };
            };
            pgadmin = {
              loadBalancer = {
                servers = [{ url = "http://localhost:5050"; }];
              };
            };
          };
        };
        tcp = {
          routers = {
            pgsql = {
              rule = "HostSNI(`${config.networking.fqdn}`)";
              entrypoints = [ "pgsql" ];
              service = "pgsql";
              tls.certResolver = "le";
            };
          };
          services = {
            pgsql = {
              loadBalancer = {
                servers = [
                  { address = "localhost:15432"; }
                ];
              };
            };
          };
        };
      };
    };
  };
}
