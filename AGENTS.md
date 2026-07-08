# Agent Guide — Flakes Workspace

Multi-host NixOS configuration using **Nix Flakes**, **Colmena**, **sops-nix**, and **disko**. Deployed to VPS hosts under the `rua.st` domain.

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

`flake.nix` is structured around four concerns:

1. **Inputs.** Pin every upstream. As of last refactor: `nixpkgs`, `flake-utils`, `disko`, `sops-nix`, `colmena`, `impermanence`. Update with `nix flake update`.
2. **`infraDomain` constant.** Single source of truth for the deployment domain. Threaded through Colmena `meta`, `specialArgs`, and cross-service URLs (keywa, hysteria, ACN cert SANs). Replace scattered `"rua.st"` literals here.
3. **`nixosConfigurations` and `colmenaConfig`.** Bound once in a `let` block, returned once from `outputs`. No duplication between Colmena and NixOS branches.
4. **`packages.build-${name}-image`.** One per `diskoHosts` entry. For keywa-pin-enabled hosts, the script fetches the LUKS key from keywa (15-min timeout, Telegram-approved) and injects it via `--pre-format-files`. It also bakes a host-scoped `sops.age` key into `/persist/var/lib/sops.key` so first-boot decryption works without operator intervention.

Colmena `keys."sops.key".keyCommand` prefers per-host age keys (`$HOME/.config/sops/age/${name}-key.txt`) and falls back to the shared `keys.txt`. The `destDir` is derived from each host's `config.sops.age.keyFile`.

## Secrets — sops with per-host keys

`.sops.yaml` declares age anchors (`*svr1`, `*tyo2`, `*nah0`, `*primary`) and per-path creation_rules:

| Path | Decryptable by |
|---|---|
| `hosts/svr1/.*` | primary + svr1 |
| `hosts/tyo2/.*` | primary + tyo2 |
| `hosts/nah0/.*` | primary + nah0 |
| `modules/.*` | primary + all three host keys |

Operational keys live at `~/.config/sops/age/${host}-key.txt`. The deploy-time Colmena keyCommand will fall back to `~/.config/sops/age/keys.txt` if a per-host key is missing.

To rotate keys or add a host:
1. Add the new host's `*anchor` to `.sops.yaml`.
2. Add a `creation_rules` block scoped to the host's path with `[primary, newHost]`.
3. Run `sops updatekeys -y` on every `secrets.yaml` under the affected scope.
4. Generate the per-host key on the operator's machine: `age-keygen -o ~/.config/sops/age/${host}-key.txt`.
5. Confirm decryption works before relying on the rotated secrets.

To edit any `secrets.yaml`: `sops hosts/${name}/secrets.yaml`.

## Module registry (`modules/default.nix`)

Add new modules here so they're importable as `self.nixosModules.<name>` from a host's `default.nix`. Hosts selectively import only what they need — adding to the registry alone does not enable a module for any host.

## tyo2-specific quirks

tyo2 is the only host running **impermanence** (`<nix-community/impermanence>`) and **keywa-pin**. These interact in non-obvious ways; record the gotchas here so they don't get lost.

### Initrd networking + keywa-pin

`keywa-pin` declares `initrdAddress`, `initrdGateway`, `initrdInterface` so initrd can reach keywa and fetch the LUKS key. After `pivot_root`, the kernel keeps this state — `eth0` already has the production address + default route before the main system's `systemd-networkd.service` runs.

This has a side effect: `network-online.target` activates from kernel state, not from `systemd-networkd-wait-online.service`. See "Boot-time ordering gotchas" below.

### Impermanence

tyo2's root is on btrfs subvolume `@tmp` (ephemeral, rolled back every boot). Only `/persist` survives. The following directories are bind-mounted from `/persist`:

- `/var/lib/gravity` (ranet state)
- `/var/lib/vnstat`
- `/var/lib/nixos` (UID/GID stability)
- `/var/log/journal` (paired with `services.journald.storage = "persistent"`)

Plus these files:
- `/etc/machine-id`
- `/var/lib/sops.key` (Colmena-baked)
- `/etc/ssh/ssh_host_{rsa,ed25519}_key`

