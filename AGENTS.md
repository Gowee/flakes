# Agent Guide — Flakes Workspace

Multi-host NixOS configuration using **Nix Flakes**, **Colmena**, **sops-nix**, **disko**, and **impermanence** (tyo2). Deployed to VPS hosts under the `rua.st` domain.

## Hosts

| Host | Role | Special |
|---|---|---|
| `svr1` | Main server (Shanghai TZ) | grafana, podman, telegraf, influxdb2 |
| `nah0` | Secondary server | gateway enabled |
| `tyo2` | Less-trusted VPS (Tokyo TZ) | **impermanence + keywa-pin + dedicated IPSec key** |
| `bud0` | Decommissioned — comment kept in flake.nix, dir retained | |

Hostname → targetHost: `${name}.${infraDomain}` where `infraDomain = "rua.st"` (single source of truth in `flake.nix`).

## Repository layout

```
flake.nix               # inputs, outputs, colmena, build-image packages
flake.lock              # input registry — keep it committed
.sops.yaml              # age key anchors + per-path creation_rules
hosts/${name}/          # per-host NixOS configs
  default.nix           # entry point: imports config + hardware + modules
  configuration.nix     # host-specific NixOS settings
  hardware-configuration.nix  # generated; do not hand-edit unless the disk layout changes
  secrets.yaml          # host-scoped sops-encrypted secrets
modules/
  default.nix           # nixosModules registry — every shared module is exported here
  common.nix            # base config imported by every active host (packages, vnstat, etc.)
  gravity/              # gravity overlay network + SRv6 + IPsec (most complex module)
  shadowsocks/, hysteria2/, telegraf/, cachix.nix, nix-maintenance.nix, config-revision.nix
  keywa-pin/            # LUKS key fetch from keywa + initrd SSH recovery (tyo2 only)
```

## `flake.nix` shape

- **Inputs.** Pin every upstream: `nixpkgs`, `flake-utils`, `disko`, `sops-nix`, `colmena`, `impermanence`. Update with `nix flake update`.
- **`infraDomain = "rua.st"`.** Threaded through Colmena `meta`, `specialArgs`, and cross-service URLs. Don't re-stringify `"rua.st"` elsewhere.
- **`nixosConfigurations` and `colmenaConfig`** are bound once in a `let` block, returned once from `outputs`. No duplication.
- **`packages.build-${name}-image`.** One per `diskoHosts` entry. For keywa-pin hosts, fetches the LUKS key from keywa (15-min timeout, Telegram-approved) via `--pre-format-files` and bakes a host-scoped `sops.age` key into `/persist/var/lib/sops.key` for first-boot decryption.

Colmena `keys."sops.key".keyCommand` prefers per-host age keys (`$HOME/.config/sops/age/${name}-key.txt`), falls back to the shared `keys.txt`. `destDir` is derived from `config.sops.age.keyFile`.

## Secrets — sops with per-host keys

`.sops.yaml` declares age anchors (`*svr1`, `*tyo2`, `*nah0`, `*primary`) and creation_rules:

| Path | Decryptable by |
|---|---|
| `hosts/svr1/.*` | primary + svr1 |
| `hosts/tyo2/.*` | primary + tyo2 |
| `hosts/nah0/.*` | primary + nah0 |
| `modules/.*` | primary + all three host keys |

Operational keys live at `~/.config/sops/age/${host}-key.txt`. Colmena's keyCommand falls back to `~/.config/sops/age/keys.txt` if a per-host key is missing.

To rotate keys or add a host:
1. Add the new host's `*anchor` to `.sops.yaml`.
2. Add a `creation_rules` block scoped to the host's path with `[primary, newHost]`.
3. Run `sops updatekeys -y` on every `secrets.yaml` under the affected scope.
4. Generate the per-host key: `age-keygen -o ~/.config/sops/age/${host}-key.txt`.
5. Confirm decryption works before relying on the rotated secrets.

To edit any `secrets.yaml`: `sops hosts/${name}/secrets.yaml`.

## Module registry (`modules/default.nix`)

Add new modules here so they're importable as `self.nixosModules.<name>` from a host's `default.nix`. Hosts selectively import only what they need — adding to the registry alone does not enable a module for any host.

## tyo2-specific quirks

tyo2 is the only host running **impermanence** and **keywa-pin**.

