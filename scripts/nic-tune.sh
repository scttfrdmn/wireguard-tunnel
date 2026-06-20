#!/usr/bin/env bash
# nic-tune.sh <on|off|probe> [iface] — toggle ENA offloads + ring depth to A/B the per-packet
# CPU cost (the lever the placement work never touched). Run with sudo on the node under test.
#
# The receive ceiling is per-packet CPU paid ~1.35M times/sec/direction. UDP-GSO/GSO/GRO batch
# that work so WireGuard crypts in bulk and the stack does fewer per-packet trips — raising the
# CPU *ceiling itself*, not just where it sits. This script flips those offloads + ring sizes so
# a sweep with `on` vs `off` measures the effect.
#
#   probe   print current offload + ring state (read-only)
#   on      enable gso/gro/tx-udp-segmentation/tx-gso-partial; set rx/tx rings to max
#   off     disable those offloads; restore rings to a conservative default (256)
#
# Idempotent; non-fatal if a feature is fixed/unsupported (logs "skip"). Affects only the data
# path, not correctness.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need ethtool
MODE="${1:?usage: nic-tune.sh <on|off|probe> [iface]}"
IF="${2:-$PRIMARY_IF}"

FEATURES="gso gro tx-udp-segmentation tx-gso-partial"

probe() {
  log "offload state for $IF:"
  ethtool -k "$IF" 2>/dev/null | grep -iE 'generic-segmentation|generic-receive|tx-udp-segmentation|tx-gso-partial' | sed 's/^/  /'
  log "ring state for $IF:"
  ethtool -g "$IF" 2>/dev/null | sed 's/^/  /'
}

set_feature() { # $1=feature $2=on|off
  if ethtool -K "$IF" "$1" "$2" >/dev/null 2>&1; then
    log "  $1 -> $2"
  else
    log "  $1: skip (fixed/unsupported)"
  fi
}

set_rings() { # $1=target (max|256)
  # current maxima
  local rxmax txmax
  rxmax=$(ethtool -g "$IF" 2>/dev/null | awk '/^Pre-set/{p=1} p&&/^RX:/{print $2; exit}')
  txmax=$(ethtool -g "$IF" 2>/dev/null | awk '/^Pre-set/{p=1} p&&/^TX:/{print $2; exit}')
  local rx tx
  if [ "$1" = max ]; then rx="$rxmax"; tx="$txmax"; else rx=256; tx=256; fi
  [ -n "$rx" ] && [ -n "$tx" ] || { log "  rings: skip (could not read maxima)"; return; }
  if ethtool -G "$IF" rx "$rx" tx "$tx" >/dev/null 2>&1; then
    log "  rings -> rx=$rx tx=$tx"
  else
    log "  rings: skip (set failed)"
  fi
}

case "$MODE" in
  probe) probe ;;
  on)
    log "nic-tune ON for $IF (offloads + max rings)"
    for f in $FEATURES; do set_feature "$f" on; done
    set_rings max ;;
  off)
    log "nic-tune OFF for $IF (offloads off + default rings)"
    for f in $FEATURES; do set_feature "$f" off; done
    set_rings 256 ;;
  *) die "unknown mode: $MODE (use on|off|probe)" ;;
esac
