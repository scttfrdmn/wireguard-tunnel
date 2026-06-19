#!/usr/bin/env bash
# measure-membw-numa.sh — per-NUMA-node memory characterization: STREAM Triad bandwidth across
# a THREAD-COUNT SWEEP, plus a pointer-chase loaded-latency probe.
#
# Why the sweep: a single full-thread STREAM run can't tell apart two very different worlds that
# produce the same "remote is 90% slower" headline:
#   (a) INTERCONNECT SATURATION — remote BW is a fixed shared ceiling; it's flat across thread
#       counts (8 threads ≈ 96 threads). Then a *metadata* hand-off across NUMA is cheap (you're
#       nowhere near the ceiling) but streaming *payload* across is expensive.
#   (b) PER-ACCESS PENALTY — remote BW scales with threads like local does, just lower per
#       thread. Then every cross-node touch pays, regardless of volume.
# The sweep (1,8,24,48,96 threads, local vs remote) distinguishes them. The pointer-chase adds
# the latency number a pipeline hand-off actually pays (STREAM measures streaming BW — the wrong
# regime for a single cache-line hand-off).
#
# Output: results/membw_numa.json
set -euo pipefail
source "$(dirname "$0")/common.sh"
need numactl
CC=$(command -v cc || command -v gcc) || die "need cc/gcc"

nodes=$(numactl -H 2>/dev/null | awk '/^available:/{print $2}')
[ -n "$nodes" ] || die "numactl -H found no nodes"
percore=$(( $(nproc) / nodes ))
THREADS_SWEEP="${THREADS_SWEEP:-1 8 24 48 $percore}"
log "NUMA nodes: $nodes; cores/node: $percore; thread sweep: $THREADS_SWEEP"

TMP=$(mktemp -d)

# --- STREAM Triad (bandwidth) ---
cat > "$TMP/stream.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
/* ~6 GiB total: far larger than LLC, so we measure DRAM not cache. Heap (malloc), NOT static
   arrays — 6 GiB of .bss overflows the arm64 small-code-model relocation range. Runtime scalar
   'q' + printed checksum stop the compiler eliminating/hoisting the Triad loop. */
int main(int argc, char** argv){
  long N = 1L<<28;                              /* 256M doubles/array */
  double q = (argc>1) ? atof(argv[1]) : 3.0;
  double *a=malloc(N*8), *b=malloc(N*8), *c=malloc(N*8);
  if(!a||!b||!c){ fprintf(stderr,"malloc failed\n"); return 1; }
  #pragma omp parallel for                      /* first-touch under the active --membind */
  for(long i=0;i<N;i++){a[i]=1.0;b[i]=2.0;c[i]=0.0;}
  double best=1e30, sink=0.0;
  for(int r=0;r<10;r++){
    double t=omp_get_wtime();
    #pragma omp parallel for
    for(long i=0;i<N;i++) c[i]=a[i]+q*b[i];     /* Triad: 2 read + 1 write */
    t=omp_get_wtime()-t;
    if(t<best) best=t;
    sink += c[(r*99991L)%N];
  }
  fprintf(stderr, "checksum %.1f\n", sink);
  printf("%.1f\n", (3.0*8*N)/1e9/best);
  return 0;
}
EOF
"$CC" -O3 -fopenmp -o "$TMP/stream" "$TMP/stream.c" || die "stream build failed"

# --- pointer-chase (loaded latency): single-thread dependent loads over a shuffled ring that's
# far bigger than cache, so each load misses to DRAM. ns/access ≈ memory latency. ---
cat > "$TMP/latency.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
/* build a random permutation cycle over N pointers (~2 GiB), then chase it. The data-dependent
   chain defeats prefetch/MLP, so this measures access LATENCY, not bandwidth. */
int main(void){
  long N = 1L<<28;                              /* 256M slots * 8B = 2 GiB */
  long *idx = malloc(N*sizeof(long));
  if(!idx){ fprintf(stderr,"malloc failed\n"); return 1; }
  for(long i=0;i<N;i++) idx[i]=i;
  /* Fisher-Yates with a cheap LCG (no Math.random dependency) */
  unsigned long s=88172645463325252UL;
  for(long i=N-1;i>0;i--){ s^=s<<13; s^=s>>7; s^=s<<17; long j=s%(i+1); long t=idx[i]; idx[i]=idx[j]; idx[j]=t; }
  long steps=200000000L, p=0; double t=omp_get_wtime();
  for(long k=0;k<steps;k++) p=idx[p];
  double dt=omp_get_wtime()-t;
  fprintf(stderr,"sink %ld\n", p);
  printf("%.2f\n", dt*1e9/steps);               /* ns per dependent access */
  return 0;
}
EOF
"$CC" -O3 -fopenmp -o "$TMP/latency" "$TMP/latency.c" || die "latency build failed"

