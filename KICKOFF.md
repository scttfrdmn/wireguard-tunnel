# KICKOFF — wg-saturate

Paste this as your first message in a Claude Code session at the repo root (or keep it as
`KICKOFF.md` and point the agent at it). It is the mandate; you will maintain `CLAUDE.md`
as living project context.

---

## Mission

Build and run a measurement harness that proves a **multi-tunnel WireGuard fabric scales
to ≥100 Gbps of encrypted throughput between two `i8ge.48xlarge` nodes, then past it to the
instance's ~180 Gbps network wall**, carrying a real NVMe-to-NVMe workload. The headline
deliverable is not a peak number — it is a **curve with every knee attributed to a measured
cause** (which AWS allowance or which CPU stage bound it), with *nothing assumed*.

The thesis: a single WireGuard tunnel can't reach 100 Gbps because every bottleneck is
keyed on the flow. N tunnels on N ports relieve all of them in lockstep, so aggregate
throughput scales near-linearly with tunnel count until a global ceiling binds.

## Ground truth — verified June 2026, do NOT re-derive from training data

If you believe any of these is wrong, **web-verify against current AWS docs before
changing it**; do not silently "correct" them from stale priors. The 180 Gbps figure in
particular is right — a common third-party number says 300, which is wrong.

- **Rig:** 2 × `i8ge.48xlarge` — Graviton4, 192 vCPU (1 thread/core), 1536 GiB DDR5-5600,
  **180 Gbps** VPC bandwidth, single network card, local Gen-3 Nitro NVMe instance store.
