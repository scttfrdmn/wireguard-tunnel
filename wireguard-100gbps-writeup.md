# Scaling WireGuard past 100 Gbps with a multi-tunnel fabric

> **Status: SCAFFOLD — no live run yet.** Every cell marked `_(not yet measured)_` is a
> placeholder to be filled from a real run via `report/`. Per the project's methodology rule,
> **nothing here is fabricated**: if a number isn't measured, it stays blank. Once
> `sweep.sh` / `measure-*.sh` have run, `report` emits the values that replace these rows.
>
> How to fill this in:
> ```bash
> cd report && go run . ../results ../report.csv > ../report.md   # table + CSV
> go run ./plot ../results ../                                    # throughput.svg, efficiency.svg
> # then transcribe report.md's numbers into the tables below (or regenerate this doc).
> ```

## Thesis

A single WireGuard tunnel cannot reach 100 Gbps on an `i8ge.48xlarge`, because every
relevant bottleneck is keyed on the **flow** — and a WireGuard interface is exactly one
UDP 5-tuple, i.e. one flow:

1. **Per-flow bandwidth cap** — one 5-tuple is limited (5 Gbps baseline / 10 Gbps in a
   cluster placement group / 25 Gbps with ENA Express UDP).
2. **Single RX queue** — one 5-tuple RSS-hashes to one ENA queue → one core's softirq.
3. **Per-peer crypto ordering** — one tunnel's ChaCha20-Poly1305 is one serial pipeline.

Running **N tunnels on N UDP ports** turns one flow into N flows = N RX queues = N crypto
pipelines, relieving all three in lockstep. So aggregate throughput should scale
near-linearly with N until a **global** ceiling binds — expected to be the instance's
~180 Gbps VPC bandwidth allowance, *not* WireGuard itself.

This document reports the measured curve and attributes **every knee to a measured cause**
(an AWS allowance counter delta, or a CPU/queue saturation signal) captured on **both**
nodes during each load window.

## Rig

- 2 × `i8ge.48xlarge` — Graviton4, 192 vCPU, 1536 GiB DDR5-5600, **180 Gbps** VPC bandwidth,
  single network card, local Gen-3 Nitro NVMe instance store.
- Cluster placement group, same AZ. Ubuntu 24.04 arm64, in-tree kernel WireGuard (6.x).
- Jumbo frames: 9001 MTU on the ENA, 8921 on the wg interfaces.
- Crypto: ChaCha20-Poly1305 (AES offload is irrelevant to WireGuard).

## Measured ceilings (baselines)

| Ceiling | Tool | Measured | Notes |
|---|---|---|---|
| Raw ENA throughput (no WG, many flows) | `measure-baseline.sh` | _(not yet measured)_ Gbps | the wall everything else is compared to |
| Raw ENA packet rate | `measure-baseline.sh` | _(not yet measured)_ pps | at jumbo MTU |
| NVMe striped sequential **read** | `measure-nvme.sh` | _(not yet measured)_ GB/s | instance-store ceiling |
| NVMe striped sequential **write** | `measure-nvme.sh` | _(not yet measured)_ GB/s | usually the sink-side limiter |
| Memory bandwidth (STREAM Triad) | `measure-membw.sh` | _(not yet measured)_ GB/s | achievable ceiling; per-run MC traffic is *inferred* against it, not read live |
| Per-core ChaCha20 throughput | derived in `report` | _(not yet measured)_ Gbps/core | from Gbps ÷ busy cores at the linear-region datapoints |

## The sweep — aggregate Gbps vs tunnel count

Mode `placement` = cluster placement group (10 Gbps/flow). Mode `ena_express` = ENA Express
UDP on (25 Gbps/flow, SRD active). Both run `N = 1, 2, 4, 8, 12, 16, 24, 32`.

### `placement`

| N | Gbps | Gbps/busy-core | sender PPS | busy cores (A/B) | binding limit (measured) |
|---|------|----------------|-----------|------------------|--------------------------|
| 1 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 2 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 4 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 8 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 12 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 16 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 24 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 32 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |

_(nm) = not yet measured._

### `ena_express`

| N | Gbps | Gbps/busy-core | sender PPS | busy cores (A/B) | SRD tx pkts | binding limit (measured) |
|---|------|----------------|-----------|------------------|-------------|--------------------------|
| 1 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 2 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 4 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 8 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 12 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 16 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 24 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| 32 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |

> SRD confirmation: a run is only a valid `ena_express` datapoint if `ena_srd_tx_pkts > 0`
> (otherwise the traffic wasn't actually riding SRD and the row is mislabeled).

### Jumbo leverage (PPS)

| MTU | peak Gbps | sender PPS at peak | binding limit |
|---|---|---|---|
| 1500 | _(not yet measured)_ | _(not yet measured)_ | _(not yet measured)_ |
| 8921 (jumbo) | _(not yet measured)_ | _(not yet measured)_ | _(not yet measured)_ |

## Real workload — NVMe→NVMe over nvme-tcp (native multipath)

End-to-end transfer driven by `measure-nvme-tcp.sh`: one nvme-tcp path per tunnel against a
single target subsystem, round-robin iopolicy, so each command rides a distinct flow. This
confirms the synthetic iperf sweep translates into real storage throughput.

| mode | N | NVMe GB/s | equiv. Gbps | Gbps/busy-core | binding limit (measured) |
|---|---|---|---|---|---|
| nvme_tcp write | 8 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| nvme_tcp write | 16 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| nvme_tcp write | 32 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| nvme_tcp read | 8 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| nvme_tcp read | 16 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |
| nvme_tcp read | 32 | _(nm)_ | _(nm)_ | _(nm)_ | _(nm)_ |

Expected sink-side limiter: the NVMe **write** ceiling from the baselines table above (the
storage, not the network), unless the network wall or memory bandwidth binds first.

## Plots

Generated by `report/plot` from `results/` (committed alongside this doc once a run exists):

- `throughput.svg` — aggregate Gbps vs N, per mode, with the ~180 Gbps wall drawn.
- `efficiency.svg` — Gbps per busy core vs N (per-core crypto efficiency).

## Findings

_(To be written from the measured curve. Expected, pending data: near-linear scaling through
the mid-range; the placement-group per-flow cap visible at N=1; a terminal knee near
~180 Gbps attributed to `bw_*_allowance_exceeded` on both nodes; ENA Express raising the
N=1 point and the early slope. **None of this is asserted until measured.**)_

## Reproducing

See `README.md` for the full run order and `CLAUDE.md` for the ground-truth facts and
guardrails. The harness is idempotent and safe to re-run; results land in `results/` and are
turned into this write-up's tables by `report/`.
