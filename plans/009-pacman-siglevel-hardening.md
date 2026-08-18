# Plan 009: Enforce package signatures for the omarchy pacman repo

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/install-omarchy-on-cachyos.sh`
> Expected drift from plans 002–004. Locate the `[omarchy]` repo block; if
> its SigLevel already differs from "Current state", STOP (someone got here
> first).

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW–MED (a wrong SigLevel makes installs fail loudly, not silently)
- **Depends on**: none strictly; land after 002/003 to avoid merge friction in the same file
- **Category**: security
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

The installer imports and locally signs the Omarchy packaging key, then
configures the repo with `SigLevel = Optional TrustedOnly` — under which
pacman accepts **unsigned** packages from the mirror (`Optional` = verify
signatures only when present). Since the key import two lines earlier makes
full verification possible, accepting unsigned packages from a remote HTTPS
mirror is an unnecessary weakening: a compromised mirror could serve
unsigned packages that pacman would install. `SigLevel = Required` closes
that at zero cost — *if* every package in the repo is actually signed, which
Step 1 verifies before changing anything.

## Current state

`bin/install-omarchy-on-cachyos.sh:54-66` at `ed6ae20` (the guard around the
append is upstream's; only the SigLevel string changes in this plan):

```bash
# Receive the Omarchy signing key
sudo pacman-key --recv-keys F0134EE680CAC571

# Locally sign and trust the key
sudo pacman-key --lsign-key F0134EE680CAC571

# Add omarchy repository to pacman.conf (skip if already present)
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
    echo -e "\n[omarchy]\nSigLevel = Optional TrustedOnly\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
else
    echo "Omarchy repository already present in pacman.conf, skipping."
fi
sudo pacman -Syu
```

Context: upstream Omarchy's own `install/preflight/pacman.sh` also
configures this repo on stock Omarchy — check what SigLevel upstream uses
(Step 1); if upstream itself ships `Optional TrustedOnly`, matching upstream
is a defensible outcome and this plan becomes a README note instead (Step 3
fork).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Upstream's own choice | `curl -sL https://raw.githubusercontent.com/basecamp/omarchy/master/install/preflight/pacman.sh` | shows upstream SigLevel |
| Repo DB signature check | `curl -sIL "https://pkgs.omarchy.org/x86_64/omarchy.db.sig"` | HTTP 200 if DB signed |
| Package sig spot-check | pick 2 package filenames from the db listing; `curl -sIL` each `.sig` | HTTP 200 |
| Syntax check | `bash -n bin/install-omarchy-on-cachyos.sh` | exit 0 |

## Scope

**In scope**:
- `bin/install-omarchy-on-cachyos.sh` — the SigLevel string only

**Out of scope**:
- The pacman-key import lines (correct as-is)
- CachyOS's own repos in `/etc/pacman.conf`
- The guard structure around the block

## Git workflow

- Branch: `advisor/009-pacman-siglevel-hardening`
- Single commit, e.g. `Require signatures for the omarchy pacman repo`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Verify signatures are actually available

1. Fetch upstream's `install/preflight/pacman.sh`; record the SigLevel it
   sets for `[omarchy]`.
2. Spot-check that `.sig` files are served next to at least 2 packages on
   the mirror — `Required` against an unsigned repo bricks the install.
3. Check whether the repo database is signed (`omarchy.db.sig`). If packages
   are signed but the DB is not, the correct value is
   `SigLevel = Required DatabaseOptional`.

Record all three results in your report.

### Step 2: Apply the strictest level the evidence supports

Typically:

```
SigLevel = Required DatabaseOptional
```

(or `Required` if the DB is signed). Do not add `TrustAll`.

**Verify**: `bash -n bin/install-omarchy-on-cachyos.sh` → exit 0;
`grep -c 'Optional TrustedOnly' bin/install-omarchy-on-cachyos.sh` → 0;
`git diff` shows a one-line change.

### Step 3 (fork): If signatures are NOT consistently available

Do not change the SigLevel. Add one sentence to README §3 noting the omarchy
repo is configured exactly as upstream configures it, and mark this plan
`REJECTED (mirror does not serve signatures — Required would break installs;
matches upstream posture)` in `plans/README.md`.

## Test plan

The mirror checks in Step 1 are the test. A full `pacman -Syu` against the
modified conf is a release gate on real hardware — note it in the report.

## Done criteria

- [ ] Step 1 results recorded (upstream SigLevel, package sigs, DB sig)
- [ ] SigLevel strengthened per evidence, or Step 3's REJECTED path taken with evidence
- [ ] `bash -n` exits 0
- [ ] `git diff` on the installer shows only the SigLevel line changed
- [ ] `plans/README.md` status row updated

## STOP conditions

- The mirror layout differs from a standard pacman repo (can't locate db or
  packages) — report what you saw.
- The `[omarchy]` block has been restructured beyond the excerpt above.

## Maintenance notes

- If Omarchy rotates its packaging key, the hardcoded key ID
  (`F0134EE680CAC571`) fails at `--recv-keys` — first thing to check when
  installs break at the key step.
- Reviewer: confirm the `\$arch` escape in the `echo -e` string survives.
