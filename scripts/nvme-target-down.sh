#!/usr/bin/env bash
# nvme-target-down.sh [n] — tear down the nvme-tcp target set up by nvme-target-up.sh.
# Run with sudo on B. configfs must be dismantled leaf-first: unlink port->subsystem,
# remove ports, disable+remove namespaces, then the subsystem. Idempotent.
set -euo pipefail
source "$(dirname "$0")/common.sh"
[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
N="${1:-64}"

CFS=/sys/kernel/config/nvmet
[ -d "$CFS" ] || { log "nvmet configfs not present; nothing to tear down"; exit 0; }

# remove ports (and their subsystem symlinks) first
for i in $(seq 0 $((N-1))); do
  port="$CFS/ports/$((100+i))"
  [ -d "$port" ] || continue
  for l in "$port"/subsystems/*; do [ -e "$l" ] && rm -f "$l"; done
  rmdir "$port" 2>/dev/null || true
done

# then the subsystem: disable + remove namespaces, then the subsystem dir
SUB="$CFS/subsystems/$NVME_NQN"
if [ -d "$SUB" ]; then
  for ns in "$SUB"/namespaces/*; do
    [ -d "$ns" ] || continue
    echo 0 > "$ns/enable" 2>/dev/null || true
    rmdir "$ns" 2>/dev/null || true
  done
  rmdir "$SUB" 2>/dev/null || true
fi

log "nvme-tcp target torn down"
