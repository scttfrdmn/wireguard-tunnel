#!/usr/bin/env bash
# server-up.sh <n_max> [forward|reverse|both] — start one iperf3 server per tunnel.
#   forward  (default) bound to the .2 (B) side, ports IPERF_BASE_PORT+i  — for A->B flows
#   reverse  bound to the .1 (A) side, ports REV_BASE+i                   — for B->A flows
#   both     start both sets (a node that both sends and receives under BIDIR)
# Unidirectional: forward on B. BIDIR: forward on B AND reverse on A.
set -euo pipefail
source "$(dirname "$0")/common.sh"
N="${1:?usage: server-up.sh <n_max> [forward|reverse|both]}"
WHICH="${2:-forward}"
REV_BASE="${REV_BASE:-$((IPERF_BASE_PORT + 1000))}"
SINK="${SINK:-iperf3}"
pkill -f 'iperf3 -s' 2>/dev/null || true
pkill -f 'socat .*TCP-LISTEN' 2>/dev/null || true
sleep 1

# SINK=devnull — raw socat sink (TCP-LISTEN -> /dev/null), forward only. Measures the wire
# without iperf3's userspace accounting. Receiver reads throughput from ENA rx_bytes (collect).
if [ "$SINK" = devnull ]; then
  need socat
  for i in $(seq 0 $((N-1))); do
    setsid socat -u "TCP-LISTEN:$((IPERF_BASE_PORT + i)),bind=$(tun_ip "$i" 2),reuseaddr,fork" OPEN:/dev/null,append </dev/null >/dev/null 2>&1 &
  done
  sleep 1
  log "started $N socat devnull sinks (forward, .2 side)"
  exit 0
fi

need iperf3
# setsid + detached fds: iperf3 -D alone does not reliably survive the SSH session that
# launched it, which breaks the sweep (run from a *separate* session). Fully detach instead.
start_srv() { setsid iperf3 -s "$@" </dev/null >/dev/null 2>&1 & }

started=""
if [ "$WHICH" = forward ] || [ "$WHICH" = both ]; then
  for i in $(seq 0 $((N-1))); do
    start_srv -B "$(tun_ip "$i" 2)" -p "$((IPERF_BASE_PORT + i))"   # .2 side (B receives)
  done
  start_srv -p "$IPERF_BASE_PORT"   # raw-ENA baseline server
  started="forward"
fi
if [ "$WHICH" = reverse ] || [ "$WHICH" = both ]; then
  for i in $(seq 0 $((N-1))); do
    start_srv -B "$(tun_ip "$i" 1)" -p "$((REV_BASE + i))"          # .1 side (A receives)
  done
  started="${started:+$started+}reverse"
fi
sleep 1
up=$(ss -ltn 2>/dev/null | grep -c ":520[0-9]\b\|:62[0-9][0-9]\b" || true)
log "started $N iperf3 servers ($started); listeners up: ~$up"
