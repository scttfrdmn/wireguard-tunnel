#!/usr/bin/env bash
# mesh-up.sh <role:a|b> <n> <peer_priv_ip> <peer_pubkeys_file>
# Brings up N point-to-point WireGuard tunnels, each on its own UDP port + /31.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need wg; need ip

ROLE="${1:?role a|b}"; N="${2:?n}"; PEER_IP="${3:?peer private ip}"; PEERPUB="${4:?peer pubkeys file}"
KEYDIR="$(dirname "$0")/../keys"
[ "$ROLE" = a ] && SELF=1 || SELF=2
[ "$ROLE" = a ] && OTHER=2 || OTHER=1

for i in $(seq 0 $((N-1))); do
  dev=$(tun_dev "$i"); port=$(tun_port "$i")
  selfip=$(tun_ip "$i" "$SELF"); peerip=$(tun_ip "$i" "$OTHER")
  peerpub=$(awk -v k="$i" '$1==k{print $2}' "$PEERPUB")
  [ -n "$peerpub" ] || die "no peer pubkey for tunnel $i in $PEERPUB"

  ip link del "$dev" 2>/dev/null || true
  ip link add "$dev" type wireguard
  wg set "$dev" listen-port "$port" private-key "$KEYDIR/priv$i"
  wg set "$dev" peer "$peerpub" endpoint "${PEER_IP}:${port}" allowed-ips "${peerip}/32" persistent-keepalive 15
  # /30 (covers .0-.3) so the .1 and .2 endpoints share a subnet and can route to each other;
  # a /31 at .1 spans only .0-.1, leaving .2 off-subnet (no inner route).
  ip addr add "${selfip}/30" dev "$dev"
  ip link set "$dev" mtu "$WG_MTU" up
done
log "brought up $N tunnels ($ROLE side); peer endpoint $PEER_IP"
log "verify handshakes:  wg show all latest-handshakes"
