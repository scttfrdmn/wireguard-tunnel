#!/usr/bin/env bash
# nvme-target-up.sh <n> — export instance-store NVMe over nvme-tcp on the B (target) side.
# Run with sudo on B, AFTER mesh-up.sh has the tunnels up.
#
# Topology (native multipath): ONE subsystem ($NVME_NQN) exposes every instance-store device
# as its own namespace, and is published on N nvmet ports — port i bound to tunnel i's B-side
# IP (10.200.i.2) on nvme-tcp service port (NVME_BASE_PORT+i). Host A then connects all N
# paths to the same subsystem; the kernel collapses them into one multipath device per
# namespace and (with round-robin iopolicy on A) sprays commands across the N tunnels =
# N flows = N RX queues = N crypto pipelines, exactly like the iperf sweep.
#
# WARNING: the instance-store devices are exported raw (ephemeral scratch).
#
# NUMA selection (for the near:far drive-ratio sweep, see PIPELINING-DESIGN.md):
#   NVME_NODE=1   export only NIC-local (node 1) drives        — no NUMA hop, shares NIC bus
#   NVME_NODE=0   export only far (node 0) drives              — extra hop, separate bus
#   NVME_NODE=    (unset) export all drives (default)
#   NVME_MAX=K    cap to at most K drives (after node filter)  — to dial exact near:far counts
set -euo pipefail
source "$(dirname "$0")/common.sh"
need nvme; need modprobe
[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
N="${1:?usage: nvme-target-up.sh <n>}"

CFS=/sys/kernel/config/nvmet
modprobe nvmet
modprobe nvmet-tcp
[ -d "$CFS" ] || die "configfs nvmet not present ($CFS); is the kernel built with NVMe target?"

# device selection, optionally filtered by NUMA node and capped
if [ -n "${NVME_NODE:-}" ]; then
  DEVS=$("$(dirname "$0")/detect-nvme.sh" --node "$NVME_NODE")
  sel="node $NVME_NODE"
else
  DEVS=$("$(dirname "$0")/detect-nvme.sh")
  sel="all nodes"
fi
[ -n "$DEVS" ] || die "no instance-store NVMe devices detected (${sel})"
mapfile -t DEVARR <<< "$DEVS"
if [ -n "${NVME_MAX:-}" ] && [ "${#DEVARR[@]}" -gt "$NVME_MAX" ]; then
  DEVARR=("${DEVARR[@]:0:$NVME_MAX}")
fi
log "exporting ${#DEVARR[@]} device(s) [${sel}${NVME_MAX:+, cap $NVME_MAX}] via nvme-tcp on $N path(s): ${DEVARR[*]}"

# --- subsystem with one namespace per device (idempotent) ---
SUB="$CFS/subsystems/$NVME_NQN"
mkdir -p "$SUB"
echo 1 > "$SUB/attr_allow_any_host"
nsid=1
for dev in "${DEVARR[@]}"; do
  ns="$SUB/namespaces/$nsid"
  mkdir -p "$ns"
  echo -n "$dev" > "$ns/device_path"
  echo 1 > "$ns/enable"
  nsid=$((nsid+1))
done

# --- one port per tunnel, each bound to that tunnel's B-side IP ---
for i in $(seq 0 $((N-1))); do
  ip=$(tun_ip "$i" 2); svc=$(nvme_port "$i")
  port="$CFS/ports/$((100+i))"
  mkdir -p "$port"
  echo ipv4    > "$port/addr_adrfam"
  echo tcp     > "$port/addr_trtype"
  echo "$ip"   > "$port/addr_traddr"
  echo "$svc"  > "$port/addr_trsvcid"
  ln -sf "$SUB" "$port/subsystems/$NVME_NQN" 2>/dev/null || true
done

log "target up: $NVME_NQN on $N path(s) (ports $(nvme_port 0)..$(nvme_port $((N-1))))"
log "tear down with: sudo ./scripts/nvme-target-down.sh"
