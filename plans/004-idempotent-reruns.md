# Plan 004: Make re-running the installer safe (remaining idempotency gaps)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report. When
> done, update the status row for this plan in `plans/README.md` — unless a
> reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/install-omarchy-on-cachyos.sh bin/amd-rocm.sh bin/fetch-omarchy.sh`
> Expected drift: plans 002/003. Reconcile with their descriptions; anything
> else is a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/002-fail-fast-and-cwd-safety.md; coordinate with 003 (patch_or_die interacts with re-patching)
- **Category**: bug
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

Installs fail midway on real machines and users re-run the script. Upstream
has already fixed two of the original re-run hazards (the `[omarchy]`
pacman.conf append is now guarded, and `nvidia.sh` guards its uwsm-env append
— both landed in the commits this branch was rebased onto). Three gaps
remain:

1. **`bin/amd-rocm.sh` still appends its env block unconditionally** to
   `~/.config/uwsm/env` — duplicates accumulate on every run, and the target
   directory is never created (`mkdir -p` missing; unquoted `$HOME` redirect
   too).
2. **`cp -r . ~/.local/share/omarchy` merges over any previous install.**
   Open upstream PR #56 reports actual failures from this: permission-denied
   errors on re-copy over a prior run's files, plus stale files from older
   Omarchy versions surviving the merge. The stale tree must be removed
   first.
3. **The "keep existing files" path in `fetch-omarchy.sh` re-patches an
   already-patched tree.** If the user declines the clean-up prompt, the
   installer proceeds to run all sed patches *again* on a tree that was
   already patched by the previous run. With plan 003's `patch_or_die`, that
   now aborts with a confusing "upstream drifted" message; the honest
   behavior is to tell the user a patched tree can't be reused.

## Current state

`bin/amd-rocm.sh:29-40` at `ed6ae20`:

```bash
# 6. Add AMD ROCm environment variables for UWSM
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

(Plan 008 rewrites the block's *contents*; this plan only wraps it. The
marker line `# AMD ROCm` must be the guard key — if 008 landed first, keep
its contents and add only the guard.)

