# node_exporter with mutual TLS reusing each host's gravity ipsec key.
#
# Identity: each host's self-signed X509 cert (derived from its gravity ipsec
# Ed25519 private key) is prebuilt and committed under monitoring-certs/ (see
# scripts/gen-monitoring-certs.sh). The private key never leaves sops; only the
# public certs ship, as store paths inside the NixOS closure.
#
# Trust: prometheus (nah0) presents nah0's cert; every exporter requires and
# verifies a client cert against the cluster bundle (which contains nah0.crt).
# The exporter's own server cert is verified by prometheus against the same
# cluster bundle (self-signed leaf pinning).
{ config, pkgs, lib, certDir, ... }:
let
  hostName = config.networking.hostName;
  dir = certDir;
  meshAddresses = config.services.gravity.address or [ ];
  meshIp =
    if meshAddresses == [ ]
    then null
    else lib.removeSuffix "/128" (builtins.head meshAddresses);
  listenAddress = if meshIp == null then "0.0.0.0" else "[${meshIp}]";

  # Static paths (cert bundle + server cert ship in the store as part of the
  # closure; rotating them is a rebuild, which restarts the service via the
  # changed web-config store path — no runtime watcher needed).
  webConfig = pkgs.writeText "node-exporter-web-config.yml" ''
    tls_server_config:
      cert_file: ${dir}/${hostName}.crt
      key_file: /run/prometheus-node-exporter/ipsec.key
      client_ca_file: ${dir}/cluster-nodes.crt
      client_auth_type: RequireAndVerifyClientCert
  '';
in
{
  assertions = [
    {
      assertion = config.services.gravity.ipsec.enable;
      message = "monitoring/node-exporter requires services.gravity.ipsec.enable (provides the sops `ipsec` secret)";
    }
    {
      assertion = config.services.gravity.ipsec.enable -> config.services.gravity.address != [ ];
      message = "monitoring/node-exporter requires services.gravity.address to be non-empty (bind address)";
    }
    {
      assertion = builtins.pathExists "${dir}/${hostName}.crt";
      message = "monitoring/node-exporter: missing ${dir}/${hostName}.crt — run scripts/gen-monitoring-certs.sh and commit the result";
    }
    {
      assertion = builtins.pathExists "${dir}/cluster-nodes.crt";
      message = "monitoring/node-exporter: missing ${dir}/cluster-nodes.crt — run scripts/gen-monitoring-certs.sh and commit the result";
    }
  ];

  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    listenAddress = listenAddress;
    openFirewall = false;
    enabledCollectors = [
      "systemd"
      "processes"
      "diskstats"
      "filesystem"
      "meminfo"
      "netdev"
      "cpu"
      "loadavg"
    ];
    extraFlags = [ "--web.systemd-socket" "--web.config.file=/run/prometheus-node-exporter/web-config.yml" ];
  };

  # The exporter's listen socket must be VRF-aware or the kernel will never
  # match SYN packets that arrive on a gn* device enslaved to the gravity VRF
  # (net.ipv6.tcp_l3mdev_accept defaults to 0: unbound socket scope is limited
  # to the default VRF). SO_BINDTODEVICE(gravity) makes the socket part of the
  # VRF; --web.systemd-socket inherits the fd from this unit.
  systemd.sockets.prometheus-node-exporter = {
    wantedBy = [ "sockets.target" ];
    # SO_BINDTODEVICE(gravity) fails if the VRF is gone; tear down the socket
    # with the device so it re-binds when gravity reappears.
    after = [ "sys-subsystem-net-devices-gravity.device" ];
    bindsTo = [ "sys-subsystem-net-devices-gravity.device" ];
    socketConfig = {
      # Bind before the address exists (device unit fires at netdev creation;
      # networkd assigns the mesh address a moment later).
      FreeBind = true;
      ListenStream = "[${meshIp}]:9100";
      BindToDevice = "gravity";
    };
  };

  systemd.services.prometheus-node-exporter = {
    # The exporter binds the gravity mesh address; wait for the VRF to appear
    # (udev-tagged .device unit) so the bind doesn't race VRF creation at boot.
    wants = [ "sops-install-secrets.service" "sys-subsystem-net-devices-gravity.device" "prometheus-node-exporter.socket" ];
    after = [ "sops-install-secrets.service" "sys-subsystem-net-devices-gravity.device" "prometheus-node-exporter.socket" ];
    bindsTo = [ "sys-subsystem-net-devices-gravity.device" ];
    wantedBy = [ "multi-user.target" ];
    # `+` prefix: run as root to read the root-only sops key and drop it (plus
    # the web-config) into the RuntimeDirectory for the node-exporter user.
    serviceConfig.ExecStartPre = [
      "+${pkgs.coreutils}/bin/install -m 0440 -o node-exporter -g node-exporter ${webConfig} /run/prometheus-node-exporter/web-config.yml"
      "+${pkgs.coreutils}/bin/install -m 0400 -o node-exporter -g node-exporter ${config.sops.secrets.ipsec.path} /run/prometheus-node-exporter/ipsec.key"
    ];
  };
}
