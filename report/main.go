// report reads a results/ tree of datapoint.json files and prints an attribution table:
// aggregate Gbps vs tunnel count, measured Gbps-per-busy-core (crypto efficiency), PPS,
// SRD activity, and the *measured* binding limit for each datapoint.
//
//	go run . ../results [out.csv] > ../report.md
package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	dp "wg-saturate/report/internal/datapoint"
)

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

	dps, _ := dp.Load(root)

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
	fmt.Println("| mode | N | Gbps | NVMe GB/s | Gbps/busy-core | sender PPS | busy cores (A/B) | SRD tx pkts | binding limit |")
	fmt.Println("|------|---|------|-----------|----------------|-----------|------------------|-------------|---------------|")
	for _, d := range dps {
		nvme := "-"
		if d.NvmeGBs > 0 {
			nvme = fmt.Sprintf("%.1f", d.NvmeGBs)
		}
		fmt.Printf("| %s | %d | %.1f | %s | %.2f | %.0f | %.0f/%.0f | %.0f | %s |\n",
			d.Mode, d.N, d.Gbps, nvme, d.GbpsPerBusyCore(), d.NodeA.TxPps,
			d.NodeA.BusyCores, d.NodeB.BusyCores, d.NodeA.SrdTx, dp.Classify(d))
	}

	// per-mode summary: peak Gbps and first hard-allowance knee
	fmt.Println("\n## Per-mode summary")
	for _, mode := range dp.Modes(dps) {
		var peak float64
		var kneeN int
		var kneeLimit string
		for _, e := range dps {
			if e.Mode != mode {
				continue
			}
			if e.Gbps > peak {
				peak = e.Gbps
			}
			lim := dp.Classify(e)
			if kneeN == 0 && lim != "linear region (unbound)" {
				kneeN, kneeLimit = e.N, lim
			}
		}
		if kneeN == 0 {
			fmt.Printf("- **%s:** peak %.1f Gbps; no knee reached (stayed in the linear region — add tunnels)\n", mode, peak)
		} else {
			fmt.Printf("- **%s:** peak %.1f Gbps; first knee at N=%d (%s)\n", mode, peak, kneeN, kneeLimit)
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
func writeCSV(path string, dps []dp.Datapoint) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	w := csv.NewWriter(f)
	defer w.Flush()

	header := []string{
		"mode", "n_tunnels", "wg_mtu", "gbps", "nvme_GBps", "rw", "gbps_per_busy_core", "sender_pps",
		"busy_cores_a", "busy_cores_b", "max_core_util_a", "max_core_util_b",
		"softirq_top_share_a", "softirq_top_share_b",
		"bw_out_a", "bw_in_a", "bw_out_b", "bw_in_b", "pps_a", "pps_b",
		"conntrack_a", "conntrack_b", "srd_tx_a", "srd_tx_b", "binding_limit",
	}
	if err := w.Write(header); err != nil {
		return err
	}
	for _, d := range dps {
		row := []string{
			d.Mode, itoa(d.N), itoa(d.MTU), ftoa(d.Gbps), ftoa(d.NvmeGBs), d.RW, ftoa(d.GbpsPerBusyCore()), ftoa(d.NodeA.TxPps),
			ftoa(d.NodeA.BusyCores), ftoa(d.NodeB.BusyCores),
			ftoa(d.NodeA.MaxCoreUtil), ftoa(d.NodeB.MaxCoreUtil),
			ftoa(d.NodeA.SoftirqTopShare), ftoa(d.NodeB.SoftirqTopShare),
			ftoa(d.NodeA.BwOut), ftoa(d.NodeA.BwIn), ftoa(d.NodeB.BwOut), ftoa(d.NodeB.BwIn),
			ftoa(d.NodeA.Pps), ftoa(d.NodeB.Pps),
			ftoa(d.NodeA.Conntrack), ftoa(d.NodeB.Conntrack),
			ftoa(d.NodeA.SrdTx), ftoa(d.NodeB.SrdTx), dp.Classify(d),
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
