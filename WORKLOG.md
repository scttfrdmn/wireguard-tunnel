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
