#!/usr/bin/env bash
# sweep.sh <mode-label>   e.g. ./sweep.sh placement   or   ./sweep.sh ena_express
# Drives one pinned flow per tunnel for N in the sweep list, captures aggregate Gbps and
# per-node attribution counters, and writes results/<mode>/N<n>/datapoint.json.
#
# Env: REMOTE_HOST=<B private ip> (for remote collect), DUR=30, SWEEP="1 2 4 8 12 16 24 32"
#
# Jumbo-vs-1500 comparison (README): the wg MTU is set when the mesh is built, via WG_MTU
# consumed by mesh-up.sh. To produce the 1500 datapoint, re-mesh at that MTU and label the
# run so it doesn't overwrite the jumbo one, e.g.:
#     WG_MTU=1500 ./scripts/mesh-up.sh a <N> <B_ip> wg-pub-b.txt   # (and on B)
#     WG_MTU=1500 ./scripts/sweep.sh placement_mtu1500
# The recorded wg_mtu is verified against the live wg0 MTU below; a mismatch means the mesh
# was not (re)built at WG_MTU and the datapoint would be mislabeled.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need iperf3; need jq
MODE="${1:?mode label}"
DUR="${DUR:-30}"
SWEEP="${SWEEP:-1 2 4 8 12 16 24 32}"
REMOTE_HOST="${REMOTE_HOST:?set REMOTE_HOST to B private ip}"
SSH="ssh -o StrictHostKeyChecking=no ubuntu@${REMOTE_HOST}"
SDIR="$(cd "$(dirname "$0")" && pwd)"

# BIDIR=1 — full-duplex: in addition to the A->B flows, drive B->A flows on a disjoint iperf
# port block (REV_BASE), so each node both sends and receives simultaneously. The headline is
# aggregate wire = A->B + B->A. Requires reverse iperf3 servers bound to A's tunnel IPs (.1) —
# start them with: ./scripts/server-up.sh <N> reverse   (on A, before this sweep).
# NOT iperf3 --bidir: paired one-way flows keep per-direction attribution clean and avoid
# forward+reverse sharing one peer's serial crypto pipeline.
BIDIR="${BIDIR:-}"
REV_BASE="${REV_BASE:-$((IPERF_BASE_PORT + 1000))}"   # reverse-flow iperf ports (B->A)

# Guard: the recorded wg_mtu must match the live tunnel, or the datapoint is mislabeled.
live_mtu=$(cat "/sys/class/net/$(tun_dev 0)/mtu" 2>/dev/null || echo "")
if [ -n "$live_mtu" ] && [ "$live_mtu" != "$WG_MTU" ]; then
  log "WARN: wg0 MTU is $live_mtu but WG_MTU=$WG_MTU — re-run mesh-up at WG_MTU=$WG_MTU first"
fi

for N in $SWEEP; do
  outdir="$RESULTS_DIR/$MODE/N$N"; mkdir -p "$outdir"
  log "=== mode=$MODE N=$N tunnels, ${DUR}s ==="

  # idempotency: clear stale per-flow output so a re-run with a smaller N can't leave
  # orphaned flow*.json files that would inflate the aggregate.
  rm -f "$outdir"/flow*.json "$outdir"/rev*.json "$outdir/node_a.json" "$outdir/node_b.json"

  # forward A->B: one client per tunnel on A
  pids=(); for i in $(seq 0 $((N-1))); do
    src=$(tun_ip "$i" 1); dst=$(tun_ip "$i" 2); port=$((IPERF_BASE_PORT + i))
    iperf3 -c "$dst" -B "$src" -p "$port" -t "$DUR" -P 1 -J > "$outdir/flow$i.json" 2>/dev/null &
    pids+=($!)
  done

  # reverse B->A (BIDIR only): drive B's clients toward A's reverse servers (bound to .1),
  # in parallel. Run on B via ssh; JSON comes back over stdout per flow into rev<i>.json.
  if [ -n "$BIDIR" ]; then
    for i in $(seq 0 $((N-1))); do
      rsrc=$(tun_ip "$i" 2); rdst=$(tun_ip "$i" 1); rport=$((REV_BASE + i))
      $SSH "iperf3 -c $rdst -B $rsrc -p $rport -t $DUR -P 1 -J" > "$outdir/rev$i.json" 2>/dev/null &
      pids+=($!)
    done
  fi

  # collect on both nodes during the window (slightly shorter than load)
  cwin=$((DUR>6 ? DUR-4 : DUR))
  ( sleep 2; "$SDIR/collect.sh" "$cwin" "$outdir/node_a.json" ) &
  ca=$!
  ( sleep 2; $SSH "sudo bash -s" "$cwin" < "$SDIR/collect.sh" > "$outdir/node_b.json" 2>/dev/null ) &
  cb=$!

  wait "${pids[@]}" || true
  wait "$ca" "$cb" 2>/dev/null || true

  # per-direction aggregate throughput
  gbps_a2b=$(jq -s '[.[].end.sum_sent.bits_per_second]|add/1e9' "$outdir"/flow*.json)
  if [ -n "$BIDIR" ] && ls "$outdir"/rev*.json >/dev/null 2>&1; then
    gbps_b2a=$(jq -s '[.[].end.sum_sent.bits_per_second]|add/1e9' "$outdir"/rev*.json 2>/dev/null || echo 0)
  else
    gbps_b2a=0
  fi
  gbps=$(jq -n --argjson f "$gbps_a2b" --argjson r "$gbps_b2a" '$f + $r')   # aggregate wire

  jq -n \
    --argjson n "$N" --arg mode "$MODE" --argjson mtu "$WG_MTU" --argjson dur "$DUR" \
    --argjson gbps "$gbps" --argjson a2b "$gbps_a2b" --argjson b2a "$gbps_b2a" \
    --slurpfile a "$outdir/node_a.json" \
    --slurpfile b "$outdir/node_b.json" \
    '{n_tunnels:$n, mode:$mode, wg_mtu:$mtu, duration_s:$dur, throughput_gbps:$gbps,
      throughput_gbps_a2b:$a2b, throughput_gbps_b2a:$b2a,
      node_a:$a[0], node_b:$b[0]}' > "$outdir/datapoint.json"

  if [ -n "$BIDIR" ]; then
    log "N=$N -> $(printf '%.1f' "$gbps") Gbps aggregate ($(printf '%.1f' "$gbps_a2b") a2b + $(printf '%.1f' "$gbps_b2a") b2a)  ($outdir/datapoint.json)"
  else
    log "N=$N -> $(printf '%.1f' "$gbps") Gbps  (datapoint: $outdir/datapoint.json)"
  fi
done
log "sweep '$MODE' complete. Run: (cd report && go run . $RESULTS_DIR)"
