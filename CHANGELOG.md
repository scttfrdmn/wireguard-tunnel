# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the major version is `0`, the public surface (script CLIs, `datapoint.json`
schema, report columns) may change between minor versions.

## [Unreleased]

### Added
- **Run 4 measured results — NUMA confound resolved + memory-BW + NVMe ratio.** With the IRQ
  fix (IRQs now NIC-local), the userspace A/B **flipped**: all-NIC-local (`NODE=1`) = **89.5 Gbps**
  vs unpinned 60 vs remote (`NODE=0`) 55 at N=32 — confirming "keep the whole receive pipeline
  on the NIC-local node" (run-3's "remote wins" was purely the NUMA-blind-IRQ artifact).
  Per-NUMA memory bandwidth measured: **local 381 / remote 69 GB/s (90% penalty)** — and the
  old all-core "5551 GB/s" was a cache-measurement bug (`measure-membw-numa.sh` fixed to use
  malloc + checksum + 6 GiB working set). NVMe near:far ratio: placement barely matters at the
  CPU-bound ~8 GB/s rate (near read 8.3 / far 7.5 / balanced 7.2). `detect-numa.sh` verdict
  corrected to recommend NIC-local co-location.
  - **Data note:** a merge bug lost most of run 4's raw `datapoint.json` before commit; the
    full experiment was **re-run as run 4b** and captured correctly (the 89.5 Gbps / 381-69
    GB/s / near-far figures above are the re-run's). Older draft numbers (run-3's confounded
    75.7, run-4's 74) remain in the historical bullets below as written at the time.

### Fixed
- **`measure-membw-numa.sh` cache/relocation bugs:** original static-BSS arrays overflowed the
  arm64 small-code-model relocation range at 6 GiB and the loop was const-folded → bogus
  300,000+ GB/s readings. Now heap-allocated with a runtime scalar + observed checksum.
- **`measure-nvme-tcp.sh` device discovery:** namespace block devices weren't symlinked under
  the subsystem sysfs dir on this kernel and appear asynchronously; now derives `/dev/nvme<inst>n*`
  from the subsystem instance and waits up to 10s for them to attach.

### Added (earlier in this Unreleased cycle)
- **`PIPELINING-DESIGN.md`** — design + experiment plan for placing the
  read→encrypt→network→decrypt→write stages across cores/NUMA. Covers 3 approaches
  (NUMA-confined per-flow, staged hand-off, RX-to-decrypt alignment), the corrected-confound
  experiment plan, and — per discussion — the NVMe near:far drive-ratio as a load-balance
  (node-1 bus contention vs far-side extra hop, offsetting on different resources).
- **`measure-membw-numa.sh`** — per-NUMA-node STREAM Triad (cpu-node × mem-node cross-product
  via numactl) → local vs remote memory bandwidth + remote-penalty %. Answers "what's the
  memory bandwidth from complex 0 vs 1, and the cost of the far-side hop." Surfaced in report.
- **`detect-nvme.sh` node-awareness** (`--node N`, `--with-node`) — tag/select instance-store
  drives by NUMA node, for the near:far ratio sweep.
- **`detect-numa.sh` PCIe probe** — counts how many instance NVMe share the NIC's PCIe
  node/bus (the NIC↔NVMe bus-contention concern); emits `nvme_sharing_nic_node`.
- **`node-setup.sh` NIC-local IRQ pinning** (`IRQ_CORES=` override) — fixes the NUMA-blind
  round-robin that pinned ENA RX IRQs to node 0 regardless of the NIC's node.
- **NUMA / device-affinity probe** (`detect-numa.sh`): reports NUMA node count, per-node
  cpulists, and NIC/NVMe → node from sysfs. Auto-run by `node-setup.sh` → `results/numa.json`;
  surfaced in the report's Ceilings. `pin-workers.sh` gained a `NODE=<n>` knob to confine
  workers to one node's cpus.
- **NUMA A/B measured result (run 3) + a confound it exposed.** `i8ge.48xlarge` = **2 NUMA
  nodes** (0:0-95, 1:96-191), ENA NIC on **node 1** (exposed in-guest, not hidden). A/B at
  N=32: userspace receivers on node 0 hit **75.7 Gbps** vs **56.3** on node 1. BUT
  `node-setup.sh` was pinning the ENA RX IRQs to cores 0–31 (all node 0, NIC-*remote*) — its
  round-robin was NUMA-blind. So the A/B actually measured "userspace co-located with the
  RX-softirq cores" (node 0, won) vs "userspace split from softirq across the complex" (node 1,
  lost) — **not** NIC-local vs NIC-remote. Honest lesson: co-locate userspace receive with the
  RX-softirq cores; the true NIC-local-everything layout is still untested.
