#!/usr/bin/env bash
# collect.sh <duration_s> <out.json>
# Snapshots everything needed to attribute the knee, over a load window. Run on a node
# WHILE the load is active. Emits a node-level JSON object.
#
# Self-contained ON PURPOSE: sweep.sh ships this script to node B with
# `ssh ... sudo bash -s < collect.sh`, where $0 is "bash" and there is no common.sh on the
# remote filesystem. So this script must NOT `source common.sh` — it inlines the handful of
# helpers it needs, and stays a drop-in copy of the equivalents there.
set -euo pipefail

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }
primary_if() { ip route show default | awk '{print $5; exit}'; }
PRIMARY_IF="${PRIMARY_IF:-$(primary_if)}"
# Snapshot ENA counters as "key value" numeric lines
ena_stats() {
  ethtool -S "$PRIMARY_IF" 2>/dev/null \
    | awk -F: 'NF==2{gsub(/ /,"",$1);gsub(/ /,"",$2); if ($2 ~ /^[0-9]+$/) print $1" "$2}'
}
ena_stat() { ena_stats | awk -v k="$1" '$1==k{print $2; f=1} END{if(!f)print 0}'; }
# total tx/rx packets: flat counter if present, else sum per-queue queue_<n>_<tx|rx>_cnt
ena_pkts() {
  local flat; flat=$(ena_stat "${1}_packets")
  if [ "${flat:-0}" != 0 ]; then echo "$flat"; return; fi
  ena_stats | awk -v d="$1" '$1 ~ ("^queue_[0-9]+_" d "_cnt$"){s+=$2} END{print s+0}'
}

need ethtool; need mpstat
DUR="${1:-20}"; OUT="${2:-/dev/stdout}"

# --- before snapshot ---
declare -A B
B[tx_packets]=$(ena_pkts tx)
B[rx_packets]=$(ena_pkts rx)
for k in bw_in_allowance_exceeded bw_out_allowance_exceeded \
         pps_allowance_exceeded conntrack_allowance_exceeded linklocal_allowance_exceeded \
         ena_srd_tx_pkts ena_srd_rx_pkts ena_srd_eligible_tx_pkts; do
  B[$k]=$(ena_stat "$k")
done
srd_util=$(ena_stat ena_srd_resource_utilization)
softirq_before=$(awk '/NET_RX/{for(i=2;i<=NF;i++)printf "%s ",$i; print ""}' /proc/softirqs)
t0=$(date +%s.%N)

# --- CPU over the window: per-core histogram + thread attribution ---
# Sample per-thread CPU concurrently with mpstat so we can name *what* pegs a core
# (ksoftirqd vs wg crypto workqueue vs iperf3 vs fio), not just that one core is at 99%.
pidlog=""; pidsampler=""
if command -v pidstat >/dev/null 2>&1; then
  pidlog=$(mktemp)
  pint=2; pcnt=$(( DUR / pint )); [ "$pcnt" -lt 1 ] && pcnt=1
  pidstat -t "$pint" "$pcnt" > "$pidlog" 2>/dev/null &
  pidsampler=$!
fi

mp=$(mpstat -P ALL 1 "$DUR" 2>/dev/null || true)
[ -n "$pidsampler" ] && { wait "$pidsampler" 2>/dev/null || true; }

# One awk pass over the per-core Average lines: busy core-equivalents (sum of (100-idle)/100,
# i.e. how many full cores' worth of work), cores over 50/90%, and a util-band histogram.
read -r busy_core_equiv cores_gt50 cores_gt90 band_0_10 band_10_50 band_50_90 band_90_100 ncores <<EOF
$(echo "$mp" | awk '/^Average:/ && $2 ~ /^[0-9]+$/ {
    busy=100-$NF; tot+=busy; n++;
    if(busy>90){g90++} else if(busy>50){g50++} else if(busy>10){g10++} else {g0++}
  }
  END{ printf "%.2f %d %d %d %d %d %d %d\n", tot/100, (g50+g90)+0, g90+0, g0+0, g10+0, g50+0, g90+0, n+0 }')
