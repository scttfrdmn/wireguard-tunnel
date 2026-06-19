#!/usr/bin/env bash
# measure-nvme-tcp.sh <mode-label> — end-to-end NVMe->NVMe transfer over the tunnels,
# using nvme-tcp native multipath (one path per tunnel, round-robin iopolicy). Run on A
# (initiator) with sudo, AFTER mesh-up.sh on both nodes and nvme-target-up.sh on B.
#
# It connects N paths to the single target subsystem (NVME_NQN), so each I/O command rides
# a different tunnel = a different 5-tuple = a different ENA RX queue + crypto pipeline.
# Then fio drives the resulting /dev/nvmeXnY multipath block devices and we record the
# aggregate GB/s plus both-node attribution counters, in the SAME datapoint.json schema as
# sweep.sh — so `report` ingests it with no changes.
#
# Env: REMOTE_HOST=<B priv ip> (both-node collect), DUR=30, SWEEP="1 2 4 8 12 16 24 32",
#      RW="read write" (which fio patterns to run), BS=1M, IODEPTH=32.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need nvme; need fio; need jq
[ "$(id -u)" -eq 0 ] || die "run as root (sudo) — nvme connect needs it"
MODE="${1:?usage: measure-nvme-tcp.sh <mode-label>}"
DUR="${DUR:-30}"
SWEEP="${SWEEP:-1 2 4 8 12 16 24 32}"
RW="${RW:-read write}"
BS="${BS:-1M}"; IODEPTH="${IODEPTH:-32}"
REMOTE_HOST="${REMOTE_HOST:?set REMOTE_HOST to B private ip}"
SSH="ssh -o StrictHostKeyChecking=no ubuntu@${REMOTE_HOST}"
SDIR="$(cd "$(dirname "$0")" && pwd)"

# nvme multipath devices for our subsystem = the namespace block devs (not the per-path ctrls).
# Read from sysfs: nvme-cli's `nvme list -o json` schema varies by version and doesn't reliably
# expose SubsystemNQN at the top level, but the kernel always lists the subsystem's namespace
# block devices under /sys/class/nvme-subsystem/<s>/ when subsysnqn matches.
mp_devices() {
  local s inst
  for s in /sys/class/nvme-subsystem/nvme-subsys*; do
    [ -e "$s/subsysnqn" ] || continue
    grep -qxF "$NVME_NQN" "$s/subsysnqn" 2>/dev/null || continue
    # subsystem instance number (nvme-subsys17 -> 17); its namespace multipath block devices
    # are /dev/nvme17n* (NOT symlinked under the subsys sysfs dir on all kernels). Exclude
    # partitions (…p1) and controller-scoped names (nvme17c17n2).
    inst=$(basename "$s" | sed 's/nvme-subsys//')
    find /dev -maxdepth 1 -regextype posix-extended \
      -regex "/dev/nvme${inst}n[0-9]+" 2>/dev/null
  done | sort -u
}

disconnect_all() { nvme disconnect -n "$NVME_NQN" >/dev/null 2>&1 || true; }
trap disconnect_all EXIT

for N in $SWEEP; do
  log "=== nvme-tcp mode=$MODE N=$N path(s), ${DUR}s ==="

  # (re)connect exactly N paths, each pinned to its tunnel's A-side source IP so the
  # outer 5-tuple is distinct per path.
  disconnect_all
  for i in $(seq 0 $((N-1))); do
    src=$(tun_ip "$i" 1); dst=$(tun_ip "$i" 2); svc=$(nvme_port "$i")
    nvme connect -t tcp -n "$NVME_NQN" -a "$dst" -s "$svc" \
      --host-traddr "$src" >/dev/null 2>&1 \
      || log "WARN: path $i ($src->$dst:$svc) failed to connect"
  done
  # namespace block devices appear asynchronously after connect — wait up to ~10s for them.
  for _try in $(seq 1 10); do
    [ "$(mp_devices | wc -l)" -gt 0 ] && break
    sleep 1
  done

  # round-robin so commands spray across all N paths/tunnels
  for h in /sys/class/nvme-subsystem/*/iopolicy; do
    [ -e "$h" ] || continue
    if grep -qxF "$NVME_NQN" "$(dirname "$h")/subsysnqn" 2>/dev/null; then
      echo round-robin > "$h" 2>/dev/null || true
    fi
  done

  mapfile -t MP < <(mp_devices)
  [ "${#MP[@]}" -gt 0 ] || { log "WARN: no multipath devices for $NVME_NQN at N=$N; skipping"; continue; }

  for rw in $RW; do
    outdir="$RESULTS_DIR/nvme_tcp_${MODE}_${rw}/N$N"; mkdir -p "$outdir"
    rm -f "$outdir"/*.json

    fioargs=(); for d in "${MP[@]}"; do fioargs+=("--name=p_$(basename "$d")" "--filename=$d"); done

    # both-node attribution during the load window
    cwin=$((DUR>6 ? DUR-4 : DUR))
    ( sleep 2; "$SDIR/collect.sh" "$cwin" "$outdir/node_a.json" ) & ca=$!
    ( sleep 2; $SSH "sudo bash -s" "$cwin" < "$SDIR/collect.sh" > "$outdir/node_b.json" 2>/dev/null ) & cb=$!

    fio --rw="$rw" --bs="$BS" --iodepth="$IODEPTH" --numjobs=1 --direct=1 --ioengine=libaio \
        --time_based --runtime="$DUR" --group_reporting --output-format=json \
        "${fioargs[@]}" > "$outdir/fio.json" 2>/dev/null || true
    wait "$ca" "$cb" 2>/dev/null || true

    # aggregate GB/s and equivalent Gbps (so it lands in report's throughput_gbps column)
    key=$([ "$rw" = write ] && echo write || echo read)
    gbytes=$(jq --arg k "$key" '[.jobs[][$k].bw_bytes]|add/1e9' "$outdir/fio.json")
    gbps=$(jq -n --argjson gb "$gbytes" '$gb*8')

    jq -n \
      --argjson n "$N" --arg mode "nvme_tcp_${MODE}_${rw}" --argjson mtu "$WG_MTU" \
      --argjson dur "$DUR" --argjson gbps "$gbps" --argjson gbytes "$gbytes" --arg rw "$rw" \
      --slurpfile a "$outdir/node_a.json" --slurpfile b "$outdir/node_b.json" \
      '{n_tunnels:$n, mode:$mode, wg_mtu:$mtu, duration_s:$dur, throughput_gbps:$gbps,
        nvme_GBps:$gbytes, rw:$rw, node_a:$a[0], node_b:$b[0]}' > "$outdir/datapoint.json"

    log "N=$N $rw -> $(printf '%.1f' "$gbytes") GB/s ($(printf '%.1f' "$gbps") Gbps)  $outdir/datapoint.json"
  done
done

disconnect_all; trap - EXIT
log "nvme-tcp sweep '$MODE' complete. Confirm it tracks the synthetic sweep in: (cd report && go run . $RESULTS_DIR)"
