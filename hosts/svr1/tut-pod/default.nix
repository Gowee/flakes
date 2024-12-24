{ config, lib, pkgs, ... }:
{
  # Enable common container config files in /etc/containers
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Useful other development tools
  environment.systemPackages = with pkgs; [
    # dive # look into docker image layers
    podman-tui # status of containers in the terminal
    # docker-compose # start group of containers for dev
    #podman-compose # start group of containers for dev
  ];

  virtualisation.oci-containers.backend = "podman";

  sops.secrets.tut-env = {
    sopsFile = ./secrets.yaml;
    mode = "0440";
    restartUnits = [ "podman-tut.service" ];
  };

  virtualisation.oci-containers.containers = {
    tut = {
      image = "docker.io/gowe/telegram-user-tracker";
      autoStart = true;
      ports = [ ];
      # the volume is expected to be created & populated manually
      volumes = [ "tut:/app/session" ];
      environmentFiles = [ config.sops.secrets.tut-env.path ];
    };
  };
}
