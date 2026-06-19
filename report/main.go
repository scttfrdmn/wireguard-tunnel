// report reads a results/ tree of datapoint.json files and prints an attribution table:
// aggregate Gbps vs tunnel count, measured Gbps-per-busy-core (crypto efficiency), PPS,
// SRD activity, and the *measured* binding limit for each datapoint.
//
//	go run . ../results > ../report.md
package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
)

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

type Datapoint struct {
	N     int     `json:"n_tunnels"`
	Mode  string  `json:"mode"`
	MTU   int     `json:"wg_mtu"`
	Gbps  float64 `json:"throughput_gbps"`
	NodeA Node    `json:"node_a"`
	NodeB Node    `json:"node_b"`
}

// classify returns the measured binding limit for a datapoint.
func classify(d Datapoint) string {
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

func maxf(x, y float64) float64 {
	if x > y {
		return x
	}
	return y
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: report <results-dir> [out.csv]")
		fmt.Fprintln(os.Stderr, "  markdown table -> stdout; if out.csv given, also writes a CSV.")
		os.Exit(1)
	}
	root := os.Args[1]
	csvPath := ""
	if len(os.Args) >= 3 {
		csvPath = os.Args[2]
	}

	var dps []Datapoint
	filepath.Walk(root, func(p string, info os.FileInfo, err error) error {
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

	// optional ceilings
	printCeiling := func(name, file string) {
		if b, e := os.ReadFile(filepath.Join(root, file)); e == nil {
			fmt.Printf("- **%s:** `%s`\n", name, string(trimNL(b)))
		}
	}

	fmt.Println("# WireGuard saturation — measured results")
	fmt.Println()
	fmt.Println("## Ceilings")
	printCeiling("Raw ENA baseline", "baseline.json")
	printCeiling("NVMe read/write", "nvme.json")
	printCeiling("Memory bandwidth", "membw.json")
	fmt.Println()

	fmt.Println("## Sweep")
	fmt.Println("| mode | N | Gbps | Gbps/busy-core | sender PPS | busy cores (A/B) | SRD tx pkts | binding limit |")
	fmt.Println("|------|---|------|----------------|-----------|------------------|-------------|---------------|")
	for _, d := range dps {
		busy := maxf(d.NodeA.BusyCores, d.NodeB.BusyCores)
		eff := 0.0
		if busy > 0 {
			eff = d.Gbps / busy
		}
		fmt.Printf("| %s | %d | %.1f | %.2f | %.0f | %.0f/%.0f | %.0f | %s |\n",
			d.Mode, d.N, d.Gbps, eff, d.NodeA.TxPps,
			d.NodeA.BusyCores, d.NodeB.BusyCores, d.NodeA.SrdTx, classify(d))
	}

	// per-mode summary: peak Gbps and first hard-allowance knee
	fmt.Println("\n## Per-mode summary")
	seen := map[string]bool{}
	for _, d := range dps {
		if seen[d.Mode] {
			continue
		}
		seen[d.Mode] = true
		var peak float64
		var kneeN int
		var kneeLimit string
		for _, e := range dps {
			if e.Mode != d.Mode {
				continue
			}
			if e.Gbps > peak {
				peak = e.Gbps
			}
			lim := classify(e)
			if kneeN == 0 && lim != "linear region (unbound)" {
				kneeN, kneeLimit = e.N, lim
			}
		}
		if kneeN == 0 {
			fmt.Printf("- **%s:** peak %.1f Gbps; no knee reached (stayed in the linear region — add tunnels)\n", d.Mode, peak)
		} else {
			fmt.Printf("- **%s:** peak %.1f Gbps; first knee at N=%d (%s)\n", d.Mode, peak, kneeN, kneeLimit)
		}
	}

	if csvPath != "" {
		if err := writeCSV(csvPath, dps); err != nil {
			fmt.Fprintf(os.Stderr, "csv: %v\n", err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "wrote %s (%d rows)\n", csvPath, len(dps))
	}
}

// writeCSV emits one row per datapoint, mirroring the markdown sweep table plus the raw
// allowance-counter deltas (so the attribution is reproducible from the CSV alone).
func writeCSV(path string, dps []Datapoint) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	w := csv.NewWriter(f)
	defer w.Flush()

	header := []string{
		"mode", "n_tunnels", "wg_mtu", "gbps", "gbps_per_busy_core", "sender_pps",
		"busy_cores_a", "busy_cores_b", "max_core_util_a", "max_core_util_b",
		"softirq_top_share_a", "softirq_top_share_b",
		"bw_out_a", "bw_in_a", "bw_out_b", "bw_in_b", "pps_a", "pps_b",
		"conntrack_a", "conntrack_b", "srd_tx_a", "srd_tx_b", "binding_limit",
	}
	if err := w.Write(header); err != nil {
		return err
	}
	for _, d := range dps {
		busy := maxf(d.NodeA.BusyCores, d.NodeB.BusyCores)
		eff := 0.0
		if busy > 0 {
			eff = d.Gbps / busy
		}
		row := []string{
			d.Mode, itoa(d.N), itoa(d.MTU), ftoa(d.Gbps), ftoa(eff), ftoa(d.NodeA.TxPps),
			ftoa(d.NodeA.BusyCores), ftoa(d.NodeB.BusyCores),
			ftoa(d.NodeA.MaxCoreUtil), ftoa(d.NodeB.MaxCoreUtil),
			ftoa(d.NodeA.SoftirqTopShare), ftoa(d.NodeB.SoftirqTopShare),
			ftoa(d.NodeA.BwOut), ftoa(d.NodeA.BwIn), ftoa(d.NodeB.BwOut), ftoa(d.NodeB.BwIn),
			ftoa(d.NodeA.Pps), ftoa(d.NodeB.Pps),
			ftoa(d.NodeA.Conntrack), ftoa(d.NodeB.Conntrack),
			ftoa(d.NodeA.SrdTx), ftoa(d.NodeB.SrdTx), classify(d),
		}
		if err := w.Write(row); err != nil {
			return err
		}
	}
	return w.Error()
}

func itoa(n int) string     { return strconv.Itoa(n) }
func ftoa(x float64) string { return strconv.FormatFloat(x, 'f', -1, 64) }

func trimNL(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == '\n' || b[len(b)-1] == ' ') {
		b = b[:len(b)-1]
	}
	return b
}
