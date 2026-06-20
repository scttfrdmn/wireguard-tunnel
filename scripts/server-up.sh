#!/usr/bin/env bash
# server-up.sh <n_max> [forward|reverse|both] — start one iperf3 server per tunnel.
#   forward  (default) bound to the .2 (B) side, ports IPERF_BASE_PORT+i  — for A->B flows
#   reverse  bound to the .1 (A) side, ports REV_BASE+i                   — for B->A flows
#   both     start both sets (a node that both sends and receives under BIDIR)
# Unidirectional: forward on B. BIDIR: forward on B AND reverse on A.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need iperf3
N="${1:?usage: server-up.sh <n_max> [forward|reverse|both]}"
WHICH="${2:-forward}"
REV_BASE="${REV_BASE:-$((IPERF_BASE_PORT + 1000))}"
pkill -f 'iperf3 -s' 2>/dev/null || true
sleep 1
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
