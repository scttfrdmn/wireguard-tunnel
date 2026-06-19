#!/usr/bin/env bash
# measure-membw.sh — achievable memory-bandwidth ceiling (STREAM Triad), all cores.
# The pipeline touches memory ~4x per wire-byte; this measures the wall that implies.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need cc 2>/dev/null || need gcc
CC=$(command -v cc || command -v gcc)
TMP=$(mktemp -d)
cat > "$TMP/stream.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#define N (1L<<27)   /* 128M doubles per array -> ~3 GiB total */
static double a[N], b[N], c[N];
int main(void){
  for(long i=0;i<N;i++){a[i]=1.0;b[i]=2.0;c[i]=0.0;}
  double best=1e30;
  for(int r=0;r<10;r++){
    double t=omp_get_wtime();
    #pragma omp parallel for
    for(long i=0;i<N;i++) c[i]=a[i]+3.0*b[i];   /* Triad */
    t=omp_get_wtime()-t;
    if(t<best) best=t;
  }
  double gb=(3.0*sizeof(double)*N)/1e9;   /* 2 read + 1 write */
  printf("%.1f\n", gb/best);
  return 0;
}
EOF
"$CC" -O3 -fopenmp -o "$TMP/stream" "$TMP/stream.c"
gbps=$(OMP_NUM_THREADS=$(nproc) OMP_PROC_BIND=true "$TMP/stream")
printf '{"test":"membw","triad_GBps":%s}\n' "$gbps" | tee "$RESULTS_DIR/membw.json"
log "memory bandwidth (Triad) = ${gbps} GB/s across $(nproc) cores"
log "at 180 Gbps wire the pipeline needs ~4x22.5=90 GB/s of memory traffic — compare to above"
rm -rf "$TMP"
