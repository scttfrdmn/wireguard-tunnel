// plot reads a results/ tree and writes two SVG charts (no external deps):
//
//	throughput.svg  — aggregate Gbps vs tunnel count N, one line per mode, with the
//	                  ~180 Gbps instance wall drawn as a reference.
//	efficiency.svg  — measured Gbps per busy core vs N (per-core ChaCha20 efficiency),
//	                  which should sag as a global ceiling starts to bind.
//
//	go run . ../results [out-dir]      # out-dir defaults to the results dir
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"

	dp "wg-saturate/report/internal/datapoint"
)

const instanceWallGbps = 180.0 // i8ge.48xlarge VPC bandwidth; the expected terminal knee

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: plot <results-dir> [out-dir]")
		os.Exit(1)
	}
	root := os.Args[1]
	outDir := root
	if len(os.Args) >= 3 {
		outDir = os.Args[2]
	}

	dps, _ := dp.Load(root)
	if len(dps) == 0 {
		fmt.Fprintln(os.Stderr, "no datapoints found under "+root+" — run the sweep first")
		os.Exit(1)
	}

	tput := plotXY(dps, func(d dp.Datapoint) float64 { return d.Gbps },
		"Aggregate throughput vs tunnel count", "tunnels (N)", "Gbps", instanceWallGbps)
	if err := os.WriteFile(filepath.Join(outDir, "throughput.svg"), []byte(tput), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "throughput.svg: %v\n", err)
		os.Exit(1)
	}

	eff := plotXY(dps, func(d dp.Datapoint) float64 { return d.GbpsPerBusyCore() },
		"Per-core crypto efficiency vs tunnel count", "tunnels (N)", "Gbps / busy core", 0)
	if err := os.WriteFile(filepath.Join(outDir, "efficiency.svg"), []byte(eff), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "efficiency.svg: %v\n", err)
		os.Exit(1)
	}

	fmt.Fprintf(os.Stderr, "wrote %s and %s (%d modes, %d datapoints)\n",
		filepath.Join(outDir, "throughput.svg"), filepath.Join(outDir, "efficiency.svg"),
		len(dp.Modes(dps)), len(dps))
}

type point struct{ x, y float64 }
type modeSeries struct {
	mode   string
	points []point
}

