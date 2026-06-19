# wg-saturate

Measure WireGuard aggregate throughput to 100 Gbps and beyond between two
`i8ge.48xlarge` nodes. **Nothing is assumed — everything in the write-up is produced
as a measured number**, and every datapoint is attributed to the limit that bound it.

## What gets measured

| Quantity | Tool | Output |
|---|---|---|
| Raw ENA ceiling (no WG) | `measure-baseline.sh` | Gbps, PPS at the wire |
| Realized per-flow cap | `sweep.sh` at N=1 (± ENA Express) | Gbps for one 5-tuple |
| Per-core ChaCha efficiency | derived in `report` | Gbps per busy core, per datapoint |
| NVMe read / write ceiling | `measure-nvme.sh` | striped MB/s, read and write |
| Memory bandwidth ceiling | `measure-membw.sh` | STREAM Triad GB/s |
| Jumbo (PPS) leverage | `sweep.sh` at MTU 1500 vs 8921 | Gbps, PPS at each MTU |
| Tunnel sweep | `sweep.sh` N=1,2,4,8,12,16,24,32 | aggregate Gbps vs N |
| Binding limit (the knee) | `collect.sh` + `report` | allowance counter deltas per N |

## Attribution: how the knee is identified

At every datapoint, `collect.sh` snapshots the ENA allowance counters before and after the
load window and records the delta, on **both** nodes:

- `bw_out_allowance_exceeded` / `bw_in_allowance_exceeded` → instance bandwidth allowance
- `pps_allowance_exceeded` → packets-per-second allowance
- `conntrack_allowance_exceeded` → tracked-connection allowance
- `ena_srd_*` → confirms SRD (ENA Express) is actually carrying packets
- per-core `mpstat` + `/proc/softirqs` → CPU/crypto saturation and RX-queue concentration

`report` classifies each datapoint as: *linear region*, *bandwidth allowance*, *PPS
allowance*, *conntrack*, *CPU/crypto*, or *single RX queue* — so the curve's knee is a
measured cause, not a guess.

## Layout

```
terraform/   two i8ge.48xlarge, cluster placement group, same AZ, jumbo subnet
scripts/     composable measurement tools (one job each)
report/      Go aggregator: per-datapoint JSON -> attribution table (md + csv)
report/plot/ Go SVG plotter: throughput.svg + efficiency.svg from results/
```

The full curve gets folded into [`wireguard-100gbps-writeup.md`](wireguard-100gbps-writeup.md)
(scaffolded with `_(not yet measured)_` placeholders until a live run fills them).

## Run order

```bash
# 0. Infra
cd terraform && terraform init && terraform apply
#    note the outputs: A/B public IPs, private IPs, primary ENI ids

# 1. On BOTH nodes
sudo ./scripts/node-setup.sh          # kernel check, packages, tuning, jumbo, IRQ pools
./scripts/keys-gen.sh a <N_MAX>       # on A: per-tunnel keys -> wg-pub-a.txt   (use 'b' on B)
#    exchange the two wg-pub-*.txt files (one scp each way)
./scripts/mesh-up.sh a <N_MAX> <B_priv_ip> wg-pub-b.txt   # on A
./scripts/mesh-up.sh b <N_MAX> <A_priv_ip> wg-pub-a.txt   # on B

# 2. Ceilings (run on A; nvme/membw on both)
./scripts/measure-baseline.sh <B_priv_ip>
./scripts/measure-nvme.sh
./scripts/measure-membw.sh

# 3. ENA Express toggle (from a host with AWS creds; both ENIs)
./scripts/enable-ena-express.sh on  <ENI_A> <ENI_B>     # or 'off'

# 4. The sweep (on A; B runs server-up.sh first)
./scripts/server-up.sh <N_MAX>                          # on B
REMOTE_HOST=<B_priv_ip> ./scripts/sweep.sh placement    # then re-run as 'ena_express'

# 4b. Real NVMe->NVMe over nvme-tcp native multipath (confirms the sweep translates to storage)
sudo REMOTE_HOST=<B_priv_ip> ./scripts/nvme-target-up.sh <N_MAX>   # on B (export instance NVMe)
sudo REMOTE_HOST=<B_priv_ip> ./scripts/measure-nvme-tcp.sh placement  # on A (read+write sweep)
sudo ./scripts/nvme-target-down.sh                       # on B when done

# 5. Report + plots  (markdown to stdout; optional CSV as 2nd arg)
cd report && go run . ../results ../report.csv > ../report.md
go run ./plot ../results ../                              # writes throughput.svg, efficiency.svg
```

## Cost warning

Two `i8ge.48xlarge` on-demand is **expensive** (~hundreds of USD/hour combined). Use Spot
where possible, run the matrix in one session, and `terraform destroy` immediately after.

## Assumptions

- Ubuntu 24.04 arm64 AMI (kernel 6.x in-tree `wireguard`, recent ENA driver).
- Key-based SSH as `ubuntu` between the two nodes for remote collection.
- Instance-store NVMe is scratch; `measure-nvme.sh` writes to raw devices.
