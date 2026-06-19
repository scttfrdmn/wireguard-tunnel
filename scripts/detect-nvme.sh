#!/usr/bin/env bash
# detect-nvme.sh — print instance-store NVMe device paths (one per line)
set -euo pipefail
need() { command -v "$1" >/dev/null || { echo "need $1" >&2; exit 1; }; }
need nvme
# Amazon instance store reports model "Amazon EC2 NVMe Instance Storage"; EBS reports "Amazon Elastic Block Store"
nvme list -o json 2>/dev/null \
  | jq -r '.Devices[] | select(.ModelNumber | test("Instance Storage")) | .DevicePath' 2>/dev/null \
  || lsblk -dn -o NAME,MODEL | awk '/Instance Storage/{print "/dev/"$1}'
