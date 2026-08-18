# Plan 005: Wire the GPU-detection scripts into the installer (finish AMD support)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report. When
> done, update the status row for this plan in `plans/README.md` — unless a
> reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/`
> Plans 002–004, 007, 008 intentionally modify these files — reconcile with
> their diffs. Any *other* drift in `bin/gpu-*.sh` is a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (changes which driver script runs on user hardware)
- **Depends on**: plans/002, plans/003; plans/007 and 008 should land first (they fix the scripts this plan activates)
- **Category**: bug / direction
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

This branch's three local commits added `bin/gpu-detect.sh`,
`bin/gpu-setup.sh`, and `bin/amd-rocm.sh` — but nothing calls them. The
installer copies only `bin/nvidia.sh` into Omarchy's install tree, so AMD
users get zero benefit from the AMD/ROCm script and all three new scripts are
dead code. The README doesn't mention AMD at all. This plan makes the
installer dispatch by detected GPU vendor, completing the feature the local
commits started.

## Current state

`bin/install-omarchy-on-cachyos.sh` at `ed6ae20` (plan 002 changes the paths
to `$SCRIPT_DIR`; plan 003 adds the `test -d` guard):

```bash
# bin/install-omarchy-on-cachyos.sh:104-106
# Replace nvidia.sh with custom CachyOS 580xx Driver Logic
cp ../bin/nvidia.sh install/config/hardware/nvidia.sh
chmod +x install/config/hardware/nvidia.sh
```

(The comment is stale — since upstream PR #47, `bin/nvidia.sh` is
detect-and-respect, not 580xx pinning. Fix the comment while you're here.)

Upstream context (verified 2026-08-17): `basecamp/omarchy` runs
`install/config/hardware/nvidia.sh` during install; there is no AMD hook in
`install/config/hardware/` (only `nvidia.sh` plus vendor-quirk subdirs like
`apple/`, `asus/`). Both our `nvidia.sh` and `amd-rocm.sh` self-guard: each
greps `lspci` for its own vendor and exits 0 when absent.

`bin/gpu-detect.sh` (complete file):

```bash
#!/bin/bash

# Detect NVIDIA (vendor ID: 10de)
if lspci -nn -d 10de: | grep -qE "VGA|3D"; then
    echo "nvidia"
# Detect AMD (vendor ID: 1002)
elif lspci -nn -d 1002: | grep -qE "VGA|3D"; then
    echo "amd"
else
    echo "none"
fi
```

`bin/gpu-setup.sh` (post-plan-002: `$SCRIPT_DIR`-anchored) dispatches
nvidia/amd/none to `nvidia.sh` / `amd-rocm.sh` / skip.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Syntax check | `bash -n bin/install-omarchy-on-cachyos.sh bin/gpu-setup.sh bin/gpu-detect.sh bin/gpu-hook.sh` | exit 0 |
| Detection smoke test | `bash bin/gpu-detect.sh` | exactly one of `nvidia`/`amd`/`none` |
| Patch dry-run | Step 3 harness | dispatch hook + all scripts present in patched tree |

## Scope

**In scope**:
- `bin/install-omarchy-on-cachyos.sh` (the nvidia.sh copy block + its comment + summary echoes)
- `bin/gpu-hook.sh` (create)
- `bin/gpu-setup.sh` (only if Step 2 finds path issues)
- `README.md` (AMD documentation, Step 4)

**Out of scope**:
- Internal logic of `bin/nvidia.sh` (plan 007) and `bin/amd-rocm.sh` (plan 008) — dispatch to them as-is.
- `bin/gpu-detect.sh` hybrid-GPU priority (NVIDIA wins when both present) — keep; document instead.

## Git workflow

- Branch: `advisor/005-gpu-dispatch-integration`
- Imperative capitalized messages (e.g. `Dispatch GPU setup by detected vendor`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Replace the hardcoded nvidia.sh copy with a dispatch bundle

Replace the copy block with:

```bash
# Replace upstream nvidia.sh with a GPU dispatcher
# (NVIDIA detect-and-respect / AMD ROCm — see bin/gpu-setup.sh)
test -d install/config/hardware || { echo "PATCH FAILED: install/config/hardware missing." >&2; exit 1; }
mkdir -p install/config/hardware/omarchy-on-cachyos
cp "$SCRIPT_DIR/gpu-detect.sh" "$SCRIPT_DIR/gpu-setup.sh" "$SCRIPT_DIR/nvidia.sh" "$SCRIPT_DIR/amd-rocm.sh" \
   install/config/hardware/omarchy-on-cachyos/
