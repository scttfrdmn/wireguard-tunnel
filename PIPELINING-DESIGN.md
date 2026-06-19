# Design: pipelining read → encrypt → network → decrypt → write across cores/NUMA

Status: **design + experiment plan** (not yet implemented). Goal: push the encrypted fabric
past the ~60–77 Gbps receive-side CPU plateau toward the ~180 Gbps network / 208 Gbps measured
ENA ceiling, by placing the pipeline's stages deliberately rather than letting the scheduler
and a NUMA-blind IRQ pinning decide.

## What we know (measured, runs 1–3)

- The fabric is **receive-side CPU bound**, not network bound: no AWS allowance ever fired;
  raw ENA hit 208 Gbps with no WireGuard. Plateau ~57–60 Gbps unpinned, 77 Gbps with naive
  userspace pinning. (`wireguard-100gbps-writeup.md`)
- The **receiver costs ~4× the sender** in CPU (≈57 vs 15 core-equivalents at N=32). Decrypt +
  receive is the heavy half — so pipelining effort belongs on the **receive** side first.
- **Per-core efficiency decays with N** (2.53 → 1.04 Gbps/core-equiv) — spreading the same
  receive pipeline across ever more cores costs more per Gbps (scheduling, cache, hand-offs).
- **`i8ge.48xlarge` is 2 NUMA nodes** (node 0 = cores 0-95, node 1 = 96-191); **ENA NIC on
  node 1**; instance NVMe split 8/8. ([[i8ge-numa-topology]] / `results/numa.json`)
- **Confound corrected:** our IRQ pinning was NUMA-blind (RX IRQs on cores 0-31 = node 0, the
  NIC-*remote* node). So run-3's "NIC-remote wins" was really "userspace co-located with the
  RX-softirq cores wins." `node-setup.sh` now pins IRQs NIC-local by default. **The
  textbook all-NIC-local layout is untested.**

## The pipeline stages and where they run today

For one tunnel `i`, receive side (the binding half):

| Stage | Kernel/user | Where it runs today | Pinnable? |
|-------|-------------|---------------------|-----------|
| 1. NIC RX → IRQ | hardware/kernel | RX IRQ `smp_affinity` (now NIC-local node) | yes (IRQ affinity) |
| 2. NAPI poll / softirq | kernel (`napi/wgN`, ksoftirqd) | follows the RX core | indirectly (RPS) |
| 3. WireGuard decrypt | kernel workqueue (`kworker/*-wg-crypt-wgN`) | floats; kernel-chosen | hard (no stable handle) |
| 4. TCP/socket delivery | kernel softirq + socket | follows; RFS can steer | RFS/RPS |
| 5. userspace read() (iperf3 / nvme-tcp) | user | `pin-workers.sh` today | yes (taskset) |
| 6. NVMe write (real workload) | kernel nvmet + device | floats; NVMe on either node | partially |

The only stages we can pin cleanly are **1 (IRQ)** and **5 (userspace)**. Stages 2–4 are
kernel-steered — the levers are **RPS/RFS/XPS** (software receive/transmit steering) and IRQ
affinity, which *indirectly* place softirq and socket delivery.

## The core design question

Two competing forces, both now measurable:

- **Co-location** keeps a flow's stages cache-warm and avoids cross-node memory traffic — but
  piles contending work onto the same cores (the efficiency decay).
- **Spreading / pipelining** gives each stage its own core(s) so they run concurrently — but
  adds hand-off latency and, if it crosses NUMA, a remote-memory penalty on every byte.

The **per-node memory-bandwidth numbers decide the trade-off** — which is why
`measure-membw-numa.sh` (new) is the first thing to run: if remote bandwidth is, say, only
20% below local, crossing the complex for a hand-off is cheap and aggressive pipelining wins;
if it's 2× worse, we must keep each flow's pipeline within one node.

## Three candidate approaches

### A. NUMA-confined per-flow pipeline (conservative; test first)
Keep each tunnel's **entire** receive chain on **one NUMA node**, and split the *set of
tunnels* across both nodes (tunnels 0–15 → node 1, 16–31 → node 0), each group steered to
its node's NIC queues.
- Pin: RX IRQ for tunnel `i` → a core on its group's node; RPS/RFS for that queue → same node;
  userspace receiver → same node.
- Pro: zero cross-node memory traffic per flow; uses both memory controllers. Simple.
- Con: only works if the NIC can deliver queues to both nodes' cores without itself becoming
  the cross-node hop (the NIC lives on node 1 — node-0 flows still DMA across the link).
- **This directly answers your question**: is it better to keep everything on the NIC's node?
  Compare group-on-node-1 vs group-on-node-0 throughput.

