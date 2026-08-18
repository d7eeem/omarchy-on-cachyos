# Plan 002: Unify the Omarchy working-tree path and make the installer fail fast

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/install-omarchy-on-cachyos.sh bin/fetch-omarchy.sh bin/gpu-setup.sh .gitignore`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (changes where the Omarchy working tree lives)
- **Depends on**: plans/001-shellcheck-ci-baseline.md
- **Category**: bug
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

The installer currently has a **live path mismatch that breaks the happy
path**: `bin/fetch-omarchy.sh` (upstream PR #48) clones Omarchy into
`$SCRIPT_DIR/../../omarchy` — a *sibling of the repo* — while the installer
still runs `cd ../omarchy`, which from `bin/` resolves to a directory *inside*
the repo that the fetch never created. Because the installer has no `set -e`
and doesn't check the `cd`, every subsequent `sed`/`cp` then runs against the
wrong tree (worst case: the repo's own `bin/` directory), and the script ends
by copying the wrong content to `~/.local/share/omarchy`.

This is not theoretical: upstream's open PR queue confirms users hit it —
PR #72 ("use absolute Omarchy path after fetch") describes exactly this
mismatch, and PRs #50, #51, #56, #59, #69, #71 all independently patch
variants of the same CWD fragility. This plan fixes the mismatch once,
coherently: one shared path definition, `set -euo pipefail`, and error-checked
navigation. (If the maintainer later merges one of those PRs, this plan's
result should supersede or match it — see Maintenance notes.)

## Current state

`bin/install-omarchy-on-cachyos.sh` (no `set -e` anywhere):

```bash
# bin/install-omarchy-on-cachyos.sh:9-26
# Fetch Omarchy from repo
echo "Fetching Omarchy source..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_DIR="$SCRIPT_DIR/../../omarchy"

if [ -f "./fetch-omarchy.sh" ]; then
    chmod +x ./fetch-omarchy.sh
    ./fetch-omarchy.sh
else
    # Fallback if script is missing
    echo "fetch-omarchy.sh not found, falling back to default clone..."
    git clone https://www.github.com/basecamp/omarchy "$OMARCHY_DIR"
fi

if [ ! -d "$OMARCHY_DIR" ]; then
    echo "Error: Failed to fetch Omarchy source at $OMARCHY_DIR"
    exit 1
fi
```

```bash
# bin/install-omarchy-on-cachyos.sh:90-91
# Navigate to Omarchy install scripts
cd ../omarchy
```

```bash
# bin/install-omarchy-on-cachyos.sh:104-106
# Replace nvidia.sh with custom CachyOS 580xx Driver Logic
cp ../bin/nvidia.sh install/config/hardware/nvidia.sh
chmod +x install/config/hardware/nvidia.sh
```

Note the three inconsistent locations: `OMARCHY_DIR` points outside the repo
(`bin/../../omarchy`), `cd ../omarchy` points inside the repo (when run from
`bin/` per the README), and `[ -f "./fetch-omarchy.sh" ]` only works when CWD
is `bin/`. Also lines 36–39: the yay build does `cd /tmp/yay` / `makepkg` /
`cd -` with no error handling.

`bin/fetch-omarchy.sh:3-6`:

```bash
# Target destination (relative to this script's location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/../../omarchy"
REPO_URL="https://github.com/basecamp/omarchy"
```

Also relevant in `fetch-omarchy.sh`: line 22 reads `CHOICE` and line 25 runs
`[ "$CHOICE" -eq 1 ]` — non-numeric input makes the test error (falls through
to the tag branch with a garbage index). Line 46 `exit 0` when the user keeps
an existing directory is correct (the script runs as a child process; the
installer continues).

`.gitignore` contains exactly `omarchy/` — an *in-repo* ignore, consistent
with the old clone location, stale for the current sibling-of-repo location.

`bin/gpu-setup.sh:4-13` uses `bash ./bin/gpu-detect.sh` etc. — works only
from the repo root, while the README instructs running from `bin/`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Syntax check | `bash -n bin/install-omarchy-on-cachyos.sh bin/fetch-omarchy.sh bin/gpu-setup.sh` | exit 0 |
| Clone-failure behavior test | see Step 6 | exits 1 before any sudo command |

## Scope

**In scope** (the only files you should modify):
- `bin/install-omarchy-on-cachyos.sh`
- `bin/fetch-omarchy.sh`
- `bin/gpu-setup.sh`
- `.gitignore` (only if the chosen location needs it — Step 1 keeps `omarchy/` valid)

**Out of scope** (do NOT touch, even though they look related):
- `bin/nvidia.sh`, `bin/amd-rocm.sh` — plans 007/008.
- The `sed` patch bodies (installer lines 93–155) — plan 003 rewrites those;
  here you only ensure they run *in the right directory*.
- Re-run/idempotency guards beyond what Step 6 verifies — plan 004.

## Git workflow

- Branch: `advisor/002-fail-fast-and-cwd-safety`
- Commit per step; imperative capitalized messages
  (e.g. `Unify Omarchy working-tree path across installer and fetch script`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Pick the single canonical working-tree location

Use **inside the repo**: `<repo-root>/omarchy`. Reasons: `.gitignore` already
ignores it; it never writes outside the directory the user consciously
cloned; it survives the repo being placed anywhere. (Open PR #51 proposed
`.tmp/omarchy` inside the repo — same idea, different name; we keep `omarchy/`
to match the existing ignore rule.)

In `bin/install-omarchy-on-cachyos.sh`, replace the definition block:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OMARCHY_DIR="$REPO_DIR/omarchy"
export OMARCHY_DIR
```