chmod +x install/config/hardware/omarchy-on-cachyos/*.sh
cp "$SCRIPT_DIR/gpu-hook.sh" install/config/hardware/nvidia.sh
chmod +x install/config/hardware/nvidia.sh
```

Create `bin/gpu-hook.sh` (new file, committed to this repo):

```bash
#!/bin/bash
# Installed as install/config/hardware/nvidia.sh by omarchy-on-cachyos.
# Delegates to the vendor-dispatching setup bundled alongside it.
set -e
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$HOOK_DIR/omarchy-on-cachyos/gpu-setup.sh"
```

Rationale: upstream's installer only invokes `hardware/nvidia.sh`, so the
dispatcher must live at that path; bundling the four scripts beside it keeps
sibling resolution working after the tree is copied to
`~/.local/share/omarchy`.

**Verify**: `bash -n bin/install-omarchy-on-cachyos.sh bin/gpu-hook.sh` →
exit 0; `grep -n "gpu-hook.sh" bin/install-omarchy-on-cachyos.sh` → 1 match;
`grep -n "580xx Driver Logic" bin/install-omarchy-on-cachyos.sh` → no matches.

### Step 2: Confirm gpu-setup.sh resolves siblings correctly

`gpu-setup.sh` must call its siblings via its own `$SCRIPT_DIR` (plan 002's
change). If plan 002 hasn't landed, apply the same `SCRIPT_DIR` pattern here.

**Verify**: `grep -n 'SCRIPT_DIR' bin/gpu-setup.sh` → present;
`grep -n '\./bin/' bin/gpu-setup.sh` → no matches.

### Step 3: Dry-run the patch section against a real clone

Reuse plan 003's harness: clone `basecamp/omarchy` at `$TESTED_OMARCHY_REF`
(from `bin/fetch-omarchy.sh`), run the patch section against it.

**Verify** in the patched tree:
- `test -x install/config/hardware/nvidia.sh`
- `head -3 install/config/hardware/nvidia.sh` shows the gpu-hook header
- `ls install/config/hardware/omarchy-on-cachyos/` → `amd-rocm.sh gpu-detect.sh gpu-setup.sh nvidia.sh`
- `bash install/config/hardware/omarchy-on-cachyos/gpu-detect.sh` → matches this machine's hardware

### Step 4: Document AMD support and update summary echoes

- Summary echo item 4 → "Replaced nvidia.sh with a GPU dispatcher (NVIDIA:
  respect existing CachyOS drivers; AMD: Mesa/ROCm setup)."
- README §4: retitle the NVIDIA-only graphics prerequisite to cover both
  vendors; add 2–4 sentences: AMD systems get Mesa/ROCm via `bin/amd-rocm.sh`;
  on hybrid NVIDIA+AMD systems the NVIDIA path wins (detection order in
  `gpu-detect.sh`); Intel-only systems are untouched. Note: open upstream
  PR #70 rewrites the README's NVIDIA text for the PR #47 behavior — align
  with its framing ("detect and respect") rather than the old 580xx language.

**Verify**: `grep -ni "amd" README.md` → matches exist;
`grep -n "580xx" README.md` → only in historical-notes context, if at all.

## Test plan

Step 3's patched-tree checks are the integration test; the detection smoke
test covers this machine's branch. Driver-script internals are plans 007/008.
Record all outputs.

## Done criteria

- [ ] `bash -n` exits 0 for all touched scripts (incl. new `bin/gpu-hook.sh`)
- [ ] `grep -n 'cp "$SCRIPT_DIR/nvidia.sh" install/config/hardware/nvidia.sh' bin/install-omarchy-on-cachyos.sh` → no matches
- [ ] Step 3 dry-run passes all four checks
- [ ] README documents AMD + hybrid behavior with detect-and-respect framing
- [ ] Only in-scope files (+ `bin/gpu-hook.sh`, `plans/README.md`) modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- Upstream no longer has `install/config/hardware/nvidia.sh` or grew a
  different GPU hook mechanism (check the Step 3 clone first).
- Plan 007 or 008 is BLOCKED in `plans/README.md` — activating unverified
  driver scripts is worse than dead code. Fall back to NVIDIA-only dispatch
  (current behavior) and report.
- `bin/gpu-setup.sh`'s cases don't match `gpu-detect.sh`'s outputs.

## Maintenance notes

- Plan 003's `test -d` guard catches upstream moving its hardware hook.
- Reviewer: the hook must use its *own* location (`BASH_SOURCE`) since it
  executes from `~/.local/share/omarchy`.
- Deferred: Intel iGPU VA-API setup — add a third `gpu-detect.sh` branch when
  there's demand.