### B. Staged pipeline with explicit hand-off (aggressive)
Dedicate **core pools per stage**: e.g. cores 96–127 = RX softirq + decrypt (NIC-local),
cores 128–159 = TCP/socket, cores 0–31 = userspace read/write. Hand off via the kernel's own
queues (RPS steers softirq→a pool; RFS steers socket delivery→the core the app last ran on).
- Pro: stages run concurrently; each pool stays cache-warm for its stage; mirrors a classic
  DPDK-style run-to-completion-vs-pipeline split.
- Con: most hand-offs cross between pools (and maybe NUMA); only worth it if
  `measure-membw-numa` says remote BW is cheap. Hardest to tune.

### C. RX-to-decrypt affinity alignment (minimal, high-leverage)
Leave userspace alone; just make the **kernel** path coherent: RX IRQ, NAPI, and the wg-crypt
kworker for tunnel `i` all on the **same NIC-local core**, via IRQ affinity + RPS + (if needed)
forcing the crypto workqueue's cpumask. Then pin userspace to the *same* node.
- Pro: smallest change; tests the textbook "everything NIC-local, cache-warm" hypothesis the
  confound left unmeasured. Likely the best effort/reward ratio.
- Con: WireGuard's `padata`/workqueue placement isn't a documented knob; may need
  `/sys/devices/virtual/workqueue/.../cpumask` or a kernel param.

## Experiment plan (one Spot session, ~$5, gated)

Run on the corrected harness (IRQs now NIC-local). All on the receiver (B), N=16/24/32:

0. **`measure-membw-numa.sh`** — local vs remote memory bandwidth + the remote penalty %.
   *This number reframes everything below.* (Also `detect-numa.sh` to re-confirm topology.)
1. **Baseline (corrected):** IRQs NIC-local (node 1), userspace unpinned — vs the old
   NUMA-blind baseline, to isolate the IRQ-placement fix alone.
2. **Approach C:** IRQs NIC-local + `NODE=1 pin-workers.sh` (userspace also node 1) — the
   true all-NIC-local layout. Does it beat run-3's 76 Gbps?
3. **Approach C′:** IRQs NIC-local + `NODE=0 pin-workers.sh` (userspace remote) — re-run the
   A/B now that softirq is correctly NIC-local. If node 1 now wins, the confound is confirmed
   and the textbook layout holds.
4. **Approach A:** split tunnels across nodes (needs an `IRQ_CORES`-per-group variant +
   RPS config) — only if 2/3 suggest headroom.
5. **RPS/RFS sweep** for the winning layout (steer softirq + socket delivery onto the decrypt
   cores) — the stage-2/4 lever we haven't touched.
6. **NVMe near:far drive-ratio sweep** (storage workload only): export 8/0, 6/2, 4/4, 2/6, 0/8
   near:far drives and measure combined NIC RX + NVMe write at each. Finds the balance point
   between node-1 bus contention and the far-side extra hop. Watch NIC RX for degradation when
   near-side write load is high (the bus-sharing signature).

Decision rule: pick the layout with the highest **Gbps/core-equiv** (efficiency), not just
peak Gbps — efficiency is what the decay metric showed is the real constraint.

## What to build before that run (offline)

- [x] `measure-membw-numa.sh` (done) — per-node + local/remote BW (prices the far-side hop).
- [x] `node-setup.sh` NIC-local IRQ pinning + `IRQ_CORES=` override (done).
- [x] `detect-nvme.sh --node N / --with-node` (done) — tag/select drives by NUMA node.
- [x] `detect-numa.sh` PCIe probe (done) — counts NVMe sharing the NIC's bus.
- [ ] `nvme-target-up.sh`: node-filter / near:far ratio knob (export drives by node) for the
      ratio sweep (step 6).
- [ ] `rps-setup.sh` — set `/sys/class/net/<if>/queues/rx-*/rps_cpus` + `rps_flow_cnt` to
      steer softirq onto a chosen core pool (approach B/C, step 5).
- [ ] `pin-workers.sh`: optional per-group split (tunnels→node map) for approach A.
- [ ] (stretch) probe/set the wg-crypt workqueue cpumask for approach C.

## NVMe placement + bus-bandwidth contention (the real-workload complication)

Two physical realities the node-abstraction above glosses over, both raised as concerns and
both real:

### 1. The NVMe→NVMe workload *must* cross the complex for half the drives
The 16 instance-store NVMe split **8 on node 0, 8 on node 1** (`results/numa.json`). For the
real `nvme-tcp` workload the full path is
`NIC (node 1) → decrypt → TCP → nvmet → NVMe write`. If the target drive is on node 0, the
decrypted payload **must** traverse the interconnect to reach it — there is no placement that
avoids it for those 8 drives. So unlike the pure-iperf sweep (which never touches disk), the
storage workload pays a *mandatory* cross-NUMA hop for ~half its writes.

