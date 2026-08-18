# Plan 006: Decide how to handle upstream Omarchy's SDDM installation (investigate)

> **Executor instructions**: This is an INVESTIGATE plan — its deliverable is
> a written recommendation appended to this file, plus at most the small code
> change in Step 4 if the investigation lands on option (b), (c), or (d).
> Run every verification command. If anything in "STOP conditions" occurs,
> stop and report.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/install-omarchy-on-cachyos.sh README.md`
> Reconcile expected drift from plans 002–004; unexpected changes to the SDDM
> block are a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: MED (login path — a wrong choice can lock users out of a GUI session)
- **Depends on**: plans/003-fix-drifted-patches-and-pin-upstream.md (fixes the version the analysis targets)
- **Category**: bug / docs
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

This project's login model is documented (README §3 item 5) as: "Omarchy
skips installation of a login display manager… this script assumes a display
manager is installed." That was true for older Omarchy. **Verified
2026-08-17: upstream now ships `install/login/sddm.sh`, run from
`install/login/all.sh`, which installs an Omarchy SDDM theme, writes
`/etc/sddm.conf.d/10-wayland.conf` and `/etc/sddm.conf.d/autologin.conf`
(autologin as `$USER` into an `omarchy` session), deletes gnome-keyring lines
from `/etc/pam.d/sddm`, and runs `systemctl enable sddm.service`.**

The installer does not remove that step, so it runs on CachyOS — where SDDM
may already be installed and configured by CachyOS itself, and where this
repo's installer separately deletes `/etc/sddm.conf` (a deliberate fix from
PR #28, "fix/sddm-session-conflict"). Whether upstream's sddm.sh is now
*better* for CachyOS users or *conflicts* with CachyOS's SDDM setup is
unknown — that's the investigation. Related signal: open upstream PR #56
proposes making Omarchy autologin **optional** so users with KDE/GNOME login
screens can keep them — evidence that autologin-by-default is contentious for
this user base.

## Current state

`bin/install-omarchy-on-cachyos.sh:68-72` at `ed6ae20`:

```bash
# Remove CachyOS SDDM config
if [ -f /etc/sddm.conf ]; then
    echo "Removing /etc/sddm.conf"
    sudo rm /etc/sddm.conf
