#!/usr/bin/env bash
# server-up.sh <n_max> — start one iperf3 server per tunnel (responder/B side).
set -euo pipefail
source "$(dirname "$0")/common.sh"
need iperf3
N="${1:?n_max}"
pkill -f 'iperf3 -s' 2>/dev/null || true
for i in $(seq 0 $((N-1))); do
  bindip=$(tun_ip "$i" 2)        # B side = .2
  port=$((IPERF_BASE_PORT + i))
  iperf3 -s -B "$bindip" -p "$port" -D
done
# also a raw-ENA server for baseline
iperf3 -s -p "$IPERF_BASE_PORT" -D 2>/dev/null || true
log "started $N per-tunnel iperf3 servers (+ baseline on $IPERF_BASE_PORT)"
