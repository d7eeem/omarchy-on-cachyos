# Plan 008: Align the AMD script with detect-and-respect; fix its packages and env vars

> **AMENDED DURING EXECUTION (2026-08-17)** after the executor's package
> verification stopped on stale premises, all evidence from `pacman -Si` on
> this CachyOS machine:
> - `libva-mesa-driver` no longer exists standalone — `mesa` itself now
>   `Provides: libva-mesa-driver`. Dropped from the install list (mesa is
>   already shipped by chwd's `amd` profile).
> - `mesa-vdpau` no longer exists anywhere — Mesa upstream removed its VDPAU
>   driver entirely (Sept 2025, VA-API-only now). Consequence: this plan's
>   original "add mesa-vdpau + keep VDPAU_DRIVER=radeonsi" idea is dead;
>   **VDPAU support is dropped entirely** (no package, no env var).
> - `rocm-smi` → `rocm-smi-lib` (the name that resolves).
> Final package list: `rocm-core rocm-hip-runtime rocm-smi-lib libva-utils`.
> Final env block: `LIBVA_DRIVER_NAME=radeonsi`, `ROCM_HOME`, `PATH` (plus
> LD_LIBRARY_PATH only if the evidence check requires it).

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/amd-rocm.sh bin/nvidia.sh`
> Expected drift: plan 004's append-guard, plan 007's chwd correction.
> Reconcile; anything else is a STOP condition. `bin/nvidia.sh` is read-only
> reference here — never modified.

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: MED (driver-adjacent changes on user systems)
- **Depends on**: plans/007-chwd-invocation-audit.md; coordinates with plans/004 (guard marker)
- **Category**: bug
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

`bin/amd-rocm.sh` (local commit, activated for users by plan 005) has two
kinds of problems:

**Philosophy mismatch.** Upstream PR #47 rewrote `bin/nvidia.sh` around
"detect and use whatever driver CachyOS has installed; never force-replace."
The AMD script predates that and still opens with
`sudo pacman -Rdd --noconfirm <nvidia packages>` — a forced, dependency-
ignoring removal of NVIDIA packages, which on a hybrid AMD+NVIDIA laptop
(where `gpu-detect.sh` would pick NVIDIA anyway, but a user may run this
script directly) or a misdetected system can break a working setup. The AMD
script should follow the same detect-and-respect shape as its NVIDIA sibling.

**Technical errors.**
1. `export GBM_BACKEND=radeonsi` — `GBM_BACKEND` is an NVIDIA-ecosystem
   variable (`nvidia-drm`); Mesa doesn't use it and `radeonsi` is not a GBM
   backend name. Best case ignored, worst case a GBM loader tries to load a
   nonexistent backend.
2. `libva-vdpau-driver` is the VA-API→VDPAU translation shim — the wrong
   direction for AMD. Mesa provides VA-API natively (`libva-mesa-driver`,
   already listed) and VDPAU natively via `mesa-vdpau` (NOT installed, yet
   `VDPAU_DRIVER=radeonsi` is exported — pointing at a driver that isn't
   there).
3. `rocm-hip-sdk` is the multi-gigabyte development SDK; the runtime
   (`rocm-hip-runtime`, already listed) is what a desktop needs. `rocm-libs`
   likewise is SDK-scale.
4. `HIP_VISIBLE_DEVICES=0` hardcoded — silently hides all but one GPU from
   HIP apps on multi-GPU systems.
5. `LD_LIBRARY_PATH=$ROCM_HOME/lib:...` in the session env — a debugging
   hazard if Arch's ROCm packages already register their libs via
   `/etc/ld.so.conf.d/`.

## Current state

`bin/amd-rocm.sh` at `ed6ae20` (complete relevant excerpts):

```bash
# lines 14-27
# 2. Remove conflicting packages
echo "[*] Removing conflicting NVIDIA packages..."
sudo pacman -Rdd --noconfirm libxnvctrl linux-cachyos-nvidia-open linux-cachyos-lts-nvidia-open nvidia-open-dkms 2>/dev/null || true

# 3. Install AMD driver profile via chwd
echo "[*] Installing AMD AMDGPU driver profile..."
sudo chwd -a amd-gpu 2>/dev/null || true

# 4. Install ROCm stack
echo "[*] Installing ROCm packages..."
sudo pacman -S --needed --noconfirm rocm-core rocm-hip-runtime rocm-hip-sdk rocm-smi rocm-libs libva-mesa-driver libva-vdpau-driver

# 5. Install VA-API utils
sudo pacman -S --needed --noconfirm libva-utils
```

```bash
# lines 29-40 (env block; plan 004 wraps it in a grep guard keyed on '# AMD ROCm')
cat >>$HOME/.config/uwsm/env <<'EOF'

# AMD ROCm
export LIBVA_DRIVER_NAME=radeonsi
export GBM_BACKEND=radeonsi
export HIP_VISIBLE_DEVICES=0
export ROCM_HOME=/opt/rocm
export PATH=$ROCM_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_HOME/lib:$LD_LIBRARY_PATH
export VDPAU_DRIVER=radeonsi
EOF
```

Exemplar for the detect-and-respect shape — `bin/nvidia.sh:17-28` (upstream
PR #47): query `pacman -Qq` for an existing driver; respect it if present;
only call chwd when nothing is installed. Match this structure.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Syntax check | `bash -n bin/amd-rocm.sh` | exit 0 |
| Package existence (read-only) | `pacman -Si mesa-vdpau rocm-hip-runtime rocm-core rocm-smi-lib 2>&1 \| grep -E '^(Name\|error)'` | names resolve (Arch/CachyOS machine) |
| ld.so.conf check (read-only) | `grep -r rocm /etc/ld.so.conf.d/ 2>/dev/null` or rocm-core file list on archlinux.org | evidence for/against LD_LIBRARY_PATH |

## Scope

**In scope**:
- `bin/amd-rocm.sh` — structure (detect-and-respect), package list, env block
- `README.md` — one or two sentences in the AMD section (if plan 005 created it)

**Out of scope**:
- The exact chwd syntax (take plan 007's verified form; if 007 hasn't landed,
  leave the chwd line untouched and note it)
- `bin/nvidia.sh` (reference only)
- The GPU-ID detection at the top of the file

## Git workflow

- Branch: `advisor/008-amd-rocm-corrections`
- Imperative capitalized messages (e.g. `Align AMD script with detect-and-respect driver policy`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Replace the forced NVIDIA removal with detect-and-respect

Delete section 2 (`pacman -Rdd ...`) entirely. In its place, mirror the
NVIDIA script's philosophy comment block: if AMD graphics packages/Mesa are
already functional (they ship by default on CachyOS), there is nothing to
remove — leftover NVIDIA packages on an AMD-only machine are inert, and
removing them by force risks breaking hybrid systems. If plan 007's findings
show the chwd AMD profile install *requires* removing a conflicting NVIDIA
profile, gate the removal on chwd actually reporting a conflict — and use
plain `pacman -R` (not `-Rdd`) so pacman's dependency checks protect the
user.

**Verify**: `grep -c 'pacman -Rdd' bin/amd-rocm.sh` → 0;
`bash -n bin/amd-rocm.sh` → exit 0.

### Step 2: Fix the package list

Replace sections 4–5 with a single install:

```bash
# Install ROCm runtime + Mesa video acceleration
echo "[*] Installing ROCm and VA-API/VDPAU packages..."
sudo pacman -S --needed --noconfirm rocm-core rocm-hip-runtime rocm-smi-lib libva-mesa-driver mesa-vdpau libva-utils
```

Changes: drop `rocm-hip-sdk` and `rocm-libs` (dev SDK scale), drop
`libva-vdpau-driver` (wrong shim), add `mesa-vdpau` (native AMD VDPAU —
makes `VDPAU_DRIVER=radeonsi` true). Verify each name with `pacman -Si`
first; if `rocm-smi-lib` isn't the CachyOS name, keep `rocm-smi` (record
which in your report).

**Verify**: `grep -c 'rocm-hip-sdk\|libva-vdpau-driver\|rocm-libs' bin/amd-rocm.sh` → 0;
`grep -c 'mesa-vdpau' bin/amd-rocm.sh` → 1.

### Step 3: Fix the environment block

Replace the heredoc contents, keeping the `# AMD ROCm` marker line intact
(plan 004's guard keys on it):

```
# AMD ROCm
export LIBVA_DRIVER_NAME=radeonsi
export VDPAU_DRIVER=radeonsi
export ROCM_HOME=/opt/rocm
export PATH=$ROCM_HOME/bin:$PATH
```

Removals with reasons (put in the commit message): `GBM_BACKEND` —
NVIDIA-specific variable, invalid value for Mesa; `HIP_VISIBLE_DEVICES=0` —
hides GPUs on multi-GPU systems; `LD_LIBRARY_PATH` — run the ld.so.conf
check first: if Arch/CachyOS ROCm packages do NOT register `/opt/rocm/lib`
system-wide, keep the line and record why.

**Verify**: `grep -c 'GBM_BACKEND\|HIP_VISIBLE_DEVICES' bin/amd-rocm.sh` → 0;
`grep -c '^# AMD ROCm$' bin/amd-rocm.sh` → 1; `bash -n` → exit 0.

### Step 4: Keep plan 004's guard consistent

If plan 004 landed, confirm its guard still matches the marker. If not
landed, leave the plain append (004 wraps it later).

**Verify**: if the guard is present:
`bash -c 'sed -n "/<<.EOF./,/^EOF/p" bin/amd-rocm.sh | grep -q "^# AMD ROCm$"'` → exit 0.

## Test plan

No framework. Evidence to record: `pacman -Si` output for every final
package name, the ld.so.conf check result, `bash -n`. Real-GPU validation
(`vainfo`, `vdpauinfo`, `rocminfo` on an AMD machine) is a release gate —
note it.

## Done criteria

- [ ] `bash -n bin/amd-rocm.sh` exits 0
- [ ] `grep -c 'pacman -Rdd\|rocm-hip-sdk\|rocm-libs\|libva-vdpau-driver\|GBM_BACKEND\|HIP_VISIBLE_DEVICES' bin/amd-rocm.sh` → 0
- [ ] `mesa-vdpau` in the install list (or a recorded reason it isn't)
- [ ] Every package name verified against `pacman -Si` (output in report)
- [ ] `# AMD ROCm` marker intact
- [ ] Only in-scope files + `plans/README.md` modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- Can't verify package names (not on Arch-compatible machine and
  archlinux.org/packages unreachable) — mark BLOCKED; don't ship unverified
  names.
- Plan 007's results say the chwd AMD install genuinely requires the NVIDIA
  package removal — then Step 1's gating design needs 007's exact conflict
  signal; coordinate rather than guess.

## Maintenance notes

- If users later report HIP apps picking the wrong GPU, the fix is a
  documented opt-in `HIP_VISIBLE_DEVICES` in the README, not a hardcoded
  export.
- Reviewer: no `LD_LIBRARY_PATH` returns unless the ld.so.conf check
  justified it; no forced `-Rdd` returns under any justification.
