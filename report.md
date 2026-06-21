# WireGuard saturation — measured results

## Ceilings
- **Raw ENA baseline:** `{"test":"baseline","streams":32,"gbps":205.71669806306008,"tx_pps":2867863}`
- **NVMe read/write:** `{"test":"nvme","devices":16,"read_GBps":52.260344373,"write_GBps":25.876960991}`
- **Memory bandwidth:** `{"test":"membw","triad_GBps":5551.1}`
- **Memory bandwidth (per-NUMA):** `{
  "test": "membw_numa",
  "nodes": 2,
  "cores_per_node": 96,
  "full_thread_cells_GBps": { "1-1":378.5,"1-0":68.2,"0-0":384.2,"0-1":68.9 },
  "thread_sweep": [{"threads":1,"local_GBps":35.9,"remote_GBps":20.0},{"threads":8,"local_GBps":266.7,"remote_GBps":53.7},{"threads":24,"local_GBps":346.0,"remote_GBps":70.6},{"threads":48,"local_GBps":381.6,"remote_GBps":69.4},{"threads":96,"local_GBps":384.8,"remote_GBps":69.0}],
  "latency_ns": { "1-1":137.37,"1-0":301.41,"0-0":140.85,"0-1":307.09 },
  "local_bw_GBps": 384.2,
  "remote_bw_GBps": 68.9,
  "remote_bw_penalty_pct": 90.0,
  "local_latency_ns": 140.85,
  "remote_latency_ns": 307.09,
  "remote_latency_ratio": 2.18
}`
- **NUMA topology:** `{
  "iface": "ens146",
  "numa_nodes": 2,
  "node_cpulist": { "1":"96-191","0":"0-95" },
  "nic_numa_node": "1",
  "nic_local_cpulist": "96-191",
  "instance_store_nvme_nodes": "0,1",
  "nic_pci": "0000:97:00.0",
  "nvme_sharing_nic_node": 8,
  "rxq_count": 32,
  "rps_enabled": 0,
  "rx_buffer_node": "1",
  "verdict": "multi-node, NIC on node 1 — keep IRQs (NIC-local already), softirq, decrypt AND userspace on node 1 (measured: NODE=1 pin-workers wins)"
}`

