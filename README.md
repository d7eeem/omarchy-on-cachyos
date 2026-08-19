# omarchy-on-cachyos

- UPDATE 18-August-2026: Omarchy 4 ("Quattro") is now supported via a new package-install wrapper, `bin/install-omarchy-quattro.sh`. This is now the recommended installation path; see §3.
- UPDATE 17-August-2026: Interactive version selection with a tested-and-verified default (currently v3.8.4); see §2.

## 1. Introduction

This project provides an installation script for implementing DHH's Omarchy configuration on top of CachyOS. Omarchy is an 'opinionated' desktop setup, based on Hyprland that emphasizes simplicity and productivity, while CachyOS offers a performance-optimized Arch Linux distribution.

## 2. What This Script Does and Does Not Do

This installation script does the following:

  1) Prompts for and fetches your preferred version of Omarchy (Stable tags or Bleeding Edge)
  2) Makes adjustments to the Omarchy install scripts to support installation on CachyOS
  3) Launches the installation of Omarchy on an already setup CachyOS system
  4) Detects your GPU vendor and dispatches accordingly: on NVIDIA systems it detects and respects whatever driver CachyOS already has installed; on AMD systems it installs the AMDGPU driver profile plus ROCm/VA-API packages

The CachyOS patches this script applies are tested against the version pinned as `TESTED_OMARCHY_REF` in `bin/fetch-omarchy.sh` (currently `v3.8.4`). Selecting any other version prompts for explicit confirmation, and every patch is verified against the actual file contents at patch time; if a pattern doesn't match, the installer aborts loudly instead of half-applying. Omarchy v4.0.0 ("Quattro") changed its install architecture entirely (no `install.sh`; it installs via Arch packages applied by `omarchy-apply-system` from an ISO/chroot instead), so this clone-and-patch script cannot support it — see §3 for the separate wrapper that does.

Note on updates: do not use Omarchy's built-in `omarchy-update` after installing via this script — the pinned checkout makes it fail immediately with a git error (harmless: it changes nothing, and your CachyOS patches are untouched). To update, re-run this installer when a newer tested version is available.

