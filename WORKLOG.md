# WORKLOG — wg-saturate

Append-only log of work done, newest at the bottom of each day.

## 2026-06-18 — Session 1: intake, normalize, offline audit

- Moved `KICKOFF.md` into the repo and read the full mandate.
- Found the repo was a flat scatter of loose files + `wg-saturate.tar.gz`. Verified the loose
  files (`collect.sh`, `sweep.sh`, `main.go`, `main.tf`, `README.md`) were byte-identical to
  copies inside the tarball. Promoted the tarball's structured layout
  (`terraform/`, `scripts/`, `report/`, `README.md`) to the repo root, removed the loose
  duplicates, made `scripts/*.sh` executable, archived the tarball to `.archive/`.
- Read every source file (12 scripts, report/main.go, 3 terraform files, README).
- Ran offline validators (no AWS, no spend):
  - `terraform validate` → PASS; `terraform fmt -check` → `outputs.tf` needs reflow.
  - `go build` → PASS; `go vet` → 1 finding (redundant newline, main.go:101);
    `gofmt -l` flags main.go.
  - `shellcheck scripts/*.sh` → only info-level (SC1091 source-follow + a few
    SC2086/SC2162/SC2013 in measure-nvme.sh / node-setup.sh).
- Wrote `CLAUDE.md` (project context) and this `WORKLOG.md`.
- Produced plan + gap analysis against the Definition of done (in chat). **Stopped before any
  code changes / AWS spend, awaiting go-ahead.**

## 2026-06-18 — Session 1 (cont.): Phase 0 + Phase 1 (offline, no spend)