- **Fixed `node-setup.sh` NUMA-blind IRQ pinning.** ENA RX IRQs now pin to the NIC-local
  node's cpulist by default (from sysfs), with an `IRQ_CORES=` override — so the next run can
  test the textbook layout (IRQs/NAPI/decrypt + userspace all on the NIC-local node).
- **Run 2 measured results (instrumented + pinning A/B).** Resolved the 0.2.0 open question:
  the receiver spends **~57 core-equivalents across ~31 cores** at N=32 (not one pegged core);
  hot threads are `napi/wgN-0` + `kworker/*-wg-crypt-wgN` + `ksoftirqd/*` + `iperf3`. Pinning
  the receive workers (`pin-workers.sh`) lifted **N=32 from 60 → 77 Gbps (+29%)** at the same
  CPU cost (efficiency 1.04 → 1.35 Gbps/core-equiv). Write-up, report, CSV, and SVGs updated;
  `results/` now holds placement / placement_pinned / ena_express datapoints from run 2.
- **CPU instrumentation** to answer "how many cores decrypt, and which thread pegs the
  bottleneck core" (the open question from the 0.2.0 run):
  - `collect.sh` now emits a per-core utilisation histogram (`util_band_*`), **busy
    core-equivalents** (`busy_core_equiv` = sum of (100-idle)/100), `cores_gt50`/`cores_gt90`,
    and a **`top_threads`** sample from concurrent `pidstat -t` (names ksoftirqd / wg crypto
    workqueue / iperf3 / fio by %CPU during the window).
  - `report` shows `core-equiv (A/B)`, `Gbps/core` (now off core-equivalents, not the noisy
    >90%-count metric), and a new **Hot threads** table; CSV gains the matching columns.
  - `report/internal/datapoint`: `BusyCoreEquiv()` / `GbpsPerCoreEquiv()` helpers (fall back
    to the old metric for pre-instrumentation datapoints, which stay parseable).
- **`pin-workers.sh`**: optional CPU-affinity knob pinning each tunnel's iperf3 worker to a
  distinct core, to A/B-test how much of the ~60 Gbps ceiling is scheduler float vs raw
  per-core ChaCha20 throughput.

### Changed
- Write-up: added a "Follow-up instrumentation" section documenting the above and what the
  next run will resolve.

## [0.2.0] - 2026-06-19

First measured run. Harness completed, hardened on real hardware, and exercised end-to-end on
2× `i8ge.48xlarge`; the write-up now carries measured numbers (see below).

### Added
- Project context (`CLAUDE.md`) and append-only `WORKLOG.md`.
- `LICENSE` (MIT, © 2026 Scott Friedman), `.gitignore`, `VERSION`, this `CHANGELOG.md`,
  `.shellcheckrc` (resolves `source` to SCRIPTDIR so the harness is SC1091-clean).
- `report`: optional CSV output via a 2nd positional arg
  (`go run . <results-dir> [out.csv]`); the CSV carries the per-node allowance-counter
  deltas so attribution is reproducible from the CSV alone.
- `keys-gen.sh`: explicit `<role:a|b>` argument that fixes the `wg-pub-<role>.txt` filename
  `mesh-up.sh` expects (legacy `<n_max>`-only form still works).
- `sweep.sh`: live-vs-recorded `wg_mtu` guard, and documentation of the MTU-1500-vs-jumbo
  workflow (re-mesh at `WG_MTU` and label the run).