# STREAM cell at a given thread count
bw_cell() { # $1=cpu-node $2=mem-node $3=threads
  OMP_NUM_THREADS="$3" OMP_PROC_BIND=spread OMP_PLACES=cores \
    numactl --cpunodebind="$1" --membind="$2" "$TMP/stream" 3.0 2>/dev/null
}
lat_cell() { # $1=cpu-node $2=mem-node -> ns
  numactl --cpunodebind="$1" --membind="$2" "$TMP/latency" 2>/dev/null
}

# Sweep bandwidth: for each thread count, local (0->0) and remote (0->other) if multi-node.
sweep_json=""
other=$(( nodes > 1 ? 1 : 0 ))
for thr in $THREADS_SWEEP; do
  [ "$thr" -le "$percore" ] || continue
  loc=$(bw_cell 0 0 "$thr")
  if [ "$nodes" -gt 1 ]; then rem=$(bw_cell 0 "$other" "$thr"); else rem=0; fi
  log "threads=$thr  local0->0=${loc} GB/s  remote0->$other=${rem} GB/s"
  sweep_json+="{\"threads\":$thr,\"local_GBps\":$loc,\"remote_GBps\":$rem},"
done
sweep_json="[${sweep_json%,}]"

# Full cpu×mem bandwidth matrix at full per-node thread count (the prior behavior, for the report)
declare -A R
for x in $(seq 0 $((nodes-1))); do for y in $(seq 0 $((nodes-1))); do
  R["$x-$y"]=$(bw_cell "$x" "$y" "$percore")
done; done
cells_json=$(for k in "${!R[@]}"; do printf '"%s":%s,' "$k" "${R[$k]}"; done | sed 's/,$//')

# Latency matrix (single-thread, all cpu×mem pairs)
declare -A L
for x in $(seq 0 $((nodes-1))); do for y in $(seq 0 $((nodes-1))); do
  L["$x-$y"]=$(lat_cell "$x" "$y"); log "latency cpu$x->mem$y = ${L[$x-$y]} ns"
done; done
lat_json=$(for k in "${!L[@]}"; do printf '"%s":%s,' "$k" "${L[$k]}"; done | sed 's/,$//')

local_bw=${R["0-0"]:-0}; remote_bw=${R["0-$other"]:-0}
local_lat=${L["0-0"]:-0}; remote_lat=${L["0-$other"]:-0}
bw_penalty=$([ "$nodes" -gt 1 ] && echo "scale=1; (1 - $remote_bw/$local_bw)*100" | bc -l || echo 0)
lat_ratio=$([ "$nodes" -gt 1 ] && echo "scale=2; $remote_lat/$local_lat" | bc -l || echo 1)

cat > "$RESULTS_DIR/membw_numa.json" <<JSON
{
  "test": "membw_numa",
  "nodes": $nodes,
  "cores_per_node": $percore,
  "full_thread_cells_GBps": { ${cells_json} },
  "thread_sweep": ${sweep_json},
  "latency_ns": { ${lat_json} },
  "local_bw_GBps": $local_bw,
  "remote_bw_GBps": $remote_bw,
  "remote_bw_penalty_pct": $bw_penalty,
  "local_latency_ns": $local_lat,
  "remote_latency_ns": $remote_lat,
  "remote_latency_ratio": $lat_ratio
}
JSON
cat "$RESULTS_DIR/membw_numa.json"
log "BW: local ${local_bw} / remote ${remote_bw} GB/s (penalty ${bw_penalty}%)"
log "Latency: local ${local_lat} / remote ${remote_lat} ns (ratio ${lat_ratio}x)"
log "Interpretation: if thread_sweep remote_GBps is FLAT across thread counts => interconnect"
log "  saturation (metadata hand-offs cheap, payload crossings expensive); if it SCALES with"
log "  threads => per-access penalty (keep everything node-local). Latency ratio is what a"
log "  single pipeline hand-off pays."
rm -rf "$TMP"
