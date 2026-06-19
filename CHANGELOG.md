# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the major version is `0`, the public surface (script CLIs, `datapoint.json`
schema, report columns) may change between minor versions.

## [Unreleased]

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
