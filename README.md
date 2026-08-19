# omarchy-on-cachyos

Install [DHH's Omarchy](https://omarchy.org) — an opinionated, Hyprland-based
desktop — on top of [CachyOS](https://cachyos.org), a performance-optimized
Arch Linux distribution, without either one clobbering the other.

The project provides two installation paths plus optional debloaters:

| Path | Script | Status |
|------|--------|--------|
| **Omarchy 4 "Quattro"** (packages) | `bin/install-omarchy-quattro.sh` | **Recommended** |
| Omarchy 3 (clone-and-patch) | `bin/install-omarchy-on-cachyos.sh` | Legacy, maintained |
| Optional debloater: per-item picker (Omarchy 4) | `bin/debloat-quattro.sh` | Opt-in, v4 only |
| Optional debloater: a-la-carchy (Omarchy 3) | `bin/debloat.sh` | Opt-in, v3 only |

This README assumes an experienced Arch user — comfortable with the shell and
with Arch terms like AUR.

## 1. What This Project Does and Does Not Do

Both installers take an **already-installed CachyOS system** and put Omarchy
on top of it, resolving the places where the two distributions' defaults
collide (see §5). They detect your GPU vendor and configure drivers
accordingly (see §6).

Neither installer:

1. Installs CachyOS or any other Linux operating system
2. Partitions, formats, or encrypts hard disks
3. Installs or configures a boot loader
4. Installs a display manager package (SDDM must already be present — see
   §2.3 — before Omarchy's install step configures it further)

All of the above happen when you install CachyOS itself.

## 2. Prerequisites: How to Install CachyOS First

Install CachyOS before running anything here (see
[cachyos.org](https://www.cachyos.org) for instructions), with these choices:

1. **File system**: BTRFS with Snapper as the snapshot manager. This aligns
   with CachyOS's default recommendation and is required for Omarchy to
   function properly.
2. **Shell**: Fish (the CachyOS default). The installers assume it.
3. **Desktop environment**: either a minimal install with no desktop, or the
   CachyOS Hyprland Desktop Environment (which also installs SDDM as the
   display manager). Do not install GNOME or KDE. Omarchy's installer later
   reconfigures SDDM for Wayland and autologin into its `omarchy` session;
   this repo's installers clear any pre-existing `/etc/sddm.conf` first so
   that reconfiguration actually takes effect (see §5.5).
4. **Full disk encryption**: your choice. Omarchy-the-distribution always
   encrypts; CachyOS makes it optional, and this project works either way.
5. **Bootloader**: any. Limine gets the most seamless Omarchy 4 integration
   (see §3); GRUB and systemd-boot are handled safely.

Other configuration choices are up to you — but note this project has not
been extensively tested beyond the maintainers' own machines.

## 3. Installing Omarchy 4 (Quattro) — Recommended

Omarchy 4 is no longer a source tree with an `install.sh`. It ships as Arch
packages (`omarchy`, `omarchy-settings`, `omarchy-keyring`, `omarchy-nvim`)
that a script called `omarchy-apply-system` applies from an ISO chroot.
`bin/install-omarchy-quattro.sh` is therefore a **package-install wrapper**,
not a clone-and-patch script: it adds the omarchy pacman repo, installs the
packages, runs `omarchy-apply-system` on your live CachyOS system, and
reconciles everything in that process that would otherwise clobber CachyOS
state.

```bash
git clone https://github.com/d7eeem/omarchy-on-cachyos.git
cd omarchy-on-cachyos
bin/install-omarchy-quattro.sh --dry-run   # review the exact plan first
bin/install-omarchy-quattro.sh             # then run it for real
```

**Dry run first.** `--dry-run` performs all read-only detection for real
(bootloader, LUKS, GPU vendor, current boot hooks, existing repos) but prints
every state-changing or privileged command with a `DRYRUN:` prefix instead of
executing it, so you can review the full plan before committing. `--yes`
skips the confirmation prompt (safe to combine with `--dry-run`).

**What the wrapper does:**

1. Adds the `[omarchy]` repo to `/etc/pacman.conf` with
   `SigLevel = Required DatabaseOptional` (the stable channel signs every
   package but not the repo database) and imports/locally signs the Omarchy
   packaging key.
2. Installs `omarchy-settings`, `omarchy`, and `omarchy-nvim` via
   `pacman -Syu --needed`.
3. Runs `omarchy-apply-system --install-user "$USER" --first-install` as
   root — Omarchy's own config/hardware/login/post-install stages.
4. Seeds your existing user account the way Omarchy handles a pre-existing
   (non-`useradd`-created) user: `omarchy-reinstall-configs` (resyncs
   shipped defaults from `/etc/skel`) then `omarchy-provision-user
   --first-install` (the runtime tweaks `/etc/skel` can't seed).
5. Writes the Fish integration file (mise + zoxide, see §5.4) and dispatches
   GPU setup (see §6).

**Reconciliation guarantees.** Omarchy's install stages are safe on a stock
Omarchy machine but destructive on CachyOS if left alone. The wrapper backs
up, restores, or overrides each of these:

- **CachyOS pacman repos are preserved.** `omarchy-apply-system` overwrites
  `/etc/pacman.conf` *and* `/etc/pacman.d/mirrorlist` with Omarchy's own
  versions partway through. The wrapper backs both up beforehand and
  restores them immediately afterward, re-appending the `[omarchy]` stanza,
  so your CachyOS repos are never left missing.
- **Boot hooks are preserved.** `omarchy-settings` ships
  `/etc/mkinitcpio.conf.d/omarchy_hooks.conf`, which replaces your
  `HOOKS=(...)` array. On a LUKS system that can silently swap the initramfs
  unlock style (classic `encrypt` vs systemd `sd-encrypt`) and make the
  machine unbootable. Before installing any packages, the wrapper captures
  your *effective* current HOOKS (main config plus every conf.d override,
  resolved the way mkinitcpio itself resolves them) and re-asserts them via
  `/etc/mkinitcpio.conf.d/zz-cachyos-keep-hooks.conf`, which sorts after
  Omarchy's file and therefore wins. `mkinitcpio -P` runs once, deliberately,
  at the end.
- **Snapper config is preserved.** Omarchy unconditionally overwrites
  `/etc/snapper/configs/root`; the wrapper backs it up and restores the
  CachyOS version after the apply.
- **User configs are backed up, not silently clobbered.**
  `omarchy-reinstall-configs` replays `/etc/skel` over your `$HOME`; the
  wrapper first backs up every `$HOME` entry that `/etc/skel` would shadow.

**Bootloader handling.** The `omarchy` package hard-depends on `limine`,
`limine-mkinitcpio-hook`, and `limine-snapper-sync` — they arrive via pacman
regardless of your actual bootloader. If Limine is your active bootloader,
the wrapper leaves Omarchy's Limine integration fully active. If it is not
(GRUB, systemd-boot), the wrapper disables `limine-snapper-sync.service` and
neutralizes `limine-mkinitcpio-hook` with a same-named no-op override in
`/etc/pacman.d/hooks/` — pacman gives that directory precedence over the
package-owned copy, so the hook is fully disabled without modifying any
package-owned file or breaking future pacman transactions.

**Verification.** After the apply, a hard-failing assertion suite checks:
CachyOS repos and `[omarchy]` both present; boot hooks still contain the
pre-install LUKS unlock hook when LUKS is in use; `limine-snapper-sync`
disabled on non-Limine machines; `sddm` and `NetworkManager` enabled; the
snapper config matches its pre-install backup; and the `omarchy` CLI exists.

## 4. Installing Omarchy 3 — Legacy Clone-and-Patch Path

The original path, still maintained for anyone staying on Omarchy v3. It
clones `basecamp/omarchy` at a chosen version, patches its install scripts
for CachyOS, and runs Omarchy's own `install.sh`.

```bash
git clone https://github.com/d7eeem/omarchy-on-cachyos.git
cd omarchy-on-cachyos/bin
chmod +x install-omarchy-on-cachyos.sh
./install-omarchy-on-cachyos.sh
```

**Version selection and patch verification.** The installer prompts for an
Omarchy version (stable tags or bleeding edge). The CachyOS patches are
tested against the version pinned as `TESTED_OMARCHY_REF` in
`bin/fetch-omarchy.sh` (currently `v3.8.4`); selecting anything else
requires explicit confirmation. Every patch is verified against the actual
file contents at patch time — on any mismatch the installer aborts loudly
instead of half-applying. Omarchy v4+ trees are refused outright (they have
no `install.sh`; use §3 instead).

**Updates.** Do not use Omarchy's built-in `omarchy-update` after installing
via this path — the pinned checkout makes it fail immediately with a git
error (harmless: it changes nothing, and your CachyOS patches are
untouched). To update, re-run this installer when a newer tested version is
available.

**Note:** review the script contents before running to understand what
changes will be made to your system.

## 5. How CachyOS/Omarchy Conflicts Are Resolved

The philosophy of this project is a strong, stable blend of CachyOS and
Omarchy that changes as little as possible in either. Software and
configuration are only touched where the two distributions' defaults
actually conflict, resolved as follows:

1. **AUR helper**: CachyOS ships Paru, Omarchy uses Yay. Yay wins and is
   installed if missing (v3 path).
2. **Shell**: CachyOS defaults to Fish, Omarchy to Bash. Fish stays your
   default interactive shell.
3. **TLDR client**: CachyOS ships Tealdeer (Rust). Tealdeer is preserved;
   Omarchy's `tldr` package is excluded to avoid the file conflict.
4. **Mise and zoxide on Fish**: Omarchy wires mise activation only for Bash
   and installs zoxide without initializing it for Fish. Both installers
   write `~/.config/fish/conf.d/omarchy-on-cachyos.fish` activating both —
   a file that survives upstream changes to Omarchy's own activation
   scripts.
5. **Login system (SDDM)**: CachyOS's Hyprland option provides the SDDM
   package itself (§2.3); Omarchy then configures it and runs unmodified.
   On v3 that's `install/login/sddm.sh` (theme, Wayland, autologin into the
   `omarchy` UWSM session, PAM keyring trim, `systemctl enable sddm`); on
   v4 the SDDM config ships as package-owned `/etc/sddm.conf.d/` drop-ins
   and `sddm.sh` only trims the PAM keyring lines. Because a legacy
   `/etc/sddm.conf` outranks every file in `/etc/sddm.conf.d/`
   (`man 5 sddm.conf`), both installers delete any pre-existing
   `/etc/sddm.conf` so Omarchy's drop-ins actually take effect. A stock
   CachyOS Hyprland install ships nothing under `/etc/sddm.conf.d/`, so
   there is no conflict there.
6. **Full disk encryption**: left entirely to your CachyOS install choice
   (§2.4); everything here works with or without LUKS.
7. **Networking** (v3 path): CachyOS enables `wpa_supplicant`, which
   conflicts with Omarchy v3's iwd and produces "connected but no traffic"
   WiFi. The v3 installer disables wpa_supplicant and points NetworkManager
   at the iwd backend. (Omarchy 4 switched to NetworkManager itself, so no
   patch is needed on that path.)
8. **Walker pin** (v3 path): CachyOS's walker package breaks compatibility
   with Omarchy v3's elephant; walker is pinned to the omarchy repo via
   `IgnorePkg`.

## 6. GPU Drivers

Both paths use the same vendor dispatch (`bin/gpu-detect.sh` →
`bin/gpu-setup.sh`):

- **NVIDIA**: detect and respect whatever NVIDIA driver CachyOS already has
  installed — no pinning or downgrading. Only if no driver is present is one
  installed via CachyOS's `chwd`, scoped to GPU device classes.
- **AMD**: installs the AMDGPU driver profile via `chwd` plus the ROCm
  runtime and VA-API packages (`bin/amd-rocm.sh`). VA-API only — Mesa
  removed VDPAU support upstream.
- **Hybrid NVIDIA+AMD**: the NVIDIA path wins (see the detection order in
  `bin/gpu-detect.sh`).
- **Intel-only**: left untouched.

### Hardware video acceleration in browsers (NVIDIA)

For NVDEC hardware decode in **Chromium**:

1. Add to `~/.config/chromium-flags.conf`:

   ```
   --enable-features=VaapiOnNvidiaGPUs
   ```

2. Install the
   [enhanced-h264ify extension](https://chromewebstore.google.com/detail/enhanced-h264ify/omkfmpieigblcllmkgbflkikinpkodlk)
   and disable the **VP8** and **AV1** codecs.

For full hardware acceleration in **Firefox**:

1. Install the
   [enhanced-h264ify add-on](https://addons.mozilla.org/en-US/firefox/addon/enhanced-h264ify/)
   and disable the **VP8** and **AV1** codecs.
2. Add these overrides to your `user.js`:

   ```js
   // FORCE NVIDIA HARDWARE ACCELERATION
   user_pref("media.hardware-video-decoding.force-enabled", true);
   user_pref("media.hardware-video-encoding.force-enabled", true);
   user_pref("layers.acceleration.force-enabled", true);
   user_pref("webgl.force-enabled", true);
   user_pref("media.ffmpeg.vaapi.enabled", true);
   user_pref("media.rdd-ffmpeg.enabled", true);
   user_pref("media.av1.enabled", true);
   user_pref("widget.dmabuf.force-enabled", true);
   user_pref("gfx.x11-egl.force-enabled", true);
   ```

## 7. Optional: Debloating

Omarchy ships a large default app selection. This project offers an optional
debloater for each install path — pick the one matching your version.

### Omarchy 4: per-item picker (`bin/debloat-quattro.sh`)

Omarchy 4's built-in `omarchy-remove-preinstalls` is all-or-nothing: one
confirm removes every preinstalled web app, every TUI wrapper, all
agent/mise CLI stubs, and a fixed package list in one shot.
`bin/debloat-quattro.sh` is a per-item alternative — it enumerates the same
candidates (packages, web apps, TUIs, agent CLI stubs) and lets you pick
exactly which ones to remove via a `gum` checklist, one category at a time.

It is derived from `basecamp/omarchy`'s own scripts
(`omarchy-remove-preinstalls` and the `omarchy-webapp-remove-all` /
`omarchy-tui-remove-all` enumeration logic), which are MIT-licensed, with
attribution in the script header. Actual removal is delegated to Omarchy's
own tools (`omarchy-pkg-drop`, `omarchy-webapp-remove`, `omarchy-tui-remove`)
so behavior tracks upstream rather than reimplementing it.

Because Omarchy's `preinstalls-removed` state flag is binary (it doesn't
represent partial removal), the script only sets it if you select
*everything* offered across every category; otherwise it leaves the flag
unset and tells you so, since some Hyprland keybindings/menu entries may
still expect the untouched items.

```bash
bin/debloat-quattro.sh --dry-run   # review what would be removed first
bin/debloat-quattro.sh             # then run it for real
```

To restore everything at any time, run Omarchy's own
`omarchy-install-preinstalls`.

### Omarchy 3: a-la-carchy (`bin/debloat.sh`)

[a-la-carchy](https://github.com/DanielCoffey1/a-la-carchy) (by
[Daniel Coffey](https://github.com/DanielCoffey1)) is a community
interactive TUI for removing default apps and webapps you don't want, with
per-item selection and confirmation prompts, plus theme/keybind/monitor
tweaks.

a-la-carchy is third-party and has no LICENSE file in its repository, so
this repo does not bundle or vendor it. Instead, the v3 installer offers to
launch it at the end of installation via `bin/debloat.sh`, which fetches the
script the same way upstream's own README instructs — but from a commit this
repo has reviewed and pinned, verifying its sha256 checksum before running
it. An unreviewed upstream change is refused rather than executed silently.
You can also run `bin/debloat.sh` standalone at any time.

One caveat: a-la-carchy itself offers to install an Omarchy menu shortcut
that re-launches it from its upstream master branch. Launches via that
shortcut are NOT covered by this repo's pin/checksum — if you enable it, you
are trusting upstream directly; prefer re-running `bin/debloat.sh` instead.

**Omarchy 4 (Quattro) users:** a-la-carchy targets Omarchy v3's
waybar/walker stack and is not wired into the Quattro path. Use
`bin/debloat-quattro.sh` (above) for per-item choice, or Omarchy's built-in
`omarchy-remove-preinstalls` if you want to remove everything at once.

## 8. Statement of Lack of Warranty

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.

Use these scripts at your own risk. Always back up your system and important
data before running installation scripts.

## 9. How to Contribute

We welcome contributions! Here's how:

1. **Fork the repository**: click "Fork" on GitHub
2. **Create a feature branch**: `git checkout -b feature/your-feature-name`
3. **Make your changes**
4. **Commit**: `git commit -m "Add descriptive commit message"`
5. **Push to your fork**: `git push origin feature/your-feature-name`
6. **Open a Pull Request** with a clear description

### Contribution guidelines

- Test your changes thoroughly on CachyOS before submitting
- Follow existing code style and conventions
- Update documentation when adding features
- Report bugs via GitHub Issues
