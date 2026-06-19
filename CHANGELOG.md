# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the major version is `0`, the public surface (script CLIs, `datapoint.json`
schema, report columns) may change between minor versions.

## [Unreleased]

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
- **Write-up scaffold** (KICKOFF #4): `wireguard-100gbps-writeup.md` — thesis, methodology,
  and result tables whose every measured cell is an explicit `_(not yet measured)_`
  placeholder for the live run to fill (nothing fabricated).
- `report/internal/datapoint`: shared package (types, `Load`, `Classify`, efficiency
  helpers) used by both `report` and `plot`, removing the duplicated parsing/classify logic.

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

## [0.1.0] - 2026-06-18

Initial import of the wg-saturate measurement harness (terraform + scripts + Go report),
as received. Baseline for all subsequent changes.

[Unreleased]: https://example.invalid/wg-saturate/compare/v0.1.0...HEAD
[0.1.0]: https://example.invalid/wg-saturate/releases/tag/v0.1.0
