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

# --- ENA RX-queue probe: RPS state + count, and a best-effort RX-buffer NUMA hint ---
# RPS (software receive steering) should be OFF when flows are already HW-spread across queues;
# a non-empty rps_cpus means it's on and adding overhead. We also note the RX-queue count and,
# where the kernel exposes it, the page-pool/ring NUMA node — relevant to whether node-0 cores
# can process a queue without reading its buffers across the interconnect (the Approach-A test).
rxq_count=$(find "/sys/class/net/$IF/queues" -maxdepth 1 -name 'rx-*' 2>/dev/null | wc -l | tr -d ' ')
rps_enabled=0
for q in "/sys/class/net/$IF/queues"/rx-*; do
  [ -e "$q/rps_cpus" ] || continue
  # rps_cpus is a hex mask like "00000000,00000000"; non-zero (any non-0/non-comma char) => on
  if grep -qE '[1-9a-f]' "$q/rps_cpus" 2>/dev/null; then rps_enabled=1; fi
done
log "ENA $IF: $rxq_count rx queues; RPS $([ "$rps_enabled" = 1 ] && echo ON || echo off)"
[ "$rps_enabled" = 1 ] && log "  WARN: RPS is ON — with flows already HW-spread this is usually pure overhead"
# RX-buffer node: AWS ENA doesn't expose a per-queue page-pool node in sysfs on most kernels;
# report the device's pci numa_node as the best available proxy (where the driver allocates).
rx_buffer_node="${nic_node}"
log "ENA RX buffers: best-effort node=$rx_buffer_node (driver allocates on the NIC's node; no per-queue knob on ENA)"

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

# --- PCIe topology: which devices share the NIC's host bridge / root complex ---
# The NIC and ~half the NVMe live on the NIC node's PCIe root; at high rate their DMA shares
# the same upstream bus into that node's memory controller. Record co-resident device count so
# we can reason about NIC<->NVMe bus contention on the shared side.
nic_pci=$(basename "$(readlink -f "/sys/class/net/$IF/device" 2>/dev/null)" 2>/dev/null || echo "")
nic_pci_node=$(cat "/sys/bus/pci/devices/$nic_pci/numa_node" 2>/dev/null || echo "?")
same_node_nvme=0
for d in /sys/class/nvme/nvme*; do
  [ -e "$d/numa_node" ] || continue
  [ "$(cat "$d/numa_node" 2>/dev/null)" = "$nic_node" ] && \
    grep -qi 'Instance' "$d/model" 2>/dev/null && same_node_nvme=$((same_node_nvme+1))
done
log "PCIe: NIC at $nic_pci (pci numa_node=$nic_pci_node); $same_node_nvme instance-NVMe share node $nic_node's PCIe/bus"
[ "$same_node_nvme" -gt 0 ] && log "  => NIC RX DMA + those $same_node_nvme drives' write DMA contend on node $nic_node's bus at high rate"

# --- verdict ---
# MEASURED (run 4b, 2026-06-19): with ENA RX IRQs pinned to the NIC-local node (node-setup.sh
# does this now), co-locating userspace receivers on that SAME node is best — NODE=<nic_node>
# pin-workers gave 89.5 Gbps vs 60 unpinned vs 55 on the remote node. (Run 3's "remote wins" was
# an artifact of NUMA-blind IRQ pinning, since corrected.) So: keep IRQs + softirq + decrypt +
# userspace all on the NIC-local node.
verdict="single-node (placement moot)"
if [ "$node_count" -gt 1 ]; then
  if [ "$nic_node" = "-1" ] || [ "$nic_node" = "absent" ]; then
    verdict="multi-node, NIC affinity HIDDEN — pin IRQs+softirq+userspace to the same node; A/B both (NODE=0 vs NODE=1 pin-workers)"
  else
    verdict="multi-node, NIC on node $nic_node — keep IRQs (NIC-local already), softirq, decrypt AND userspace on node $nic_node (measured: NODE=$nic_node pin-workers wins)"
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
  "nic_pci": "${nic_pci}",
  "nvme_sharing_nic_node": ${same_node_nvme:-0},
  "rxq_count": ${rxq_count:-0},
  "rps_enabled": ${rps_enabled:-0},
  "rx_buffer_node": "${rx_buffer_node}",
  "verdict": "$verdict"
}
JSON
[ "$OUT" = /dev/stdout ] || log "wrote $OUT"
