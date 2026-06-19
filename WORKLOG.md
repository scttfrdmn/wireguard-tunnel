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

### Next (pending user go-ahead; Phases 2-4 still offline until live run)
- Phase 2: real NVMe→NVMe over nvme-tcp native multipath; plots from results/.
- Scaffold `wireguard-100gbps-writeup.md` with explicit "not yet measured" rows.
- Phase 3: terraform Spot option + written cost estimate.
- Phase 4 (GATED on "go ahead, spend"): apply → run matrix → fold measured numbers in.