// plotXY renders one SVG line chart overlaying every mode's (N, accessor) series.
// Input is assumed sorted by (mode, N), as dp.Load returns it.
// If wall>0 it draws a dashed horizontal reference line labeled with the wall value.
func plotXY(dps []dp.Datapoint, accessor func(dp.Datapoint) float64, title, xlab, ylab string, wall float64) string {
	// build per-mode series
	byMode := map[string]*modeSeries{}
	var order []string
	for _, d := range dps {
		s := byMode[d.Mode]
		if s == nil {
			s = &modeSeries{mode: d.Mode}
			byMode[d.Mode] = s
			order = append(order, d.Mode)
		}
		s.points = append(s.points, point{x: float64(d.N), y: accessor(d)})
	}

	// data ranges
	minX, maxX := 0.0, 1.0
	maxY := 0.0
	first := true
	for _, m := range order {
		for _, p := range byMode[m].points {
			if first {
				minX, maxX = p.x, p.x
				first = false
			}
			if p.x < minX {
				minX = p.x
			}
			if p.x > maxX {
				maxX = p.x
			}
			if p.y > maxY {
				maxY = p.y
			}
		}
	}
	if wall > maxY {
		maxY = wall
	}
	maxY *= 1.10 // headroom
	if maxY <= 0 {
		maxY = 1
	}
	if maxX <= minX {
		maxX = minX + 1
	}

	// canvas geometry
	const w, h = 760, 460
	const ml, mr, mt, mb = 70, 180, 50, 60 // margins (wide right margin for the legend)
	plotW := float64(w - ml - mr)
	plotH := float64(h - mt - mb)
	sx := func(x float64) float64 { return float64(ml) + (x-minX)/(maxX-minX)*plotW }
	sy := func(y float64) float64 { return float64(mt) + plotH - (y/maxY)*plotH }

	colors := []string{"#1f77b4", "#d62728", "#2ca02c", "#9467bd", "#ff7f0e", "#17becf", "#8c564b", "#e377c2"}

	var b []byte
	app := func(s string) { b = append(b, s...) }
	app(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" font-family="sans-serif" font-size="12">`, w, h))
	app(fmt.Sprintf(`<rect width="%d" height="%d" fill="white"/>`, w, h))
	app(fmt.Sprintf(`<text x="%d" y="24" font-size="16" font-weight="bold">%s</text>`, ml, esc(title)))

	// axes
	app(fmt.Sprintf(`<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="#333"/>`,
		float64(ml), float64(mt), float64(ml), float64(mt)+plotH))
	app(fmt.Sprintf(`<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="#333"/>`,
		float64(ml), float64(mt)+plotH, float64(ml)+plotW, float64(mt)+plotH))

	// y gridlines + labels (5 ticks)
	for i := 0; i <= 5; i++ {
		yv := maxY * float64(i) / 5
		yy := sy(yv)
		app(fmt.Sprintf(`<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="#eee"/>`,
			float64(ml), yy, float64(ml)+plotW, yy))
		app(fmt.Sprintf(`<text x="%g" y="%g" text-anchor="end">%.0f</text>`, float64(ml)-8, yy+4, yv))
	}
	// x ticks at the actual N values present (union, sorted)
	for _, xv := range xTicks(byMode, order) {
		xx := sx(xv)
		app(fmt.Sprintf(`<text x="%g" y="%g" text-anchor="middle">%.0f</text>`, xx, float64(mt)+plotH+18, xv))
	}
	app(fmt.Sprintf(`<text x="%g" y="%g" text-anchor="middle">%s</text>`, float64(ml)+plotW/2, float64(h)-18, esc(xlab)))
	app(fmt.Sprintf(`<text x="18" y="%g" text-anchor="middle" transform="rotate(-90 18 %g)">%s</text>`,
		float64(mt)+plotH/2, float64(mt)+plotH/2, esc(ylab)))

	// wall reference
	if wall > 0 {
		yy := sy(wall)
		app(fmt.Sprintf(`<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="#999" stroke-dasharray="6 4"/>`,
			float64(ml), yy, float64(ml)+plotW, yy))
		app(fmt.Sprintf(`<text x="%g" y="%g" text-anchor="end" fill="#777">~%.0f Gbps wall</text>`,
			float64(ml)+plotW, yy-5, wall))
	}

	// series
	for i, m := range order {
		c := colors[i%len(colors)]
		pts := byMode[m].points
		var path []byte
		for j, p := range pts {
			cmd := "L"
			if j == 0 {
				cmd = "M"
			}
			path = append(path, fmt.Sprintf("%s%g %g ", cmd, sx(p.x), sy(p.y))...)
		}
		app(fmt.Sprintf(`<path d="%s" fill="none" stroke="%s" stroke-width="2"/>`, string(path), c))
		for _, p := range pts {
			app(fmt.Sprintf(`<circle cx="%g" cy="%g" r="3" fill="%s"/>`, sx(p.x), sy(p.y), c))
		}
		// legend entry
		ly := float64(mt) + 8 + float64(i)*18
		lx := float64(ml) + plotW + 16
		app(fmt.Sprintf(`<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="2"/>`, lx, ly, lx+18, ly, c))
		app(fmt.Sprintf(`<text x="%g" y="%g">%s</text>`, lx+24, ly+4, esc(m)))
	}

	app(`</svg>`)
	return string(b)
}

func xTicks(byMode map[string]*modeSeries, order []string) []float64 {
	seen := map[float64]bool{}
	var xs []float64
	for _, m := range order {
		for _, p := range byMode[m].points {
			if !seen[p.x] {
				seen[p.x] = true
				xs = append(xs, p.x)
			}
		}
	}
	sort.Float64s(xs)
	return xs
}

func esc(s string) string {
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '&':
			out = append(out, "&amp;"...)
		case '<':
			out = append(out, "&lt;"...)
		case '>':
			out = append(out, "&gt;"...)
		default:
			out = append(out, s[i])
		}
	}
	return string(out)
}
