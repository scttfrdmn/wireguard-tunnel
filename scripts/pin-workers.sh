#!/usr/bin/env bash
# pin-workers.sh <n> [base_core] — pin each tunnel's userspace iperf3 worker to a core, to
# test how CPU placement affects the receive-side throughput ceiling. Run on the RECEIVER (B).
#
# node-setup.sh pins the ENA RX-queue IRQs (→ NAPI/softirq, and the per-CPU wg-crypt decrypt
# work that follows the receiving CPU). The iperf3 servers float unless pinned. Three modes:
#
#   (default)   one distinct core per worker, round-robin over all cores.
#   NODE=<n>    confine workers to NUMA node <n>'s cpus (the A/B that found NIC-local best).
#   ALIGN=1     RUN-TO-COMPLETION: pin worker i to the SAME core as the i-th ENA RX IRQ, so the
#               app thread shares a core with the softirq/decrypt that feeds it (cache-warm,
#               no cross-core hand-off). This is the locality lever the design review flagged
#               as the likely next 10-20% — the default and NODE modes pin app cores
#               INDEPENDENTLY of where IRQs landed, leaving softirq-core != app-core.
#   SPLIT=1     node-split for Approach A: workers for tunnels 0..n/2-1 → NIC-local node,
#               n/2..n-1 → the other node (paired with a split IRQ map; see node-setup IRQ_CORES).
#
# Idempotent. ALIGN/SPLIT/NODE are mutually exclusive; precedence ALIGN > SPLIT > NODE > default.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need taskset; need pgrep
N="${1:?usage: pin-workers.sh <n> [base_core]}"
BASE="${2:-0}"
NPROC=$(nproc)
NODE="${NODE:-}"
ALIGN="${ALIGN:-}"
SPLIT="${SPLIT:-}"

# expand a kernel cpulist ("0-3,8,12-13") into a flat bash array on stdout-via-nameref
expand_cpulist() { # $1=cpulist ; echoes space-separated cores
  local cl="$1" p out=""
  IFS=',' read -ra _parts <<< "$cl"
  for p in "${_parts[@]}"; do
    if [[ "$p" == *-* ]]; then
      for c in $(seq "${p%-*}" "${p#*-}"); do out+="$c "; done
    else out+="$p "; fi
  done
  echo "$out"
}

# the ordered list of cores the ENA RX IRQs are currently pinned to (from /proc/irq).
ena_irq_cores() {
  local irq c
  while read -r irq; do
    c=$(cat "/proc/irq/$irq/smp_affinity_list" 2>/dev/null | head -1)
    # smp_affinity_list may be a range; take the first core
    c=${c%%-*}; c=${c%%,*}
    [ -n "$c" ] && echo "$c"
  done < <(grep -i "$PRIMARY_IF" /proc/interrupts | awk -F: '{gsub(/ /,"",$1);print $1}')
}

# build the core pool + addressing mode
corepool=()
mode="default"
if [ -n "$ALIGN" ]; then
  mode="align"
  mapfile -t corepool < <(ena_irq_cores)
  [ "${#corepool[@]}" -gt 0 ] || die "ALIGN=1 but found no ENA RX IRQ affinities for $PRIMARY_IF"
  log "ALIGN: pinning worker i -> core of ENA RX IRQ (i mod ${#corepool[@]}); cores: ${corepool[*]:0:8}..."
elif [ -n "$SPLIT" ]; then
  mode="split"
  nic_node=$(cat "/sys/class/net/$PRIMARY_IF/device/numa_node" 2>/dev/null || echo 0)
  [ "$nic_node" = "-1" ] && nic_node=0
  other=$(( nic_node == 0 ? 1 : 0 ))
  read -ra near < <(expand_cpulist "$(cat "/sys/devices/system/node/node${nic_node}/cpulist")")
  read -ra far  < <(expand_cpulist "$(cat "/sys/devices/system/node/node${other}/cpulist")")
  log "SPLIT: tunnels 0..$((N/2-1)) -> node $nic_node, $((N/2))..$((N-1)) -> node $other"
elif [ -n "$NODE" ]; then
  mode="node"
  read -ra corepool < <(expand_cpulist "$(cat "/sys/devices/system/node/node${NODE}/cpulist" 2>/dev/null || true)")
  [ "${#corepool[@]}" -gt 0 ] || die "NODE=$NODE but its cpulist is missing"
  log "NODE: confining workers to NUMA node $NODE (${#corepool[@]} cores)"
else
  for c in $(seq 0 $((NPROC-1))); do corepool+=("$c"); done
fi

pin_to() { # $1=port $2=core
  local pids pid
  pids=$(pgrep -f "iperf3 -s .* -p $1(\$| )" 2>/dev/null || true)
  [ -n "$pids" ] || pids=$(pgrep -f "iperf3 -s.*-p $1" 2>/dev/null || true)
  [ -n "$pids" ] || { echo "miss"; return; }
  for pid in $pids; do taskset -a -p -c "$2" "$pid" >/dev/null 2>&1 || true; done
  echo "ok"
}

pinned=0; missed=0
for i in $(seq 0 $((N-1))); do
  port=$((IPERF_BASE_PORT + i))
  if [ "$mode" = split ]; then
    if [ "$i" -lt $((N/2)) ]; then core=${near[$(( i % ${#near[@]} ))]}; else core=${far[$(( (i-N/2) % ${#far[@]} ))]}; fi
  else
    core=${corepool[$(( (BASE + i) % ${#corepool[@]} ))]}
  fi
  [ "$(pin_to "$port" "$core")" = ok ] && pinned=$((pinned+1)) || missed=$((missed+1))
done

log "pinned $pinned worker(s) [mode=$mode] (missed $missed)"
[ "$missed" -eq 0 ] || log "WARN: $missed worker(s) not found — is server-up.sh running with N>=$N?"
[ "$mode" = align ] && log "note: ALIGN co-locates app with softirq; kernel wg-crypt (per-CPU) already follows the IRQ core."