Implications for the design:
- **Drive selection matters.** `measure-nvme-tcp.sh` / `nvme-target-up.sh` currently export
  *all* 16 devices. We should add a knob to export **only NIC-local (node-1) drives**, and
  A/B that against all-16 and node-0-only. If NIC-local-only gets within the write ceiling
  (25.9 GB/s is far above 77 Gbps≈9.6 GB/s, so even 8 drives have headroom), confining the
  storage target to the NIC's node removes the mandatory hop entirely.
- This is the one place where "keep everything on the NIC's node" is unambiguously right —
  *if* node-1's 8 drives sustain the needed write rate. `detect-nvme.sh` should tag each
  device with its `numa_node` so we can pick.
- The membw-numa remote penalty (step 0) directly prices the cost of *not* doing this.

### 2. Shared bus bandwidth between NIC and NVMe on node 1
The ENA NIC **and** 8 NVMe drives both hang off node 1's PCIe/host-bridge. At high rate they
**share the same upstream bus/interconnect bandwidth to that node's memory controller.** So
the very layout that's best for latency/locality (everything NIC-local) could create a
**bus-bandwidth conflict**: 75+ Gbps of NIC RX DMA *plus* multi-GB/s of NVMe write DMA, both
funneling through node 1's PCIe root and into node-1 memory, may contend before the CPU is
even the limit. This would show up as throughput *not* improving (or regressing) when we move
storage onto node 1 despite removing the NUMA hop — a different bottleneck than CPU or memory.

How we'll detect/quantify it:
- **Topology:** `lspci -tv` + `/sys/bus/pci/devices/*/numa_node` to confirm NIC and which
  NVMe share a PCIe root complex / host bridge on node 1 (add to `detect-numa.sh`).
- **The decisive A/B for this:** run the full NVMe→NVMe workload with the target drives
  **all on node 1** (NIC-local, shares the bus) vs **all on node 0** (remote memory hop, but
  NIC and storage DMA use *different* host bridges → no bus sharing). If node-0 drives win
  *despite* the NUMA penalty, bus contention on node 1 is real and dominant. This is a clean,
  measurable either/or — and it may invert the "NIC-local is best" conclusion specifically for
  the storage workload.
- Watch for it in the data as: NIC RX throughput dropping when NVMe write load is added on the
  same node (compare the iperf-only sweep vs the nvme-tcp sweep at equal N, same placement).

### 3. The two effects are on *different resources* → it's a load-balance, not a binary
This is the key reframing. The far-side cost and the near-side cost don't compete for the same
resource, so they can **offset**:

- A **node-0 (far) drive** adds an **extra pipeline hop** — decrypt (node 1) → cross-complex
  DMA → write (node 0). Costs: interconnect bandwidth + the remote-memory penalty. But its
  write-DMA rides **node 0's PCIe bus**, which the NIC does *not* use → no NIC contention.
- A **node-1 (near) drive** has **no extra hop**, but its write-DMA **shares node 1's PCIe
  bus with NIC RX-DMA** → contention at high rate.

So pushing *some* write traffic to the far side **relieves node-1's shared bus** at the price
of an extra hop on that fraction. The optimum is almost certainly a **split ratio**, not "all
near" or "all far":

```
total write BW  ≈  near_drives·(bus_share_limit) + far_drives·(min(remote_BW, interconnect_share))
```
Push far-side load up until either (a) node-1 bus contention is relieved enough that NIC RX
stops suffering, or (b) the interconnect / remote-mem penalty on the far fraction becomes the
new limit — whichever binds first. **Think of the far side as a second, deeper pipeline lane
running in parallel with the near lane**, and balance fill between them.

This makes the experiment a *sweep over the near:far drive ratio*, not a single A/B:
- `detect-nvme.sh --with-node` tags each drive's node; `nvme-target-up.sh` gains a node-filter
  / ratio knob so we can export, e.g., 8 near / 0 far, 6/2, 4/4, 0/8.
- Measure NIC RX throughput **and** NVMe write GB/s at each ratio. The peak combined number
  names the balance point — and it's the quantity `measure-membw-numa.sh` (remote penalty) +
  the per-bus ceiling let us predict before the run.

**Net:** the pure-network pipeline wants everything NIC-local (node 1). The storage pipeline is
a **balancing act** — distribute writes near:far to trade node-1 bus contention against the
far-side extra hop, modeling the far lane as a parallel deeper pipeline. The optimum is a
ratio we'll find by sweep, informed by the measured local/remote BW and per-bus limits.

## Open questions this plan answers

1. **Per-node and local-vs-remote memory bandwidth** (the question that prompted this) —
   step 0. Until measured, we can't say whether to confine pipelines per-node or span them.
2. Is the **textbook NIC-local layout** actually best, once IRQs are placed correctly? —
   steps 2–3 (the confound rerun).
3. Does **explicit stage pipelining** (B) beat run-to-completion per flow (A/C)? — step 4,
   contingent on the membw-numa result.
