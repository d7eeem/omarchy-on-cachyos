# Handoff — omarchy-on-cachyos

Orientation for whoever (human or agent) picks this project up next.
Written 2026-08-19 at commit `d582373`. User-facing docs live in
`README.md`; the full engineering record lives in `plans/` — this file is
the map between them.

## What this repo is now

A standalone project (fork of `mroboff/omarchy-on-cachyos`, **not**
PR-bound — clone URLs point at `d7eeem/`; `FUNDING.yml` deliberately still
credits the original author). It installs Omarchy 4 on CachyOS with a
per-item debloater:

| Component | Script | State |
|---|---|---|
| Omarchy 4 "Quattro" package wrapper | `bin/install-omarchy-quattro.sh` | Built, dry-run-verified, **not yet run for real anywhere** |
| v4 per-item debloat picker | `bin/debloat-quattro.sh` | Built, mock-verified, needs real-v4 TUI run |
| GPU dispatch | `bin/gpu-detect.sh` → `gpu-setup.sh` → `nvidia.sh`/`amd-rocm.sh` | Working; NVIDIA regex covers 580xx/470xx; AMD is VA-API-only |

## How this got here (compressed history, 2026-08-17 → 08-19)

1. Rebased the fork onto upstream `mroboff` main (14 commits incl. the
   version-selection fetcher and detect-and-respect nvidia.sh), then ran a
   full advisor audit → 14 plans, all executed by subagents in isolated
   worktrees with reviewed diffs. `plans/README.md` has the status table.
2. Load-bearing discoveries (each recorded in the relevant plan file):
   - **Omarchy v4.0.0 removed `install.sh` entirely** — v4 = Arch packages
     (`omarchy`, `omarchy-settings`, `omarchy-keyring`) applied by
     `omarchy-apply-system` from an ISO chroot, `OMARCHY_PATH=/usr/share/omarchy`.
   - v4's post-install **clobbers `/etc/pacman.conf` AND
     `/etc/pacman.d/mirrorlist`**; `omarchy-settings` ships an mkinitcpio
     `HOOKS` override that can **break LUKS boot**; `omarchy` hard-depends
     on limine/plymouth. The wrapper's whole job is reconciling these
     (backups, `zz-cachyos-keep-hooks.conf`, pacman-hook no-op override for
     non-Limine machines, assertion suite).
   - `chwd -a amd-gpu` had been a silenced no-op for its entire life
     (classid vs profile-name confusion); now `chwd -i amd`. Mesa dropped
     VDPAU upstream (Sept 2025) — never re-add `mesa-vdpau`/`VDPAU_DRIVER`.
   - **raw.githubusercontent.com served stale content** for basecamp/omarchy
     during the audit. Verify upstream facts via `git clone`/`ls-remote`;
     tag- or commit-addressed raw URLs are acceptable, branch paths are not.
3. README fully rewritten (Quattro-first, factored sections) 2026-08-19.

## Working conventions (keep these)

- **Follow Omarchy's native interfaces**: the Quattro picker derives its
  candidate lists and removal behavior from the installed Omarchy scripts,
  with MIT attribution in its header.
- **Plan → executor → review**: plans in `plans/NNN-*.md` are self-contained
  for a zero-context executor, stamped with the commit they were written
  against (drift-check first). Executors run in isolated git worktrees; the
  reviewer re-runs done criteria, reads the whole diff, then fast-forwards
  main. Never merge a worktree branch while your shell's cwd is inside it.
- **Lint gate**: `bash -n bin/*.sh` plus `shellcheck --severity=error
  bin/*.sh` (locally via the `gh-runner-runner` docker image; in CI via the
  `Jenkinsfile`). Run it before every push.
- Every state-changing script offers `--dry-run`; privileged ops flow
  through `run`/`run_root`-style helpers so dry-run is enforceable by grep.

## CI / infrastructure (lives OUTSIDE this repo, on the dev machine)

`~/Documents/gh-runner/` — docker compose stack (docker socket mounted =
root-equivalent; secrets in `.env`, unrecoverable, never commit or print):

- 3 ephemeral GitHub Actions runners (`d7eeem/feather`,
  `d7eeem/omarchy-on-cachyos`, `d7eeem/garage-webui-ng`). Note: this repo's
  Actions workflow was **removed** in favor of Jenkins, so `runner-omarchy`
  currently serves nothing — keep or retire deliberately.
- 1 Jenkins inbound agent (`docker-host` → `http://10.10.10.62:8080`,
  websocket). **Currently failing its handshake — almost certainly a stale
  `JENKINS_AGENT_SECRET`**; fix = copy a fresh secret from Manage Jenkins →
  Nodes → docker-host into `.env`, `docker compose up -d jenkins-agent`.
  Until then, pushes queue no CI; the local lint gate is the only check.
- The repo's `Jenkinsfile` is a faithful port of the old lint workflow
  (agent label `docker`; `Dockerfile.agent` already ships shellcheck).

## Release gates (the honest "not done" list)

1. **Real-hardware/VM validation of the Quattro wrapper** — dry-run proved
   the command plan, never the outcome. Wanted: one GRUB+LUKS VM, one
   Limine VM, fresh CachyOS each. The dev machine (Limine+LUKS+AMD) is the
   favorable in-place case — a
   pre-assessed reinstall brief exists at
   `~/Documents/omarchy-reinstall-brief.md` (machine-specific, not in repo).
2. **Real interactive run of `bin/debloat-quattro.sh` on a v4 machine**
   (same VM gate) — enumeration/dry-run are mock-verified only.
3. **Jenkins agent secret** (above) — then confirm a green build on push.
4. Backlog seeds, if wanted: opt-in debloat prompt inside the Quattro
   wrapper (deliberately deferred until gate 1 passes).

## Fast orientation for an agent

Read in this order: this file → `plans/README.md` (status + discoveries
index) → the specific plan file for whatever you're touching (011 = v4
strategy evidence, 012 = wrapper design + execution findings, 007/008 = GPU
evidence trail). Trust the plan files' quoted evidence over memory; re-probe
upstream (`basecamp/omarchy`) via git before relying on any claim about it —
it moves fast and the CDN lies.