fi
```

Upstream `install/login/all.sh` (fetched 2026-08-17):

```
run_logged $OMARCHY_INSTALL/login/plymouth.sh        # removed by this repo's patches
run_logged $OMARCHY_INSTALL/login/default-keyring.sh
run_logged $OMARCHY_INSTALL/login/sddm.sh            # NOT removed — runs today
run_logged $OMARCHY_INSTALL/login/hibernation.sh
run_logged $OMARCHY_INSTALL/login/limine-snapper.sh  # removed by this repo's patches
```

Key behaviors of upstream `install/login/sddm.sh`: writes
`/etc/sddm.conf.d/10-wayland.conf` (Wayland compositor command); creates
`/etc/sddm.conf.d/autologin.conf` with `User=$USER` / `Session=omarchy`
unless one exists; edits `/etc/pam.d/sddm`; enables `sddm.service`.

README §3 item 5 and §4 item 3 describe the pre-3.x login model.

Historical context: `626d90b Fix: Remove sddm.conf to enable UWSM session`,
PR #28 `fix/sddm-session-conflict` — the `/etc/sddm.conf` removal is a
deliberate, tested decision. Do not remove it without evidence.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Read upstream sddm.sh at the tested ref | `git -C <clone> show <TESTED_OMARCHY_REF>:install/login/sddm.sh` | file contents |
| Check CachyOS SDDM defaults | inspect `/etc/sddm.conf.d/` and `pacman -Qo` on files there (read-only) | inventory |
| Syntax check (if Step 4 applies) | `bash -n bin/install-omarchy-on-cachyos.sh` | exit 0 |

## Scope

**In scope**:
- This plan file (append findings + recommendation)
- `README.md` §3 item 5 / §4 item 3 (rewrite to match the decided model)
- `bin/install-omarchy-on-cachyos.sh` — ONLY if the decision is (b), (c), or (d); only the login-patch lines

**Out of scope**:
- Upstream Omarchy source (only patched at install time)
- The plymouth/limine-snapper removals (they stay removed)

## Steps

### Step 1: Characterize both SDDM configurations

- Read upstream `install/login/sddm.sh` in full at the tested ref.
- Inventory what CachyOS's Hyprland install ships for SDDM: which package
  owns `sddm`, what lives in `/etc/sddm.conf.d/` on a stock install (use this
  machine if it is a CachyOS system; otherwise consult CachyOS's
  `cachyos-hyprland-settings` package repo online), and what `/etc/sddm.conf`
  contained (the file PR #28 deletes).

**Verify**: findings written under "## Investigation results" with file paths
and package names cited.

### Step 2: Enumerate the interaction risks

Answer with evidence, in writing:

1. Does upstream's `autologin.conf` (`User=$USER`) resolve to the right user
   when run from this installer's context?
2. Do CachyOS's sddm.conf.d drop-ins and upstream's conflict (same keys,
   different values), and which wins (lexicographic drop-in order)?
3. Does the PAM edit break anything CachyOS configures?
4. Is PR #28's `/etc/sddm.conf` deletion still needed once upstream's
   drop-ins exist, or redundant/harmful?

### Step 3: Recommend one of four options

- **(a) Keep upstream sddm.sh** (no installer change) — if it integrates
  cleanly; this plan then only rewrites the README.
- **(b) Remove sddm.sh like plymouth** — add
  `patch_or_die install/login/all.sh 'login/sddm\.sh' '/run_logged \$OMARCHY_INSTALL\/login\/sddm\.sh/d'`
  beside the existing login patches — if it conflicts with CachyOS SDDM.
- **(c) Conditional** — run it only when no display manager is enabled
  (`systemctl is-enabled sddm ly gdm lightdm` all negative).
- **(d) Keep sddm.sh but make autologin opt-in** (adopts open upstream
  PR #56's idea): prompt the user during install; if they decline, patch
  upstream's sddm.sh to skip writing `autologin.conf`. Choose this only if
  Step 2 shows the rest of sddm.sh is benign on CachyOS.

Append the recommendation with rationale to this file.

### Step 4: Apply the small code change (options b/c/d) and fix the README

Rewrite README §3 item 5 to describe the actual post-decision model. Update
the installer's summary echoes if a patch was added.

**Verify**: `bash -n bin/install-omarchy-on-cachyos.sh` → exit 0;
`grep -n "sddm" README.md` reflects the new model.

## Test plan

Every claim in the results section must cite a file path, package, or
upstream line. If (b)/(c)/(d): the new patch must pass plan 003's dry-run
harness. A real login test on hardware/VM is a release gate — say so in the
report.

## Done criteria

- [ ] "## Investigation results" appended, answering Step 2's four questions with citations
- [ ] One recommendation chosen with rationale (a/b/c/d)
- [ ] README login-model text no longer claims Omarchy skips display managers
- [ ] If code changed: `bash -n` passes and the patch survives the plan-003 harness
- [ ] `plans/README.md` status row updated

## STOP conditions

- Upstream's login/all.sh at the tested ref doesn't list `sddm.sh` (the
  tested ref predates the feature — re-derive facts at that ref).
- CachyOS's stock SDDM state cannot be determined — report trade-offs and
  mark BLOCKED rather than guessing on a login-path change.

## Investigation results (executed 2026-08-17 on a live CachyOS machine; sources: v3.8.4 scratch clone, pacman -Qo/-Ql, /etc inspection read-only, man 5 sddm.conf)

1. **`User=$USER` resolves correctly**: install.sh runs as the invoking user;
   sddm.sh's heredoc is expanded by the parent bash before `sudo tee`. Live
   confirmation: this machine's `/etc/sddm.conf.d/autologin.conf` contains
   the real user, not root.
2. **No conf.d conflict with CachyOS**: no package owns the Omarchy drop-ins;
   `sddm` ships only vendor defaults in `/usr/lib/sddm/sddm.conf.d/`; no
   cachyos-* package touches `/etc/sddm.conf.d/` or `/etc/pam.d/sddm`.
3. **PAM edit is safe**: `/etc/pam.d/sddm` is stock (sddm-owned); the sed
   removes only greeter-path gnome-keyring `-auth`/`-password` lines,
   pairing with Omarchy's passwordless default keyring;
   `/etc/pam.d/sddm-autologin` is untouched.
4. **PR #28's `/etc/sddm.conf` deletion is load-bearing, keep it**: per
   `man 5 sddm.conf`, `/etc/sddm.conf` has the HIGHEST precedence — a
   leftover copy (historically written by CachyOS's Calamares installer)
   would silently override every Omarchy drop-in. No package owns that file,
   so deleting it removes only an ISO-era artifact, and sddm.sh never
   recreates it.

**Decision: (a) — keep upstream sddm.sh unmodified.** The existing
`/etc/sddm.conf` removal is precisely what makes upstream's conf.d approach
take effect. README §2.5, §3.5, §4.3 rewritten to describe the real model
(landed at a524a62). Caveat: the reference machine is post-install; the
pre-install `/etc/sddm.conf` contents weren't observable, but PR #28's
history plus the precedence rule justify the deletion regardless. Option (d)
(optional autologin, upstream PR #56's idea) remains open as a future
enhancement — not needed for correctness.

## Maintenance notes

- Whichever option lands, PR #28's `/etc/sddm.conf` deletion must be
  re-justified or removed in the same change — record the verdict here.
- If the maintainer merges upstream PR #56 (optional autologin), reconcile —
  it overlaps option (d).
- Reviewer: login path; insist on a tested boot on real hardware or a VM
  before merging anything beyond README edits.
