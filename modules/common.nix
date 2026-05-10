{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # DNS utility
    ldns

    # Suggested utilities
    nmap
    htop # interactive process viewer
    ncdu # disk usage analyzer
    tshark # terminal-based wireshark
    strace # system call tracer
    lsof # list open files
  ];

  services.vnstat.enable = true;

  programs.fish.enable = true;

  users.defaultUserShell = pkgs.fish;
  users.users.root.shell = pkgs.fish;
}
