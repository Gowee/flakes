#!/usr/bin/env bash
# Regenerate the monitoring mTLS cert bundle from each host's gravity ipsec
# Ed25519 key (kept in sops). Outputs committed files under monitoring-certs/:
#   <host>.crt           self-signed leaf, SAN = DNS:<host>.rua.st,IP:<meshIP>
#   cluster-nodes.crt    concatenation of all host certs
#
# Why committed store paths instead of colmena keyCommand: certs become part
# of the NixOS closure (/nix/store, a persistent btrfs subvolume on
# impermanence hosts), so they survive root rollbacks and no per-apply key
# upload happens. Regeneration is byte-identical given the same key + params,
# so a rotation shows up as a clean git diff.
#
# Requires: sops + the operator's primary age key (~/.config/sops/age/keys.txt).
# Run after rotating any host's ipsec key, then commit and deploy.
set -euo pipefail

cd "$(dirname "$0")/.."

  SERIAL=1
NOT_BEFORE=20260101000000Z
NOT_AFTER=20360101000000Z
INFRA_DOMAIN=rua.st

# host -> sops file holding its `ipsec` secret. nah0 uses the shared gravity
# secret; every other host overrides with a dedicated key in hosts/<h>/secrets.yaml.
declare -A SOPS_FILE=(
[nah0]=modules/gravity/secrets.yaml
[tyo2]=hosts/tyo2/secrets.yaml
[nium0]=hosts/nium0/secrets.yaml
[tyo3]=hosts/tyo3/secrets.yaml
[fra0]=hosts/fra0/secrets.yaml
)

# Derive a host's mesh IPv6 (first address, /128 stripped) from the hive.
mesh_ip() {
local host="$1"
nix eval --json ".#colmenaHive.nodes.${host}.config.services.gravity.address" 2>/dev/null \
| tr -d '[]"' \
    | sed 's|/128$||'
}

TMP_KEY="$(mktemp)"
OUT_DIR="$(mktemp -d)"
trap 'rm -f "$TMP_KEY"; rm -rf "$OUT_DIR"' EXIT

for host in "${!SOPS_FILE[@]}"; do
  ip="$(mesh_ip "$host")"
  echo "==> ${host} (mesh $ip)"
  sops -d --extract '["ipsec"]' "${SOPS_FILE[$host]}" > "$TMP_KEY"
  openssl req -new -x509 \
    -key "$TMP_KEY" \
    -out "$OUT_DIR/${host}.crt" \
    -subj "/CN=${host}.${INFRA_DOMAIN}" \
    -set_serial "$SERIAL" \
    -not_before "$NOT_BEFORE" \
    -not_after "$NOT_AFTER" \
    -addext "subjectAltName=DNS:${host}.${INFRA_DOMAIN},IP:${ip}"
done

# Bundle order matters only for readability; prometheus/exporter treat it as a
# flat trust pool.
cat "$OUT_DIR/nah0.crt" \
  "$OUT_DIR/tyo2.crt" \
  "$OUT_DIR/nium0.crt" \
  "$OUT_DIR/tyo3.crt" \
  "$OUT_DIR/fra0.crt" \
  > "$OUT_DIR/cluster-nodes.crt"

# Publish only after every host succeeded, so an interrupted run leaves the
# committed certs untouched.
mv "$OUT_DIR"/*.crt monitoring-certs/

echo "==> done: monitoring-certs/{<host>.crt, cluster-nodes.crt}"

