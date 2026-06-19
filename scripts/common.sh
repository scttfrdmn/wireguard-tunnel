#!/usr/bin/env bash
# common.sh — shared config + helpers. Source this from other scripts.
set -euo pipefail

# --- tunable config ---
BASE_PORT="${BASE_PORT:-51820}"        # wg listen port for tunnel 0
TUN_NET="${TUN_NET:-10.200}"           # /31 per tunnel: 10.200.<i>.1 <-> .2
WG_MTU="${WG_MTU:-8921}"               # 9001 ENA MTU - 80B headroom
IPERF_BASE_PORT="${IPERF_BASE_PORT:-5201}"
NVME_BASE_PORT="${NVME_BASE_PORT:-4420}"               # nvme-tcp svc port for tunnel 0
NVME_NQN="${NVME_NQN:-nqn.2026-06.io.wg-saturate:target}"  # one subsystem, N paths to it
RESULTS_DIR="${RESULTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/results}"

# Primary (ENA) interface = the one carrying the default route
primary_if() { ip route show default | awk '{print $5; exit}'; }
PRIMARY_IF="${PRIMARY_IF:-$(primary_if)}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

tun_dev()  { echo "wg$1"; }
tun_port() { echo "$((BASE_PORT + $1))"; }
tun_ip()   { echo "${TUN_NET}.$1.$2"; }   # $1=index $2=1|2
nvme_port() { echo "$((NVME_BASE_PORT + $1))"; }   # nvme-tcp svc port for tunnel $1

# Snapshot ENA counters as "key value" numeric lines
ena_stats() {
  ethtool -S "$PRIMARY_IF" 2>/dev/null \
    | awk -F: 'NF==2{gsub(/ /,"",$1);gsub(/ /,"",$2); if ($2 ~ /^[0-9]+$/) print $1" "$2}'
}
ena_stat() { ena_stats | awk -v k="$1" '$1==k{print $2; f=1} END{if(!f)print 0}'; }

mkdir -p "$RESULTS_DIR"