In `bin/fetch-omarchy.sh`, make the target honor the caller's choice with the
same default:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${OMARCHY_DIR:-$(dirname "$SCRIPT_DIR")/omarchy}"
```

**Verify**: `grep -n '\.\./\.\./omarchy' bin/*.sh` → no matches.

### Step 2: Make every reference use the canonical variables

In `bin/install-omarchy-on-cachyos.sh`:

- `[ -f "./fetch-omarchy.sh" ]` block → use `"$SCRIPT_DIR/fetch-omarchy.sh"`
  (both the test and the invocation; keep the `chmod +x`).
- Fallback clone: `git clone https://github.com/basecamp/omarchy "$OMARCHY_DIR"`
  (also drop the nonstandard `www.` prefix).
- `cd ../omarchy` → `cd "$OMARCHY_DIR"`.
- `cp ../bin/nvidia.sh ...` → `cp "$SCRIPT_DIR/nvidia.sh" ...`.

**Verify**: `grep -n 'cd \.\./omarchy\|\.\./bin/\|"\./fetch-omarchy' bin/install-omarchy-on-cachyos.sh` → no matches.

### Step 3: Add strict mode to the installer

Immediately after the shebang: `set -euo pipefail`.

`set -e` interaction notes: the `command -v` checks and `[ -f /etc/sddm.conf ]`
are inside conditionals — unaffected. The `read -r` prompts return 0 on
normal input. `grep -q '^\[omarchy\]'` at line 61 is inside `if !` — fine.
The yay block's `cd /tmp/yay` / `cd -` is replaced in Step 4. All variables
are defined before use, so `set -u` is safe.

**Verify**: `bash -n bin/install-omarchy-on-cachyos.sh` → exit 0.

### Step 4: Contain the yay build in a subshell

Replace:

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay
makepkg -si --noconfirm
cd -
```

with:

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay
(cd /tmp/yay && makepkg -si --noconfirm)
```

**Verify**: `grep -n 'cd -' bin/install-omarchy-on-cachyos.sh` → no matches.

### Step 5: Guard fetch-omarchy.sh's version choice and anchor gpu-setup.sh

In `bin/fetch-omarchy.sh`, after the `read -r -p ... CHOICE` line, add input
validation before `CHOICE` is used in arithmetic:

```bash
if [[ -n "$CHOICE" && ! "$CHOICE" =~ ^[0-9]+$ ]] || { [[ -n "$CHOICE" ]] && (( CHOICE < 1 || CHOICE > ${#RELEASES[@]} + 1 )); }; then
    echo "Invalid choice '$CHOICE'. Defaulting to Bleeding Edge."
    CHOICE=1
fi
```

In `bin/gpu-setup.sh`, add
`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` after `set -e`
and change the three invocations to `"$SCRIPT_DIR/gpu-detect.sh"`,
`"$SCRIPT_DIR/nvidia.sh"`, `"$SCRIPT_DIR/amd-rocm.sh"` (keep the `bash `
prefix).

**Verify**: `bash -n bin/fetch-omarchy.sh bin/gpu-setup.sh` → exit 0;
`grep -n '\./bin/' bin/gpu-setup.sh` → no matches.

### Step 6: Behavioral check of fail-fast (safe, offline)

Simulate clone failure with a stubbed git (safe: the script exits before any
`sudo`):

```bash
mkdir -p /tmp/claude-fake-bin
printf '#!/bin/bash\nif [ "$1" = clone ] || [ "$1" = ls-remote ] || [ "$2" = clone ]; then exit 128; fi\nexec /usr/bin/git "$@"\n' > /tmp/claude-fake-bin/git
chmod +x /tmp/claude-fake-bin/git
cd /tmp && PATH=/tmp/claude-fake-bin:$PATH bash /home/t1nk33r/Documents/omarchy-on-cachyos/bin/install-omarchy-on-cachyos.sh </dev/null; echo "exit=$?"
```

(`</dev/null` makes the fetch script's `read` take defaults; the stub also
fails `git ls-remote` so the release listing is empty.) Note the run starts
from `/tmp` — proving CWD independence.

**Verify**: non-zero exit; output contains an explicit clone/fetch error; no
output from any step after the Omarchy-directory check (no "Making
adjustments"). Clean up `/tmp/claude-fake-bin`.

## Test plan

Step 6 is the regression test for both bugs (wrong-CWD and non-fatal clone).
Record its output. Additionally run the happy-path fetch dry: from `/tmp`,
run `bash <repo>/bin/fetch-omarchy.sh` with input `1`, confirm the clone
lands in `<repo>/omarchy` (then `rm -rf <repo>/omarchy`).

## Done criteria

- [ ] `bash -n` exits 0 for all three in-scope scripts
- [ ] `grep -rn '\.\./\.\./omarchy\|cd \.\./omarchy\|\.\./bin/' bin/` → no matches
- [ ] `grep -n "set -euo pipefail" bin/install-omarchy-on-cachyos.sh` → 1 match near the top
- [ ] Step 6 behavioral check passes (non-zero exit, no post-fetch steps ran, works from `/tmp`)
- [ ] Happy-path fetch lands in `<repo>/omarchy` (then cleaned up)
- [ ] `git status --porcelain` shows only in-scope files + `plans/README.md`
- [ ] `plans/README.md` status row updated

## STOP conditions

- The excerpts under "Current state" don't match the live files (drift — the
  maintainer may have merged PR #72/#71/#51; reconcile with that merge
  instead of applying this plan blindly).
- `set -e` breaks a code path not listed in Step 3's notes — report the line
  rather than sprinkling `|| true`.
- Step 6 still reaches "Making adjustments" — the flow differs from the
  plan's assumption.

## Maintenance notes

- Open upstream PRs #50/#51/#56/#59/#69/#71/#72 overlap this plan. If the
  maintainer merges any of them later, prefer the merged version's variable
  names and close the gap; the invariant to preserve is: **one exported
  `OMARCHY_DIR`, defined from `SCRIPT_DIR`, used by fetch, cd, and cp alike.**
- Plans 003/004/005 assume `set -euo pipefail`, `$SCRIPT_DIR`, and
  `$OMARCHY_DIR` exist — land this first.
- Reviewer: confirm `fetch-omarchy.sh` still works when invoked standalone
  (no exported `OMARCHY_DIR`) via its `${OMARCHY_DIR:-...}` default.
