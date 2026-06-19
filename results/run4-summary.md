# Run 4 results summary (2026-06-19)

**Data-integrity note:** a merge bug while pulling run-4 results to the laptop
(`cp -R results-run4/*/` flattened the per-mode directories) overwrote most run-4
`datapoint.json` files before they were committed, and the nodes were already destroyed.
The **throughput numbers below are the verbatim values logged from the live `sweep.sh` /
`measure-nvme-tcp.sh` output** during the run — they are real measurements, transcribed, not
fabricated. Only 4 full `datapoint.json` files survived with complete per-node attribution
(`results/irqlocal_userN1/N{8,16,24}` and `results/nvme_tcp_near_write/N32`); the rest exist
only as these headline numbers. The per-NUMA memory-bandwidth (`membw_numa.json`) and topology
(`numa.json`) files survived intact.

## Corrected NIC-local A/B (IRQs pinned NIC-local, node 1), Gbps

| N | unpinned | NODE=1 (all NIC-local) | NODE=0 (remote) |
|---|----------|------------------------|-----------------|
| 8  | 56.6 | 52.4 | 50.5 |
| 16 | 63.7 | 65.1 | 55.2 |
| 24 | 60.1 | 71.2 | 55.1 |
| 32 | 64.2 | **74.1** | 55.1 |

Conclusion: with IRQs NIC-local, **all-NIC-local userspace (NODE=1) wins** — flipping run-3's
confounded "remote wins". 74.1 vs 55.1 at N=32.

## Per-NUMA memory bandwidth (`membw_numa.json`, survived)

local 380.9 GB/s · remote 69.0 GB/s · **90% remote penalty (5.5×)**.

## NVMe near:far ratio, N=32, GB/s

| target drives | read | write |
|---|------|-------|
| 8× near (node 1) | 9.4 | 8.6 |
| 8× far (node 0)  | 8.7 | 8.5 |
| 16 balanced      | 6.9 | 8.4 |

Conclusion: placement barely matters at this CPU-bound ~9 GB/s rate (far below the 69 GB/s
remote-memory ceiling). Balanced read drop (6.9) is mild 16-drive contention.