## Sweep
| mode | N | Gbps | NVMe GB/s | core-equiv (A/B) | Gbps/core | max util (A/B) | SRD tx | binding limit |
|------|---|------|-----------|------------------|-----------|----------------|--------|---------------|
| align | 16 | 68.5 | - | 18.3/42.1 | 1.63 | 21/100 | 0 | CPU / crypto |
| align | 24 | 75.8 | - | 19.9/53.9 | 1.41 | 23/100 | 0 | CPU / crypto |
| align | 32 | 79.3 | - | 20.9/61.4 | 1.29 | 19/100 | 0 | CPU / crypto |
| bidir_split | 32 | 117.6 | - | 51.6/58.9 | 2.00 | 95/100 | 0 | CPU / crypto |
| ena_express | 1 | 7.9 | - | 1.9/3.5 | 2.23 | 10/44 | 15 | single RX queue (need more tunnels) |
| ena_express | 2 | 15.7 | - | 3.7/7.0 | 2.25 | 23/78 | 42 | linear region (unbound) |
| ena_express | 4 | 27.8 | - | 7.2/13.3 | 2.10 | 26/84 | 39 | linear region (unbound) |
| ena_express | 8 | 45.5 | - | 12.1/24.9 | 1.83 | 26/86 | 51 | linear region (unbound) |
| ena_express | 12 | 54.7 | - | 14.4/36.3 | 1.51 | 21/98 | 306 | CPU / crypto |
| ena_express | 16 | 55.5 | - | 14.2/42.5 | 1.31 | 20/100 | 12627 | CPU / crypto |
| ena_express | 24 | 55.7 | - | 14.0/51.8 | 1.08 | 18/100 | 27530 | CPU / crypto |
| ena_express | 32 | 58.7 | - | 14.7/57.6 | 1.02 | 19/98 | 8795 | CPU / crypto |
| irqlocal_unpinned | 8 | 41.2 | - | 11.2/20.3 | 2.03 | 16/96 | 0 | CPU / crypto |
| irqlocal_unpinned | 16 | 67.6 | - | 18.1/44.7 | 1.51 | 19/100 | 0 | CPU / crypto |
| irqlocal_unpinned | 24 | 56.8 | - | 14.3/52.0 | 1.09 | 14/100 | 0 | CPU / crypto |
| irqlocal_unpinned | 32 | 59.8 | - | 15.0/60.1 | 0.99 | 12/100 | 0 | CPU / crypto |
| irqlocal_userN0 | 8 | 37.8 | - | 10.3/20.2 | 1.87 | 17/94 | 0 | linear region (unbound) |
| irqlocal_userN0 | 16 | 56.3 | - | 14.4/43.0 | 1.31 | 16/100 | 0 | CPU / crypto |
| irqlocal_userN0 | 24 | 55.2 | - | 13.7/51.5 | 1.07 | 13/100 | 0 | CPU / crypto |
| irqlocal_userN0 | 32 | 55.4 | - | 13.4/59.3 | 0.93 | 20/100 | 0 | CPU / crypto |
| irqlocal_userN1 | 8 | 39.3 | - | 10.7/20.3 | 1.94 | 19/97 | 0 | CPU / crypto |
| irqlocal_userN1 | 16 | 75.1 | - | 20.1/41.4 | 1.81 | 24/100 | 0 | CPU / crypto |
| irqlocal_userN1 | 24 | 77.1 | - | 20.4/54.1 | 1.43 | 21/100 | 0 | CPU / crypto |
| irqlocal_userN1 | 32 | 79.6 | - | 21.1/62.0 | 1.28 | 21/100 | 0 | CPU / crypto |
| numa_node0 | 8 | 53.3 | - | 14.0/29.0 | 1.84 | 23/96 | 0 | CPU / crypto |
| numa_node0 | 16 | 61.4 | - | 16.2/36.7 | 1.67 | 27/100 | 0 | CPU / crypto |
| numa_node0 | 24 | 70.8 | - | 18.6/47.0 | 1.51 | 25/100 | 0 | CPU / crypto |
| numa_node0 | 32 | 75.7 | - | 20.0/54.5 | 1.39 | 28/99 | 0 | CPU / crypto |
| numa_node1 | 8 | 55.9 | - | 14.8/29.6 | 1.89 | 38/84 | 0 | linear region (unbound) |
| numa_node1 | 16 | 57.3 | - | 14.7/44.2 | 1.30 | 21/100 | 0 | CPU / crypto |
| numa_node1 | 24 | 57.0 | - | 14.2/0.0 | 4.02 | 16/0 | 0 | linear region (unbound) |
| numa_node1 | 32 | 56.3 | - | 14.0/58.0 | 0.97 | 16/98 | 0 | CPU / crypto |
| nvme_tcp_balanced_read | 32 | 57.9 | 7.2 | 1.1/0.0 | 51.67 | 100/0 | 0 | CPU / crypto |
| nvme_tcp_balanced_write | 32 | 62.6 | 7.8 | 1.1/0.0 | 55.43 | 56/0 | 0 | linear region (unbound) |
| nvme_tcp_far_read | 32 | 59.9 | 7.5 | 47.3/0.0 | 1.27 | 76/0 | 0 | linear region (unbound) |
| nvme_tcp_far_write | 32 | 63.6 | 7.9 | 14.8/0.0 | 4.29 | 28/0 | 0 | linear region (unbound) |
| nvme_tcp_near_read | 32 | 66.8 | 8.3 | 46.7/0.0 | 1.43 | 76/0 | 0 | linear region (unbound) |
| nvme_tcp_near_write | 32 | 58.9 | 7.4 | 13.2/0.0 | 4.46 | 26/0 | 0 | linear region (unbound) |
| nvme_tcp_placement_read | 8 | 49.8 | 6.2 | 0.0/0.0 | 0.00 | 76/0 | 1843513 | linear region (unbound) |
| nvme_tcp_placement_read | 16 | 71.3 | 8.9 | 0.0/0.0 | 71.28 | 99/0 | 1349375 | CPU / crypto |
| nvme_tcp_placement_read | 32 | 67.1 | 8.4 | 0.0/0.0 | 67.13 | 100/0 | 560 | CPU / crypto |
| nvme_tcp_placement_write | 8 | 51.2 | 6.4 | 0.0/0.0 | 0.00 | 29/0 | 102709 | linear region (unbound) |
| nvme_tcp_placement_write | 16 | 59.0 | 7.4 | 0.0/0.0 | 0.00 | 63/0 | 95073 | linear region (unbound) |
| nvme_tcp_placement_write | 32 | 66.7 | 8.3 | 0.0/0.0 | 66.67 | 100/0 | 559 | CPU / crypto |
| placement | 1 | 7.9 | - | 1.8/3.1 | 2.54 | 10/24 | 0 | single RX queue (need more tunnels) |
| placement | 2 | 15.7 | - | 3.8/6.8 | 2.32 | 13/74 | 0 | linear region (unbound) |
| placement | 4 | 29.1 | - | 7.6/13.6 | 2.14 | 33/85 | 0 | linear region (unbound) |
| placement | 8 | 48.0 | - | 12.7/25.1 | 1.91 | 19/85 | 0 | linear region (unbound) |
| placement | 12 | 56.0 | - | 14.7/36.7 | 1.53 | 22/98 | 0 | CPU / crypto |
| placement | 16 | 55.3 | - | 14.0/42.1 | 1.31 | 17/100 | 0 | CPU / crypto |
| placement | 24 | 55.8 | - | 13.9/51.1 | 1.09 | 16/100 | 0 | CPU / crypto |
| placement | 32 | 59.9 | - | 15.0/57.5 | 1.04 | 18/99 | 0 | CPU / crypto |
| placement_pinned | 1 | 7.9 | - | 1.9/3.3 | 2.39 | 11/47 | 55 | single RX queue (need more tunnels) |
| placement_pinned | 2 | 15.6 | - | 3.8/7.2 | 2.17 | 22/80 | 50 | linear region (unbound) |
| placement_pinned | 4 | 26.4 | - | 6.7/12.4 | 2.13 | 15/99 | 4981 | CPU / crypto |
| placement_pinned | 8 | 42.2 | - | 11.1/20.9 | 2.02 | 23/97 | 252 | CPU / crypto |
| placement_pinned | 12 | 52.9 | - | 14.2/29.2 | 1.82 | 31/96 | 347 | CPU / crypto |
| placement_pinned | 16 | 58.6 | - | 15.4/33.7 | 1.74 | 28/99 | 643 | CPU / crypto |
| placement_pinned | 24 | 69.2 | - | 18.4/45.4 | 1.53 | 23/100 | 137 | CPU / crypto |
| placement_pinned | 32 | 77.2 | - | 20.3/57.1 | 1.35 | 24/100 | 452 | CPU / crypto |
| rps_on | 16 | 73.4 | - | 19.3/48.4 | 1.52 | 26/100 | 0 | CPU / crypto |
| rps_on | 24 | 77.1 | - | 19.9/55.5 | 1.39 | 26/100 | 0 | CPU / crypto |
| rps_on | 32 | 79.0 | - | 20.5/0.0 | 3.86 | 18/0 | 0 | linear region (unbound) |
| split | 16 | 74.6 | - | 19.9/42.2 | 1.77 | 24/100 | 0 | CPU / crypto |
| split | 24 | 94.1 | - | 22.8/54.9 | 1.72 | 23/100 | 0 | CPU / crypto |
| split | 32 | 95.3 | - | 23.4/37.2 | 2.56 | 23/79 | 0 | linear region (unbound) |
| split64 | 32 | 99.3 | - | 27.9/65.5 | 1.52 | 23/97 | 0 | CPU / crypto |
| split64 | 40 | 103.2 | - | 26.5/70.3 | 1.47 | 24/100 | 0 | CPU / crypto |
| split64 | 48 | 100.3 | - | 25.3/0.0 | 3.97 | 21/0 | 0 | linear region (unbound) |
| split64 | 64 | 103.1 | - | 26.0/89.5 | 1.15 | 21/100 | 0 | CPU / crypto |
| uni_rings1024 | 40 | 113.0 | - | 29.0/70.9 | 1.59 | 47/99 | 0 | CPU / crypto |
| uni_ringsmax | 40 | 103.0 | - | 26.2/81.6 | 1.26 | 22/100 | 0 | CPU / crypto |

