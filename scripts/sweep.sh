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

# SINK=devnull — replace the iperf3 server/client pair with a raw socat blaster→/dev/null sink,
# to measure throughput WITHOUT iperf3's per-interval userspace accounting cost. Sender:
# `socat -u /dev/zero TCP:dst:port` per tunnel; receiver runs the matching sinks (server-up.sh
# SINK=devnull). Throughput is read from the receiver's ENA rx_bytes delta (in node_b.json),
# not iperf3 JSON. Isolates "is iperf3 itself part of the 113 ceiling?". Forward/A->B only.
SINK="${SINK:-iperf3}"

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
  rm -f "$outdir"/flow*.json "$outdir"/wgrev_*.json "$outdir/node_a.json" "$outdir/node_b.json"

  # forward A->B: one client per tunnel on A. iperf3 (default) writes per-flow JSON; the
  # devnull sink uses socat /dev/zero->TCP for `DUR` seconds (timeout-bounded), no JSON.
  pids=(); for i in $(seq 0 $((N-1))); do
    src=$(tun_ip "$i" 1); dst=$(tun_ip "$i" 2); port=$((IPERF_BASE_PORT + i))
    if [ "$SINK" = devnull ]; then
      timeout "$((DUR+2))" socat -u OPEN:/dev/zero "TCP:${dst}:${port},bind=${src}" >/dev/null 2>&1 &
    else
      iperf3 -c "$dst" -B "$src" -p "$port" -t "$DUR" -P 1 -J > "$outdir/flow$i.json" 2>/dev/null &
    fi
    pids+=($!)
  done

  # reverse B->A (BIDIR only): drive B's clients toward A's reverse servers (bound to .1).
  # Launch ALL reverse clients inside ONE ssh session (background+wait on B), writing per-flow
  # JSON to /tmp on B — N separate ssh calls would hit sshd MaxSessions (~10) and starve the
  # remote collect. We scp the rev*.json back after the window.
  revpid=""
  if [ -n "$BIDIR" ]; then
    $SSH "rm -f /tmp/wgrev_*.json; for i in \$(seq 0 $((N-1))); do \
            iperf3 -c $TUN_NET.\$i.1 -B $TUN_NET.\$i.2 -p \$(($REV_BASE+i)) -t $DUR -P 1 -J \
              > /tmp/wgrev_\$i.json 2>/dev/null & done; wait" >/dev/null 2>&1 &
    revpid=$!
  fi

  # collect on both nodes during the window (slightly shorter than load)
  cwin=$((DUR>6 ? DUR-4 : DUR))
  ( sleep 2; "$SDIR/collect.sh" "$cwin" "$outdir/node_a.json" ) &
  ca=$!
  ( sleep 2; $SSH "sudo bash -s" "$cwin" < "$SDIR/collect.sh" > "$outdir/node_b.json" 2>/dev/null ) &
  cb=$!

  wait "${pids[@]}" || true
  [ -n "$revpid" ] && { wait "$revpid" 2>/dev/null || true; }
  wait "$ca" "$cb" 2>/dev/null || true

  # pull the reverse per-flow JSON back from B (BIDIR)
  if [ -n "$BIDIR" ]; then
    scp -o StrictHostKeyChecking=no -q "ubuntu@${REMOTE_HOST}:/tmp/wgrev_*.json" "$outdir/" 2>/dev/null || true
  fi

  # per-direction A->B throughput.
  #   devnull sink: no iperf3 JSON — use the receiver's wire rx_gbps (from node_b.json).
  #   iperf3:       sum the per-flow sum_sent + compute the per-flow rate distribution.
  flow_min=0; flow_med=0; flow_max=0; flow_cv=0
  if [ "$SINK" = devnull ]; then
    gbps_a2b=$(jq -r '.rx_gbps // 0' "$outdir/node_b.json" 2>/dev/null || echo 0)
  else
    gbps_a2b=$(jq -s '[.[].end.sum_sent.bits_per_second]|add/1e9' "$outdir"/flow*.json)
    # per-flow rate distribution (receiver-true sum_received) — proves diminishing returns:
    # as N rises, mean per-flow rate falling ~1/N while the sum stays flat = aggregate-limited.
    read -r flow_min flow_med flow_max flow_cv < <(jq -s '
      [.[].end.sum_received.bits_per_second/1e9] | sort as $s |
      ($s|add/length) as $m |
      "\($s[0]) \($s[(length/2|floor)]) \($s[-1]) \(if $m>0 then (([.[]|(.-$m)*(.-$m)]|add/length)|sqrt)/$m else 0 end)"
    ' "$outdir"/flow*.json 2>/dev/null | tr -d '"' || echo "0 0 0 0")
  fi
  if [ -n "$BIDIR" ] && ls "$outdir"/wgrev_*.json >/dev/null 2>&1; then
    gbps_b2a=$(jq -s '[.[].end.sum_sent.bits_per_second]|add/1e9' "$outdir"/wgrev_*.json 2>/dev/null || echo 0)
  else
    gbps_b2a=0
  fi
  gbps=$(jq -n --argjson f "${gbps_a2b:-0}" --argjson r "${gbps_b2a:-0}" '$f + $r')   # aggregate wire

  jq -n \
    --argjson n "$N" --arg mode "$MODE" --argjson mtu "$WG_MTU" --argjson dur "$DUR" \
    --arg sink "$SINK" \
    --argjson gbps "$gbps" --argjson a2b "${gbps_a2b:-0}" --argjson b2a "${gbps_b2a:-0}" \
    --argjson fmin "${flow_min:-0}" --argjson fmed "${flow_med:-0}" --argjson fmax "${flow_max:-0}" --argjson fcv "${flow_cv:-0}" \
    --slurpfile a "$outdir/node_a.json" \
    --slurpfile b "$outdir/node_b.json" \
    '{n_tunnels:$n, mode:$mode, sink:$sink, wg_mtu:$mtu, duration_s:$dur, throughput_gbps:$gbps,
      throughput_gbps_a2b:$a2b, throughput_gbps_b2a:$b2a,
      flow_gbps_min:$fmin, flow_gbps_median:$fmed, flow_gbps_max:$fmax, flow_gbps_cv:$fcv,
      node_a:$a[0], node_b:$b[0]}' > "$outdir/datapoint.json"

  if [ -n "$BIDIR" ]; then
    log "N=$N -> $(printf '%.1f' "$gbps") Gbps aggregate ($(printf '%.1f' "$gbps_a2b") a2b + $(printf '%.1f' "$gbps_b2a") b2a)  ($outdir/datapoint.json)"
  else
    log "N=$N -> $(printf '%.1f' "$gbps") Gbps  (datapoint: $outdir/datapoint.json)"
  fi
done
log "sweep '$MODE' complete. Run: (cd report && go run . $RESULTS_DIR)"
