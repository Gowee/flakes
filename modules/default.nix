{
  telegraf = import ./telegraf;
  shadowsocks = import ./shadowsocks;
  gravity = import ./gravity;
  cachix = import ./cachix.nix;
  hysteria2 = import ./hysteria2;
  nix-maintenance = import ./nix-maintenance.nix;
  common = import ./common.nix;
  config-revision = import ./config-revision.nix;
  keywa-pin = import ./keywa-pin;
  keywa-sops = import ./keywa-sops;
}