## Bidirectional (aggregate wire = A→B + B→A)
| mode | N | aggregate Gbps | A→B | B→A | core-equiv (A/B) | max util (A/B) | allowance fired? |
|------|---|----------------|-----|-----|------------------|----------------|------------------|
| bidir_split | 32 | **117.6** | 52.6 | 65.0 | 51.6/58.9 | 95/100 | no (CPU-bound) |

## Hot threads during load (top by %CPU)
| mode | N | node A (sender/encrypt) | node B (receiver/decrypt) |
|------|---|-------------------------|---------------------------|
| align | 16 | |__napi/wg1-0:26 |__napi/wg8-0:24 |__napi/wg0-0:24 |__napi/wg13-0:24 | |__iperf3:41 |__iperf3:41 |__iperf3:40 |__iperf3:40 |
| align | 24 | |__napi/wg20-0:20 |__napi/wg7-0:19 |__napi/wg0-0:19 |__napi/wg14-0:19 | |__kworker/174:0-mm_percpu_wq:11 |__kworker/156:0-events:11 |__kworker/163:0-mm_percpu_wq:11 |__kworker/153:0-wg-crypt-wg17:11 |
| align | 32 | |__napi/wg29-0:17 |__napi/wg14-0:17 |__napi/wg9-0:16 |__napi/wg7-0:16 | |__iperf3:43 |__iperf3:41 |__iperf3:40 |__iperf3:40 |
| bidir_split | 32 | |__iperf3:36 |__iperf3:32 |__iperf3:30 |__napi/wg29-0:28 | |__napi/wg28-0:31 |__napi/wg8-0:30 |__napi/wg6-0:29 |__napi/wg4-0:28 |
| ena_express | 1 | |__iperf3:21 |__napi/wg0-0:16 |__pidstat:10 |__kworker/1:1-wg-crypt-wg0:6 | |__iperf3:38 |__napi/wg0-0:38 |__pidstat:11 |__kworker/1:3-wg-crypt-wg0:8 |
| ena_express | 2 | |__napi/wg1-0:23 |__napi/wg0-0:15 |__iperf3:15 |__iperf3:15 | |__iperf3:36 |__iperf3:36 |__napi/wg0-0:33 |__napi/wg1-0:32 |
| ena_express | 4 | |__napi/wg1-0:24 |__napi/wg3-0:23 |__napi/wg2-0:22 |__napi/wg0-0:22 | |__iperf3:36 |__iperf3:36 |__napi/wg0-0:34 |__napi/wg2-0:33 |
| ena_express | 8 | |__napi/wg4-0:28 |__napi/wg7-0:27 |__napi/wg2-0:27 |__napi/wg5-0:26 | |__iperf3:44 |__iperf3:44 |__iperf3:44 |__iperf3:44 |
| ena_express | 12 | |__napi/wg10-0:26 |__napi/wg7-0:24 |__napi/wg2-0:22 |__napi/wg5-0:22 | |__iperf3:64 |__iperf3:64 |__iperf3:64 |__iperf3:63 |
| ena_express | 16 | |__napi/wg10-0:17 |__napi/wg5-0:16 |__napi/wg12-0:15 |__napi/wg15-0:15 | |__ksoftirqd/1:7 |__ksoftirqd/25:6 |__ksoftirqd/5:6 |__ksoftirqd/20:6 |
| ena_express | 24 | |__pidstat:10 |__napi/wg22-0:10 |__napi/wg10-0:10 |__napi/wg16-0:9 | |__kworker/22:3-wg-crypt-wg21:8 |__kworker/4:1-wg-crypt-wg3:8 |__kworker/1:3-wg-crypt-wg18:8 |__kworker/1:0-wg-crypt-wg5:7 |
| ena_express | 32 | |__pidstat:10 |__napi/wg31-0:7 |__napi/wg20-0:7 |__napi/wg18-0:6 | |__iperf3:61 |__iperf3:59 |__iperf3:54 |__iperf3:54 |
| irqlocal_unpinned | 8 | |__napi/wg3-0:28 |__napi/wg2-0:27 |__napi/wg1-0:27 |__napi/wg5-0:26 | |__iperf3:28 |__iperf3:28 |__iperf3:28 |__iperf3:27 |
| irqlocal_unpinned | 16 | |__napi/wg8-0:19 |__napi/wg12-0:19 |__napi/wg15-0:19 |__napi/wg13-0:18 | |__iperf3:59 |__iperf3:59 |__iperf3:59 |__iperf3:58 |
| irqlocal_unpinned | 24 | |__napi/wg14-0:11 |__napi/wg8-0:11 |__pidstat:10 |__napi/wg22-0:9 | |__kworker/121:5-mm_percpu_wq:10 |__kworker/103:6-wg-crypt-wg17:10 |__kworker/122:1-events:10 |__kworker/100:0-events:10 |
| irqlocal_unpinned | 32 | |__pidstat:10 |__napi/wg18-0:8 |__napi/wg23-0:8 |__napi/wg22-0:8 | |__kworker/121:2-mm_percpu_wq:13 |__kworker/124:3-wg-crypt-wg14:12 |__kworker/111:4-wg-crypt-wg14:12 |__kworker/113:4-mm_percpu_wq:11 |
| irqlocal_userN0 | 8 | |__napi/wg2-0:25 |__napi/wg1-0:25 |__napi/wg7-0:25 |__napi/wg5-0:24 | |__iperf3:47 |__iperf3:31 |__iperf3:31 |__iperf3:30 |
| irqlocal_userN0 | 16 | |__napi/wg7-0:17 |__napi/wg9-0:16 |__napi/wg15-0:16 |__napi/wg12-0:15 | |__iperf3:77 |__iperf3:75 |__iperf3:74 |__iperf3:74 |
| irqlocal_userN0 | 24 | |__pidstat:11 |__napi/wg23-0:10 |__napi/wg20-0:10 |__napi/wg12-0:9 | |__kworker/98:0-wg-crypt-wg1:11 |__kworker/117:1-wg-crypt-wg7:10 |__kworker/118:1-wg-crypt-wg7:10 |__kworker/111:9-wg-crypt-wg2:9 |
| irqlocal_userN0 | 32 | |__pidstat:11 |__napi/wg31-0:6 |__napi/wg22-0:6 |__napi/wg30-0:6 | |__kworker/113:5-wg-crypt-wg26:10 |__kworker/98:9-wg-crypt-wg29:9 |__kworker/101:5-mm_percpu_wq:9 |__kworker/110:2-wg-crypt-wg28:9 |
| irqlocal_userN1 | 8 | |__napi/wg0-0:29 |__napi/wg3-0:28 |__napi/wg5-0:26 |__napi/wg2-0:26 | |__ksoftirqd/103:32 |__iperf3:31 |__iperf3:26 |__iperf3:26 |
| irqlocal_userN1 | 16 | |__napi/wg9-0:25 |__napi/wg7-0:24 |__napi/wg14-0:24 |__napi/wg8-0:24 | |__iperf3:38 |__iperf3:38 |__iperf3:37 |__iperf3:37 |
| irqlocal_userN1 | 24 | |__napi/wg20-0:21 |__napi/wg9-0:19 |__napi/wg0-0:19 |__napi/wg7-0:19 | |__kworker/187:0-mm_percpu_wq:12 |__ksoftirqd/112:11 |__kworker/176:4-mm_percpu_wq:11 |__kworker/167:4-mm_percpu_wq:11 |
| irqlocal_userN1 | 32 | |__napi/wg19-0:17 |__napi/wg14-0:17 |__napi/wg7-0:17 |__napi/wg31-0:16 | |__kworker/189:4-wg-crypt-wg27:23 |__kworker/128:4-mm_percpu_wq:22 |__kworker/186:4-mm_percpu_wq:22 |__kworker/129:2-mm_percpu_wq:22 |
| numa_node0 | 8 | |__napi/wg7-0:28 |__napi/wg6-0:28 |__napi/wg2-0:27 |__napi/wg1-0:26 | |__iperf3:63 |__iperf3:32 |__iperf3:31 |__iperf3:31 |
| numa_node0 | 16 | |__napi/wg3-0:29 |__napi/wg7-0:29 |__napi/wg4-0:27 |__napi/wg8-0:24 | |__iperf3:49 |__iperf3:37 |__iperf3:36 |__iperf3:36 |
| numa_node0 | 24 | |__napi/wg7-0:20 |__napi/wg23-0:20 |__napi/wg22-0:19 |__napi/wg8-0:18 | |__iperf3:45 |__iperf3:38 |__iperf3:36 |__iperf3:36 |
| numa_node0 | 32 | |__napi/wg26-0:18 |__napi/wg12-0:17 |__napi/wg8-0:16 |__napi/wg7-0:15 | |__iperf3:58 |__iperf3:41 |__iperf3:38 |__iperf3:36 |
| numa_node1 | 8 | |__napi/wg4-0:28 |__napi/wg2-0:26 |__napi/wg3-0:25 |__napi/wg1-0:25 | |__iperf3:47 |__iperf3:47 |__iperf3:47 |__iperf3:47 |
| numa_node1 | 16 | |__napi/wg2-0:16 |__napi/wg4-0:16 |__napi/wg7-0:16 |__napi/wg0-0:16 | |__kworker/27:4-wg-crypt-wg1:7 |__kworker/6:4-wg-crypt-wg7:7 |__ksoftirqd/24:7 |__ksoftirqd/2:6 |
| numa_node1 | 24 | |__napi/wg0-0:11 |__napi/wg7-0:10 |__pidstat:10 |__napi/wg22-0:10 | - |
| numa_node1 | 32 | |__pidstat:10 |__napi/wg7-0:8 |__napi/wg11-0:7 |__napi/wg31-0:7 | |__iperf3:70 |__iperf3:69 |__iperf3:68 |__iperf3:66 |
| nvme_tcp_balanced_read | 32 | |__fio:100 |__pidstat:11 | - |
| nvme_tcp_balanced_write | 32 | |__fio:100 |__pidstat:11 | - |
| nvme_tcp_far_read | 32 | |__fio:22 |__kworker/0:4H+nvme_tcp_wq:19 |__kworker/0:1H+nvme_tcp_wq:17 |__kworker/116:4-wg-crypt-wg23:14 | - |
| nvme_tcp_far_write | 32 | |__fio:25 |__pidstat:11 |__napi/wg7-0:10 |__napi/wg4-0:9 | - |
| nvme_tcp_near_read | 32 | |__kworker/0:1H-nvme_tcp_wq:19 |__kworker/0:3H-nvme_tcp_wq:19 |__kworker/0:0H-nvme_tcp_wq:18 |__kworker/0:2H-nvme_tcp_wq:18 | - |
| nvme_tcp_near_write | 32 | |__fio:25 |__pidstat:12 |__napi/wg7-0:8 |__napi/wg3-0:8 | - |
| placement | 1 | |__napi/wg0-0:18 |__iperf3:13 |__pidstat:8 |__kworker/1:2-wg-crypt-wg0:6 | |__iperf3:37 |__napi/wg0-0:34 |__pidstat:8 |__kworker/1:0-wg-crypt-wg0:6 |
| placement | 2 | |__iperf3:21 |__iperf3:21 |__napi/wg1-0:19 |__napi/wg0-0:16 | |__iperf3:36 |__iperf3:36 |__napi/wg0-0:35 |__napi/wg1-0:33 |
| placement | 4 | |__napi/wg0-0:33 |__napi/wg1-0:25 |__napi/wg3-0:23 |__napi/wg2-0:23 | |__iperf3:36 |__iperf3:36 |__napi/wg0-0:35 |__napi/wg2-0:35 |
| placement | 8 | |__napi/wg7-0:28 |__napi/wg4-0:27 |__napi/wg5-0:27 |__napi/wg2-0:25 | |__iperf3:43 |__iperf3:43 |__iperf3:43 |__iperf3:42 |
| placement | 12 | |__napi/wg7-0:25 |__napi/wg10-0:25 |__napi/wg5-0:24 |__napi/wg4-0:24 | |__iperf3:64 |__iperf3:64 |__iperf3:63 |__iperf3:63 |
| placement | 16 | |__napi/wg10-0:16 |__napi/wg12-0:16 |__napi/wg5-0:16 |__napi/wg15-0:16 | |__ksoftirqd/5:10 |__ksoftirqd/1:10 |__ksoftirqd/14:9 |__ksoftirqd/3:9 |
| placement | 24 | |__napi/wg22-0:11 |__napi/wg16-0:11 |__pidstat:10 |__napi/wg12-0:9 | |__kworker/1:5-wg-crypt-wg17:10 |__kworker/9:2-wg-crypt-wg10:9 |__kworker/2:2-mm_percpu_wq:9 |__kworker/18:5-mm_percpu_wq:8 |
| placement | 32 | |__pidstat:10 |__napi/wg31-0:7 |__napi/wg20-0:6 |__napi/wg3-0:6 | |__iperf3:64 |__iperf3:58 |__iperf3:52 |__iperf3:52 |
| placement_pinned | 1 | |__napi/wg0-0:18 |__iperf3:17 |__pidstat:9 |__kworker/1:2-wg-crypt-wg0:6 | |__iperf3:45 |__napi/wg0-0:32 |__pidstat:11 |__kworker/1:4-wg-crypt-wg0:5 |
| placement_pinned | 2 | |__iperf3:20 |__napi/wg1-0:19 |__napi/wg0-0:19 |__iperf3:16 | |__iperf3:46 |__iperf3:35 |__napi/wg1-0:33 |__napi/wg0-0:30 |
| placement_pinned | 4 | |__napi/wg3-0:28 |__napi/wg1-0:27 |__iperf3:20 |__napi/wg2-0:20 | |__iperf3:48 |__iperf3:48 |__iperf3:36 |__napi/wg3-0:31 |
| placement_pinned | 8 | |__napi/wg7-0:28 |__napi/wg5-0:26 |__napi/wg2-0:26 |__napi/wg6-0:25 | |__iperf3:40 |__iperf3:39 |__iperf3:35 |__iperf3:35 |
| placement_pinned | 12 | |__napi/wg5-0:29 |__napi/wg8-0:29 |__napi/wg11-0:29 |__napi/wg2-0:28 | |__iperf3:45 |__iperf3:37 |__iperf3:35 |__iperf3:34 |
| placement_pinned | 16 | |__napi/wg12-0:27 |__napi/wg11-0:24 |__napi/wg2-0:23 |__napi/wg13-0:21 | |__iperf3:39 |__iperf3:35 |__iperf3:34 |__iperf3:33 |
| placement_pinned | 24 | |__napi/wg12-0:22 |__napi/wg11-0:21 |__napi/wg2-0:20 |__napi/wg13-0:20 | |__ksoftirqd/8:16 |__ksoftirqd/4:16 |__ksoftirqd/20:16 |__ksoftirqd/28:15 |
| placement_pinned | 32 | |__napi/wg2-0:16 |__napi/wg31-0:15 |__napi/wg1-0:14 |__napi/wg25-0:12 | |__iperf3:53 |__iperf3:39 |__iperf3:39 |__iperf3:38 |
| rps_on | 16 | |__napi/wg0-0:22 |__napi/wg1-0:21 |__napi/wg9-0:20 |__napi/wg8-0:20 | |__iperf3:56 |__iperf3:56 |__iperf3:56 |__iperf3:55 |
| rps_on | 24 | |__napi/wg20-0:21 |__napi/wg9-0:19 |__napi/wg14-0:18 |__napi/wg0-0:17 | |__kworker/123:10-wg-crypt-wg20:17 |__kworker/126:6-wg-crypt-wg20:15 |__ksoftirqd/100:14 |__kworker/121:4-wg-crypt-wg18:14 |
| rps_on | 32 | |__napi/wg31-0:18 |__napi/wg9-0:15 |__napi/wg6-0:15 |__napi/wg19-0:14 | - |
| split | 16 | |__napi/wg9-0:29 |__napi/wg8-0:26 |__napi/wg14-0:26 |__napi/wg4-0:24 | |__iperf3:52 |__iperf3:51 |__iperf3:51 |__iperf3:51 |
| split | 24 | |__napi/wg9-0:27 |__napi/wg14-0:25 |__napi/wg19-0:24 |__napi/wg7-0:21 | |__ksoftirqd/12:13 |__ksoftirqd/101:12 |__iperf3:12 |__ksoftirqd/111:11 |
| split | 32 | |__napi/wg19-0:23 |__napi/wg9-0:20 |__napi/wg29-0:20 |__napi/wg14-0:18 | |__iperf3:24 |__napi/wg16-0:14 |__pidstat:12 |__ksoftirqd/14:10 |
| split64 | 32 | |__napi/wg28-0:26 |__napi/wg9-0:25 |__napi/wg30-0:24 |__napi/wg20-0:24 | |__ksoftirqd/9:13 |__ksoftirqd/96:12 |__ksoftirqd/109:12 |__ksoftirqd/101:11 |
| split64 | 40 | |__napi/wg9-0:24 |__napi/wg28-0:23 |__napi/wg22-0:22 |__napi/wg20-0:21 | |__iperf3:21 |__napi/wg32-0:14 |__ksoftirqd/109:13 |__ksoftirqd/96:13 |
| split64 | 48 | |__napi/wg28-0:19 |__napi/wg30-0:17 |__napi/wg20-0:17 |__napi/wg22-0:16 | - |
| split64 | 64 | |__pidstat:12 |__napi/wg59-0:11 |__napi/wg57-0:11 |__napi/wg62-0:11 | |__iperf3:23 |__napi/wg32-0:15 |__ksoftirqd/109:12 |__ksoftirqd/104:12 |
| uni_rings1024 | 40 | |__napi/wg29-0:20 |__napi/wg31-0:20 |__napi/wg28-0:20 |__napi/wg24-0:19 | |__iperf3:39 |__napi/wg32-0:10 |__kworker/11:1-wg-crypt-wg10:8 |__pidstat:7 |
| uni_ringsmax | 40 | |__napi/wg33-0:20 |__napi/wg31-0:18 |__napi/wg29-0:18 |__napi/wg34-0:18 | |__iperf3:36 |__ksoftirqd/111:11 |__kworker/8:1-wg-crypt-wg32:11 |__kworker/15:3-wg-crypt-wg32:10 |

