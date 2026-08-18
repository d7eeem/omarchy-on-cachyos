# Plan 003: Fix silently-dead upstream patches, verify every patch, make version selection safe

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/install-omarchy-on-cachyos.sh bin/fetch-omarchy.sh`
> Expected drift: plan 002's path/strict-mode changes. Reconcile with its
> descriptions; other drift is a STOP condition. ALSO run the upstream probe
> in Step 1 — the `basecamp/omarchy` facts here were verified on 2026-08-17
> and upstream moves fast.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (changes what gets installed on user systems)
- **Depends on**: plans/002-fail-fast-and-cwd-safety.md
- **Category**: bug
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

The installer's core mechanism is `sed`-patching a fresh clone of
`basecamp/omarchy`. `sed -i` exits 0 whether or not its pattern matched, so
when upstream edits a patched line, the patch silently stops applying. Direct
verification against upstream master (2026-08-17) shows **5 of the current 12
patch operations are dead or stale today**:

1. All three `bin/omarchy-update-restart` seds — upstream completely rewrote
   that script (it now compares the running kernel against
   `/usr/lib/modules/*/vmlinuz`; it is kernel-name-agnostic and works on
   `linux-cachyos` unpatched). The seds match nothing. **Obsolete: remove.**
2. The mise-activation sed — upstream's `config/uwsm/env` line is now
   `omarchy-cmd-present mise && eval "$(mise activate bash --shims)"` (note
   `--shims`); the sed pattern lacks `--shims` and matches nothing. Net
   effect: **fish users get no mise activation**, which README §3 item 4
   promises. **Broken: replace with a drift-proof approach.**
3. The `alt-bootloaders.sh` removal sed — upstream `install/login/all.sh` no
   longer contains that line. **Obsolete: remove.**
4. The `omarchy-ai-skill.sh` sed (`s/ln -s/ln -sf/`) — upstream already uses
   `ln -sfn`, so the sed now mangles it to `ln -sffn` (harmless to ln, but
   the patch's purpose no longer exists). **Obsolete: remove.**

Additionally, `fetch-omarchy.sh` (PR #48) now lets users clone **any of 5
recent tags or bleeding-edge master**, but the patch set is only ever tested
against one tree — so patch/version mismatch is now a *designed-in* hazard.
This plan (a) removes the dead patches, (b) hard-verifies every surviving
patch so a mismatch aborts loudly instead of silently shipping a broken
system, and (c) marks which version the patch set is tested against.

## Current state

All excerpts from `bin/install-omarchy-on-cachyos.sh` at `ed6ae20`; plan 002
renames paths but leaves the patch bodies intact.

Dead patches to REMOVE:

```bash
# lines 96-99
# Update restart-needed for kernel updates to use cachyos instead of arch
sed -i "s/ | sed 's\/-arch\/\\\.arch\/'//" bin/omarchy-update-restart
sed -i "s/'{print \$2}'/'{print \$2 \"-\" \$1}' | sed 's\/-linux\/\/'/" bin/omarchy-update-restart
sed -i '/linux-cachyos/ ! s/pacman -Q linux/pacman -Q linux-cachyos/' bin/omarchy-update-restart
```

```bash
# lines 108-109
# Fix omarchy-ai-skill.sh symlink to be idempotent on re-runs
sed -i 's/ln -s/ln -sf/' install/config/omarchy-ai-skill.sh
```

```bash
# lines 117-118
# Remove alt-bootloaders.sh source line from install.sh
sed -i '/run_logged \$OMARCHY_INSTALL\/login\/alt-bootloaders\.sh/d' install/login/all.sh
```

Broken patch to REPLACE (lines 154–155) — one long sed rewriting the mise
line in `config/uwsm/env` into a bash/fish conditional. Its replacement text
has its own latent bugs ($SHELL compared to `/bin/fish` while CachyOS uses
`/usr/bin/fish`; fish syntax piped to `source` in an sh-sourced file) — do
not preserve it; Step 3 takes a different approach.

Patches that still apply (verified upstream 2026-08-17) — KEEP, wrapped with
verification in Step 4:

- `sed -i '/tldr/d' install/omarchy-base.packages` (upstream has `tldr` at its own line)
- preflight/post-install `pacman.sh` removal seds (both `run_logged` lines present upstream)
- plymouth.sh and limine-snapper.sh removal seds (both lines present upstream)
- `cp .../nvidia.sh install/config/hardware/nvidia.sh` (target dir exists upstream)
- network.sh heredoc append, lines 123–139 (`install/config/hardware/network.sh` exists upstream)
- walker-elephant.sh sed, lines 141–152 (`install/config/walker-elephant.sh` exists upstream)

The user-facing summary echoes (lines 163–174, items 1–10) must be kept in
sync with whatever you change.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Syntax check | `bash -n bin/install-omarchy-on-cachyos.sh` | exit 0 |
| Upstream probe | Step 1 commands | facts confirmed or STOP |
| Patch dry-run harness | Step 5 | all patches verified in a real clone |

## Scope

**In scope**:
- `bin/install-omarchy-on-cachyos.sh`
- `bin/fetch-omarchy.sh` (Step 2 only: default + tested-version marker)
- `README.md` — only the sentences listed in Step 6

**Out of scope**:
- `bin/nvidia.sh`, `bin/amd-rocm.sh`, `bin/gpu-*.sh` (plans 005/007/008)
- SDDM logic (plan 006), SigLevel value (plan 009)
- `~/.local/share/omarchy` copy/idempotency (plan 004)

## Git workflow

- Branch: `advisor/003-fix-drifted-patches`
- Commit per step; imperative capitalized messages.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Probe upstream for drift since this plan was written

```bash
curl -sL https://raw.githubusercontent.com/basecamp/omarchy/master/config/uwsm/env | grep -n "mise"
curl -sL https://raw.githubusercontent.com/basecamp/omarchy/master/install/login/all.sh
curl -sL https://raw.githubusercontent.com/basecamp/omarchy/master/install/config/omarchy-ai-skill.sh | grep -n "ln -"
for f in install/config/hardware/network.sh install/config/walker-elephant.sh install/preflight/all.sh install/post-install/all.sh; do
  printf "%s: " "$f"; curl -s -o /dev/null -w "%{http_code}\n" "https://raw.githubusercontent.com/basecamp/omarchy/master/$f"; done
```

Expected (2026-08-17): mise line contains `--shims`; login/all.sh lists
plymouth, default-keyring, sddm, hibernation, limine-snapper (no
alt-bootloaders); ai-skill uses `ln -sfn`; all four files return 200. If
materially different, STOP and report.

### Step 2: Record the tested Omarchy version

In `bin/fetch-omarchy.sh`, add near the top:

```bash
# The Omarchy version this repo's CachyOS patches are tested against.
# Update when re-verifying the patch set (see plans/003).
TESTED_OMARCHY_REF="<latest stable tag from Step 1's ls-remote, e.g. v3.1.4>"
```

(Get the tag list with `git ls-remote --tags --refs https://github.com/basecamp/omarchy | awk -F/ '{print $3}' | sort -V | tail -5`.)

In the version menu, annotate the matching entry as `(tested)` when
`${RELEASES[i]}` equals `$TESTED_OMARCHY_REF`, and print one warning line
when the user picks anything else:
`echo "Note: CachyOS patches are tested against $TESTED_OMARCHY_REF; other versions are verified at patch time and will abort on mismatch."`

Also remove `--depth 1` from the tag-clone arguments (`BRANCH_ARGS`): Omarchy
self-updates via git in `~/.local/share/omarchy`, and a shallow clone cripples
that.

**Verify**: `bash -n bin/fetch-omarchy.sh` → exit 0;
`grep -n 'depth 1' bin/fetch-omarchy.sh` → no matches;
`grep -n 'TESTED_OMARCHY_REF' bin/fetch-omarchy.sh` → ≥ 2 matches.

### Step 3: Remove the dead patches and fix mise-for-fish (plus zoxide)

1. Delete the three `omarchy-update-restart` sed lines and their comment.
2. Delete the `omarchy-ai-skill.sh` sed and its comment.
3. Delete the `alt-bootloaders.sh` sed and its comment.
4. Replace the long mise sed with drift-proof fish integration (leave
   upstream's bash mise line untouched):

```bash
# Add fish integrations (upstream only wires bash): mise and zoxide.
# Lives in the user's fish config, so it survives upstream changes to uwsm/env.
FISH_CONF_DIR="$HOME/.config/fish/conf.d"
mkdir -p "$FISH_CONF_DIR"
cat > "$FISH_CONF_DIR/omarchy-on-cachyos.fish" <<'EOF'
# Added by omarchy-on-cachyos
if status is-interactive
    command -q mise; and mise activate fish | source
    command -q zoxide; and zoxide init fish | source
end
EOF
```

The zoxide line adopts open upstream PR #66's finding: Omarchy installs
zoxide as a base package but only initializes it for bash, so `z` is broken
on CachyOS's default fish shell. Writing a single `conf.d` file (rather than
appending to `config.fish`) is idempotent by construction.

5. Update the numbered summary echoes: drop the removed items, add
   "Added mise and zoxide integration for the fish shell."

**Verify**: `bash -n bin/install-omarchy-on-cachyos.sh` → exit 0;
`grep -c "omarchy-update-restart\|alt-bootloaders\|ln -sf" bin/install-omarchy-on-cachyos.sh` → 0;
`grep -c "zoxide" bin/install-omarchy-on-cachyos.sh` → ≥ 1.

### Step 4: Add hard verification to every remaining patch

Add a helper near the top of the installer:

```bash
# Apply a sed patch and hard-fail if the target pattern was not present.
# Usage: patch_or_die <file> <grep-pattern-that-must-exist-BEFORE> <sed-expr>
patch_or_die() {
    local file="$1" pattern="$2" expr="$3"
    grep -q "$pattern" "$file" || {
        echo "PATCH FAILED: pattern '$pattern' not found in $file — the selected Omarchy version does not match this patch set." >&2
        echo "Re-run and select the tested version, or update the patches." >&2
        exit 1
    }
    sed -i "$expr" "$file"
}
```

Convert the five surviving seds:

```bash
patch_or_die install/omarchy-base.packages '^tldr$' '/^tldr$/d'
patch_or_die install/preflight/all.sh 'preflight/pacman\.sh' '/run_logged \$OMARCHY_INSTALL\/preflight\/pacman\.sh/d'
patch_or_die install/login/all.sh 'login/plymouth\.sh' '/run_logged \$OMARCHY_INSTALL\/login\/plymouth\.sh/d'
patch_or_die install/login/all.sh 'login/limine-snapper\.sh' '/run_logged \$OMARCHY_INSTALL\/login\/limine-snapper\.sh/d'
patch_or_die install/post-install/all.sh 'post-install/pacman\.sh' '/run_logged \$OMARCHY_INSTALL\/post-install\/pacman\.sh/d'
```

Guard the file-targeted operations:

```bash
test -d install/config/hardware || { echo "PATCH FAILED: install/config/hardware missing." >&2; exit 1; }
cp "$SCRIPT_DIR/nvidia.sh" install/config/hardware/nvidia.sh
test -f install/config/hardware/network.sh || { echo "PATCH FAILED: network.sh missing." >&2; exit 1; }
# ...existing network.sh heredoc append unchanged...
```

For the walker-elephant sed (it *inserts* rather than substitutes, so a
missing file is the failure mode):
`test -f install/config/walker-elephant.sh || { echo "PATCH FAILED: walker-elephant.sh missing." >&2; exit 1; }`
before the existing sed, and after it verify the insertion landed:
`grep -q "IgnorePkg.*walker" install/config/walker-elephant.sh || { echo "PATCH FAILED: walker pin not applied." >&2; exit 1; }`

**Verify**: `grep -c "patch_or_die" bin/install-omarchy-on-cachyos.sh` → 6
(1 definition + 5 uses); `grep -c "PATCH FAILED" bin/install-omarchy-on-cachyos.sh` → ≥ 5; `bash -n` → exit 0.

### Step 5: Dry-run the patch section against a real clone (both versions)

In a scratch dir, clone upstream twice — once at master, once at
`$TESTED_OMARCHY_REF` — and run the patch section (helper + all patch calls,
with `SCRIPT_DIR` pointing at the real repo's `bin/`) against each.

**Verify** in each patched tree: exit 0; `grep -c '^tldr$'
install/omarchy-base.packages` → 0; plymouth/limine-snapper absent from
`install/login/all.sh`; `pacman.sh` absent from preflight and post-install
`all.sh`; `grep -q "wifi.backend=iwd" install/config/hardware/network.sh`;
`grep -q "IgnorePkg.*walker" install/config/walker-elephant.sh`;
`cmp bin/nvidia.sh <tree>/install/config/hardware/nvidia.sh`. If master fails
where the tag passes, that is *the system working* — note which patch and
keep the tag as tested ref. Clean up the scratch dir.

### Step 6: Update README

- §3 item 4 (Mise): mise and zoxide are activated for fish via
  `~/.config/fish/conf.d/omarchy-on-cachyos.fish`; upstream handles bash.
- §5/version-selection text: add one sentence — patches are tested against
  `$TESTED_OMARCHY_REF`; other selections are verified at patch time and the
  installer aborts on mismatch rather than half-applying.

**Verify**: `grep -n "conf.d\|tested" README.md` → both present.

## Test plan

Step 5 is the test (two real clones, every patch verified, effects grepped).
Record full output. The throwaway harness is not committed.

## Done criteria

- [ ] `bash -n` exits 0 for both in-scope scripts
- [ ] `grep -c "omarchy-update-restart\|alt-bootloaders" bin/install-omarchy-on-cachyos.sh` → 0
- [ ] The `omarchy-ai-skill.sh` sed is gone
- [ ] `grep -c "patch_or_die" bin/install-omarchy-on-cachyos.sh` → 6
- [ ] Fish integration writes one `conf.d` file covering mise + zoxide
- [ ] `fetch-omarchy.sh` has `TESTED_OMARCHY_REF`, no `--depth 1`
- [ ] Step 5 dry-run passes at `$TESTED_OMARCHY_REF` (master result recorded either way)
- [ ] Summary echoes match the actual adjustments
- [ ] Only in-scope files + `plans/README.md` modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- Step 1's probe contradicts this plan's upstream facts.
- Plan 002 hasn't landed (`grep -q "set -euo pipefail" bin/install-omarchy-on-cachyos.sh` fails).
- Any patch fails the Step 5 dry-run at the chosen tested tag — report which
  pattern; do not loosen patterns to force a pass.
- You are tempted to sed `config/uwsm/env` after all — the point of Step 3 is
  to stop depending on upstream's exact quoting.

## Maintenance notes

- The maintenance ritual is now: bump `TESTED_OMARCHY_REF`, re-run the Step 5
  harness, fix any `PATCH FAILED`, ship. Consider committing the harness as
  `bin/verify-patches.sh` in a follow-up (deferred to keep scope tight).
- Open upstream PR #66 (zoxide) overlaps Step 3's fish file — if the
  maintainer merges it, keep exactly one zoxide init (prefer the conf.d file;
  it's idempotent).
- Plan 011 (surviving `omarchy-update`) builds on the tested-ref concept.
- Reviewer: check the summary echoes; users read them as a contract.
