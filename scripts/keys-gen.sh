#!/usr/bin/env bash
# keys-gen.sh <role:a|b> <n_max> — generate per-tunnel keypairs, write pubkeys file to exchange.
# The role fixes the pubkeys filename (wg-pub-a.txt / wg-pub-b.txt) that mesh-up.sh expects.
# Back-compat: `keys-gen.sh <n_max>` still works, defaulting role to ROLE env or 'a'.
set -euo pipefail
source "$(dirname "$0")/common.sh"
need wg

# Accept either `<role> <n>` or legacy `<n>`.
if [ "${1:-}" = a ] || [ "${1:-}" = b ]; then
  ROLE="$1"; N="${2:?usage: keys-gen.sh <role:a|b> <n_max>}"
else
  ROLE="${ROLE:-a}"; N="${1:?usage: keys-gen.sh <role:a|b> <n_max>}"
fi
[ "$ROLE" = a ] || [ "$ROLE" = b ] || die "role must be 'a' or 'b' (got '$ROLE')"

KEYDIR="$(dirname "$0")/../keys"
mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
PUBFILE="$(dirname "$0")/../wg-pub-${ROLE}.txt"
: > "$PUBFILE"

for i in $(seq 0 $((N-1))); do
  if [ ! -f "$KEYDIR/priv$i" ]; then
    (umask 077; wg genkey | tee "$KEYDIR/priv$i" | wg pubkey > "$KEYDIR/pub$i")
    chmod 600 "$KEYDIR/priv$i"
  fi
  echo "$i $(cat "$KEYDIR/pub$i")" >> "$PUBFILE"
done

log "generated $N keypairs in $KEYDIR (role=$ROLE)"
log "send this to the peer:  $PUBFILE"
