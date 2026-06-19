#!/usr/bin/env bash
# measure-nvme.sh — striped sequential read + write ceiling across instance-store NVMe.
# WARNING: writes directly to raw instance-store devices (ephemeral scratch).
set -euo pipefail
source "$(dirname "$0")/common.sh"
need fio; need jq
DEVS=$("$(dirname "$0")/detect-nvme.sh")
[ -n "$DEVS" ] || die "no instance-store NVMe devices detected"
ND=$(echo "$DEVS" | wc -l)
log "found $ND instance-store NVMe devices:"; echo "$DEVS" >&2

# one fio job per device (array avoids word-splitting pitfalls)
fioargs=(); for d in $DEVS; do fioargs+=("--name=j_$(basename "$d")" "--filename=$d"); done

run() { # $1=rw
  fio --rw="$1" --bs=1M --iodepth=32 --numjobs=1 --direct=1 --ioengine=libaio \
      --time_based --runtime=20 --group_reporting --output-format=json "${fioargs[@]}" 2>/dev/null
}

log "sequential READ ceiling…"
# shellcheck disable=SC2162  # 'read' here is an arg to the run() function, not the builtin
rd=$(run read  | jq '[.jobs[].read.bw_bytes]  | add/1e9')
log "sequential WRITE ceiling…  (the sink-side limiter)"
wr=$(run write | jq '[.jobs[].write.bw_bytes] | add/1e9')

printf '{"test":"nvme","devices":%s,"read_GBps":%s,"write_GBps":%s}\n' "$ND" "$rd" "$wr" \
  | tee "$RESULTS_DIR/nvme.json"
log "read=${rd} GB/s  write=${wr} GB/s  (write usually binds before read)"