- **Real NVMe→NVMe over nvme-tcp** (KICKOFF #2): `nvme-target-up.sh` / `nvme-target-down.sh`
  (B-side kernel nvmet over nvme-tcp, one port per tunnel against one subsystem) and
  `measure-nvme-tcp.sh` (A-side: connect N native-multipath paths, round-robin iopolicy,
  fio read+write sweep, both-node attribution, emits the same `datapoint.json` schema as the
  iperf sweep). `report` gained `nvme_GBps` + `rw` columns to surface these.
- **Plots** (KICKOFF #3): `report/plot` — a stdlib-only Go SVG plotter emitting
  `throughput.svg` (Gbps vs N, per mode, with the ~180 Gbps wall) and `efficiency.svg`
  (Gbps/busy-core vs N).
- **Write-up** (KICKOFF #4): `wireguard-100gbps-writeup.md` — now filled with **measured
  results** from the 2026-06-19 live run (2× `i8ge.48xlarge` Spot, us-west-2d), plus
  `report.md`, `report.csv`, `throughput.svg`, `efficiency.svg`, and the full `results/` tree.
  Headline: near-linear scaling 1→8 tunnels to ~55 Gbps, plateau at ~57–60 Gbps bound by
  **receive-side CPU/crypto** (no AWS allowance fired; raw ENA baseline was 208 Gbps). The
  100 Gbps target was not reached on this config — reported honestly with full attribution.
- `report/internal/datapoint`: shared package (types, `Load`, `Classify`, efficiency
  helpers) used by both `report` and `plot`, removing the duplicated parsing/classify logic.
- **Spot support** (KICKOFF "prefer Spot"): `terraform` `use_spot` (default `true`),
  `max_spot_price`, and `root_volume_size` variables; a conditional `instance_market_options`
  spot block (one-time, terminate-on-interruption); and a `pricing_mode` output.
- **`COSTS.md`**: written cost model grounded in live AWS prices fetched 2026-06-18 —
  On-Demand $22.78/instance-hr ($45.56/hr for the rig) vs Spot $2.28–8.40/instance-hr —
  with per-session scenarios, EBS/transfer notes, and re-check commands.

### Changed
- Normalized repo layout: promoted the structured `terraform/ scripts/ report/` tree to
  the repo root and removed the byte-identical loose duplicate files; archived the original
  tarball under `.archive/`.
- `collect.sh` is now self-contained (inlines the few helpers it needs) so it works when
  piped to node B over SSH; it no longer `source`s `common.sh`.
- License is **MIT** (per project owner), superseding KICKOFF.md's "Apache-2.0" note.

### Fixed
- Remote (node B) attribution: `sweep.sh` shipped `collect.sh` to B via `ssh ... bash -s`,
  but `collect.sh` sourced `common.sh` (absent on B) — `node_b.json` came back empty,
  silently dropping half the both-node counter attribution. Now collected on both sides.
- `sweep.sh` idempotency: stale `flow*.json` / `node_*.json` from a prior larger-N run are
  cleared before each datapoint, so a re-run at smaller N can't inflate the aggregate Gbps.
- `keys-gen.sh` wrote `wg-pub-<hostname>.txt` instead of the `wg-pub-a/b.txt` the rest of
  the flow expects; tightened key file permissions (`umask 077`, `keys/` 700).
- Cleared shellcheck findings (`SC2086` array-ified fio args in `measure-nvme.sh`,
  `SC2013` while-read loop in `node-setup.sh`); `go vet`/`gofmt`/`terraform fmt` clean.

#### Fixed during the live run (real-hardware bugs)
- **`collect.sh` aborted before writing output.** A `read -r top_share < <(awk … printf)`
  with no trailing newline returned non-zero at EOF and, under `set -e`, killed the script —
  so *every* `node_a.json`/`node_b.json` was empty and the sweep died at N=1. Switched to
  command substitution. (This was the single highest-impact bug — it silently voided all
  attribution.)
- **WireGuard tunnels had no inner route.** `mesh-up.sh` assigned `/31` addresses, but
  `10.200.i.1/31` spans only `.0–.1`, leaving the `.2` peer off-subnet. Handshakes completed
  but pings failed. Changed to `/30`.
- **`node-setup.sh` install aborted** on Ubuntu 24.04 (no `awscli` apt package; the nodes
  don't need it). Removed it; ENA Express is toggled from the operator host.
- **`nvme-tcp`/`nvmet-tcp` modules absent** on the AWS kernel base image — they live in
  `linux-modules-extra-$(uname -r)`. `node-setup.sh` now installs it and `modprobe`s both.
- **ENA counters differ on the i8ge driver:** no flat `tx_packets`, only per-queue
  `queue_<n>_tx_cnt`. Added an `ena_pkts` helper (flat counter if present, else sum
  per-queue) in `common.sh` and `collect.sh`; `tx_pps` is correct again.
- **`measure-nvme-tcp.sh` found no multipath devices** — `nvme list -o json` on this
  nvme-cli version doesn't expose `SubsystemNQN` at top level. Now reads namespace block
  devices from `/sys/class/nvme-subsystem/*` by matching `subsysnqn`.
- **`server-up.sh` iperf3 servers didn't survive the launching SSH session** (`-D` alone is
  unreliable); switched to `setsid` with detached fds. `common.sh` also reclaims a
  root-owned `results/` (left by a prior sudo run) so non-sudo measure scripts can write.

## [0.1.0] - 2026-06-18

Initial import of the wg-saturate measurement harness (terraform + scripts + Go report),
as received. Baseline for all subsequent changes.

[Unreleased]: https://example.invalid/wg-saturate/compare/v0.2.0...HEAD
[0.2.0]: https://example.invalid/wg-saturate/compare/v0.1.0...v0.2.0
[0.1.0]: https://example.invalid/wg-saturate/releases/tag/v0.1.0
