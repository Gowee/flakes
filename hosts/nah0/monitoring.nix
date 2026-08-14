# Grafana on nah0, fronted by the traefik gateway (grafana.rua.st).
# Prometheus (prometheus-server module) is scraped at 127.0.0.1:9090.
{ config, pkgs, lib, infraDomain, ... }:
{
  sops.secrets.grafana_secret_key = {
    sopsFile = ./secrets.yaml;
    owner = "grafana";
    group = "grafana";
  };

  sops.secrets.grafana_admin_password = {
    sopsFile = ./secrets.yaml;
    owner = "grafana";
    group = "grafana";
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain = "grafana.${infraDomain}";
        root_url = "https://grafana.${infraDomain}/";
      };
      security = {
        # public endpoint (grafana.rua.st) -> non-default admin + sops password
        admin_user = "admin";
        admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
        secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
      };
      # login-only: no anonymous browsing, no self-registration
      "auth.anonymous".enabled = false;
      users.allow_sign_up = false;
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:9090";
          isDefault = true;
        }
      ];
    };
  };
}
