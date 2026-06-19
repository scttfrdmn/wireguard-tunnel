#!/usr/bin/env bash
# measure-membw-numa.sh — per-NUMA-node STREAM Triad: local vs remote memory bandwidth.
#
# The aggregate membw number (measure-membw.sh) hides what a cross-NUMA pipeline cares about:
# how fast can node X's cores read/write memory that physically lives on node Y? This runs the
# full cpu-node x mem-node cross-product with numactl bindings and reports each cell, so we can
# quantify the remote-access penalty before designing a pipeline that may hand data across the
# complex.
#
# Output: results/membw_numa.json — { "<cpu>-><mem>": GBps, ..., "local_avg":, "remote_avg":,
#         "remote_penalty_pct": }
set -euo pipefail
source "$(dirname "$0")/common.sh"
need numactl
CC=$(command -v cc || command -v gcc) || die "need cc/gcc"

nodes=$(numactl -H 2>/dev/null | awk '/^available:/{print $2}')
[ -n "$nodes" ] || die "numactl -H found no nodes"
log "NUMA nodes: $nodes"

# cores-per-node so each cell uses one node's worth of threads (apples-to-apples)
THREADS="${THREADS:-$(( $(nproc) / nodes ))}"
log "threads per cell: $THREADS"

TMP=$(mktemp -d)
cat > "$TMP/stream.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#define N (1L<<27)            /* 128M doubles/array -> ~3 GiB total */
static double a[N], b[N], c[N];
int main(void){
  #pragma omp parallel for   /* first-touch under the active numactl --membind */
  for(long i=0;i<N;i++){a[i]=1.0;b[i]=2.0;c[i]=0.0;}
  double best=1e30;
  for(int r=0;r<10;r++){
    double t=omp_get_wtime();
    #pragma omp parallel for
    for(long i=0;i<N;i++) c[i]=a[i]+3.0*b[i];   /* Triad: 2 read + 1 write */
    t=omp_get_wtime()-t;
    if(t<best) best=t;
  }
  printf("%.1f\n", (3.0*sizeof(double)*N)/1e9/best);
  return 0;
}
EOF
"$CC" -O3 -fopenmp -o "$TMP/stream" "$TMP/stream.c" || die "stream build failed"

cell() { # $1=cpu-node $2=mem-node -> GB/s
  OMP_NUM_THREADS="$THREADS" OMP_PROC_BIND=true \
    numactl --cpunodebind="$1" --membind="$2" "$TMP/stream" 2>/dev/null
}

declare -A R
local_sum=0; local_n=0; remote_sum=0; remote_n=0
for x in $(seq 0 $((nodes-1))); do
  for y in $(seq 0 $((nodes-1))); do
    g=$(cell "$x" "$y"); R["$x-$y"]=$g
    if [ "$x" = "$y" ]; then
      log "cpu node $x -> mem node $y (LOCAL):  ${g} GB/s"
      local_sum=$(echo "$local_sum + $g" | bc -l); local_n=$((local_n+1))
    else
      log "cpu node $x -> mem node $y (remote): ${g} GB/s"
      remote_sum=$(echo "$remote_sum + $g" | bc -l); remote_n=$((remote_n+1))
    fi
  done
done

local_avg=$(echo "scale=1; $local_sum / $local_n" | bc -l)
remote_avg=$([ "$remote_n" -gt 0 ] && echo "scale=1; $remote_sum / $remote_n" | bc -l || echo 0)
penalty=$([ "$remote_n" -gt 0 ] && echo "scale=1; (1 - $remote_avg/$local_avg)*100" | bc -l || echo 0)

cells_json=$(for k in "${!R[@]}"; do printf '"%s":%s,' "$k" "${R[$k]}"; done | sed 's/,$//')
cat > "$RESULTS_DIR/membw_numa.json" <<JSON
{
  "test": "membw_numa",
  "nodes": $nodes,
  "threads_per_cell": $THREADS,
  "cells_GBps": { ${cells_json} },
  "local_avg_GBps": $local_avg,
  "remote_avg_GBps": $remote_avg,
  "remote_penalty_pct": $penalty
}
JSON
cat "$RESULTS_DIR/membw_numa.json"
log "local avg ${local_avg} GB/s, remote avg ${remote_avg} GB/s, remote penalty ${penalty}%"
log "=> a cross-NUMA pipeline hand-off pays ~${penalty}% on any memory it touches remotely"
rm -rf "$TMP"
