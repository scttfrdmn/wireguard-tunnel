#!/usr/bin/env bash
# detect-numa.sh [out.json] — probe NUMA topology and device-to-node affinity, to decide
# whether process placement should avoid jumping the NUMA complex.
#
# The open question (from the pinning result): the receiver's decrypt path spreads across
# ~31 cores; if those cores straddle two NUMA nodes while the ENA's DMA/IRQs sit on one node,
# every cross-node packet pays an interconnect penalty. This script answers, with measured
# sysfs values (never assumed):
#
#   1. How many NUMA nodes does the instance present? (1 => the whole concern is moot)
#   2. Which node is the ENA NIC attached to?  (-1 => hypervisor hides it; infer empirically)
#   3. Which node(s) are the instance-store NVMe attached to?
#   4. Which CPUs belong to each node? (for pinning decrypt/workers to the NIC-local node)
#
# Emits human-readable to stderr and (optionally) a JSON summary for the report.
set -euo pipefail
source "$(dirname "$0")/common.sh"

OUT="${1:-/dev/stdout}"
IF="$PRIMARY_IF"

# --- node count + per-node cpulists ---
nodes_dir=/sys/devices/system/node
node_count=$(find "$nodes_dir" -maxdepth 1 -name 'node[0-9]*' 2>/dev/null | wc -l | tr -d ' ')
[ "$node_count" -ge 1 ] || node_count=1
log "NUMA nodes presented to the guest: $node_count"
if [ "$node_count" -eq 1 ]; then
  log "  => single NUMA node: there is no complex to jump; placement is intra-node only."
fi

declare -A NODE_CPUS
for nd in "$nodes_dir"/node[0-9]*; do
  [ -d "$nd" ] || continue
  n=${nd##*/node}
  NODE_CPUS[$n]=$(cat "$nd/cpulist" 2>/dev/null || echo "?")
  log "  node $n cpus: ${NODE_CPUS[$n]}"
done

# --- NIC -> node ---
nic_node=$(cat "/sys/class/net/$IF/device/numa_node" 2>/dev/null || echo "")
nic_localcpus=$(cat "/sys/class/net/$IF/device/local_cpulist" 2>/dev/null || echo "")
if [ -z "$nic_node" ]; then
  log "NIC $IF: no numa_node file (device affinity not exposed)"
  nic_node="absent"
elif [ "$nic_node" = "-1" ]; then
  log "NIC $IF: numa_node = -1 (HYPERVISOR HIDES affinity — infer empirically, see note)"
else
  log "NIC $IF: attached to NUMA node $nic_node (local cpus: ${nic_localcpus:-?})"
fi

# --- NVMe instance-store -> node(s) ---
nvme_nodes=""
for d in /sys/class/nvme/nvme*; do
  [ -e "$d/numa_node" ] || continue
  ctrl=${d##*/}
  nn=$(cat "$d/numa_node" 2>/dev/null || echo "?")
  model=$(cat "$d/model" 2>/dev/null | tr -s ' ' || echo "?")
  case "$model" in
    *Instance*Storage*) tag="instance-store" ;;
    *Elastic*) tag="ebs" ;;
    *) tag="other" ;;
  esac
  log "NVMe $ctrl ($tag): numa_node=$nn"
  [ "$tag" = "instance-store" ] && nvme_nodes="$nvme_nodes $nn"
done
nvme_nodes=$(echo "$nvme_nodes" | tr ' ' '\n' | grep -v '^$' | sort -u | paste -sd, - 2>/dev/null || echo "")

# --- verdict ---
verdict="single-node (placement moot)"
if [ "$node_count" -gt 1 ]; then
  if [ "$nic_node" = "-1" ] || [ "$nic_node" = "absent" ]; then
    verdict="multi-node, NIC affinity HIDDEN — pin decrypt/workers per node and A/B the two halves"
  else
    verdict="multi-node, NIC on node $nic_node — pin decrypt/workers to node $nic_node cpus"
  fi
fi
log "VERDICT: $verdict"

# --- JSON summary ---
cpus_json=$(for n in "${!NODE_CPUS[@]}"; do printf '"%s":"%s",' "$n" "${NODE_CPUS[$n]}"; done | sed 's/,$//')
cat > "$OUT" <<JSON
{
  "iface": "$IF",
  "numa_nodes": $node_count,
  "node_cpulist": { ${cpus_json:-} },
  "nic_numa_node": "$nic_node",
  "nic_local_cpulist": "${nic_localcpus}",
  "instance_store_nvme_nodes": "${nvme_nodes}",
  "verdict": "$verdict"
}
JSON
[ "$OUT" = /dev/stdout ] || log "wrote $OUT"
