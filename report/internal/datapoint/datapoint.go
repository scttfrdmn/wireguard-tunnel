// Package datapoint loads and classifies the per-datapoint JSON the measurement scripts
// emit (results/<mode>/N<n>/datapoint.json), shared by the report and plot binaries.
package datapoint

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
)

// Node is one node's slice of a datapoint: CPU/softirq saturation and the ENA allowance
// counter deltas measured over the load window by collect.sh.
type Node struct {
	BusyCores       float64 `json:"busy_cores"`
	MaxCoreUtil     float64 `json:"max_core_util"`
	SoftirqTopShare float64 `json:"softirq_rx_top_core_share"`
	BwIn            float64 `json:"bw_in_allowance_exceeded"`
	BwOut           float64 `json:"bw_out_allowance_exceeded"`
	Pps             float64 `json:"pps_allowance_exceeded"`
	Conntrack       float64 `json:"conntrack_allowance_exceeded"`
	SrdTx           float64 `json:"ena_srd_tx_pkts"`
	SrdEligibleTx   float64 `json:"ena_srd_eligible_tx_pkts"`
	SrdUtil         float64 `json:"ena_srd_resource_utilization"`
	TxPps           float64 `json:"tx_pps"`
}

// Datapoint is one sweep point: N tunnels at a given mode/MTU and the resulting throughput,
// with both nodes' attribution counters.
type Datapoint struct {
	N       int     `json:"n_tunnels"`
	Mode    string  `json:"mode"`
	MTU     int     `json:"wg_mtu"`
	Gbps    float64 `json:"throughput_gbps"`
	NvmeGBs float64 `json:"nvme_GBps"` // set only by measure-nvme-tcp.sh; 0 for the iperf sweep
	RW      string  `json:"rw"`        // "read"/"write" for nvme-tcp datapoints, else ""
	NodeA   Node    `json:"node_a"`
	NodeB   Node    `json:"node_b"`
}

// Classify returns the measured binding limit for a datapoint, from counter deltas on both
// nodes — never inferred. Order matters: a hard allowance trumps a soft CPU/queue signal.
func Classify(d Datapoint) string {
	a, b := d.NodeA, d.NodeB
	switch {
	case a.BwOut > 0 || b.BwIn > 0 || a.BwIn > 0 || b.BwOut > 0:
		return "bandwidth allowance (instance wall)"
	case a.Pps > 0 || b.Pps > 0:
		return "PPS allowance (use jumbo)"
	case a.Conntrack > 0 || b.Conntrack > 0:
		return "conntrack allowance"
	case a.MaxCoreUtil > 95 || b.MaxCoreUtil > 95:
		return "CPU / crypto"
	case a.SoftirqTopShare > 0.5 || b.SoftirqTopShare > 0.5:
		return "single RX queue (need more tunnels)"
	default:
		return "linear region (unbound)"
	}
}

// BusyCores returns the larger of the two nodes' busy-core counts (the sender and receiver
// crypto cost differ; the binding side is the bigger one).
func (d Datapoint) BusyCores() float64 {
	if d.NodeA.BusyCores > d.NodeB.BusyCores {
		return d.NodeA.BusyCores
	}
	return d.NodeB.BusyCores
}

// GbpsPerBusyCore is the measured per-core crypto efficiency; 0 if no busy cores recorded.
func (d Datapoint) GbpsPerBusyCore() float64 {
	if bc := d.BusyCores(); bc > 0 {
		return d.Gbps / bc
	}
	return 0
}

// Load walks a results tree and returns every datapoint.json, sorted by (mode, N).
func Load(root string) ([]Datapoint, error) {
	var dps []Datapoint
	err := filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || filepath.Base(p) != "datapoint.json" {
			return nil
		}
		b, e := os.ReadFile(p)
		if e != nil {
			return nil
		}
		var d Datapoint
		if json.Unmarshal(b, &d) == nil && d.N > 0 {
			dps = append(dps, d)
		}
		return nil
	})
	sort.Slice(dps, func(i, j int) bool {
		if dps[i].Mode != dps[j].Mode {
			return dps[i].Mode < dps[j].Mode
		}
		return dps[i].N < dps[j].N
	})
	return dps, err
}

// Modes returns the distinct modes present, in first-seen (sorted) order.
func Modes(dps []Datapoint) []string {
	seen := map[string]bool{}
	var out []string
	for _, d := range dps {
		if !seen[d.Mode] {
			seen[d.Mode] = true
			out = append(out, d.Mode)
		}
	}
	return out
}