`/persist` itself must be `neededForBoot = true` (set manually in `hardware-configuration.nix` since disko doesn't expose it on btrfs subvolumes).

## Boot-time ordering gotchas — **read this before adding systemd services**

This section documents a real class of failures we've already hit. Apply these rules before adding any systemd service that runs `ip` commands or touches a specific netdev.

### `network-online.target` is unreliable on hosts with initrd networking

`network-online.target` is a passive target — it becomes "active" when its dependency graph has nothing pending. systemd does **not** gate it on `systemd-networkd-wait-online.service` having completed. On hosts where the kernel already has a configured interface at PID 1 startup (tyo2 with keywa-pin, or any host with initrd networking), the target activates before `systemd-networkd.service` even runs.

The historical buggy pattern (inherited from upstream `NickCao/flakes` and present in our repo before the fix): `after/wants = [ "network-online.target" ]` on services that reference a VRF. This races on every boot.

### Right way to gate a service on a specific netdev

Use the **synthetic device unit** `sys-subsystem-net-devices-<name>.device` plus `BindsTo`:

```nix
systemd.services.<name> = {
  after = [
    "network-online.target"
    "sys-subsystem-net-devices-<iface>.device"
  ];
  wants = [ "network-online.target" ];
  bindsTo = [ "sys-subsystem-net-devices-<iface>.device" ];
  wantedBy = [ "multi-user.target" ];
  # ...
};
```

The `.device` unit activates only when udev tags the netdev in `/sys/class/net/`. For systemd-networkd-created netdevs (VRFs, bridges, VLANs, etc.) this happens after the netdev is real and `ip route add … dev <iface>` will succeed. `BindsTo` is stronger than `After` — if the device disappears, the service is stopped and ExecStop runs.

Verify on a live host:
```bash
systemctl status sys-subsystem-net-devices-gravity.device
# Active: active (plugged) since <boot time>
```

### Wrong ways

- **`After=systemd-networkd.service`.** Doesn't work. Networkd is `Type=notify-reload`; its READYNOTIFY fires when the daemon accepts bus messages, NOT when netdevs are created. The window between networkd-up and netdev-present is exactly the race.
- **`After=network-online.target` alone.** Doesn't work on hosts with initrd networking, as above. May appear to work on svr1/nah0 because networkd is fast enough that the order happens to hold — but it's not guaranteed.
- **`RequiredForOnline = false` on a VRF `.network` file.** Opts the link out of wait-online's "at least one link online" calculation. Reduces wait-online to waiting on the physical uplink, which activates as soon as it has a route — irrespective of VRF state. Present in this repo by default; do not add it to the gravity `.network` file.

### Existing places this matters

- `modules/gravity/default.nix:504+` — `gravity-srv6.service`. Runs `ip -6 route add … dev gravity`.
- `modules/gravity/default.nix:553+` — `gravity-ipsec.service`. Its `updown` script (around lines 538-549) does `ip link set … master gravity`.

Both already have the `.device BindsTo` fix. Don't regress them.

## Common workflows

### Deploy

```bash
# One host
nix run nixpkgs#colmena -- apply --on <hostname>

# All active hosts
nix run nixpkgs#colmena -- apply
```

Colmena runs `nixos-rebuild switch` (or boot, depending on flags) on each target. After a switch, systemd re-evaluates unit dependencies — services that gained new `bindsTo`/`after` will only run cleanly after a reboot unless the underlying state is already present.

### Recovering `gravity-srv6` after a failed start

If a manual `ip` invocation left a stale route (e.g. only the first `ExecStart` succeeded), delete it before re-starting:

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

Comment out the host name in `flake.nix` (both lists). Do not delete `hosts/${name}/` unless the host is permanently decommissioned — keeping the directory preserves context and makes restoration a one-line edit.

## Engineering standards

- **Commits.** Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`). Subject ≤50 chars. Multi-paragraph body only when the why isn't obvious.
- **AI co-authorship.** When a commit's content was drafted or substantially edited with AI assistance, append `Co-authored-by: opencode <noreply@opencode.ai>` to the message body before pushing.
- **Formatting.** `nix run nixpkgs#nixpkgs-fmt -- .` before committing. CI does not enforce this; manual discipline.
- **Validation.** Run `nix eval` on the changed systemd/services attrs to confirm the rendered unit is what you expect:
  ```bash
  nix eval .#nixosConfigurations.<host>.config.systemd.services.<name>.bindsTo
  nix eval .#nixosConfigurations.<host>.config.systemd.services.<name>.after
  ```
- **Push.** After successful deployment and a clean working tree, push to `origin/primary`. Rebases that rewrite commit hashes require `--force-with-lease` — never plain `--force`. Coordinate force-pushes; this is a multi-operator repo.
- **Persistence.** Keep decommissioned host directories; comment them out in `flake.nix` instead.

## Debugging recipes

### "Cannot find device gravity" (or any VRF)

1. Is the VRF in `/sys/class/net`? `ls /sys/class/net/gravity`. If no, networkd hasn't created it yet.
2. Is the synthetic `.device` unit active? `systemctl status sys-subsystem-net-devices-gravity.device`.
3. Is systemd-networkd running? `systemctl status systemd-networkd.service`. When did it start? `systemctl show systemd-networkd.service | grep ActiveEnter`.
4. Boot chronology — compare timestamps:
   ```bash
   systemctl show systemd-networkd.service         | grep ExecMainStart
   systemctl show sys-subsystem-net-devices-gravity.device | grep ActiveEnter
   systemctl show gravity-srv6.service             | grep ExecMainStart
   ```
   If srv6 started before the `.device` was active, the `.device BindsTo` fix is missing or wrong.

### Service activated but route table is wrong

`ip -6 route show table <id>` to inspect. For tyo2, the localsid table is 100. If a stale route blocks re-activation, see "Recovering gravity-srv6" above.

### Initrd vs main-system state mismatch on tyo2

If `eth0` shows duplicate addresses or a wrong default route, suspect keywa-pin's `initrdAddress`/`initrdGateway` lingering past `pivot_root`. The kernel state is not rolled back impermanence-style; only `ip` commands can fix it. Document any such occurrence before rebooting.

### Force-push safety

This repo has multiple operators. `--force-with-lease` is the default. If you must rewrite already-pushed history (e.g., amending attribution), check `git log @{u}..HEAD` first to confirm you're not about to clobber a peer's push.