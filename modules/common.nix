{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # DNS utility
    drill

    # Suggested utilities
    htop # interactive process viewer
    ncdu # disk usage analyzer
    tshark # terminal-based wireshark
    strace # system call tracer
    lsof # list open files
  ];

  programs.fish.enable = true;

  users.defaultUserShell = pkgs.fish;
  users.users.root.shell = pkgs.fish;
}