EOF
busy_cores=$cores_gt90   # preserve the original field's meaning (# cores >90% busy)
max_busy=$(echo "$mp" | awk '/^Average:/ && $2 ~ /^[0-9]+$/ {b=100-$NF; if(b>m)m=b} END{printf "%.1f", m+0}')

# Top threads by %CPU during the window (thread rows in pidstat -t have TGID column "-").
# This is the field that answers "which single thread is the bottleneck core running".
top_threads="[]"
if [ -n "$pidlog" ] && [ -s "$pidlog" ]; then
  top_threads=$(awk '/^Average:/ && $3=="-" { pct=$(NF-2); comm=$NF; if (pct+0>5) print pct"\t"comm }' "$pidlog" \
    | sort -rn | head -8 \
    | awk -F'\t' 'BEGIN{printf "["} {gsub(/[\\"]/,"",$2); printf "%s{\"comm\":\"%s\",\"pct\":%.1f}", (NR>1?",":""), $2, $1} END{printf "]"}')
  [ -n "$top_threads" ] || top_threads="[]"
fi
[ -n "$pidlog" ] && rm -f "$pidlog"

# --- after snapshot ---
t1=$(date +%s.%N); dt=$(echo "$t1 - $t0" | bc -l)
declare -A A
A[tx_packets]=$(ena_pkts tx)
A[rx_packets]=$(ena_pkts rx)
for k in "${!B[@]}"; do
  case "$k" in tx_packets|rx_packets) continue;; esac
  A[$k]=$(ena_stat "$k")
done
softirq_after=$(awk '/NET_RX/{for(i=2;i<=NF;i++)printf "%s ",$i; print ""}' /proc/softirqs)

# softirq concentration: top core's share of total NET_RX delta.
# NB: command substitution (not `read`) — awk's printf emits no trailing newline, so a
# `read` here returns non-zero at EOF and aborts the script under `set -e`.
top_share=$(paste -d' ' <(echo "$softirq_before") <(echo "$softirq_after") | awk '{
  half=NF/2; tot=0; top=0;
  for(i=1;i<=half;i++){d=$(i+half)-$i; if(d<0)d=0; tot+=d; if(d>top)top=d}
  if(tot>0) printf "%.3f", top/tot; else printf "0"
}')

d() { echo $(( A[$1] - B[$1] )); }
tx_pps=$(echo "($(d tx_packets))/$dt" | bc -l)

cat > "$OUT" <<JSON
{
  "host": "$(hostname -s)",
  "duration_s": $DUR,
  "tx_pps": $(printf '%.0f' "$tx_pps"),
  "busy_cores": $busy_cores,
  "max_core_util": $max_busy,
  "ncores": ${ncores:-0},
  "busy_core_equiv": ${busy_core_equiv:-0},
  "cores_gt50": ${cores_gt50:-0},
  "cores_gt90": ${cores_gt90:-0},
  "util_band_0_10": ${band_0_10:-0},
  "util_band_10_50": ${band_10_50:-0},
  "util_band_50_90": ${band_50_90:-0},
  "util_band_90_100": ${band_90_100:-0},
  "top_threads": ${top_threads:-[]},
  "softirq_rx_top_core_share": $top_share,
  "bw_in_allowance_exceeded": $(d bw_in_allowance_exceeded),
  "bw_out_allowance_exceeded": $(d bw_out_allowance_exceeded),
  "pps_allowance_exceeded": $(d pps_allowance_exceeded),
  "conntrack_allowance_exceeded": $(d conntrack_allowance_exceeded),
  "linklocal_allowance_exceeded": $(d linklocal_allowance_exceeded),
  "ena_srd_tx_pkts": $(d ena_srd_tx_pkts),
  "ena_srd_rx_pkts": $(d ena_srd_rx_pkts),
  "ena_srd_eligible_tx_pkts": $(d ena_srd_eligible_tx_pkts),
  "ena_srd_resource_utilization": ${srd_util:-0}
}
JSON
