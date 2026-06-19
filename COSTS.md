# Cost estimate — wg-saturate

**Bottom line:** the rig is **2 × `i8ge.48xlarge`**. On-Demand that is **~$45.56/hour**
combined; Spot in the cheapest checked AZ is **~$4.56–$14.41/hour** combined. A full
measurement session is a few hours, so budget roughly **$30–$140 on Spot** or **$90–$180+
on-demand** for a 2–4 hour run, plus negligible EBS. **`terraform destroy` the moment the
matrix is done** — idle instances bill at the same rate as working ones.

> Prices below were fetched live from the AWS Pricing API and EC2 Spot price history on
> **2026-06-18** (region defaults `us-east-1`). Spot prices float continuously — re-check
> before a run (commands at the bottom). This file is a *model*, not a quote.

## Per-instance hourly rate (i8ge.48xlarge, Linux, shared tenancy)

| Pricing | $/instance-hour | Source |
|---|---|---|
| **On-Demand** | **$22.7808** | Pricing API, us-east-1, 2026-06-18 |
| **Spot — us-east-1a** | $7.2048 | Spot history, 2026-06-18 (≈68% off OD) |
| **Spot — us-east-1c** | $8.3959 | Spot history, 2026-06-18 |
| **Spot — us-east-1d** | $8.1462 | Spot history, 2026-06-18 |
| **Spot — us-west-2d** | $2.2781 | Spot history, 2026-06-18 (≈90% off OD; outlier — verify capacity) |
| **Spot — us-west-2a/b/c** | $6.05 / $6.34 / $6.49 | Spot history, 2026-06-18 |

The Spot/On-Demand ratio at the time of writing was ~32–37% of On-Demand in `us-east-1`
(i.e. a 63–68% discount); the cheapest `us-west-2d` reading was a ~90% discount but a single
low AZ reading is worth confirming for capacity before relying on it.

## Combined rig cost (2 nodes)

| Mode (AZ) | $/hour (2 nodes) | 2 h | 3 h | 4 h |
|---|---|---|---|---|
| On-Demand | $45.56 | $91.12 | $136.68 | $182.25 |
| Spot — us-east-1a | $14.41 | $28.82 | $43.23 | $57.64 |
| Spot — us-west-2d | $4.56 | $9.11 | $13.67 | $18.22 |

Formula: `cost = rate_per_instance_hour × 2 instances × hours`.

### EBS and the rest

- Root EBS: 2 × 100 GiB **gp3** at **$0.08/GB-month** ⇒ **~$0.022/hour** combined
  (~$0.07 for a 3-hour session). **Negligible.** Tune via `root_volume_size`.
- Instance-store NVMe (the scratch target for `measure-nvme*`): **included** in the instance
  price — not separately billed.
- EBS VPC lane (60 Gbps) is provisioned separately from VPC networking and is not used by
  the throughput tests.
- Same-AZ, same-VPC traffic between the two nodes is **not** charged as data transfer. (Keep
  both nodes in one AZ — which the cluster placement group already requires.)
- ENA Express / SRD: no separate charge.

## How long is a "session"?

A full matrix is dominated by the sweep: `DUR=30 s` per datapoint × 8 values of N × 2 modes
(`placement`, `ena_express`) × (iperf + nvme-tcp read + nvme-tcp write), plus baselines and
setup. That is on the order of an hour of actual load; with `node-setup`, key exchange, ENA
Express toggles, debugging, and re-runs, **plan for 2–4 wall-clock hours**. The hourly rates
above make the spend obvious: every idle hour on-demand is ~$45.

## Spot vs On-Demand for this workload

`terraform/` defaults to **Spot** (`use_spot = true`), per KICKOFF's preference. Trade-off:

- **Spot pro:** 60–90% cheaper, which is the difference between a ~$30 and a ~$140 session.
- **Spot con:** AWS can reclaim the instance with a 2-minute warning. The harness is
  idempotent and re-runnable, so an interruption means re-`apply` and re-run — but an
  interruption *mid-sweep* loses that session's in-progress datapoints. For a one-shot,
  attended run of a few hours this is usually an acceptable risk; for an unattended or
  must-finish run, set `use_spot = false`.
- **Capacity:** 2 × `i8ge.48xlarge` **in a cluster placement group, same AZ** is a chunky
  ask. If Spot capacity isn't available the `apply` fails fast (no charge) — fall back to
  On-Demand or try another AZ/region.
- `max_spot_price`: leave empty (caps at On-Demand, AWS's recommended default). Setting a low
  cap doesn't save money — it just causes launch failures and interruptions.

## Guardrails (from KICKOFF, restated)

- **No `terraform apply` / no spend without an explicit "go ahead, spend"** in-session.
- Always **`terraform destroy`** at the end of a session; confirm with the `pricing_mode`
  output what you actually launched.
- Validate everything offline first (this repo: `shellcheck`, `go build/vet`,
  `terraform validate`) so the paid clock only runs while measuring.

## Re-check prices before a run

```bash
# On-Demand (Pricing API is global; endpoint lives in us-east-1):
aws pricing get-products --region us-east-1 --service-code AmazonEC2 \
  --filters Type=TERM_MATCH,Field=instanceType,Value=i8ge.48xlarge \
            Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
            Type=TERM_MATCH,Field=tenancy,Value=Shared \
            Type=TERM_MATCH,Field=preInstalledSw,Value=NA \
            Type=TERM_MATCH,Field=capacitystatus,Value=Used \
            Type=TERM_MATCH,Field=regionCode,Value=us-east-1 \
  --max-results 1 \
  --query 'PriceList[0]' --output text \
  | python3 -c 'import sys,json;d=json.load(sys.stdin) if False else json.loads(sys.stdin.read());print(d["terms"]["OnDemand"])'

# Live Spot, per AZ (cheap, instant, no spend):
aws ec2 describe-spot-price-history --region us-east-1 \
  --instance-types i8ge.48xlarge --product-descriptions "Linux/UNIX" \
  --start-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'SpotPriceHistory[].{AZ:AvailabilityZone,Spot:SpotPrice}' --output table
```
