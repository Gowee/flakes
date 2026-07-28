{ config, pkgs, infraDomain, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nah0"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Set your time zone.
  time.timeZone = "Asia/Taipei";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  # networking.useDHCP = false; # check hardware config
  # networking.interfaces.ens3.useDHCP = true;

  networking.firewall.enable = false;
  networking.domain = infraDomain;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;




  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  # users.users.jane = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  # };

  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVTLe5ElQ9zegq5F99LWvi4S5YlH5J0tut+Jxwp/FaNZmgSK6uEY7ySu4r/dKn+dwIwHEej152BMZO2/hGjhmw="
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBDijuXohDJEgkv9izzEGJ1vLx/4sSs00aDq3RAI7bj"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPKJtITC6SV5Og1+G9qNkqbAojHCtuxi+4GKRMMW+yHl" # Actions ENV: deploy
  ];
  users.users.root.initialHashedPassword = "";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # future host-specific packages
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
    priority = 100;
  };

  services.gateway.enable = true;

  services.gravity = {
    enable = true;
    reload.enable = true;
    divi = {
      enable = true;
      prefix = "2a0c:b641:69c:faf4:0:4::/96";
      oif = "eth0";
    };
    srv6 = {
      enable = true;
      prefix = "2a0c:b641:69c:faf";
    };
    address = [ "2a0c:b641:69c:faf0::1/128" ];
    bird = {
      enable = true;
      # exit.enable = true;
      prefix = "2a0c:b641:69c:faf0::/60";
    };

    ipsec = {
      enable = true;
      organization = "gowee";
      commonName = config.networking.hostName;
      port = 13000;
      interfaces = [ "eth0" ];
      endpoints = [
        {
          serialNumber = "0";
          addressFamily = "ip4";
        }
        {
          serialNumber = "1";
          addressFamily = "ip6";
        }
      ];
    };
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?


  sops = {
    defaultSopsFile = ./secrets.yaml;
    age = {
      keyFile = "/var/lib/sops.key";
      generateKey = false;
    };
  };
}
