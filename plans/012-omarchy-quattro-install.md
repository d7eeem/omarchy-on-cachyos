# Plan 012: Quattro (v4) install support — package wrapper with CachyOS reconciliation

> **Executor instructions**: Follow this plan step by step. Steps 1–2 are
> investigation (results go in your report NOTES; the reviewer appends them
> here). Steps 3–6 implement. Run every verification command. Touch only
> in-scope files. STOP conditions are binding. Commit per logical unit;
> imperative capitalized messages. Do NOT push. NEVER run pacman/systemctl
> with sudo, never execute the produced installer for real — the ONLY
> execution allowed is its `--dry-run` mode, which must not touch the system.

## Status

- **Priority**: P1 (maintainer signed off: "bump to install omarchy quattro")
- **Effort**: M–L
- **Risk**: HIGH (boot path, package management on user systems) — mitigated by dry-run contract + assertion suite; real-hardware run is a release gate
- **Depends on**: plans/011 spike (design basis), all v3 plans (landed)
- **Category**: direction / feature
- **Planned at**: commit `04527e7`, 2026-08-18

## Why this matters

Omarchy v4 ("Quattro") abandoned `install.sh`: it ships as Arch packages
(`omarchy`, `omarchy-settings`, `omarchy-keyring`, `omarchy-nvim`) applied by
`omarchy-apply-system` from an ISO chroot. This repo currently pins v3.8.4
and refuses v4 trees. The maintainer wants Quattro installable on CachyOS.
Per the plan-011 spike, the shape is a **package-install wrapper**: add the
omarchy repo, install the packages, run the apply stages with CachyOS
pre/post reconciliation, and verify with a post-apply assertion suite
(replacing `patch_or_die`, since package-owned files can't be sed-patched).

## Verified ground truth (reviewer-recon 2026-08-18 + plan-011 spike — treat as fact)

- Stable channel exists and serves Quattro: `https://pkgs.omarchy.org/stable/x86_64/`
  has `omarchy-4.0.0-1`, `omarchy-settings-4.0.0-1`, `omarchy-keyring-20251027-1`,
  `omarchy-nvim-2026.8.13-1`; package `.sig` files are served (HTTP 200), so
  `SigLevel = Required DatabaseOptional` remains correct (confirm the db sig
  status yourself for the stable path).
- `omarchy` DEPENDS (from the repo db): `omarchy-keyring, omarchy-settings=4.0.0,
  limine, limine-mkinitcpio-hook, limine-snapper-sync, snapper, hyprland,
  quickshell, uwsm, sddm, xdg-desktop-portal-hyprland, wireplumber, pipewire,
  gnome-keyring, gum, jq, git, perl, fakeroot, pacman-contrib,
  ttf-jetbrains-mono-nerd-basic`. `omarchy-settings` DEPENDS includes `plymouth`.
  **Consequence: limine/plymouth arrive via pacman and CANNOT be skipped.**
- `tldr` is NOT a dependency — it comes only from `install/omarchy-base.packages`
  (ISO builder list). The tealdeer conflict only appears if the wrapper installs
  the base-app list (Step 1 decides how much of it to install).
- v4's `omarchy-apply-system` (root-only, `--install-user USER`): sources
  `install/config/all.sh` → `omarchy-apply-hardware` (`hardware/all.sh`) →
  `login/all.sh` (only `sddm.sh`) → `post-install/all.sh`. Its `--upgrade` flag
  is a no-op inside install/. Known clobber points: `install/post-install/pacman.sh`
  does `cp -f .../pacman-${OMARCHY_MIRROR:-stable}.conf /etc/pacman.conf`
  (**would wipe the CachyOS repos — fatal if unreconciled**);
  `install/config/snapper.sh` unconditionally overwrites
  `/etc/snapper/configs/root` and enables `snapper-cleanup.timer` +
  `limine-snapper-sync.service`; `install/config/config.sh` does
  `cp -R $OMARCHY_PATH/config/* ~/.config/` (mass user-config overwrite).
- omarchy-settings ships `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` setting
  `HOOKS=(... plymouth ... btrfs-overlayfs)`. mkinitcpio applies conf.d files
  lexically, later assignments win. **On a CachyOS system whose HOOKS include
  `encrypt`/`sd-encrypt` (LUKS), letting omarchy's HOOKS override and then
  regenerating initramfs can make the system unbootable. This is the plan's
  #1 safety constraint.**
- v4 networking: `install/hardware/network.sh` disables iwd; NetworkManager is
  the default — aligned with CachyOS; the v3 iwd patch is obsolete here.
- v4 still uses uwsm (dependency + `default/uwsm/env.d/10-omarchy`), so this
  repo's NVIDIA/AMD uwsm env approach and `gpu-detect.sh`/`gpu-setup.sh`/
  `nvidia.sh`/`amd-rocm.sh` remain applicable. v4's own
  `install/hardware/nvidia.sh` kernel regex (`^linux(-zen|-lts|...)?$`) misses
  `linux-cachyos*` kernels (spike finding) — our GPU dispatch fixes that gap.
- The v3→v4 migration reference is `bin/omarchy-upgrade-to-quattro` (2370
  lines, curl-pipeable): surgical awk `[omarchy]` pacman.conf rewrite, config
  hashing/backup (`known_config_default_hashes`, `backup_config_file`),
  retired-package removal, service transitions. Use it as a REFERENCE for
  technique; do not curl|bash it and do not assume a v3 Omarchy exists (our
  target machine is CachyOS without Omarchy, or with this repo's v3 install).
- Maintainer decisions (from sign-off): fresh-CachyOS-first; keep the v3
  installer working and untouched; Quattro is a NEW script.

## Scope

**In scope** (only these):
- `bin/install-omarchy-quattro.sh` (create — the wrapper)
- `README.md` (new Quattro section; mark it the recommended path; keep v3 docs)
- `bin/gpu-setup.sh` ONLY if a verify step reveals an incompatibility (report first)

**Out of scope**:
- `bin/install-omarchy-on-cachyos.sh`, `bin/fetch-omarchy.sh` (v3 path stays as-is)
- `.github/workflows/lint.yml` (new script is covered by the `bin/*.sh` glob)
- Any real execution of privileged commands on this machine

## The dry-run contract (the testable core — non-negotiable)

`install-omarchy-quattro.sh` must support `--dry-run`: print every
state-changing command (prefixed `DRYRUN:`) instead of executing, while still
performing read-only detection (bootloader, LUKS, current HOOKS, GPU vendor,
existing repos). All privileged/state-changing operations MUST flow through
two helpers so the contract is enforceable by review:

```bash
run() { if $DRY_RUN; then echo "DRYRUN: $*"; else "$@"; fi; }
run_root() { if $DRY_RUN; then echo "DRYRUN: sudo $*"; else sudo "$@"; fi; }
```

No `sudo` outside `run_root`. `grep -n 'sudo' bin/install-omarchy-quattro.sh`
must only match the helper definition and comments.

## Steps

### Step 1: Investigate the exact apply sequence for a non-ISO machine

In a scratch clone of `basecamp/omarchy` at tag `v4.0.0` (clone technique:
shallow master clone + `git fetch --depth 1 origin tag v4.0.0`), determine and
record in NOTES, with quoted lines:

1. Where `OMARCHY_PATH` content comes from when installed by package
   (`/usr/share/omarchy` per the packages) and what `omarchy-apply-system`
   needs beyond the packages (env vars, log file paths, `omarchy-finalize-user`
   or equivalent user-level step for a PRE-EXISTING user — `/etc/skel` only
   fires at useradd, so find the supported path that seeds an existing user's
   `$HOME`: `omarchy-finalize-user`, `omarchy-reinstall-configs`, or the
   upgrade script's `apply_user_transition`).
2. Which of `install/config/all.sh`'s ~60 scripts are safe/unsafe on a live
   CachyOS system — produce a table (script → verdict: safe / clobber /
   boot-risk / skip-worthy) at least for: snapper.sh, config.sh (user configs),
   enable-services.sh, firewall.sh, lockscreen-pam.sh, theme-system.sh, and
   the full `post-install/` and `login/` sets.
3. How base apps get installed outside the ISO (is there an
   `omarchy-install-preinstalls` / package-list step the wrapper should
   optionally run?) and whether `tldr` rides along there (tealdeer file
   conflict: `tealdeer` owns `/usr/bin/tldr`).
4. Whether the `stable` channel db is signed (`omarchy.db.sig` on the stable
   path) to finalize the SigLevel string.

### Step 2: Decide the reconciliation set (write it down before coding)

From Step 1 + ground truth, enumerate every pre/post fix the wrapper performs.
Minimum required set (extend as Step 1 dictates):

- **pacman.conf**: back up before apply; after apply, restore the CachyOS
  pacman.conf and surgically (re)append only the `[omarchy]` stanza
  (`SigLevel = Required DatabaseOptional`,
  `Server = https://pkgs.omarchy.org/stable/$arch` — adjust per Step 1.4).
  Never leave the system without its CachyOS repos.
- **mkinitcpio HOOKS (boot safety)**: BEFORE anything regenerates initramfs,
  capture the effective current HOOKS; write
  `/etc/mkinitcpio.conf.d/zz-cachyos-keep-hooks.conf` re-asserting them (zz-
  sorts last, so it wins over `omarchy_hooks.conf`). If the machine uses LUKS
  (detect via `lsblk -o FSTYPE` containing crypto_LUKS or /etc/crypttab), the
  preserved HOOKS MUST retain their encrypt/sd-encrypt hook. Then regenerate
  initramfs once, deliberately, at the end (`run_root mkinitcpio -P`).
- **Bootloader**: detect the active bootloader (limine vs grub vs
  systemd-boot; e.g. `/boot/limine.conf` / `bootctl is-installed` /
  `/boot/grub`). If NOT limine: after apply, disable
  `limine-snapper-sync.service` and ensure no limine hook can rewrite boot
  entries (investigate what `limine-mkinitcpio-hook` triggers on and neuter
  it for non-limine systems in a pacman-safe way — e.g. a
  `/etc/mkinitcpio.conf.d`/hook override or masking the service — document
  the chosen mechanism). If limine IS the bootloader (CachyOS offers it),
  leave omarchy's integration active.
- **snapper**: back up `/etc/snapper/configs/root` before apply; restore the
  CachyOS version after (README already requires Snapper at CachyOS install).
- **User configs**: before the user-level seeding step, back up `~/.config`
  dirs it will overwrite (mirror the upgrade script's backup technique) —
  never silently clobber.
- **GPU**: after apply, run this repo's `gpu-setup.sh` dispatch (fixes the
  linux-cachyos kernel gap; NVIDIA detect-and-respect; AMD ROCm) via `run`.
- **Fish integrations**: write the same
  `~/.config/fish/conf.d/omarchy-on-cachyos.fish` (mise + zoxide) as the v3
  installer.
- **SDDM**: v4 writes drop-ins only; delete stale `/etc/sddm.conf` first
  (same PR #28 rationale, plan 006 evidence).

### Step 3: Write `bin/install-omarchy-quattro.sh`

Structure (match the repo's bash style — `set -euo pipefail`, SCRIPT_DIR
anchor, section comments, gum-free plain echos):

1. Flags: `--dry-run` (contract above), `--yes` (skip confirmations).
2. Preflight: refuse root (script uses sudo itself); require pacman + a
   CachyOS system (`/etc/cachyos-release` or cachyos repos in pacman.conf —
   warn+confirm if absent); detect bootloader, LUKS, GPU, current HOOKS;
   print a plan summary and confirm.
3. Repo + keyring: pacman-key recv/lsign (reuse key ID `F0134EE680CAC571`
   unless Step 1 shows the keyring package supersedes it — prefer installing
   `omarchy-keyring` via pacman after adding the repo, then `pacman-key
   --populate omarchy` if the package provides it; record what you chose);
   append the `[omarchy]` stanza (guarded, like the v3 installer).
4. `run_root pacman -Syu --needed omarchy-settings omarchy omarchy-nvim`
   (order per dependencies; `--needed` for idempotency).
5. Pre-apply reconciliation (backups, zz-hooks drop-in) per Step 2.
6. Apply: `run_root omarchy-apply-system --install-user "$USER" --first-install`
   with any env it needs — UNLESS Step 1 shows a subset invocation is safer
   (e.g. sourcing selected stage scripts); justify the choice in NOTES.
7. User-level seeding for the existing user (Step 1.1's supported path) +
   fish conf.d + GPU dispatch.
8. Post-apply reconciliation + `run_root mkinitcpio -P` + assertion suite.
9. Assertion suite (hard-fail with a clear message on any miss):
   - CachyOS repos present in `/etc/pacman.conf` AND `[omarchy]` present
   - effective mkinitcpio HOOKS still contain the pre-install encrypt hook
     when LUKS was detected, and `zz-cachyos-keep-hooks.conf` exists
   - non-limine machine → `limine-snapper-sync.service` not enabled
   - `systemctl is-enabled sddm` → enabled; NetworkManager enabled
   - `/etc/snapper/configs/root` matches the pre-install backup
   - `command -v omarchy` (or the v4 CLI entrypoint) exists

### Step 4: Idempotency

Re-running with `--dry-run` twice must produce the same plan; every append
is guarded; backups use timestamped names and never overwrite an earlier
backup of the same run day.

### Step 5: Dry-run verification harness

Run `bash bin/install-omarchy-quattro.sh --dry-run --yes` on THIS machine
(safe by contract) and verify:
- exit 0; zero non-DRYRUN state changes (`git status` clean, no /etc writes —
  spot-check mtimes of /etc/pacman.conf and /etc/mkinitcpio.conf.d/)
- the DRYRUN command sequence contains, in order: repo stanza append → pacman
  install → backups → zz-hooks write → apply-system → user seeding → GPU
  dispatch → restores → mkinitcpio -P
- on this AMD machine the GPU line dispatches to amd-rocm.sh
- `bash -n` and `shellcheck --severity=error` (via the gh-runner image:
  `docker run --rm --entrypoint sh -v "$PWD:/repo" -w /repo gh-runner-runner
  -c 'shellcheck --severity=error bin/install-omarchy-quattro.sh'`) pass.

### Step 6: README

New "Installing Omarchy 4 (Quattro) — recommended" section: what the wrapper
does (packages, not clone-and-patch), the reconciliation guarantees (CachyOS
repos preserved, boot hooks preserved, snapper preserved), bootloader note
(limine users get full integration; grub/systemd-boot users get limine
services disabled), the dry-run flag, and an explicit statement that the v3
clone-and-patch path remains available and unchanged. Update the header
UPDATE line.

## Done criteria

- [ ] `bash -n` + shellcheck (error severity) pass for the new script
- [ ] `grep -cE '(^|[^"#])sudo ' bin/install-omarchy-quattro.sh` matches only the run_root helper (verify by reading matches)
- [ ] Dry-run harness passes all Step 5 checks; output captured in NOTES
- [ ] Step 1 investigation table + Step 2 reconciliation set in NOTES
- [ ] Assertion suite covers every bullet in Step 3.9
- [ ] README section present; v3 files untouched (`git diff --stat 04527e7..HEAD` shows only in-scope files)
- [ ] Working tree clean after commits

## STOP conditions

- Step 1 shows `omarchy-apply-system` cannot run outside a chroot at all
  (hard environment check in v4.0.0 code) — report; the fallback design
  (sourcing selected stage scripts directly) needs reviewer sign-off first.
- The limine-mkinitcpio-hook cannot be safely neutered for non-limine
  systems without breaking pacman transactions — report options, do not pick
  one silently.
- Any step would require executing a privileged command for real.

## Execution results (2026-08-18, sonnet executor — key investigation findings)

- `omarchy-apply-system` has **no chroot check** (root + existing user only)
  — runs on a live machine; but its stages are blank-chroot full-applies.
- **Mirrorlist clobber discovered**: `install/post-install/pacman.sh` also
  does `cp -f .../mirrorlist-stable /etc/pacman.d/mirrorlist` — added to the
  backup/restore set alongside pacman.conf.
- **Timing fix**: backups + the `zz-cachyos-keep-hooks.conf` drop-in are
  written BEFORE `pacman -Syu`, because `limine-mkinitcpio-hook` can rebuild
  the initramfs in the same transaction that installs `omarchy_hooks.conf`.
- User seeding path for a pre-existing user: `omarchy-reinstall-configs`
  (replays /etc/skel over $HOME) + `omarchy-provision-user --first-install`
  (aka "omarchy finalize user"); both non-root.
- limine-hook neutering: same-named no-op hook in `/etc/pacman.d/hooks/`
  (pacman.conf(5): custom HookDir wins over /usr/share/libalpm/hooks) —
  package-upgrade-safe, reversible by deleting the override.
- Base-app list (and its `tldr`) is NOT installed by the wrapper — only the
  four omarchy packages — so the tealdeer conflict never arises.
- Stable-channel db unsigned, packages signed → `Required DatabaseOptional`.
- v4 login/sddm.sh only edits PAM; SDDM config is package-owned drop-ins;
  `/etc/sddm.conf` deletion remains the right lever (plan 006 holds for v4).
- Dry-run harness verified on this machine (limine + LUKS + AMD): exit 0,
  zero state changes, correct command ordering, AMD dispatch.
- Open item: whether `omarchy-keyring`'s post-install populates pacman-key
  trust (assumed; recv/lsign of F0134EE680CAC571 covers it regardless).

## Maintenance notes

- Real-hardware validation (a fresh CachyOS VM: one GRUB+LUKS, one Limine)
  is the release gate before announcing Quattro support.
- Version bumps: the stable channel moves; the assertion suite is the
  regression net. Consider pinning `omarchy=4.0.0-1` explicitly if the
  channel proves fast-moving.
- The v3 path should be marked legacy in the README once Quattro is
  hardware-validated.