- **Initrd networking (keywa-pin).** `initrdAddress`/`initrdGateway`/`initrdInterface` configure `eth0` in initrd to fetch the LUKS key. After `pivot_root`, the kernel keeps this state. This is load-bearing for LUKS unlock — do not strip it.
- **Impermanence.** Root is btrfs subvolume `@tmp` (rolled back every boot). Only `/persist` survives. Bind-mounted from `/persist`: `/var/lib/gravity`, `/var/lib/vnstat`, `/var/lib/nixos`, `/var/log/journal`. Plus files `/etc/machine-id`, `/var/lib/sops.key`, `/etc/ssh/ssh_host_{rsa,ed25519}_key`. `/persist` itself is `neededForBoot = true` (set manually in `hardware-configuration.nix`; disko doesn't expose it on btrfs subvolumes).

## Boot-time ordering: gating services on netdevs

For any systemd service that runs `ip` commands against a specific interface, use the synthetic device unit plus `BindsTo`:

```nix
systemd.services.<name> = {
  after = [
    "network-online.target"
    "sys-subsystem-net-devices-<iface>.device"
  ];
  wants = [ "network-online.target" ];
  bindsTo = [ "sys-subsystem-net-devices-<iface>.device" ];
  wantedBy = [ "multi-user.target" ];
};
```

The `.device` unit activates when udev tags the netdev in `/sys/class/net/`. For systemd-networkd-created netdevs (VRFs, bridges, VLANs) this happens after the netdev is real. `BindsTo` is stronger than `After` — it also tears the service down if the device disappears.

Don't use:
- `After=systemd-networkd.service` — networkd's READYNOTIFY fires before netdevs are created.
- `After=network-online.target` alone — does not reliably wait for VRF creation.
- `linkConfig.RequiredForOnline = false` on a VRF `.network` file — opts out of wait-online.

Existing places this matters: `gravity-srv6.service` and `gravity-ipsec.service` in `modules/gravity/default.nix` already use the `.device BindsTo` pattern. Don't regress them.

## Common workflows

### Deploy

```bash
# One host
nix run nixpkgs#colmena -- apply --on <hostname>

# All active hosts
nix run nixpkgs#colmena -- apply
```

After a switch, systemd re-evaluates unit dependencies — services that gained new `bindsTo`/`after` will only run cleanly after a reboot unless the underlying state is already present.

### Recover `gravity-srv6` after a failed start

A stale partial route (e.g. only the first `ExecStart` succeeded on a prior boot) blocks re-activation:

```bash
ssh root@<host> 'ip -6 route delete blackhole default table localsid; systemctl start gravity-srv6.service'
```

### Add a host

1. Create `hosts/${name}/` with `default.nix`, `configuration.nix`, `hardware-configuration.nix`.
2. Add `${name}` to the `hosts` list in `flake.nix`.
3. If using disko, add to `diskoHosts`.
4. Add `&${name}` anchor + `creation_rules` block in `.sops.yaml`.
5. Generate the per-host age key: `age-keygen -o ~/.config/sops/age/${name}-key.txt`.
6. Commit, deploy, then `sops updatekeys -y` on all secrets the host needs.

### Disable a host

Comment out the host name in `flake.nix` (both lists). Do not delete `hosts/${name}/` — keeping the directory preserves context and makes restoration a one-line edit.

## Engineering standards

- **Commits.** Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`). Subject ≤50 chars. Multi-paragraph body only when the why isn't obvious.
- **AI co-authorship.** When a commit's content was drafted or substantially edited with AI assistance, append `Co-authored-by: opencode <noreply@opencode.ai>` to the message body before pushing.
- **Formatting.** `nix run nixpkgs#nixpkgs-fmt -- .` before committing.
- **Validation.** Run `nix eval` on changed systemd/services attrs to confirm the rendered unit is what you expect:
  ```bash
  nix eval .#nixosConfigurations.<host>.config.systemd.services.<name>.bindsTo
  nix eval .#nixosConfigurations.<host>.config.systemd.services.<name>.after
  ```
- **Push.** After successful deployment and a clean working tree, push to `origin/primary`. Rebases that rewrite commit hashes require `--force-with-lease` — never plain `--force`. Coordinate force-pushes; this is a multi-operator repo.

## Debugging recipes

### "Cannot find device gravity" (or any VRF)

1. `ls /sys/class/net/gravity` — does the VRF exist?
2. `systemctl status sys-subsystem-net-devices-gravity.device` — is the `.device` unit active?
3. Compare timestamps to localize the race:
   ```bash
   systemctl show systemd-networkd.service         | grep ExecMainStart
   systemctl show sys-subsystem-net-devices-gravity.device | grep ActiveEnter
   systemctl show gravity-srv6.service             | grep ExecMainStart
   ```
   If srv6 started before the `.device` was active, the `.device BindsTo` fix is missing.

### Force-push safety

Before `--force-with-lease`, check `git log @{u}..HEAD` to confirm you're not about to clobber a peer's push.