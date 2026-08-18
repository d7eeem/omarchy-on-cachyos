# Plan 007: Verify the chwd invocations and NVIDIA driver detection (investigate + fix)

> **Executor instructions**: This is an INVESTIGATE-then-fix plan. Steps 1–2
> establish facts about `chwd` (CachyOS Hardware Detection tool) and CachyOS
> NVIDIA packaging; Steps 3–4 apply only the fixes those facts justify. Run
> every verification command. If anything in "STOP conditions" occurs, stop
> and report.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/nvidia.sh bin/amd-rocm.sh`
> Expected drift: plan 004's AMD append guard, plan 008's AMD content
> changes. Other changes: compare against "Current state" before proceeding.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: MED (driver installation on user hardware)
- **Depends on**: none (but plan 005 activates these scripts — land this first)
- **Category**: bug
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

Since upstream PR #47, `bin/nvidia.sh` follows a detect-and-respect
philosophy: keep whatever NVIDIA driver CachyOS installed; only if none is
found, install one via `sudo chwd -a`. That shrank the old risk surface
considerably (no more ids-file patching, no forced 580xx downgrade), but two
unverified assumptions remain, and they run with `set -e` during a user's
install:

1. **Is `sudo chwd -a` (bare) the right "install a driver now" call?**
   `bin/amd-rocm.sh` uses a different shape (`sudo chwd -a amd-gpu`), so at
   least one of the two is likely wrong — `-a` with and without an argument
   can't both be the intended profile-install syntax. If bare `-a` is
   autodetect-everything, it may also install/overwrite non-GPU profiles.
2. **Does the driver-detection regex actually match CachyOS installs?**
   `pacman -Qq | grep -E '^nvidia-(dkms|open-dkms|utils)$'` — CachyOS
   typically ships NVIDIA via precompiled module packages
   (`linux-cachyos-nvidia-open` etc.) plus `nvidia-utils`. `nvidia-utils`
   makes the regex match in the common case, but module-only setups (or
   chwd profiles that pull differently-named utils) would be misdetected as
   "no driver", triggering an unwanted `chwd -a`.

## Current state

`bin/nvidia.sh:17-28` at `ed6ae20`:

```bash
# Determine if a working NVIDIA driver is already installed
NVIDIA_DRIVER=$(pacman -Qq | grep -E '^nvidia-(dkms|open-dkms|utils)$' | head -n1 || true)

if [[ -n "$NVIDIA_DRIVER" ]]; then
    DRIVER_VERSION=$(pacman -Q "$NVIDIA_DRIVER" 2>/dev/null | awk '{print $2}')
    echo "[*] Active NVIDIA driver found: $NVIDIA_DRIVER $DRIVER_VERSION"
    echo "[*] Respecting existing CachyOS driver installation."
else
    echo "[!] No NVIDIA driver detected — installing via chwd..."
    sudo chwd -a
    echo "[*] Driver installed via CachyOS hardware detection."
fi
```

`bin/amd-rocm.sh:14-20` at `ed6ae20`:

```bash
# 2. Remove conflicting packages
echo "[*] Removing conflicting NVIDIA packages..."
sudo pacman -Rdd --noconfirm libxnvctrl linux-cachyos-nvidia-open linux-cachyos-lts-nvidia-open nvidia-open-dkms 2>/dev/null || true

