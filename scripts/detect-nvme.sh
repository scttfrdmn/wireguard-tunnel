#!/usr/bin/env bash
# detect-nvme.sh [--node N] [--with-node] — print instance-store NVMe device paths.
#   (no args)      one device path per line (back-compat)
#   --node N       only devices whose controller is on NUMA node N
#   --with-node    print "<path> <numa_node>" per line (for selection/balancing)
#
# Why node-aware: the 16 instance-store drives split across both NUMA nodes; the NIC is on
# one node, so for the nvme-tcp workload, drives on the *other* node carry an EXTRA pipeline
# hop (decrypt on the NIC node -> cross-complex DMA -> write on the remote drive). Selecting
# or balancing drives by node lets us account for that hop instead of paying it blindly.
set -euo pipefail
need() { command -v "$1" >/dev/null || { echo "need $1" >&2; exit 1; }; }
need nvme

WANT_NODE=""; WITH_NODE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --node) WANT_NODE="$2"; shift 2 ;;
    --with-node) WITH_NODE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# device -> numa_node via the block device's controller in sysfs.
dev_node() { # $1=/dev/nvmeXnY -> node (or -1)
  local base ctrl
  base=$(basename "$1")                 # nvme9n1
  ctrl=${base%n*}                       # nvme9
  cat "/sys/class/nvme/$ctrl/numa_node" 2>/dev/null || echo -1
}

# list instance-store device paths (same detection as before)
devs=$(nvme list -o json 2>/dev/null \
  | jq -r '.Devices[] | select(.ModelNumber | test("Instance Storage")) | .DevicePath' 2>/dev/null) \
  || devs=$(lsblk -dn -o NAME,MODEL | awk '/Instance Storage/{print "/dev/"$1}')

for d in $devs; do
  n=$(dev_node "$d")
  [ -n "$WANT_NODE" ] && [ "$n" != "$WANT_NODE" ] && continue
  if [ "$WITH_NODE" = 1 ]; then echo "$d $n"; else echo "$d"; fi
done
