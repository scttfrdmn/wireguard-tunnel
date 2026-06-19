#!/usr/bin/env bash
# enable-ena-express.sh <on|off> <eni_a> <eni_b>
# Toggles ENA Express + ENA Express UDP on both ENIs. Run where AWS creds exist.
set -euo pipefail
MODE="${1:?on|off}"; ENI_A="${2:?eni a}"; ENI_B="${3:?eni b}"
command -v aws >/dev/null || { echo "aws cli required" >&2; exit 1; }

if [ "$MODE" = on ]; then
  SRD='{"EnaSrdEnabled":true,"EnaSrdUdpSpecification":{"EnaSrdUdpEnabled":true}}'
else
  SRD='{"EnaSrdEnabled":false,"EnaSrdUdpSpecification":{"EnaSrdUdpEnabled":false}}'
fi

for eni in "$ENI_A" "$ENI_B"; do
  aws ec2 modify-network-interface-attribute \
    --network-interface-id "$eni" \
    --ena-srd-specification "$SRD"
  echo "set ENA Express=$MODE (UDP=$MODE) on $eni"
done

echo "NOTE: WireGuard outer traffic is UDP — ENA Express UDP must be ON for the tunnels to ride SRD."
echo "Confirm on the nodes after load:  ethtool -S <ena> | grep ena_srd"