## Receiver stage cost (core-equivalents: dec=decrypt sirq=napi ksd=ksoftirqd mm=mm_percpu_wq app=iperf3)
| mode | N | Gbps | receiver (node B) stage breakdown |
|------|---|------|-----------------------------------|
| align | 16 | 68.5 | dec=32.1 sirq=0.0 ksd=0.0 mm=0.0 app=5.5 |
| align | 24 | 75.8 | dec=17.3 sirq=0.0 ksd=0.0 mm=0.0 app=0.0 |
| align | 32 | 79.3 | dec=46.5 sirq=0.0 ksd=0.0 mm=0.0 app=10.0 |
| bidir_split | 32 | 117.6 | dec=23.9 sirq=5.6 ksd=1.1 mm=5.9 app=0.0 |
| irqlocal_userN1 | 16 | 75.1 | dec=30.8 sirq=0.0 ksd=0.0 mm=0.0 app=5.5 |
| irqlocal_userN1 | 24 | 77.1 | dec=16.9 sirq=0.0 ksd=0.0 mm=0.0 app=0.0 |
| irqlocal_userN1 | 32 | 79.6 | dec=31.2 sirq=0.0 ksd=0.0 mm=0.0 app=0.0 |
| rps_on | 16 | 73.4 | dec=34.8 sirq=0.0 ksd=0.0 mm=0.0 app=7.6 |
| rps_on | 24 | 77.1 | dec=21.6 sirq=0.0 ksd=0.0 mm=0.0 app=0.0 |
| split | 16 | 74.6 | dec=30.2 sirq=0.0 ksd=0.0 mm=0.0 app=7.1 |
| split | 24 | 94.1 | dec=17.9 sirq=0.0 ksd=0.0 mm=0.0 app=0.1 |
| split | 32 | 95.3 | dec=17.8 sirq=0.0 ksd=0.0 mm=0.0 app=0.3 |
| split64 | 32 | 99.3 | dec=16.7 sirq=1.4 ksd=1.4 mm=3.8 app=0.0 |
| split64 | 40 | 103.2 | dec=22.1 sirq=1.6 ksd=1.4 mm=1.2 app=0.2 |
| split64 | 64 | 103.1 | dec=21.4 sirq=1.9 ksd=1.4 mm=1.6 app=0.2 |
| uni_rings1024 | 40 | 113.0 | dec=12.2 sirq=0.9 ksd=0.8 mm=3.3 app=0.4 |
| uni_ringsmax | 40 | 103.0 | dec=23.8 sirq=1.5 ksd=1.1 mm=6.5 app=0.4 |