User amendments: **MIT license** (© 2026 Scott Friedman, supersedes KICKOFF's Apache-2.0),
and **SemVer 2.0.0 + Keep a Changelog** practices.

**Phase 0 — hygiene:**
- Added `LICENSE` (MIT), `.gitignore` (excludes keys/, wg-pub-*.txt, results/, tfstate, etc.),
  `VERSION` (0.1.0), `CHANGELOG.md` (Keep a Changelog), `.shellcheckrc` (source-path=SCRIPTDIR).
- Fixed `go vet` (redundant newline) + `gofmt`; `terraform fmt` on outputs.tf.

**Phase 1 — correctness & idempotency:**
- **collect.sh self-contained:** was sourcing common.sh, which doesn't exist on node B when
  shipped via `ssh ... bash -s` → node_b.json came back empty, gutting both-node attribution.
  Inlined the needed helpers. THIS was the highest-leverage correctness bug.
- **sweep.sh idempotency:** clears stale flow*.json / node_*.json before each datapoint so a
  smaller-N re-run can't inflate the aggregate. Added live-vs-recorded wg_mtu guard + doc for
  the MTU-1500-vs-jumbo workflow.
- **keys-gen.sh:** explicit `<role:a|b>` arg (was `hostname -s` → wrong pubkey filename);
  tightened key perms.
- **report:** optional CSV output (`go run . <results> [out.csv]`) carrying per-node counter
  deltas. Validated end-to-end against synthetic fixtures (linear / CPU-crypto / bw-allowance
  classifications all correct; md + csv verified).
- **shellcheck:** array-ified fio args (SC2086), while-read IRQ loop (SC2013); now `-x` CLEAN.
- Updated README run order (keys-gen role arg, CSV) and CLAUDE.md (license/versioning, gaps).

**Validation (all green, offline):** shellcheck -x clean; go build/vet/gofmt clean;
terraform fmt + validate clean; bash -n clean.

## 2026-06-18 — Session 1 (cont.): Phase 2 (offline, no spend)

KICKOFF priorities #2, #3, #4 — all built and offline-validated; none require AWS yet.

**2a — real NVMe→NVMe over nvme-tcp native multipath (#2):**
- `nvme-target-up.sh` (B): kernel nvmet over nvme-tcp; ONE subsystem ($NVME_NQN) exposes
  each instance-store device as a namespace, published on N ports (port i bound to tunnel
  i's B-side IP). `nvme-target-down.sh` tears it down leaf-first (configfs ordering).
- `measure-nvme-tcp.sh` (A): connects N paths to the subsystem (each pinned to its tunnel's
  source IP via --host-traddr → distinct 5-tuple), sets round-robin iopolicy so commands
  spray across tunnels, runs fio read+write, collects both-node attribution, and emits the
  SAME datapoint.json schema as sweep.sh (+ nvme_GBps/rw) so `report` ingests it unchanged.
- Added NVME_BASE_PORT / NVME_NQN / nvme_port() to common.sh.

**2b — plots (#3):** `report/plot` (stdlib-only Go SVG) → throughput.svg (Gbps vs N per
mode, ~180 Gbps wall drawn) + efficiency.svg (Gbps/busy-core vs N). Verified well-formed via
xmllint.

**2c — write-up scaffold (#4):** `wireguard-100gbps-writeup.md` with thesis, rig, methodology
and result tables where every measured cell is `_(not yet measured)_` (honoring "never
fabricate"). Includes the exact commands to fill it from `report/`.

**Refactor:** extracted `report/internal/datapoint` (types, Load, Classify, efficiency
helpers); `report` and `plot` share it — no duplicated parsing/classify.

**Validation (all green, offline):** go build/vet/gofmt clean across all 3 packages;
report+plot exercised on multi-mode fixtures (md/csv/nvme-tcp columns/SVG); shellcheck -x +
bash -n clean on all 16 scripts. Docs (README/CHANGELOG/CLAUDE) updated.

## 2026-06-18 — Session 1 (cont.): Phase 3 (offline, no spend)

- Terraform: added `use_spot` (default **true**, per KICKOFF), `max_spot_price`,
  `root_volume_size` vars; conditional `instance_market_options` spot block (one-time,
  terminate-on-interruption, max_price→null when uncapped); `pricing_mode` output.
  `terraform fmt`+`validate` clean.
- **COSTS.md** grounded in LIVE AWS prices (read-only API calls cost nothing): On-Demand
  **$22.7808/instance-hr** (Pricing API) ⇒ **$45.56/hr** for the rig; Spot **$7.20** us-east-1a,
  down to **$2.28** us-west-2d (Spot history, 2026-06-18). gp3 $0.08/GB-mo ⇒ EBS negligible.
  Per-session scenarios (2–4h), Spot-vs-OD trade-off, capacity caveat, re-check commands.
- Confirmed local `aws` CLI has active creds; used it only for read-only price queries.
- Docs wired: README cost section, CHANGELOG, CLAUDE.md.

### Next (pending user go-ahead; remaining work)
- Stretch: eBPF tc-bpf flowlet steerer (single-flow case); MPTCP sweep variant.
- LIVE RUN (GATED on "go ahead, spend"): `terraform apply` (Spot) → run the matrix →
  `report` + `plot` → fold measured numbers into the write-up + commit the SVGs →
  `terraform destroy`. Offline work is complete; the harness is ready.

## 2026-06-19 — Session 2: LIVE RUN (authorized: Spot, us-west-2d)

Dedicated key `wg-saturate` (generated + imported; scofri private key wasn't local).
2× i8ge.48xlarge Spot in us-west-2d (usw2-az4), ~$2.28/instance-hr. Preflight (read-only,
free): confirmed offering, AZ, 640 vCPU Spot quota. Operator IP <operator-ip>.

**Six real-hardware bugs found & fixed (all folded back into the repo + CHANGELOG):**
1. `collect.sh` `read`-without-newline aborted under `set -e` → all node JSON empty, sweep
   died at N=1. (Highest impact.) Fixed to command substitution.
2. `/31` tunnel addressing → no inner route (.2 off-subnet); changed to `/30`.
3. `node-setup.sh` died on missing `awscli` apt package; removed.
4. `nvme-tcp`/`nvmet-tcp` modules in linux-modules-extra, not base; node-setup installs now.
5. i8ge ENA driver has per-queue `queue_N_tx_cnt`, no flat `tx_packets`; added `ena_pkts`.
6. `measure-nvme-tcp.sh` mp-device discovery via sysfs (nvme list -o json lacks SubsystemNQN).
   Plus: setsid for iperf3 servers; reclaim root-owned results/.

**Measured results (DUR=15):**
- Ceilings: raw ENA **208 Gbps** / 2.90 Mpps (no WG!), NVMe 52.3 GB/s read / 25.9 write,
  membw 4885 GB/s.
- placement sweep: 7.9→15.8→30.9→54.7 (N=1..8, near-linear) → plateau ~57–60 (N=12..32).
- ena_express: same curve; SRD barely engaged (srd_tx tiny vs eligible) — reported honestly.
- nvme-tcp: read peak 8.9 GB/s (71 Gbps), tracks the synthetic sweep.
- **Attribution: plateau is receive-side CPU/crypto (node_b max_core_util 98–99%), NO AWS
  allowance fired. 100 Gbps NOT reached; bottleneck is crypto, not the 180 Gbps wall.**

Generated report.md/report.csv/throughput.svg/efficiency.svg; filled the write-up with
measured numbers + honest caveats. **`terraform destroy` complete (9 resources), instances
gone, project key pair deleted from AWS. Billing stopped.** Total spend: well under $5.

### Next (optional, offline or future live)
- Stretch: isolate the saturated receive core (ksoftirqd vs worker); RPS/RFS tuning to push
  past 60 Gbps. eBPF flowlet steerer; MPTCP variant; longer ena_express window for SRD.

## 2026-06-19 — Session 3: instrumentation + Spot run 2 (us-west-2d)

Used **`truffle spot`** (spore.host CLI) for the cost preflight — confirmed us-west-2d still
$2.2781/instance-hr (90% off), cleaner than raw describe-spot-price-history. spore.host is a
catalog of streamable research-viz apps (ChimeraX/ParaView/QGIS/etc.); truffle is its EC2
discovery CLI.

Built CPU instrumentation first (offline, committed): collect.sh per-core histogram +
busy_core_equiv + pidstat top_threads; report core-equiv/Gbps-per-core + Hot threads table;
pin-workers.sh affinity knob. Then ran it live.

Run 2 (key re-imported, operator IP updated to <operator-ip>, all 6 prior fixes held — clean
setup on first try; nvme-tcp modules + pidstat present):
- placement: 7.9/15.7/29.1/48.0/56.0/55.3/55.8/59.9 (N=1..32) — same ~60 plateau.
- **Instrumentation ANSWERS the open question:** receiver at N=32 = ~57 core-equivalents
  across ~31 cores >50% (NOT one pegged core). Hot threads: napi/wgN-0 + kworker wg-crypt-wgN
  + ksoftirqd + iperf3. Receiver costs ~4x sender (57 vs 15 coreEq). Per-core efficiency
  DEGRADES with N: 2.53→1.04 Gbps/coreEq.
- **PINNING A/B (the headline):** placement_pinned 42.2/58.6/69.2/**77.2** at N=8/16/24/32 —
  +29% at N=32, same ~57 coreEq, efficiency 1.04→1.35 Gbps/core. Confirms the ceiling is
  CPU placement / cache locality, not a hard wall. Best result yet: 77 Gbps.
- ena_express: same as placement; SRD still barely engaged.
- Skipped nvme-tcp re-run (have it from run 1; saved spend).

Pulled results (24 datapoints), regenerated report/CSV/SVGs, rewrote write-up with both runs +
the pinning table + an honest "pinning was userspace-only" caveat + the pipelining note.
**terraform destroy complete (9 resources, []), key pair deleted. Billing stopped.** ~25 min, <$5.

### Next
- User idea to pursue: **pipeline read|encrypt|network|decrypt|write across cores** (top
  follow-up; recorded in the write-up). Also: pin the kernel decrypt path (RPS/RFS/XPS +
  wg-crypt kworker affinity), pinned ena_express run, finer N grid.

## 2026-06-19 — Session 4: NUMA probe + NIC-affinity A/B (run 3)

truffle spot reconfirmed us-west-2d $2.2781/hr. Built detect-numa.sh (sysfs probe) + NODE=
knob on pin-workers.sh offline, then ran live.

**Classified:** i8ge.48xlarge = 2 NUMA nodes (0:0-95, 1:96-191). ENA NIC on node 1
(EXPOSED, numa_node=1, not hidden). Instance NVMe split 8/8 across nodes. The guest does
surface device affinity — answers the user's "is it visible in a VM" question: yes here.

**Decisive A/B (receiver userspace pinning, N=8/16/24/32):**
- NODE=1 (NIC-LOCAL): 55.9/57.3/57.0/56.3 — flat ~56, work smeared 55 cores, 0.97 Gbps/core.
- NODE=0 (NIC-REMOTE): 53.3/61.4/70.8/75.7 — climbs to 75.7, work in 30 cores, 1.39 Gbps/core.
- **COUNTERINTUITIVE: NIC-remote WINS.** Kernel RX/softirq/wg-crypt already lives on the
  NIC-local node; co-locating userspace there contends. Splitting the pipeline across nodes
  (kernel on NIC-local, userspace on the other) is the win — empirical confirmation of the
  pipelining idea. Fixed detect-numa.sh verdict to recommend A/B, not blind NIC-local pinning.

Captured insights to memory (i8ge-numa-topology, wg-saturate-key-findings, truffle-spot-tool).
Pulled numa.json + numa_node0/1 datapoints; report now 38 datapoints/7 modes. Updated write-up
NUMA section with the measured A/B + mechanism. terraform destroy complete, key deleted,
billing stopped. ~25 min, <$5.

### Next: design explicit cross-NUMA pipelining (read|encrypt|net|decrypt|write).

## 2026-06-19 — Session 5: NIC-local IRQ fix + membw-numa + NVMe ratio (run 4)

Built offline first: measure-membw-numa.sh (per-node STREAM), node-setup NIC-local IRQ pinning,
detect-nvme --node, detect-numa PCIe probe, nvme-target-up NVME_NODE/NVME_MAX, PIPELINING-DESIGN.md.

Live run 4 (us-west-2d Spot, IP updated to <operator-ip>):
- **IRQ fix verified**: ENA IRQs now on cores 96-191 (node 1, NIC-local) — confirmed via
  /proc/irq smp_affinity_list.
- **membw-numa** (after fixing 2 bugs live — arm64 BSS reloc overflow + const-folding →
  malloc+checksum): LOCAL 381 GB/s, REMOTE 69 GB/s, 90% penalty. Old 5551 = cache bug.
- **Corrected NIC-local A/B (N=32)**: NODE=1 (all NIC-local) 74.1 > unpinned 64.2 > NODE=0 55.1.
  FLIPS run-3's confounded result; confirms NIC-local co-location is best (user was right).
  ksoftirqd now on node-1 cores (118,120,126…) — softirq followed the IRQs.
- **NVMe near:far** (fixed mp_devices: derive /dev/nvme<inst>n* + 10s settle): near read 9.4 /
  far 8.7 / balanced 6.9 GB/s, writes ~8.5. Placement barely matters — CPU-bound far below the
  69 GB/s remote ceiling. Balanced read drop = mild contention, the only ratio signal.

Corrected detect-numa verdict + numa.json + write-up (run-3 confound kept as history, run-4
resolution added). Report = 42 datapoints / 9 modes. terraform destroy complete, key deleted,
billing stopped. ~30 min, <$6.

### Next: implement explicit cross-core pipelining (RPS/RFS for stages 2-4); the placement
### levers are now well-characterized.

## 2026-06-19 — Session 6: pipelining/NUMA-placement toolkit (offline build, plan-mode)

Entered plan mode; a Plan agent design-reviewed the Linux RX-steering approach and
course-corrected (folded into PIPELINING-DESIGN.md). User chose "full build, everything" +
"pure-network first". Built ALL levers offline (no spend):
- pin-workers.sh: ALIGN=1 (per-flow IRQ<->app run-to-completion, the predicted next win),
  SPLIT=1 (node-split groups), kept NODE=.
- node-setup.sh: IRQ_SPLIT=1 (half IRQs NIC-local, half far, index-aligned w/ tunnel split).
- rps-setup.sh (new): RPS+RFS on/off + 192-cpu hex-mask builder (measure RPS, don't assume).
- set-crypt-affinity.sh + probe-wq.sh (new): wg-crypt WQ affinity_scope/cpumask if writable.
- collect.sh: per-thread-class %CPU rollup (decrypt/softirq/ksoftirqd/app) -> settles Story A
  (serial) vs B (distributed). report: new "Receiver stage cost" table. detect-numa: RPS
  state + rx_buffer_node.
- measure-membw-numa.sh: thread sweep (1/8/24/48/96) + pointer-chase latency probe to test
  whether the 90% remote-BW hit is interconnect saturation (likely) vs per-access penalty.

Design-review verdicts (built but expected outcomes): RPS = dead end at N>=16 (flows already
HW-spread); Approach-A node-split = likely dead end (ENA RX buffers stay on NIC node, so node-0
cores would stream payload across the 69 GB/s link — rx_buffer_node probe will confirm);
wg-crypt cpumask = probably no-op (per-CPU WQ already follows NIC-local IRQ). Real lever = ALIGN.

Validation: shellcheck -x clean (22 scripts); go build/vet/gofmt clean; report backward-compat
verified (stage table absent on old data, present w/ fixture); C probes compile-checked (omp
stubbed on mac). NO SPEND. Plan file: ~/.claude/plans/cuddly-sprouting-liskov.md.

### Next: live run (gated) — Phase-0 probes, settle Story A/B via stage rollup, membw thread
### sweep, then labelled sweeps: irqlocal_userN1 baseline -> align -> rfs -> rps_on -> split.

## 2026-06-20 — Session 7: live placement run (run 5) — NODE-SPLIT WINS at 95.3 Gbps

Authorized spend. us-west-2d Spot $2.37/inst-hr, IP-><operator-ip>. Ran the placement toolkit
built in session 6.

Phase-0 free probes: RPS off, 32 rxq, rx buffers node 1; wg-crypt WQ is PER-CPU (kworkers
exist, no /sys/.../workqueue entry) -> not steerable, placement follows IRQ core (confirms
why IRQ pinning already captured it).

membw thread-sweep ANSWERED the 90% question: remote BW plateaus ~69 GB/s by 24 threads (flat
to 96) = INTERCONNECT SATURATION; single-access latency only 2.18x (307 vs 141 ns) ~ SLIT
10:20. So moderate cross-node hand-offs are cheap; only bulk streaming hits the wall.

Lever sweep (N=32): irqlocal_userN1 79.6 / align 79.3 / rps_on 79.0 (neutral) /
**split 95.3 Gbps** @ 2.56 Gbps/core-equiv (vs 1.28), receiver 79% peak (not pegged), 37
core-equiv vs 62. NODE-SPLIT is the winner — contradicts the design-review dead-end
prediction. WHY: NIC-local-only was single-mem-controller bound (hot: wg-crypt + mm_percpu_wq
churn ~21% each); splitting across both nodes' mem subsystems relieves it; cross-node cheap.

Pulled per-mode (verified before destroy — run-4 lesson); report 65 dp/19 modes; updated
write-up headline+placement section+run log, CHANGELOG, memory. terraform destroy complete,
key deleted, billing stopped. ~35 min, <$6.

### Next options: tighten collect.sh stage rollup (softirq/app under-counted); push split toward
### 100 (finer N, split ratio other than 50/50, NVMe over split); or call it — 95.3 is near-wall.

## 2026-06-20 — Session 8: GOAL MET — 103.2 Gbps (run 6) + collect.sh rollup fix

Did #2 (offline) then #1 (live), per user "1 & 2, can't walk away when so close".

#2 collect.sh stage-rollup fix: pidstat -t prefixes thread comms with "|__", which broke the
^napi/^ksoftirqd anchors (read 0). Stripped the prefix; added mm_percpu_wq "memmgmt" class.
report+datapoint gain stage_memmgmt_ce. Validated; committed.

#1 push-to-100 (us-west-2d Spot, N_MAX=64, IP unchanged):
- node-split sweep: N=32 99.3 / N=40 **103.2** / N=48 100.3 / N=64 103.1 Gbps.
  **CROSSES 100 at N=40 — PROJECT GOAL MET.** No AWS allowance fired; receiver CPU-saturated
  (100% peak, 70-89 core-equiv) = aggregate ChaCha20 wall across all 192 cores.
- Stage rollup fix CONFIRMED working live: all classes populate (N=40: dec=22.1 sirq=1.6
  ksd=1.4 mm=1.2 app=0.2). NIC has 32 HW queues; 64 tunnels share 2:1, scales fine (CPU-bound).
- Full progression: 60->77->89.5->95.3->103.2 Gbps via placement alone; network never bound.

Bumped VERSION 0.3.0; CHANGELOG [0.3.0] release. report 69 dp/20 modes. Pulled per-mode +
verified before destroy; terraform destroy complete, key deleted, billing stopped. ~40 min, <$7.

### Status: KICKOFF headline deliverable achieved (>=100 Gbps, every knee attributed). Remaining
### optional: NVMe-over-split workload at 100G; finer split ratios; the original write-up's
### remaining "not yet measured" rows if any.

## 2026-06-20 — Session 9: push past 103 — bidirectional ~136 Gbps aggregate (run 7)

Plan-mode review: corrected two of my framings (encrypt≈decrypt crypto cost, NOT 1/4; no
single 180 aggregate cap — in/out metered separately). Built offline: nic-tune.sh (offload/ring
A/B), sweep.sh BIDIR=1 (paired opposing flows), server-up forward|reverse|both, collect
stage_crypt relabel, report bidirectional table. Committed offline build, then ran live.

Run 7 (us-west-2d Spot, N_MAX=64, IRQ_SPLIT on BOTH nodes — both are receivers now):
- OFFLOAD lever DEAD on ENA: GSO/GRO already on; tx-udp-segmentation [fixed] off; RX ring
  1024->8192 didn't help (113->103 unidir). Per-byte cost not reducible; placement is the lever.
- Unidir re-baseline 113 Gbps N=40 (warmer instance than run-6's 103).
- BIDIRECTIONAL node-split: N=32 117.6 / N=48 **136.2** / N=64 112.5 Gbps aggregate. PEAK ~136.
  No allowance fired (bw_in/out/pps=0 both nodes); node A CPU-saturated 100%. Wall = aggregate
  CPU, never network. Confirms no single 180 aggregate cap.
- HARNESS BUG found+fixed: sweep.sh BIDIR launched N parallel ssh reverse-clients -> hit sshd
  MaxSessions ~10 -> starved remote collect -> N>=40 datapoint crashed. Fixed: all reverse
  clients in ONE ssh session, scp rev json back. (The live higher-N points were gathered via a
  manual single-ssh workaround; N=32 has the committed full-attribution datapoint.)

Pulled clean datapoints (uni baselines + bidir N=32 full attribution); higher-N per-direction
numbers recorded in write-up as measured-via-direct-iperf. report 72 dp/23 modes. terraform
destroy complete, key deleted, billing stopped. ~50 min, <$8.

### Status: KICKOFF fully answered — proved >=100 (103 unidir) AND pushed to the wall (~136
### bidir aggregate), wall attributed to aggregate ChaCha20 CPU (not the 180 network allowance).
### Remaining optional: symmetric BIDIR=1 re-sweep (now bug-fixed) for clean per-N datapoints;
### explicit cross-core pipelining.

## 2026-06-20 — Session 10: tidy bidirectional re-sweep (run 8) — FINAL 148.4 Gbps, v0.4.0

Clean symmetric BIDIR=1 sweep exercising the bug-fixed single-ssh reverse path:
- N=32 **148.4** / N=40 142.8 / N=48 132.2 / N=64 127.4 Gbps aggregate. Balanced directions
  (69.5 + 78.9 at peak) — earlier imbalance was the ssh artifact, confirmed gone.
- Peak attribution: no allowance fired, both nodes 99-100% CPU (~70 core-equiv each), node A
  stage_crypt 38.8 core-equiv (two full crypto pipelines). Wall = aggregate CPU, final.
- All 4 datapoints full-attribution, committed. report 75 dp/23 modes.
- Bumped VERSION 0.4.0, CHANGELOG [0.4.0] release; write-up headline + run-7 table updated to
  the clean 148.4 numbers; memory updated. terraform destroy complete, key deleted, billing
  stopped. ~30 min, <$5.

### PROJECT COMPLETE. KICKOFF fully delivered: >=100 Gbps proven (103 unidir), pushed to the
### wall (148 bidir aggregate), every knee attributed, wall = aggregate ChaCha20 CPU not the
### 180 Gbps network allowance. Harness shellcheck/go clean; results + write-up + plots committed.

## 2026-06-21 — Session 11: unidirectional A->B limit exposed & explained (run 9)

User refocused: ONLY A->B matters (bidir aggregate is a different premise). Goal = find the
A->B wall, prove diminishing returns exhausted, explain WHY.

Built instrumentation offline (committed): collect.sh per-core kernel(soft+sys) vs usr
core-equiv + per-RX-queue byte cv + per-flow rate cv + wire rx_gbps; sweep.sh per-flow
distribution + SINK=devnull (socat); server-up devnull sinks; report "Unidirectional limit
analysis" table. shellcheck/go clean, backward-compatible.

Run 9 (us-west-2d Spot, N_MAX=128, pure A->B):
- Best A->B ~111-115 Gbps (N=96). Curve non-monotonic 102/93/89/90/111-115/109 — ceiling ~110-115.
- THE EXPLANATION: receiver busy CPU is ~100% KERNEL softirq+sys, USERSPACE=0% (N=32 coreEq 67.1
  = kernel 67.0, usr 0.06; N=64 coreEq 97.4 all kernel). The "missing core-equiv" from prior runs
  = un-threaded per-packet receive-stack work (NAPI/GRO/TCP/decrypt-in-softirq). pidstat couldn't
  name it; the mpstat class split does.
- Ruled out: app (usr~0, devnull moot), RSS hot-queue (rxq cv 1.04->0.38 = spreads BETTER),
  network (bw/pps=0, raw ENA 205). Wall = aggregate per-packet receive CPU; offload levers dead.
- WALL: ~115 Gbps A->B on i8ge.48xlarge. To exceed needs hw UDP-GSO (ENA fixed-off) or fewer
  packets/Gbps (jumbo maxed). Diminishing returns exhausted.
- Caveat: collect-over-ssh null at N=96/128 (starved when B slammed by 96+ flows); throughput
  clean, attribution clean at N<=64 (proves the story).

Pulled datapoints, verified, terraform destroy complete, key deleted, billing stopped. <$8.
Updated write-up (leads with the A->B result now), CHANGELOG, memory.

### A->B answer documented: ~115 Gbps, per-packet receive-CPU bound, fully attributed.
