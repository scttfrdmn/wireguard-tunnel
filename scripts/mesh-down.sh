#!/usr/bin/env bash
# mesh-down.sh [n_max] — remove wg0..wg(n-1) (default 64)
set -euo pipefail
source "$(dirname "$0")/common.sh"
N="${1:-64}"
for i in $(seq 0 $((N-1))); do ip link del "$(tun_dev "$i")" 2>/dev/null || true; done
log "removed up to $N tunnels"
