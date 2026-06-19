#!/usr/bin/env bash
# set-crypt-affinity.sh [node] — steer WireGuard's wg-crypt workqueue(s) to a NUMA node, if the
# kernel exposes a writable handle. Run with sudo on the RECEIVER. Default node = the NIC's node.
#
# Precedence of handles (best first):
#   1. affinity_scope=numa  (kernel 6.5+; keeps worker pools from drifting cross-node) — usually
#      writable even when the WQ is not WQ_UNBOUND, so this is the realistic lever on 6.17.
#   2. cpumask=<node mask>  (only if the WQ is WQ_UNBOUND -> cpumask writable).
#   3. neither -> no-op with a clear log line: the WQ is per-CPU and its placement already
#      follows the ENA RX IRQ core (which node-setup.sh pins NIC-local). Nothing to do.
#
# Idempotent. Acts on every wg-crypt-* workqueue present.
set -euo pipefail
source "$(dirname "$0")/common.sh"
[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
WQ_ROOT=/sys/devices/virtual/workqueue

NODE="${1:-}"
if [ -z "$NODE" ]; then
  NODE=$(cat "/sys/class/net/$PRIMARY_IF/device/numa_node" 2>/dev/null || echo 0); [ "$NODE" = "-1" ] && NODE=0
fi

# hex cpumask for a node's cpulist (grouped 32-bit words, high word first) — same scheme as
# rps-setup.sh, kept local so this script is standalone.
node_mask() {
  local cl; cl=$(cat "/sys/devices/system/node/node${NODE}/cpulist") || return 1
  local p c nbits; nbits=$(nproc)
  local -a bits=(); for ((i=0;i<nbits;i++)); do bits[i]=0; done
  IFS=',' read -ra parts <<< "$cl"
  for p in "${parts[@]}"; do
    if [[ "$p" == *-* ]]; then for ((c=${p%-*};c<=${p#*-};c++)); do bits[c]=1; done; else bits[p]=1; fi
  done
  local words=$(( (nbits + 31) / 32 )) w out=""
  for (( w=words-1; w>=0; w-- )); do
    local word=0
    for (( b=0; b<32; b++ )); do local idx=$(( w*32 + b )); [ "$idx" -lt "$nbits" ] && [ "${bits[idx]}" = 1 ] && word=$(( word | (1<<b) )); done
    out+=$(printf '%08x' "$word"); [ "$w" -gt 0 ] && out+=","
  done
  echo "$out"
}

wqs=()
while IFS= read -r d; do wqs+=("$d"); done < <(find "$WQ_ROOT" -maxdepth 1 -name 'wg-crypt-*' 2>/dev/null)
[ "${#wqs[@]}" -gt 0 ] || { log "no wg-crypt-* workqueues found (is a wg mesh up?)"; exit 0; }

mask=""; did=""
for wq in "${wqs[@]}"; do
  if [ -e "$wq/affinity_scope" ] && [ -w "$wq/affinity_scope" ]; then
    echo numa > "$wq/affinity_scope" 2>/dev/null && did="affinity_scope=numa"
  elif [ -w "$wq/cpumask" ]; then
    [ -n "$mask" ] || mask=$(node_mask)
    echo "$mask" > "$wq/cpumask" 2>/dev/null && did="cpumask(node $NODE)"
  fi
done

if [ -n "$did" ]; then
  log "set wg-crypt affinity: $did on ${#wqs[@]} workqueue(s)"
else
  log "wg-crypt WQ not sysfs-steerable (per-CPU): placement follows the ENA RX IRQ core, already NIC-local — no-op"
fi