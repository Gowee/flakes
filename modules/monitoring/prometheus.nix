# Prometheus server (nah0) scraping every gravity host's node_exporter over the
# mesh IPv6, with mutual TLS reusing gravity ipsec keys. Targets are discovered
# from the hive (single source of truth) rather than hardcoded.
{ config, pkgs, lib, self, certDir, ... }:
let
  dir = certDir;

  # Discover mesh nodes from self.colmenaHive (same lazy self-eval pattern as
  # the sops.key destDir in flake.nix).
  nodes = builtins.attrNames self.colmenaHive.nodes;
  meshNodes = builtins.filter
    (n: self.colmenaHive.nodes.${n}.config.services.gravity.enable or false)
    nodes;
  targets = map
    (n:
      let
        addrs = self.colmenaHive.nodes.${n}.config.services.gravity.address or [ ];
        ip =
          if addrs == [ ]
          then null
          else lib.removeSuffix "/128" (builtins.head addrs);
      in
      if ip == null then null else "[${ip}]:9100")
    meshNodes;
  targets' = builtins.filter (t: t != null) targets;
in
{
  assertions = [
    {
      assertion = builtins.pathExists "${dir}/nah0.crt";
      message = "monitoring/prometheus: missing ${dir}/nah0.crt — run scripts/gen-monitoring-certs.sh and commit the result";
    }
    {
      assertion = builtins.pathExists "${dir}/cluster-nodes.crt";
      message = "monitoring/prometheus: missing ${dir}/cluster-nodes.crt — run scripts/gen-monitoring-certs.sh and commit the result";
    }
  ];

  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "127.0.0.1";
    # `promtool check` stats key_file, which is sops-installed at boot (only
    # exists at runtime), so a build-time check would fail — skip it.
    checkConfig = false;
    globalConfig.scrape_interval = "15s";
    scrapeConfigs = [
      {
        job_name = "node_exporter";
        scheme = "https";
        tls_config = {
          cert_file = "${dir}/nah0.crt";
          key_file = "/run/prometheus/ipsec.key";
          ca_file = "${dir}/cluster-nodes.crt";
          insecure_skip_verify = false;
        };
        static_configs = [
          {
            targets = targets';
            labels = {
              env = "production";
            };
          }
        ];
      }
    ];
  };

  systemd.services.prometheus = {
    wants = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    # `+` prefix: root copies the sops ipsec key for the prometheus user.
    serviceConfig.ExecStartPre = [
      "+${pkgs.coreutils}/bin/install -d -m 0755 -o prometheus -g prometheus /run/prometheus"
      "+${pkgs.coreutils}/bin/install -m 0400 -o prometheus -g prometheus ${config.sops.secrets.ipsec.path} /run/prometheus/ipsec.key"
    ];
  };

  # Prometheus runs in the main routing table (grafana scrapes it over loopback).
  # The shared gravity module keeps the mesh /48 source-policy-filtered, so an
  # unbound main-table socket has no path into the mesh: the /48 dev gravity
  # route in main recurses into the gravity VRF, where the `[l3mdev-table]
  # unreachable` rule (rule pref 2000) blackholes main-table traffic before it
  # ever reaches a gn* tunnel; `ip route get` falls through to the eth0 default.
  #
  # A routing policy rule hopping main-table traffic for the mesh /48 straight
  # into table 200 is the only working escape: the reply then arrives on a gn*
  # VRF slave, and the kernel's l3mdev ingress lookup finds the mesh /128's
  # `local` route (proto kernel, metric 0) in table 200, so it is delivered to
  # the unbound prometheus socket. This mirrors the manual `ip -6 rule add to
  # 2a0c:b641:69c::/48 lookup 200 pref 1500` that was verified live. Priority
  # 1500 sits between the mesh's rule-500 SRv6 src selector and the rule-1000
  # l3mdev table, above the rule-2000 unreachable.
  systemd.network.networks.gravity.routingPolicyRules = [
    {
      Family = "ipv6";
      To = "2a0c:b641:69c::/48";
      Table = config.systemd.network.netdevs.gravity.vrfConfig.Table;
      Priority = 1500;
    }
  ];

  # No cert-rotation watcher needed: certs are store paths, so rotating them is
  # a rebuild — the changed scrape config store paths restart prometheus on
  # switch, and prometheus/common re-reads tls_config cert files from disk on
  # each new connection (GetClientCertificate hash check) afterwards.
}