Exemplar to copy — `bin/nvidia.sh:34-49` already does this correctly
(upstream PR #47):

```bash
mkdir -p "$HOME/.config/uwsm"
if ! grep -q "GBM_BACKEND=nvidia-drm" "$HOME/.config/uwsm/env" 2>/dev/null; then
    cat >>"$HOME/.config/uwsm/env" <<'EOF'
...
EOF
    echo "[*] NVIDIA environment variables written to ~/.config/uwsm/env"
else
    echo "[*] NVIDIA environment variables already present."
fi
```

`bin/install-omarchy-on-cachyos.sh:157-160` at `ed6ae20`:

```bash
# Copy omarchy installation files to ~/.local/share/omarchy
mkdir -p ~/.local/share/omarchy
cp -r . ~/.local/share/omarchy
cd ~/.local/share/omarchy
```

`bin/fetch-omarchy.sh:43-47` ("keep existing" path):

```bash
    else
        echo "Proceeding with existing files in $TARGET_DIR..."
        # If user chooses not to delete, we should skip the clone but continue the script
        exit 0
    fi
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Syntax check | `bash -n bin/install-omarchy-on-cachyos.sh bin/amd-rocm.sh bin/fetch-omarchy.sh` | exit 0 |
| Guard simulation | Step 4 | second append skipped |

## Scope

**In scope**:
- `bin/amd-rocm.sh` — env-append guard only (not the block's contents)
- `bin/install-omarchy-on-cachyos.sh` — stale `~/.local/share/omarchy` handling
- `bin/fetch-omarchy.sh` — honest messaging on the keep-existing path

**Out of scope**:
- Env block contents / package lists (plan 008), chwd calls (plan 007)
- pacman.conf and nvidia.sh guards — already correct upstream; do not touch
- SigLevel (plan 009)

## Git workflow

- Branch: `advisor/004-idempotent-reruns`
- Imperative capitalized messages (e.g. `Guard AMD env append against re-runs`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Guard the AMD env append

Rework `bin/amd-rocm.sh`'s section 6 to match the `nvidia.sh` exemplar
exactly in structure: `mkdir -p "$HOME/.config/uwsm"`, then a
`grep -q '^# AMD ROCm$' "$HOME/.config/uwsm/env" 2>/dev/null` guard around
the (unchanged) heredoc, with the quoted `"$HOME/..."` redirect and the
written/already-present echo pair.

**Verify**: `bash -n bin/amd-rocm.sh` → exit 0;
`grep -n 'mkdir -p "$HOME/.config/uwsm"' bin/amd-rocm.sh` → 1 match;
heredoc contents unchanged (`git diff bin/amd-rocm.sh` shows no lines inside
the `EOF` block modified).

### Step 2: Remove the stale install tree before copying

Replace the copy block in the installer with:

```bash
# Copy omarchy installation files to ~/.local/share/omarchy
# Remove any previous install tree first: cp -r over an old tree merges
# stale files and can fail on permissions (upstream PR #56).
if [ -d "$HOME/.local/share/omarchy" ]; then
    echo "Removing previous ~/.local/share/omarchy..."
    rm -rf "$HOME/.local/share/omarchy"
fi
mkdir -p "$HOME/.local/share/omarchy"
cp -r . "$HOME/.local/share/omarchy"
cd "$HOME/.local/share/omarchy"
```

**Verify**: `grep -n 'previous ~/.local/share/omarchy\|Removing previous' bin/install-omarchy-on-cachyos.sh` → 1 match; `bash -n` → exit 0.

### Step 3: Make the keep-existing path honest about patching

In `bin/fetch-omarchy.sh`, change the keep-existing message to state the
consequence, since the installer will re-patch (and, after plan 003, abort on
an already-patched tree):

```bash
    else
        echo "Keeping existing files in $TARGET_DIR."
        echo "Note: if this tree was already patched by a previous run, the"
        echo "installer's patch verification will abort. Choose 'y' for a clean"
        echo "clone if the previous run got past the patching stage."
        exit 0
    fi
```

**Verify**: `grep -n "already patched" bin/fetch-omarchy.sh` → 1 match;
`bash -n bin/fetch-omarchy.sh` → exit 0.

### Step 4: Simulate double-run of the AMD guard (no sudo, no system changes)

```bash
T=$(mktemp -d); export FAKE_HOME="$T"
for i in 1 2; do
  mkdir -p "$FAKE_HOME/.config/uwsm"
  if ! grep -q '^# AMD ROCm$' "$FAKE_HOME/.config/uwsm/env" 2>/dev/null; then
    printf '\n# AMD ROCm\nexport LIBVA_DRIVER_NAME=radeonsi\n' >> "$FAKE_HOME/.config/uwsm/env"
    echo "append $i"
  else
    echo "skip $i"
  fi
done
grep -c '^# AMD ROCm$' "$FAKE_HOME/.config/uwsm/env"; rm -rf "$T"
```

**Verify**: prints `append 1`, `skip 2`, then `1`.

## Test plan

Step 4's simulation is the test for the guard; Steps 2–3 are verified by
grep + `bash -n` (their behavior only manifests on a real re-run, which is a
release gate — note that in your report).

## Done criteria

- [ ] `bash -n` exits 0 for all three in-scope files
- [ ] AMD env append matches the nvidia.sh guard structure (mkdir -p, grep guard, quoted redirect)
- [ ] Stale `~/.local/share/omarchy` is removed before copy
- [ ] fetch-omarchy.sh keep-existing path explains the re-patch consequence
- [ ] Heredoc contents unchanged in amd-rocm.sh (wrapping only)
- [ ] Step 4 simulation passes
- [ ] Only in-scope files + `plans/README.md` modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- Plan 002 hasn't landed (no `set -euo pipefail` in the installer) — the
  `rm -rf "$HOME/.local/share/omarchy"` must never run with an unset-variable
  risk; `set -u` is the backstop this plan assumes.
- `bin/amd-rocm.sh` no longer contains the `# AMD ROCm` marker (plan 008
  restructured it) — use whatever stable marker 008 left, and update this
  plan's guard pattern accordingly in the same commit.

## Maintenance notes

- Plan 008 rewrites the AMD env contents — whichever of 004/008 lands second
  must keep guard-marker and contents consistent.
- Reviewer: scrutinize the `rm -rf` targets — both are fixed literals under
  `$HOME`, never derived from user input; keep it that way.
- Deferred: uninstall/rollback support — out of scope for an installer of
  this size.