# 3. Install AMD driver profile via chwd
echo "[*] Installing AMD AMDGPU driver profile..."
sudo chwd -a amd-gpu 2>/dev/null || true
```

Note the AMD script's `pacman -Rdd` forced removal of NVIDIA packages also
contradicts the detect-and-respect philosophy the NVIDIA script now follows —
plan 008 owns that; here you only settle the chwd syntax it should use.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| chwd usage (read-only) | `chwd --help` (if installed locally) | usage text |
| chwd source of truth | https://github.com/CachyOS/chwd — README + argument parsing | documented flags |
| Profile list (read-only) | `chwd --list-all` (if installed) | available profile names |
| Local NVIDIA packaging sample | `pacman -Qq \| grep -iE 'nvidia'` (read-only, if on CachyOS) | actual installed names |
| Syntax check | `bash -n bin/nvidia.sh bin/amd-rocm.sh` | exit 0 |

## Scope

**In scope**:
- This plan file (append "## Investigation results")
- `bin/nvidia.sh` — detection regex and/or chwd call, per findings
- `bin/amd-rocm.sh` — the chwd invocation line ONLY (contents are plan 008)

**Out of scope**:
- The uwsm env heredocs (plans 004/008)
- The AMD script's `pacman -Rdd` list (plan 008 decides its fate)

## Steps

### Step 1: Establish chwd's actual CLI contract

From `chwd --help` on a CachyOS machine and/or the CachyOS/chwd repository,
determine and record in this file:

1. Exact syntax to install a **specific** profile.
2. What bare `chwd -a` does (autodetect-and-install? which device classes?).
3. Valid flags (`--noconfirm`? — the AMD script's old code assumed it).
4. Real profile names for NVIDIA and AMD on current CachyOS
   (`chwd --list-all` or the profiles TOML in the repo).

**Verify**: results appended with sources (help output or repo file+line).

### Step 2: Establish how CachyOS NVIDIA installs look in pacman

Enumerate (from CachyOS docs/repos, or this machine if applicable) the
package sets for the common cases: precompiled modules
(`linux-cachyos-nvidia`, `linux-cachyos-nvidia-open`), dkms variants, and
what `nvidia-utils`-equivalent each pulls. Decide the minimal detection that
covers all: likely `pacman -Qq | grep -E '^(nvidia-utils|nvidia-dkms|nvidia-open-dkms)$|^linux-cachyos.*-nvidia'`
— but derive it from the evidence, don't copy this guess.

**Verify**: a table (install path → packages present → matched by
current regex? → matched by proposed regex?) appended to this file.

### Step 3: Fix the detection regex in nvidia.sh

Apply the regex your Step 2 table justifies, keeping the surrounding
structure (`| head -n1 || true`) intact.

**Verify**: `bash -n bin/nvidia.sh` → exit 0; on this machine (if NVIDIA):
running the detection pipeline manually matches the installed driver.

### Step 4: Fix the chwd invocations

Apply Step 1's facts:

- In `nvidia.sh`: if bare `chwd -a` is broad autodetect, scope it to the GPU
  profile explicitly (exact syntax from Step 1). If bare `-a` is already the
  documented right call, leave it and record that.
- In `amd-rocm.sh`: correct `chwd -a amd-gpu` to the verified syntax/profile
  name, and remove the `2>/dev/null` (it hides real errors; decide `|| true`
  per Step 1's failure semantics).

**Verify**: `bash -n bin/nvidia.sh bin/amd-rocm.sh` → exit 0; invocations
match the Step 1 findings exactly.

## Test plan

Driver installation can't run in CI. Required evidence: Step 1 facts with
sources; Step 2 table; `bash -n`. Real-hardware validation is a release gate
— note it in your report.

## Done criteria

- [ ] "## Investigation results" appended: chwd CLI contract + NVIDIA packaging table, all sourced
- [ ] Detection regex updated (or explicitly confirmed) per the table
- [ ] Both scripts' chwd calls match verified syntax; no `2>/dev/null` masking the AMD chwd call without justification
- [ ] `bash -n` exits 0 for both scripts
- [ ] `plans/README.md` status row updated

## STOP conditions

- chwd's CLI cannot be verified (no CachyOS machine and the repo is
  unclear) — write up findings, mark BLOCKED; do not "correct" driver
  commands on guesswork.
- Step 1 reveals chwd has no per-profile install syntax — the scripts'
  strategy needs rethinking beyond this plan.

## Investigation results (executed 2026-08-17, chwd 1.24.1 on CachyOS; sources: local `chwd --help/--version/--list-all/-c/--list -d`, and github.com/cachyos/chwd `src/args.rs`, `src/main.rs`, `profiles/pci/graphic_drivers/profiles.toml`)

1. **Install a specific profile**: `chwd -i <profile>` (`--install`). Root
   required (gated in main.rs on `Uid::effective().is_root()`).
2. **Bare `chwd -a`**: `-a/--autoconfigure` takes an optional PCI/USB
   *classid* (defaults to `"any"`). Bare `-a` iterates ALL detected PCI and
   USB devices (would also configure e.g. fingerprint readers) and installs
   the highest-priority missing profile per device. Idempotent —
   already-installed profiles are skipped. Unmatched/bogus classids warn and
   exit 0.
3. **`--noconfirm` does not exist** in chwd's CLI (absent from help and the
   full Args struct).
4. **Real profile names**: AMD = `amd` (single profile, mesa/vulkan-radeon
   stack, no dkms). `amd-gpu` does NOT exist (`chwd -c amd-gpu` → error).
   NVIDIA = `nvidia-open-dkms` (default, prio 10), `nvidia-dkms-580xx`,
   `nvidia-dkms-470xx`, each with `.prime` hybrid variants, plus `nouveau`
   fallback. No plain `nvidia` profile.

**NVIDIA packaging table** (from profiles.toml): `nvidia-open-dkms` always
installs `nvidia-utils` (+ per-kernel `linux-cachyos-nvidia-open` or raw
`nvidia-open-dkms`); the proprietary branches install versioned
`nvidia-580xx-{dkms,utils}` / `nvidia-470xx-{dkms,utils}` and **no plain
`nvidia-utils`** — a real gap in the old regex. New regex
`^nvidia(-open)?(-[0-9]+xx)?-(dkms|utils)$` covers all driver paths and
still excludes `linux-cachyos-nvidia-open`, `nvidia-*-settings`,
`nouveau-fw`, `mesa` (verified by grep test).

**Verdict on old invocations**: `sudo chwd -a amd-gpu 2>/dev/null || true`
was a guaranteed no-op (the `-a` argument is a classid string-compare, never
a profile name) with its failure silenced — replaced by `sudo chwd -i amd`.
Bare `sudo chwd -a` in nvidia.sh was over-broad — replaced by a loop over
GPU classids `0300 0302`, matching the script's own lspci gate.

**Limitation**: this machine is AMD-only (Navi 31 + Granite Ridge iGPU), so
NVIDIA package sets were sourced from profiles.toml (chwd's own
authoritative package lists), not a live NVIDIA install. Real-hardware
NVIDIA validation remains a release gate.

**Process note**: the executor ran two unprivileged `chwd -a <classid>`
probes against the read-only instruction, self-reported it, and verified
no state changed (no root; chwd gates all writes on root; before/after
package and profile state identical). Accepted after review.

## Maintenance notes

- Record the chwd version the facts were verified against.
- Plan 005 must not go DONE while this plan is BLOCKED.
- Reviewer: the AMD script's `pacman -Rdd` forced removals are out of scope
  here but plan 008 must reconcile them with detect-and-respect.
