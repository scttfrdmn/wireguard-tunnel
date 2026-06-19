# WireGuard saturation — measured results

## Ceilings
- **Raw ENA baseline:** `{"test":"baseline","streams":32,"gbps":205.71669806306008,"tx_pps":2867863}`
- **NVMe read/write:** `{"test":"nvme","devices":16,"read_GBps":52.260344373,"write_GBps":25.876960991}`
- **Memory bandwidth:** `{"test":"membw","triad_GBps":5551.1}`

## Sweep
| mode | N | Gbps | NVMe GB/s | core-equiv (A/B) | Gbps/core | max util (A/B) | SRD tx | binding limit |
|------|---|------|-----------|------------------|-----------|----------------|--------|---------------|
| ena_express | 1 | 7.9 | - | 1.9/3.5 | 2.23 | 10/44 | 15 | single RX queue (need more tunnels) |
| ena_express | 2 | 15.7 | - | 3.7/7.0 | 2.25 | 23/78 | 42 | linear region (unbound) |
| ena_express | 4 | 27.8 | - | 7.2/13.3 | 2.10 | 26/84 | 39 | linear region (unbound) |
| ena_express | 8 | 45.5 | - | 12.1/24.9 | 1.83 | 26/86 | 51 | linear region (unbound) |
| ena_express | 12 | 54.7 | - | 14.4/36.3 | 1.51 | 21/98 | 306 | CPU / crypto |
| ena_express | 16 | 55.5 | - | 14.2/42.5 | 1.31 | 20/100 | 12627 | CPU / crypto |
| ena_express | 24 | 55.7 | - | 14.0/51.8 | 1.08 | 18/100 | 27530 | CPU / crypto |
| ena_express | 32 | 58.7 | - | 14.7/57.6 | 1.02 | 19/98 | 8795 | CPU / crypto |
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

## Hot threads during load (top by %CPU)
| mode | N | node A (sender/encrypt) | node B (receiver/decrypt) |
|------|---|-------------------------|---------------------------|
| ena_express | 1 | |__iperf3:21 |__napi/wg0-0:16 |__pidstat:10 |__kworker/1:1-wg-crypt-wg0:6 | |__iperf3:38 |__napi/wg0-0:38 |__pidstat:11 |__kworker/1:3-wg-crypt-wg0:8 |
| ena_express | 2 | |__napi/wg1-0:23 |__napi/wg0-0:15 |__iperf3:15 |__iperf3:15 | |__iperf3:36 |__iperf3:36 |__napi/wg0-0:33 |__napi/wg1-0:32 |
| ena_express | 4 | |__napi/wg1-0:24 |__napi/wg3-0:23 |__napi/wg2-0:22 |__napi/wg0-0:22 | |__iperf3:36 |__iperf3:36 |__napi/wg0-0:34 |__napi/wg2-0:33 |
| ena_express | 8 | |__napi/wg4-0:28 |__napi/wg7-0:27 |__napi/wg2-0:27 |__napi/wg5-0:26 | |__iperf3:44 |__iperf3:44 |__iperf3:44 |__iperf3:44 |
| ena_express | 12 | |__napi/wg10-0:26 |__napi/wg7-0:24 |__napi/wg2-0:22 |__napi/wg5-0:22 | |__iperf3:64 |__iperf3:64 |__iperf3:64 |__iperf3:63 |
| ena_express | 16 | |__napi/wg10-0:17 |__napi/wg5-0:16 |__napi/wg12-0:15 |__napi/wg15-0:15 | |__ksoftirqd/1:7 |__ksoftirqd/25:6 |__ksoftirqd/5:6 |__ksoftirqd/20:6 |
| ena_express | 24 | |__pidstat:10 |__napi/wg22-0:10 |__napi/wg10-0:10 |__napi/wg16-0:9 | |__kworker/22:3-wg-crypt-wg21:8 |__kworker/4:1-wg-crypt-wg3:8 |__kworker/1:3-wg-crypt-wg18:8 |__kworker/1:0-wg-crypt-wg5:7 |
| ena_express | 32 | |__pidstat:10 |__napi/wg31-0:7 |__napi/wg20-0:7 |__napi/wg18-0:6 | |__iperf3:61 |__iperf3:59 |__iperf3:54 |__iperf3:54 |
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

## Per-mode summary
- **ena_express:** peak 58.7 Gbps; first knee at N=1 (single RX queue (need more tunnels))
- **nvme_tcp_placement_read:** peak 71.3 Gbps; first knee at N=16 (CPU / crypto)
- **nvme_tcp_placement_write:** peak 66.7 Gbps; first knee at N=32 (CPU / crypto)
- **placement:** peak 59.9 Gbps; first knee at N=1 (single RX queue (need more tunnels))
- **placement_pinned:** peak 77.2 Gbps; first knee at N=1 (single RX queue (need more tunnels))
