# WireGuard saturation — measured results

## Ceilings
- **Raw ENA baseline:** `{"test":"baseline","streams":32,"gbps":208.11797752368577,"tx_pps":2903048}`
- **NVMe read/write:** `{"test":"nvme","devices":16,"read_GBps":52.269935966,"write_GBps":25.87717058}`
- **Memory bandwidth:** `{"test":"membw","triad_GBps":4885.4}`

## Sweep
| mode | N | Gbps | NVMe GB/s | Gbps/busy-core | sender PPS | busy cores (A/B) | SRD tx pkts | binding limit |
|------|---|------|-----------|----------------|-----------|------------------|-------------|---------------|
| ena_express | 1 | 7.9 | - | 0.00 | 111801 | 0/0 | 12 | single RX queue (need more tunnels) |
| ena_express | 2 | 15.7 | - | 0.00 | 222899 | 0/0 | 11 | linear region (unbound) |
| ena_express | 4 | 30.5 | - | 0.00 | 433571 | 0/0 | 17 | linear region (unbound) |
| ena_express | 8 | 52.8 | - | 0.00 | 749688 | 0/0 | 47 | linear region (unbound) |
| ena_express | 12 | 54.1 | - | 27.04 | 765188 | 0/2 | 21 | CPU / crypto |
| ena_express | 16 | 55.9 | - | 55.89 | 793769 | 0/1 | 19 | CPU / crypto |
| ena_express | 24 | 57.6 | - | 57.60 | 813087 | 0/1 | 11418 | CPU / crypto |
| ena_express | 32 | 59.7 | - | 59.70 | 843671 | 0/1 | 3487 | CPU / crypto |
| nvme_tcp_placement_read | 8 | 49.8 | 6.2 | 0.00 | 166455 | 0/0 | 1843513 | linear region (unbound) |
| nvme_tcp_placement_read | 16 | 71.3 | 8.9 | 71.28 | 121509 | 1/0 | 1349375 | CPU / crypto |
| nvme_tcp_placement_read | 32 | 67.1 | 8.4 | 67.13 | 51 | 1/0 | 560 | CPU / crypto |
| nvme_tcp_placement_write | 8 | 51.2 | 6.4 | 0.00 | 576246 | 0/0 | 102709 | linear region (unbound) |
| nvme_tcp_placement_write | 16 | 59.0 | 7.4 | 0.00 | 362288 | 0/0 | 95073 | linear region (unbound) |
| nvme_tcp_placement_write | 32 | 66.7 | 8.3 | 66.67 | 51 | 1/0 | 559 | CPU / crypto |
| placement | 1 | 7.9 | - | 0.00 | 111815 | 0/0 | 0 | single RX queue (need more tunnels) |
| placement | 2 | 15.8 | - | 0.00 | 223592 | 0/0 | 0 | linear region (unbound) |
| placement | 4 | 30.9 | - | 0.00 | 437635 | 0/0 | 0 | linear region (unbound) |
| placement | 8 | 54.7 | - | 0.00 | 777865 | 0/0 | 0 | linear region (unbound) |
| placement | 12 | 56.2 | - | 11.24 | 793637 | 0/5 | 0 | CPU / crypto |
| placement | 16 | 57.3 | - | 57.32 | 813619 | 0/1 | 0 | CPU / crypto |
| placement | 24 | 57.9 | - | 57.87 | 813065 | 0/1 | 0 | CPU / crypto |
| placement | 32 | 60.0 | - | 60.01 | 847649 | 0/1 | 0 | CPU / crypto |

## Per-mode summary
- **ena_express:** peak 59.7 Gbps; first knee at N=1 (single RX queue (need more tunnels))
- **nvme_tcp_placement_read:** peak 71.3 Gbps; first knee at N=16 (CPU / crypto)
- **nvme_tcp_placement_write:** peak 66.7 Gbps; first knee at N=32 (CPU / crypto)
- **placement:** peak 60.0 Gbps; first knee at N=1 (single RX queue (need more tunnels))
