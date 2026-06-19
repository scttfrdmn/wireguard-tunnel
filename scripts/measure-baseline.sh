#!/usr/bin/env bash
# measure-baseline.sh <peer_priv_ip> [parallel] [duration]
# Raw network ceiling over the ENA with no WireGuard, many flows.
# Requires iperf3 -s running on the peer (start with: iperf3 -s -p 5201 on B).
set -euo pipefail
source "$(dirname "$0")/common.sh"
need iperf3; need jq
PEER="${1:?peer private ip}"; P="${2:-32}"; T="${3:-30}"

log "baseline: $P parallel streams, ${T}s, raw ENA to $PEER"
before_tx=$(ena_pkts tx); before_ts=$(date +%s.%N)
out=$(iperf3 -c "$PEER" -p "$IPERF_BASE_PORT" -P "$P" -t "$T" -J)
after_tx=$(ena_pkts tx); after_ts=$(date +%s.%N)

gbps=$(echo "$out" | jq '.end.sum_sent.bits_per_second/1e9')
dt=$(echo "$after_ts - $before_ts" | bc -l)
pps=$(echo "($after_tx - $before_tx)/$dt" | bc -l)

printf '{"test":"baseline","streams":%s,"gbps":%s,"tx_pps":%.0f}\n' "$P" "$gbps" "$pps" \
  | tee "$RESULTS_DIR/baseline.json"
