#!/usr/bin/env bash
# server-up.sh <n_max> — start one iperf3 server per tunnel (responder/B side).
set -euo pipefail
source "$(dirname "$0")/common.sh"
need iperf3
N="${1:?n_max}"
pkill -f 'iperf3 -s' 2>/dev/null || true
sleep 1
# setsid + detached fds: iperf3 -D alone does not reliably survive the SSH session that
# launched it, which breaks the sweep (run from a *separate* session). Fully detach instead.
start_srv() { setsid iperf3 -s "$@" </dev/null >/dev/null 2>&1 & }
for i in $(seq 0 $((N-1))); do
  bindip=$(tun_ip "$i" 2)        # B side = .2
  port=$((IPERF_BASE_PORT + i))
  start_srv -B "$bindip" -p "$port"
done
# also a raw-ENA server for baseline
start_srv -p "$IPERF_BASE_PORT"
sleep 1
up=$(ss -ltn 2>/dev/null | grep -c ":$IPERF_BASE_PORT\b\|:520[0-9]\b" || true)
log "started $N per-tunnel iperf3 servers (+ baseline on $IPERF_BASE_PORT); listeners up: ~$up"
