#!/usr/bin/env bash
# pin-workers.sh <n> [base_core] — pin each tunnel's userspace worker to a distinct core, to
# test whether removing CPU-scheduler float lifts the ~60 Gbps receive-side crypto ceiling.
#
# Why: node-setup.sh pins the ENA RX-queue IRQs round-robin, but the WireGuard decrypt
# workqueue, ksoftirqd, and the per-tunnel iperf3 server all float across the 192 cores. When
# one serial stage pegs a single core (observed: receiver ~99%), the scheduler bouncing that
# work between cores hurts cache locality. This script pins what we *can* from userspace:
#
#   - tunnel i's iperf3 server  -> core  (base_core + i) % nproc
#
# It does NOT pin the kernel's wg crypto workers (kernel-controlled; no stable userspace
# handle). Treat this as an experiment knob: run a sweep with it on vs off and compare. Run on
# the RECEIVER (B) where the ceiling binds; harmless to also run on A. Idempotent.
#
# NOTE: this pins iperf3 servers by their bind port. For the nvme-tcp workload the equivalent
# worker is the kernel nvmet thread (also not userspace-pinnable); pinning helps the iperf
# sweep most directly.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need taskset; need pgrep
N="${1:?usage: pin-workers.sh <n> [base_core]}"
BASE="${2:-0}"
NPROC=$(nproc)

pinned=0; missed=0
for i in $(seq 0 $((N-1))); do
  port=$((IPERF_BASE_PORT + i))
  core=$(( (BASE + i) % NPROC ))
  # find the iperf3 server PID(s) bound to this port (server-up.sh starts one per port)
  pids=$(pgrep -f "iperf3 -s .* -p $port(\$| )" 2>/dev/null || true)
  [ -n "$pids" ] || pids=$(pgrep -f "iperf3 -s.*-p $port" 2>/dev/null || true)
  if [ -z "$pids" ]; then missed=$((missed+1)); continue; fi
  for pid in $pids; do
    taskset -a -p -c "$core" "$pid" >/dev/null 2>&1 && pinned=$((pinned+1)) || missed=$((missed+1))
  done
done

log "pinned $pinned iperf3 worker(s) to cores ${BASE}..$(((BASE+N-1)%NPROC)) (missed $missed)"
[ "$missed" -eq 0 ] || log "WARN: $missed worker(s) not found — is server-up.sh running with N>=$N?"
log "note: kernel wg-crypto/ksoftirqd threads are NOT pinned (kernel-controlled); compare a"
log "      sweep with pinning on vs off to isolate the scheduler-float contribution."