- **i8ge gating:** ENA Express only on `12xlarge`+; EFA only on `48xlarge`; **no Instance
  Bandwidth Configuration** on the i-series (don't try to rebalance EBS↔VPC). The EBS lane
  (60 Gbps) is provisioned separately from VPC networking — they don't compete.
- **Per-flow cap:** a single 5-tuple is limited to **5 Gbps** baseline / **10 Gbps** in a
  cluster placement group / **25 Gbps** with ENA Express UDP. A WireGuard interface is one
  UDP 5-tuple = one flow, so one tunnel hits one cap.
- **Three serialization points, all per-tunnel:** (1) the per-flow cap, (2) single RX queue
  (one 5-tuple RSS-hashes to one ENA queue → one core's softirq), (3) per-peer crypto
  ordering. N tunnels = N flows = N queues = N crypto pipelines.
- **Crypto is ChaCha20-Poly1305 only.** AES-NI / Graviton AES offload is irrelevant. Per-
  core throughput is ~2–4 Gbps (assume; **measure it** — it's a primary output, not a
  constant). Use in-tree kernel WireGuard on a 6.x kernel, not `wireguard-go`.
- **Jumbo is mandatory.** 9001 MTU on the ENA, ~8921 on wg. PPS is the real limiter; jumbo
  cuts it ~6×.
- **Distribution control surface** (the axis is *who reassembles*):
  - per-flow, zero reordering: ECMP (`fib_multipath_hash_policy=1`) — needs many flows.
  - sub-flow, layer reassembles: **MPTCP** and **NVMe/TCP native multipath** (round-robin /
    queue-depth) — reorder-safe, the workhorses here.
  - per-packet, you own reordering: bonding `balance-rr` or an **eBPF flowlet steerer**.
  - ENA Express SRD reorders *within* one outer flow's path-spray; it does **not**
    reassemble across your N tunnels.
- **Placement:** cluster placement group, same AZ. **Terminal knee** is expected at
  ~180 Gbps, attributed to `bw_*_allowance_exceeded` — i.e. the Nitro allowance, not WG.

## Repo

If the harness is already present, **audit, complete, and harden it**; do not duplicate.
If absent, build it to this layout:

```
terraform/   two i8ge.48xlarge, cluster placement group, same AZ, jumbo subnet, SG
scripts/     composable measurement tools (one job each, idempotent):
             node-setup, keys-gen, mesh-up/down, enable-ena-express, detect-nvme,
             measure-baseline, measure-nvme, measure-membw, collect, server-up, sweep
report/      Go: per-datapoint JSON -> attribution table (md + csv)
```

Existing components already build (the Go report compiles and classifies datapoints).
Verify each script with `shellcheck`, fix what fails, and make the whole flow runnable.

### Gaps to close (priority order)

1. **Make the core matrix run-ready and idempotent.** Every `measure-*` and the `sweep`
   must run clean on the real nodes, re-runnable without manual cleanup.
2. **Real NVMe→NVMe transfer path** over `nvme-tcp` with native multipath (one connection
   per tunnel or ECMP-spread), reorder-safe at command granularity. Measure end-to-end
   GB/s and confirm it tracks the synthetic sweep.
3. **Plots** from `results/`: aggregate Gbps vs N (per mode), Gbps/busy-core vs N. Keep
   deps minimal; a small Go or `uv`-managed Python plotter is fine.
4. **Fold measured numbers back into `wireguard-100gbps-writeup.md`** — replace every
   "assume/measure" row with what the rig produced. (This closes the loop.)
5. **Stretch / Phase 2:** an eBPF (`tc-bpf` egress) flowlet steerer for the single-flow
   case, and an MPTCP variant of the sweep. Build only after 1–4 are solid.

## Definition of done

- [ ] `terraform apply` stands up the rig; `destroy` leaves nothing behind.
- [ ] One command per ceiling (baseline, NVMe r/w, memory BW) emits a JSON number.
- [ ] `sweep.sh` produces `results/<mode>/N<n>/datapoint.json` for both `placement` and
      `ena_express`, with both-node attribution counters captured.
- [ ] `report` emits a table where **every** row's binding limit is set from measured
      counter deltas, plus per-mode peak and knee.
- [ ] ≥100 Gbps demonstrated; the run is pushed until a measured global ceiling binds.
- [ ] ENA Express runs confirm SRD is actually carrying packets (`ena_srd_*` > 0).
- [ ] The write-up's assumption rows are replaced with measured values.
- [ ] `shellcheck` clean; Go builds and `go vet` passes.

## Methodology rules (non-negotiable)

- **Never fabricate a measurement.** If a number requires live hardware you haven't run,
  leave it blank and say so. Do not fill in plausible values.
- Baseline (no WireGuard) first — it's the ceiling everything is measured against.
- Attribute knees by **counter deltas on both nodes**, not by inference.
- The sender encrypts, the receiver decrypts — collect on **both** sides.
- Memory bandwidth is measured as the achievable **ceiling** (STREAM Triad); in-flight
  per-run memory traffic is *inferred* against it (guest PMU won't expose live MC
  counters). State this honestly; don't present the inference as a direct read.

## Engineering conventions

- **Go-first** for tools that benefit from it; Python only when forced, managed with `uv`.
  Bash for system-glue scripts. Small, composable, Unix-named utilities.
- Apache-2.0. No secrets in the repo. Scripts idempotent and safe to re-run.
- Hardware-first: let the measured numbers drive conclusions, not the other way around.

## Cost & safety guardrails

- Two `i8ge.48xlarge` on-demand is **hundreds of USD/hour**. **Never** run
  `terraform apply`, launch instances, or otherwise spend money without an explicit
  "go ahead, spend" from me in this session. Estimate the cost before proposing any spend.
- Prefer Spot. Always `terraform destroy` at the end of a session. Surface anything that
  needs live AWS or money as a blocking question rather than proceeding.
- Validate everything you can offline (shellcheck, go build, dry-runs) before asking to run.

## How to proceed

1. Read the repo and this file. Produce a short **plan + gap analysis** against the
   Definition of done. Show it before doing work.
2. Write/maintain **`CLAUDE.md`** (project context: the ground-truth facts above, the
   run order, the conventions) and a **`WORKLOG.md`** you append to as you go.
3. Work in feature branches; keep commits small and labeled by component.
4. Do offline hardening first (shellcheck, go build/vet, idempotency). **Do not touch AWS
   or spend money** until I say so.

**Your first task:** read the repo, then output the plan, the gap analysis, and a draft
`CLAUDE.md`. Stop there and wait for my go-ahead before anything that costs money.
