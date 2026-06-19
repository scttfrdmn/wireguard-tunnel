# CLAUDE.md — wg-saturate project context

Living context for this repo. Source of intent: `KICKOFF.md` (the mandate).
Append progress to `WORKLOG.md`. Keep this file current as facts are measured.

## Mission

Build and run a measurement harness proving a **multi-tunnel WireGuard fabric** scales to
**≥100 Gbps of encrypted throughput** between two `i8ge.48xlarge` nodes, then past it to the
instance's **~180 Gbps network wall**, carrying a real NVMe→NVMe workload. The deliverable
is a **throughput-vs-tunnel-count curve where every knee is attributed to a measured cause**
(a specific AWS allowance counter or a specific CPU stage) — never inferred, never assumed.

**Thesis:** a single WireGuard tunnel can't reach 100 Gbps because every bottleneck is keyed
on the *flow* (a WG iface = one UDP 5-tuple = one flow). N tunnels on N ports = N flows =
N RX queues = N crypto pipelines, relieving all serialization points in lockstep, so
aggregate throughput scales near-linearly with N until a global ceiling binds.

## Ground truth — verified June 2026, do NOT re-derive from training data

Web-verify against current AWS docs before changing any of these; do not "correct" from
stale priors. The 180 Gbps figure is right (a common third-party number says 300 — wrong).

- **Rig:** 2 × `i8ge.48xlarge` — Graviton4, 192 vCPU (1 thread/core), 1536 GiB DDR5-5600,
  **180 Gbps** VPC bandwidth, single network card, local Gen-3 Nitro NVMe instance store.
