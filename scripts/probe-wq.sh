#!/usr/bin/env bash
# probe-wq.sh — report whether WireGuard's crypt workqueue is steerable from sysfs.
#
# In-tree WireGuard creates a per-device "wg-crypt-<dev>" workqueue for encrypt/decrypt.
# Whether we can pin it depends on its type:
#   - WQ_UNBOUND  -> /sys/devices/virtual/workqueue/wg-crypt-<dev>/cpumask is WRITABLE (steerable)
#   - per-CPU (WQ_CPU_INTENSIVE) -> cpumask absent/read-only; placement follows the receiving CPU
#     (so it is governed by ENA IRQ affinity, which node-setup.sh already pins NIC-local)
# Kernel 6.5+ also exposes per-wq `affinity_scope` (cache|numa|cpu|system) which IS often
# writable even for non-unbound pools — set to `numa` to keep worker pools node-local.
#
# Read-only probe; prints findings + a one-line verdict for set-crypt-affinity.sh to act on.
set -euo pipefail
WQ_ROOT=/sys/devices/virtual/workqueue

dev="${1:-}"   # optional wg device, e.g. wg0; else auto-detect first wg-crypt-*
if [ -z "$dev" ]; then
  first=$(find "$WQ_ROOT" -maxdepth 1 -name 'wg-crypt-*' 2>/dev/null | head -1)
  [ -n "$first" ] || { echo "no wg-crypt-* workqueue found (is a wg mesh up?)"; exit 0; }
  wq="$first"
else
  wq="$WQ_ROOT/wg-crypt-$dev"
fi
[ -d "$wq" ] || { echo "workqueue dir not found: $wq"; exit 0; }

echo "workqueue: $wq"
find "$wq" -maxdepth 1 -mindepth 1 -printf '  attr: %f\n' 2>/dev/null | sort

cpumask_writable=no; scope_writable=no
if [ -w "$wq/cpumask" ]; then cpumask_writable=yes; fi
if [ -e "$wq/affinity_scope" ] && [ -w "$wq/affinity_scope" ]; then scope_writable=yes; fi
echo "cpumask:        $(cat "$wq/cpumask" 2>/dev/null || echo '(none)')  [writable=$cpumask_writable]"
echo "affinity_scope: $(cat "$wq/affinity_scope" 2>/dev/null || echo '(none)')  [writable=$scope_writable]"
echo "max_active:     $(cat "$wq/max_active" 2>/dev/null || echo '(none)')"

if [ "$cpumask_writable" = yes ]; then
  echo "VERDICT: cpumask writable -> WQ_UNBOUND, steerable via set-crypt-affinity.sh cpumask"
elif [ "$scope_writable" = yes ]; then
  echo "VERDICT: affinity_scope writable -> set it to 'numa' to keep crypt pools node-local"
else
  echo "VERDICT: not sysfs-steerable -> per-CPU WQ; placement follows ENA IRQ affinity (already NIC-local)"
fi
