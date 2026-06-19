#!/usr/bin/env bash
# rps-setup.sh <on|off> [cpulist] — toggle RPS + RFS (software receive steering) on the ENA.
# Run with sudo on the RECEIVER. Lets us MEASURE (not assume) whether RPS helps; the design
# review predicts it's neutral/negative at N>=16 because the 32 outer flows are already hashed
# to distinct HW RX queues by RSS, so RPS just adds inter-core IPIs.
#
#   on  [cpulist]  RPS: set each rx queue's rps_cpus to <cpulist> (default = NIC-local node).
#                  RFS: rps_sock_flow_entries=32768 + per-queue rps_flow_cnt=2048 (steer inner
#                       TCP socket delivery toward the app core).
#   off            clear rps_cpus on all queues and zero the RFS tables (the expected baseline).
set -euo pipefail
source "$(dirname "$0")/common.sh"
[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
MODE="${1:?usage: rps-setup.sh <on|off> [cpulist]}"
IF="$PRIMARY_IF"

# mask helper: build the hex rps_cpus mask (comma-grouped 32-bit words, high word first) for a
# cpulist. Kernel accepts a plain hex string without commas for <=32 cpus, but ENA boxes here
# have 192 cpus, so we must emit grouped words.
cpulist_to_mask() { # $1=cpulist -> hex mask like "ffffffff,00000000,..."
  local cl="$1" p c nbits=$(( $(nproc) ))
  # build a bit array
  local -a bits=(); for ((i=0;i<nbits;i++)); do bits[i]=0; done
  IFS=',' read -ra parts <<< "$cl"
  for p in "${parts[@]}"; do
    if [[ "$p" == *-* ]]; then for ((c=${p%-*};c<=${p#*-};c++)); do bits[c]=1; done
    else bits[p]=1; fi
  done
  # emit 32-bit words high->low
  local words=$(( (nbits + 31) / 32 )) w word out=""
  for (( w=words-1; w>=0; w-- )); do
    word=0
    for (( b=0; b<32; b++ )); do
      local idx=$(( w*32 + b )); [ "$idx" -lt "$nbits" ] && [ "${bits[idx]}" = 1 ] && word=$(( word | (1<<b) ))
    done
    out+=$(printf '%08x' "$word"); [ "$w" -gt 0 ] && out+=","
  done
  echo "$out"
}

queues=("/sys/class/net/$IF/queues"/rx-*)
if [ "$MODE" = on ]; then
  cl="${2:-}"
  if [ -z "$cl" ]; then
    nn=$(cat "/sys/class/net/$IF/device/numa_node" 2>/dev/null || echo 0); [ "$nn" = "-1" ] && nn=0
    cl=$(cat "/sys/devices/system/node/node${nn}/cpulist")
  fi
  mask=$(cpulist_to_mask "$cl")
  sysctl -qw net.core.rps_sock_flow_entries=32768 || true
  for q in "${queues[@]}"; do
    [ -e "$q/rps_cpus" ] && echo "$mask" > "$q/rps_cpus" 2>/dev/null || true
    [ -e "$q/rps_flow_cnt" ] && echo 2048 > "$q/rps_flow_cnt" 2>/dev/null || true
  done
  log "RPS+RFS ON: rps_cpus=$mask (cpulist $cl) on ${#queues[@]} queues; sock_flow_entries=32768"
else
  sysctl -qw net.core.rps_sock_flow_entries=0 || true
  for q in "${queues[@]}"; do
    [ -e "$q/rps_cpus" ] && echo 0 > "$q/rps_cpus" 2>/dev/null || true
    [ -e "$q/rps_flow_cnt" ] && echo 0 > "$q/rps_flow_cnt" 2>/dev/null || true
  done
  log "RPS+RFS OFF: cleared rps_cpus + rps_flow_cnt on ${#queues[@]} queues (baseline)"
fi