## Per-mode summary
- **align:** peak 79.3 Gbps; first knee at N=16 (CPU / crypto)
- **bidir_split:** peak 117.6 Gbps; first knee at N=32 (CPU / crypto)
- **ena_express:** peak 58.7 Gbps; first knee at N=1 (single RX queue (need more tunnels))
- **irqlocal_unpinned:** peak 67.6 Gbps; first knee at N=8 (CPU / crypto)
- **irqlocal_userN0:** peak 56.3 Gbps; first knee at N=16 (CPU / crypto)
- **irqlocal_userN1:** peak 79.6 Gbps; first knee at N=8 (CPU / crypto)
- **numa_node0:** peak 75.7 Gbps; first knee at N=8 (CPU / crypto)
- **numa_node1:** peak 57.3 Gbps; first knee at N=16 (CPU / crypto)
- **nvme_tcp_balanced_read:** peak 57.9 Gbps; first knee at N=32 (CPU / crypto)
- **nvme_tcp_balanced_write:** peak 62.6 Gbps; no knee reached (stayed in the linear region — add tunnels)
- **nvme_tcp_far_read:** peak 59.9 Gbps; no knee reached (stayed in the linear region — add tunnels)
- **nvme_tcp_far_write:** peak 63.6 Gbps; no knee reached (stayed in the linear region — add tunnels)
- **nvme_tcp_near_read:** peak 66.8 Gbps; no knee reached (stayed in the linear region — add tunnels)
- **nvme_tcp_near_write:** peak 58.9 Gbps; no knee reached (stayed in the linear region — add tunnels)
- **nvme_tcp_placement_read:** peak 71.3 Gbps; first knee at N=16 (CPU / crypto)
- **nvme_tcp_placement_write:** peak 66.7 Gbps; first knee at N=32 (CPU / crypto)
- **placement:** peak 59.9 Gbps; first knee at N=1 (single RX queue (need more tunnels))
- **placement_pinned:** peak 77.2 Gbps; first knee at N=1 (single RX queue (need more tunnels))
- **rps_on:** peak 79.0 Gbps; first knee at N=16 (CPU / crypto)
- **split:** peak 95.3 Gbps; first knee at N=16 (CPU / crypto)
- **split64:** peak 103.2 Gbps; first knee at N=32 (CPU / crypto)
- **uni_rings1024:** peak 113.0 Gbps; first knee at N=40 (CPU / crypto)
- **uni_ringsmax:** peak 103.0 Gbps; first knee at N=40 (CPU / crypto)