- **i8ge gating:** ENA Express only on `12xlarge`+; EFA only on `48xlarge`; **no Instance
  Bandwidth Configuration** on the i-series (don't rebalance EBS↔VPC). EBS lane (60 Gbps) is
  provisioned separately from VPC networking — they don't compete.
- **Per-flow cap:** one 5-tuple is capped at **5 Gbps** baseline / **10 Gbps** in a cluster
  placement group / **25 Gbps** with ENA Express UDP. One WG iface = one 5-tuple = one flow.
- **Three serialization points, all per-tunnel:** (1) per-flow cap, (2) single RX queue (one
  5-tuple RSS-hashes to one ENA queue → one core's softirq), (3) per-peer crypto ordering.
- **Crypto is ChaCha20-Poly1305 only.** AES-NI / Graviton AES offload is irrelevant.
  Per-core throughput ~2–4 Gbps — **a primary measured output, not a constant**. Use in-tree
  kernel WireGuard on a 6.x kernel, not `wireguard-go`.
- **Jumbo is mandatory.** 9001 MTU on ENA, 8921 on wg. PPS is the real limiter; jumbo ~6×.
- **Distribution control surface** (axis = *who reassembles*):
  - per-flow, zero reorder: ECMP (`fib_multipath_hash_policy=1`) — needs many flows.
  - sub-flow, layer reassembles: **MPTCP** and **NVMe/TCP native multipath** — the workhorses.
  - per-packet, you own reordering: bonding `balance-rr` or an eBPF flowlet steerer.
  - ENA Express SRD reorders *within* one outer flow's path-spray; it does **not** reassemble
    across the N tunnels.
- **Placement:** cluster placement group, same AZ. **Terminal knee** expected ~180 Gbps,
  attributed to `bw_*_allowance_exceeded` (the Nitro allowance, not WireGuard).

## Repo layout

```
terraform/   two i8ge.48xlarge, cluster placement group, same AZ, jumbo subnet, SG
scripts/     composable measurement tools (one job each, idempotent):
             common.sh (shared helpers), node-setup, keys-gen, mesh-up/down,
             enable-ena-express, detect-nvme, measure-baseline, measure-nvme,
             measure-membw, collect, server-up, sweep,
             nvme-target-up/down, measure-nvme-tcp (real NVMe→NVMe over nvme-tcp)
report/      Go: per-datapoint JSON -> attribution table (md + csv)
report/plot/ Go SVG plotter -> throughput.svg + efficiency.svg
report/internal/datapoint/  shared types, Load, Classify, efficiency helpers
results/     (generated) <mode>/N<n>/datapoint.json + baseline/nvme/membw.json
wireguard-100gbps-writeup.md  the deliverable; measured rows folded in from report/
```

## Run order (operator)

```bash
# 0. Infra  -- COSTS MONEY, requires explicit go-ahead
cd terraform && terraform init && terraform apply   # note A/B IPs + ENI ids

# 1. On BOTH nodes
sudo ./scripts/node-setup.sh                         # kernel, pkgs, tuning, jumbo, IRQ
./scripts/keys-gen.sh <N_MAX>                        # per-tunnel keys + pubkeys file
#   exchange the two wg-pub-*.txt files (scp each way)
./scripts/mesh-up.sh a <N_MAX> <B_priv_ip> wg-pub-b.txt   # on A
./scripts/mesh-up.sh b <N_MAX> <A_priv_ip> wg-pub-a.txt   # on B

# 2. Ceilings (baseline on A; nvme/membw on both)
./scripts/measure-baseline.sh <B_priv_ip>
./scripts/measure-nvme.sh
./scripts/measure-membw.sh

# 3. ENA Express toggle (host with AWS creds; both ENIs)
./scripts/enable-ena-express.sh on <ENI_A> <ENI_B>   # or 'off'

# 4. The sweep (B runs server-up first; sweep drives A)
./scripts/server-up.sh <N_MAX>                       # on B
REMOTE_HOST=<B_priv_ip> ./scripts/sweep.sh placement # re-run as 'ena_express'

# 5. Report
cd report && go run . ../results > ../report.md
```

## Methodology rules (non-negotiable)

- **Never fabricate a measurement.** If a number needs live hardware not yet run, leave it
  blank and say so. No plausible fillers.
- Baseline (no WireGuard) first — the ceiling everything is measured against.
- Attribute knees by **counter deltas on both nodes**, not by inference.
- Sender encrypts, receiver decrypts — collect on **both** sides.
- Memory bandwidth = achievable **ceiling** (STREAM Triad); per-run memory traffic is
  *inferred* against it (guest PMU won't expose live MC counters). State this honestly.

## Engineering conventions

- **Go-first** for tools that benefit; Python only when forced, via `uv`. Bash for glue.
  Small, composable, Unix-named utilities.
- **License: MIT** (© 2026 Scott Friedman), per project owner — this supersedes KICKOFF.md's
  "Apache-2.0" note. No secrets in the repo. Scripts idempotent and safe to re-run.
- **Versioning: SemVer 2.0.0**; changes tracked in `CHANGELOG.md` (Keep a Changelog format).
  Current version in `VERSION` (0.1.0). While major is 0, the public surface (script CLIs,
  `datapoint.json` schema, report columns) may shift between minor versions.
- Hardware-first: measured numbers drive conclusions, not the reverse.

## Cost & safety guardrails (HARD)

- Two `i8ge.48xlarge` on-demand is **hundreds of USD/hour**. **NEVER** `terraform apply`,
  launch instances, enable ENA Express via AWS API, or otherwise spend money without an
  explicit "go ahead, spend" from the user in the current session. Estimate cost first.
- Prefer Spot. Always `terraform destroy` at session end. Surface anything needing live AWS
  or money as a blocking question rather than proceeding.
- Validate everything offline first (shellcheck, go build/vet, terraform validate, dry-runs).

## Offline validation status (2026-06-18, after Phase 0+1+2)

- `terraform validate`: PASS. `terraform fmt -check`: clean.
- `go build ./...`/`go vet ./...`/`gofmt -l`: clean across `report`, `report/plot`,
  `report/internal/datapoint`. `report` + `plot` exercised against multi-mode synthetic
  fixtures — markdown/CSV, nvme-tcp columns, both-node classification, and well-formed SVG
  (xmllint) all verified.
- `shellcheck -x scripts/*.sh`: CLEAN (`.shellcheckrc` sets source-path=SCRIPTDIR).
  `bash -n` on all scripts: clean.
- Local toolchain: go 1.26.4, terraform 1.15.5, shellcheck present, jq 1.8.1.
  No `aws` CLI assumed locally; AWS work is gated on go-ahead regardless.

## Open gaps (not yet done — see WORKLOG.md "Next")

- Terraform **Spot** option + a written cost estimate before proposing any spend
  (KICKOFF prefers Spot; current config is on-demand).
- Stretch / Phase 2 of KICKOFF: eBPF (`tc-bpf`) flowlet steerer for the single-flow case;
  MPTCP variant of the sweep. Build only after the core matrix has run.
- The write-up's `_(not yet measured)_` rows + the SVG plots require a **live run** to fill.
- All live-AWS items remain gated on an explicit "go ahead, spend".

## Done so far (offline)

- Phase 0: hygiene (MIT license, .gitignore, SemVer/Keep-a-Changelog, fmt/vet/shellcheck).
- Phase 1: both-node remote-collect fix, sweep idempotency, keys-gen role, report CSV.
- Phase 2: nvme-tcp NVMe→NVMe path (#2), SVG plots (#3), write-up scaffold (#4),
  shared `datapoint` package.
```