This script does not:

 1) Install CachyOS or any other Linux operating system
 2) Partition, format, or encrypt hard disks
 3) Install or configure a boot loader
 4) Install a display manager package (SDDM must already be present — see §5.3 — before this script's Omarchy install step configures it further)

All of the above need to be done when you install CachyOS. 

## 3. Installing Omarchy 4 (Quattro) — Recommended

Omarchy 4 ("Quattro") is not a source tree with an `install.sh` anymore — it ships as Arch packages (`omarchy`, `omarchy-settings`, `omarchy-keyring`, `omarchy-nvim`) that a script called `omarchy-apply-system` applies from an ISO chroot. `bin/install-omarchy-quattro.sh` is a **package-install wrapper**, not a clone-and-patch script: it adds the `omarchy` pacman repo, installs those packages, runs `omarchy-apply-system` on your already-installed CachyOS system, and reconciles the parts of that process that would otherwise clobber CachyOS state. This is now the recommended way to install Omarchy on CachyOS.

**What the wrapper does:**

1. Adds the `[omarchy]` repo to `/etc/pacman.conf` (`SigLevel = Required DatabaseOptional` — the stable channel signs every package but not the repo database itself) and imports/locally signs the Omarchy packaging key.
2. Installs `omarchy-settings`, `omarchy`, and `omarchy-nvim` with `pacman -Syu --needed`.
3. Runs `omarchy-apply-system --install-user "$USER" --first-install` as root, which drives Omarchy's own config/hardware/login/post-install stages.
4. Seeds your existing user account the same way Omarchy does for a pre-existing (non-`useradd`-created) user: `omarchy-reinstall-configs` (resyncs shipped defaults from `/etc/skel`) and `omarchy-provision-user --first-install` (the runtime tweaks `/etc/skel` can't seed).
5. Writes the same `~/.config/fish/conf.d/omarchy-on-cachyos.fish` this repo's v3 installer writes (mise + zoxide activation for Fish), and dispatches to this repo's `bin/gpu-setup.sh` (NVIDIA: respect the existing CachyOS driver; AMD: AMDGPU/ROCm profile).

**Reconciliation guarantees** — Omarchy's own install stages do things that are safe on a stock Omarchy machine but destructive on CachyOS if left unreconciled. The wrapper backs up and restores or overrides each of these:

- **CachyOS pacman repos are preserved.** `omarchy-apply-system` overwrites `/etc/pacman.conf` and `/etc/pacman.d/mirrorlist` with Omarchy's own stable-channel versions partway through the apply. The wrapper backs both up beforehand and restores them immediately afterward, re-appending the `[omarchy]` stanza, so your CachyOS repos are never left missing.
- **Boot hooks are preserved.** `omarchy-settings` ships `/etc/mkinitcpio.conf.d/omarchy_hooks.conf`, which sets its own `HOOKS=(...)` array. mkinitcpio applies conf.d files lexically, so this can silently override how your initramfs unlocks a LUKS root (e.g. switching between the classic `encrypt` hook and the systemd `sd-encrypt` hook), which can make an encrypted system unbootable. Before installing any packages, the wrapper captures your system's *effective* current `HOOKS` (main config plus every existing conf.d override, resolved the same way mkinitcpio itself resolves them) and writes it back as `/etc/mkinitcpio.conf.d/zz-cachyos-keep-hooks.conf`, which sorts after `omarchy_hooks.conf` and wins. `mkinitcpio -P` is only run once, deliberately, at the end.
- **Snapper config is preserved.** `install/config/snapper.sh` unconditionally overwrites `/etc/snapper/configs/root`. The wrapper backs it up first and restores the CachyOS version after the apply.
- **User configs are backed up, not silently clobbered.** `omarchy-reinstall-configs` replays `/etc/skel` over your `$HOME`. The wrapper backs up every `$HOME` entry that `/etc/skel` would shadow before running it.

**Bootloader note:** the `omarchy` package hard-depends on `limine`, `limine-mkinitcpio-hook`, and `limine-snapper-sync` — these packages arrive regardless of what bootloader you actually use. If limine is your active bootloader, the wrapper leaves Omarchy's limine integration active. If it is not (grub, systemd-boot), the wrapper disables `limine-snapper-sync.service` and neutralizes `limine-mkinitcpio-hook` with a same-named, no-op override under `/etc/pacman.d/hooks/` — pacman gives hooks in that directory precedence over the package-owned copy in `/usr/share/libalpm/hooks/`, so this fully disables it without modifying any package-owned file (and without breaking future pacman transactions).

After the apply, the wrapper runs a hard-failing assertion suite: CachyOS repos and `[omarchy]` both present, boot hooks still contain the pre-install LUKS unlock hook when LUKS is in use, `limine-snapper-sync.service` disabled on non-limine machines, `sddm`/`NetworkManager` enabled, the snapper config matches the pre-install backup, and the `omarchy` CLI is present.

**Dry run:** `bin/install-omarchy-quattro.sh --dry-run` performs all read-only detection (bootloader, LUKS, GPU vendor, current boot hooks, existing repos) for real but prints every state-changing or privileged command with a `DRYRUN:` prefix instead of running it, so you can review the exact plan before committing to it. Add `--yes` to skip the confirmation prompt (still safe in combination with `--dry-run`).

```bash
git clone https://github.com/mroboff/omarchy-on-cachyos.git
cd omarchy-on-cachyos
bin/install-omarchy-quattro.sh --dry-run   # review the plan first
bin/install-omarchy-quattro.sh             # then run it for real
```

**The v3 clone-and-patch path (§§4–8 below, `bin/install-omarchy-on-cachyos.sh`) remains available and unchanged** for anyone who wants to stay on Omarchy v3.

## 4. Important Notes

This script (and README.md) is intended primarily for the experienced Arch Linux user. The author of this README.md assumes the reader is comfortable using a shell/command line and is familiar with Arch specific terms such as AUR.

The philosophy behind this script is to produce a strong and stable blend of CachyOS and Omarchy that changes as little as possible between the two. This script does not add software or make configuration changes outside of what CachyOS or Omarchy provide as default, except when such software or configurations provided by CachyOS and Omarchy are in conflict. In these cases, the script will choose the following:

1. AUR helper: CachyOS uses Paru by default while Omarchy uses Yay. This script opts for Yay and will install it if not already installed.

2. Shell: CachyOS uses the Fish shell by default while Omarchy uses Bash. This script will keep Fish as the default interactive shell.

3. TLDR implementation: CachyOS installs Tealdeer by default, which is a TLDR implementation written in Rust. This script will preserve use of Tealdeer.

4. Mise and zoxide: Omarchy only wires up Mise activation for Bash, and only installs zoxide (a base package) without initializing it for any shell but Bash. This script activates both for the Fish shell by writing `~/.config/fish/conf.d/omarchy-on-cachyos.fish`, which survives upstream changes to Omarchy's own activation scripts.

5. Login System: Omarchy's installer (`install/login/sddm.sh`) does configure SDDM: it installs an Omarchy SDDM theme, writes `/etc/sddm.conf.d/10-wayland.conf` and `/etc/sddm.conf.d/autologin.conf` (Wayland plus autologin as your user into the `omarchy` UWSM session), trims the gnome-keyring lines from `/etc/pam.d/sddm`, and runs `systemctl enable sddm.service`. This script runs that step unmodified — it does not install the SDDM package itself, but CachyOS's Hyprland Desktop Environment option does (see §5.3), so SDDM is already present and enabled by the time Omarchy's installer runs. Because `/etc/sddm.conf` takes precedence over every file in `/etc/sddm.conf.d/` (see `man 5 sddm.conf`), this script deletes any pre-existing `/etc/sddm.conf` before running Omarchy's installer, so Omarchy's drop-ins are the ones that actually take effect rather than being silently overridden. Testing found no CachyOS-owned files under `/etc/sddm.conf.d/` on a stock CachyOS Hyprland install, so there is nothing there for Omarchy's drop-ins to conflict with.

6. Full Disk Encryption: As a distribution, Omarchy automatically turns on full disk encryption via LUKS. This script, however, leaves this decision up to the user. CachyOS can be installed with or without full disk encryption, and this script will install Omarchy on either setup.

7. GPU Drivers: *This script detects your GPU vendor and dispatches accordingly. On NVIDIA systems, it detects and respects whatever NVIDIA driver CachyOS already has installed rather than pinning or downgrading a specific series. On AMD systems, it installs the AMDGPU driver profile via CachyOS's* `chwd` *tool along with ROCm and VA-API packages. On hybrid NVIDIA+AMD systems, the NVIDIA path wins (see the detection order in* `bin/gpu-detect.sh`*). Intel-only systems are left untouched.*

## 5. Pre-Requisites

IMPORTANT: This script does not install CachyOS. You must do that separately (and first.) This script is intended to be run on a fresh installation of CachyOS with the following configuration choices made: (Note, for information on installing CachyOS, please refer to https://www.cachyos.org.) 

1. File System: You must choose BTRFS as the file system and Snapper as the snapshot manager. This aligns with CachyOS's default recommendation for most systems, and is required for Omarchy to properly function.

2. Shell: You must choose Fish as the default shell for this installation script to work properly. (This is the default CachyOS shell choice.)

3. Desktop Environment to Install: You can install a minimal system with no desktop environment or you can choose to install the CachyOS Hyprland Desktop Environment. If you have CachyOS install Hyprland, it will also install SDDM as the login display manager by default. Do not install GNOME or KDE. Omarchy's own installer later reconfigures this SDDM install for Wayland and autologin into its `omarchy` session (see §4.5); this script clears any pre-existing `/etc/sddm.conf` first so that reconfiguration takes effect cleanly.

4. Graphics Drivers: This script detects your GPU vendor (`bin/gpu-detect.sh`) and dispatches setup accordingly (`bin/gpu-setup.sh`). On NVIDIA systems, it detects and respects whatever driver CachyOS already has installed rather than pinning or downgrading to a specific series. On AMD systems, it installs the AMDGPU driver profile via CachyOS `chwd`, plus the ROCm runtime and VA-API packages (`bin/amd-rocm.sh`) — VA-API only, since Mesa dropped VDPAU support upstream. On hybrid NVIDIA+AMD systems, the NVIDIA path wins (see the detection order in `bin/gpu-detect.sh`). Intel-only systems are left untouched by this script.

   **Important (NVIDIA users):** 

   To enable hardware video decode via NVDEC in chromium, you must:
   
   1. Add the following to `~/.config/chromium-flags.conf`:       ```       --enable-features=VaapiOnNvidiaGPUs       ```
   2. Install the [enhanced-h264ify extension](https://chromewebstore.google.com/detail/enhanced-h264ify/omkfmpieigblcllmkgbflkikinpkodlk) and disable **VP8** and **AV1** codecs.
   
   
   
   To fully enable hardware acceleration in Firefox, you must 
   
   1. Install the [enhanced-h264ify add-on](https://addons.mozilla.org/en-US/firefox/addon/enhanced-h264ify/) and disable **VP8** and **AV1** codecs and manually add the following overrides to your `user.js`:
   
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

Other configuration changes are up to you. Note, however, that this script has not been extensively tested on various CachyOS installations other than the author's own machine.

## 6. Installation Instructions

```bash
# Clone the repository
git clone https://github.com/mroboff/omarchy-on-cachyos.git

# Navigate to the project directory
cd omarchy-on-cachyos/bin

# Make the script executable
chmod +x install-omarchy-on-cachyos.sh

# Run the installation script
./install-omarchy-on-cachyos.sh
```

**Note:** Please review the script contents before running to understand what changes will be made to your system.

## 7. Optional: Debloating (a-la-carchy)

Omarchy ships a large default app selection. [a-la-carchy](https://github.com/DanielCoffey1/a-la-carchy)
(by [Daniel Coffey](https://github.com/DanielCoffey1)) is a community
interactive TUI for removing default apps and webapps you don't want, with
per-item selection and confirmation prompts, plus some theme/keybind/monitor
tweaks.

a-la-carchy is third-party and has no LICENSE file in its repository, so this
repo does not bundle or vendor it. Instead, `bin/install-omarchy-on-cachyos.sh`
offers to launch it at the end of installation via `bin/debloat.sh`, which
fetches the script the same way upstream's own README instructs
(`bash <(curl -fsSL .../a-la-carchy.sh)`) but from a commit this repo has
reviewed and pinned, verifying its sha256 checksum before running it — so an
unreviewed change upstream is refused rather than executed silently. You can
also run it standalone anytime with `bin/debloat.sh`.

**Omarchy 4 (Quattro) users:** a-la-carchy targets Omarchy v3's waybar/walker
stack and is not wired into the Quattro install path. Use Omarchy's built-in
`omarchy-remove-preinstalls` instead.

## 8. Statement of Lack of Warranty

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Use this script at your own risk. Always backup your system and important data before running installation scripts.

## 9. How to Contribute

We welcome contributions to improve this project! Here's how you can help:

1. **Fork the Repository**: Click the "Fork" button on GitHub to create your own copy
2. **Create a Feature Branch**: `git checkout -b feature/your-feature-name`
3. **Make Your Changes**: Implement your improvements or fixes
4. **Commit Your Changes**: `git commit -m "Add descriptive commit message"`
5. **Push to Your Fork**: `git push origin feature/your-feature-name`
6. **Open a Pull Request**: Submit a PR with a clear description of your changes

### Contribution Guidelines
- Test your changes thoroughly on CachyOS before submitting
- Follow existing code style and conventions
- Update documentation if adding new features
- Report bugs using GitHub Issues 
