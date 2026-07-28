{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # DNS utility
    ldns

    # Suggested utilities
    nmap
    htop # interactive process viewer
    # ncdu # disk usage analyzer
    # tshark # terminal-based wireshark
    strace # system call tracer
    lsof # list open files

    vim
    tmux
    curl
    # git
    bandwhich
    iperf3
    tcpdump
    mtr
    jq
    conntrack-tools
  ];

  boot.kernel.sysctl."net.netfilter.nf_conntrack_max" = 65536;

  services.vnstat.enable = true;

  programs.fish.enable = true;

  users.defaultUserShell = pkgs.fish;
  users.users.root.shell = pkgs.fish;
}
