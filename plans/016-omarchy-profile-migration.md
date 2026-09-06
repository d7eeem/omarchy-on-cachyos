# 016 — Carry an existing Omarchy profile onto CachyOS (export / import / doctor)

Written and executed 2026-09-07 against `643bb57`. Branch: `omocachy-profile`,
merged into `omocachy`.

## Problem

Plans 012 and 015 built the *system* half of this project: a CachyOS machine
ends up running Omarchy 4 without either distribution clobbering the other.
The half that was missing is the reason a person does this at all — the
machine they are leaving carries a desktop they built: a Quickshell layer
(`shell.json` plus 44 plugin directories on the dev machine), Hyprland
config, mise tool versions, an explicit package set, enabled user units,
terminal/TUI config.

`omarchy-apply-system` and `omarchy-provision-user` reproduce Omarchy's
*defaults*, not that. Nothing in this repo carried a user's own layer, so the
documented migration story ended with "now set your desktop up again".

## What the two candidate repositories offered

Both were read in full before deciding (`bin/*.sh`, READMEs, git history).

`jeanmartins7/omarchy-on-cachyos` (a fork of `mroboff/omarchy-on-cachyos`,
this project's own upstream) — its v4 installer is a different architecture
from ours: it rsyncs an Omarchy *source tree* into `/usr/share/omarchy`,
probes for `omarchy-apply` / `omarchy-setup` / `omarchy-install` script name
variants, and structures `~/.config/omarchy` into `~/.dotfiles` with GNU Stow.

Adopted from it:

| Idea | Where it landed | Why |
|---|---|---|
| NVIDIA generation probe from the PCI device id, with an open-GSP capability flag | `bin/nvidia.sh` | Detects the one silent misconfiguration our detect-and-respect logic could not see: an `nvidia-open*` package on a pre-Turing card, which has no GSP firmware and never initialises. We report and warn; package *choice* stays with `chwd`, which has its own device-id table (plan 007). |
| `nvidia-vaapi-driver` alongside `libva-utils` | `bin/nvidia.sh` | We already export `LIBVA_DRIVER_NAME=nvidia`; without that package the variable points at nothing and browsers silently fall back to software decode. |
| `options nvidia_drm modeset=1 fbdev=1` drop-in | `bin/nvidia.sh` | Required for Wayland. Written only when nothing in `/etc/modprobe.d` already sets it, so an existing CachyOS choice wins. |
| Tee'ing a run's output to a log file | `start_logging` in `bin/lib/common.sh` | A migration is long and unattended; a transcript is worth having. |

Rejected, with reasons:

- **rsync a source tree into `/usr/share/omarchy`** — Omarchy 4 *is* packages
  (plan 011/012). Writing into a pacman-owned directory makes every file a
  `pacman -Qkk` mismatch and the next `omarchy update` overwrites it.
- **`ln -sf /dev/null /etc/pacman.d/hooks/omarchy-boot.hook`** — those hook
  names do not exist in 4.0.2 (`pacman -Ql omarchy omarchy-settings`), and a
  symlink to `/dev/null` is not how a hook is neutralised; plan 015's
  same-named no-op files in `/etc/pacman.d/hooks/` are.
- **`sudo chwd -a` (bare)** — a silenced no-op / over-broad autoconfigure;
  plan 007 already fixed this to class-scoped `-a 0300/0302` and `chwd -i amd`.
- **Bootstrapping `yay`** — CachyOS ships `paru`. The importer uses whichever
  of `paru`/`yay` exists and reports honestly when neither does.
- **Appending NVIDIA env to `~/.config/uwsm/env`** — that file belongs to the
  user (often dotfile-managed). Plan 015's `uwsm/env.d/50-omocachy-gpu` is a
  file we own and can rewrite.
- **Moving `~/.config/omarchy` into `~/.dotfiles` and symlinking it (Stow)** —
  a destructive re-layout of a live desktop for no gain here. The dev machine
  already has `yadm`; the exporter records its remote and stays out of the way.
- **`~/.config/hypr/nvidia.conf`** — Omarchy 4's Hyprland config is Lua
  (`hyprland.lua`, `monitors.lua`, ...); a stray `.conf` is dead weight.

## What was built

Three scripts plus two libraries, sharing this repo's dry-run contract.

- `bin/lib/common.sh` — `run`, `run_root`, `write_root_file`,
  `append_root_file`, `write_user_file`, `info/warn/die`, `confirm`,
  `require_*`, `start_logging`. Extracted verbatim from
  `install-omarchy-quattro.sh` (whose dry-run output is byte-identical after
  the extraction, timestamps normalised) so the new scripts do not fork a
  second copy of the contract.
- `bin/lib/profile.sh` — the bundle format (schema 1), the exclude/secret
  policy, the package deny policy, plugin enumeration, `shell.json` plugin-id
  extraction, bundle resolution (directory or archive).
- `share/profile-paths.conf` — the capture list, relative to `$HOME`, as data.
- `bin/omocachy-profile-export.sh` — read-only with respect to the system;
  writes a bundle (`home/` payload + `manifest.json` + `SUMMARY.md` +
  package/service/system metadata), optionally an archive.
- `bin/omocachy-profile-import.sh` — stages `configs`, `packages`, `mise`,
  `services`, `verify`; backs up every path it would shadow and generates
  `rollback.sh`; merges rather than replaces; parks host-specific files.
- `bin/omocachy-doctor.sh` — read-only checks of the system layer, the
  Quickshell layer, tooling, and (with `--bundle`) the machine against a
  bundle.

## Load-bearing findings

1. **24 of 43 plugins on the dev machine have no git remote.** A migration
   that re-cloned plugin repositories from `shell.json` ids would have
   silently lost more than half of them. The payload therefore carries plugin
   *contents*; `manifest.json` records remote/branch/commit for the ones that
   do have a remote, and the doctor calls a missing local-only plugin a
   separate failure ("nothing but this bundle has them").
2. **`shell.json` references plugins the shell needs by id.** An id with no
   directory in `~/.config/omarchy/plugins` makes the shell drop that part of
   its graph with no visible error — the failure mode this lab has hit before
   (a missing lock plugin takes the lock IPC target with it). Both the doctor
   and the exporter's manifest cross-check ids against directories.
3. **`git status --ignored` is the right size lever.** Plugin checkouts carry
   build output (an 80 MB Rust `target/` in one). Excluding each repo's
   ignored files took the dev machine's plugin payload from 230 MB to 138 MB
   with nothing lost that the checkout cannot rebuild.
4. **tar `--exclude` anchoring, measured, not assumed.** For `--slim`,
   `.config/omarchy/themes/*/backgrounds` and `*/backgrounds` both leave the
   wallpapers in the archive; unanchored `*backgrounds` drops the directories
   and their contents (themes 520 MiB → 348 MiB).
5. **Name-based secret sweeps eat the workflow they carry.** The first pass
   removed `~/.local/bin/gotify-token-fetch`, `omarchy-drive-set-password`
   and two `docs/media/add-token.png` files. The sweep now exempts
   executables (a script is not a token) and source/asset extensions, and
   writes both the removals and the exemptions into the bundle.
6. **Some captured config legitimately carries credentials inline.**
   `shell.json` holds plugin service URLs and API keys (Sonarr/Radarr on the
   dev machine). Those must travel, so the exporter greps the staged payload
   and marks the bundle sensitive in `SUMMARY.md` (bundle dir 0700, archive
   0600) instead of pretending it is safe to share.
7. **Host-specific files must not be restored blind.**
   `~/.config/hypr/monitors.lua` from another machine is wrong and can leave
   no usable display; `uwsm/env.d/50-omocachy-gpu` from an AMD source on an
   NVIDIA target breaks acceleration. They are parked as
   `<name>.from-<source-host>` unless `--restore-host-specific`.
8. **A rollback that `rm -rf`s before copying is observable.** The first
   rollback run left Hyprland reporting `cannot open .../hyprland.lua` — the
   live compositor reloaded inside the copy window. The generated
   `rollback.sh` now stages the copy beside the target and swaps it in.

## Package policy

The importer never installs, by policy (regex → reason in
`PROFILE_PKG_DENY`): kernels/headers, bootloaders, the NVIDIA/mesa driver
stack, `omarchy*`/`quickshell*` (the wrapper's job), base-system packages,
`cachyos-*` metapackages, and `tldr` (conflicts with CachyOS's tealdeer —
§4.2 of the README). Every skip is printed with its reason and written to
`~/.local/state/omocachy/reports/import-<ts>/`.

Verified by unit-probing `profile_pkg_denied` over 24 names (all of the above
deny; `tealdeer`, `ghostty`, `mise-bin`, `herdr`, `firefox` allow) and by a
synthetic-bundle `--only packages --dry-run` on the dev machine: 2 denied
with reasons, 2 resolved from configured repos into one pacman transaction,
1 unresolvable name routed to the AUR helper.

## Validation performed

In the disposable Omarchy 4.0.2 VM (`~/Work/t1nk33r-lab`, isolated, no
network) unless stated otherwise:

1. `bash -n` + `shellcheck --severity=warning -x` clean on all of `bin/*.sh`
   and `bin/lib/*.sh`.
2. `install-omarchy-quattro.sh --dry-run` output byte-identical before and
   after the `lib/common.sh` extraction (timestamps normalised).
3. Real export on the dev machine (`--slim`): 43 plugins, 24 local-only,
   515 MB payload, 0 secrets removed, 5 exemptions listed, 16 files flagged
   for inline credentials.
4. Real export inside the guest: 138 MB payload, 105 MB `.tar.zst`; archive
   copied to the host and back with matching sha256.
5. `./lab reset` to a pristine guest (0 plugins), then
   `omocachy-doctor.sh --bundle`: correctly **failed** with 44 missing
   plugins / 25 missing local-only plugins.
6. `omocachy-profile-import.sh --bundle <archive> --yes` on that pristine
   guest: configs OK, packages OK (nothing to install), mise SKIPPED
   (offline, list written), services OK, verify OK; 44 plugins restored,
   `monitors.lua` parked as `monitors.lua.from-omarchy-lab`.
7. `omocachy-doctor.sh --bundle`: 0 failed, 0 warnings, including
   `hyprctl configerrors` clean and `omarchy-shell shell ping` answering.
8. `./lab test`: all green (boot, session, `hyprctl reload`, 254 keybindings,
   `shell.json`, shell IPC, `lock isLocked`, tmux, herdr).
9. Screenshot `run/shots/after-import-2.png`: the pristine guest renders the
   migrated bar (workspaces, nettraf counters, clock, moon, indicators,
   tray) and the liquidglass sunrise/prayer widget — i.e. the profile, not
   Omarchy defaults.
10. `rollback.sh --dry-run` then a real rollback: guest back to 0 plugins,
    parked file gone, config valid after a reload. Re-import afterwards
    proved a second run is idempotent and writes its own backup set.

## Still unverified (release gates)

- **The CachyOS half remains untested on real CachyOS** — unchanged from plan
  015 gate 1. The lab can only run an Omarchy guest (`LAB_DISTRO` supports
  omarchy/debian/fedora), so `install-omarchy-quattro.sh` has still only been
  dry-run there, and the doctor's CachyOS branches (`ID=cachyos`,
  `[cachyos*]` repos, the HOOKS drop-in) SKIP on an Omarchy host.
- **The `packages` and `mise` stages never ran against a network.** Their
  classification is verified, the transactions are not.
- **`--restore-host-specific`** and the AUR-helper path are code-reviewed but
  not executed.
