# omarchy-on-cachyos

- UPDATE 20-May-2026: The install script now includes interactive version selection for choosing between Stable releases and Bleeding Edge.
- UPDATE 1-October-2025: The install script has been updated to support Omarchy 3.0+ out of the box.

## 1. Introduction

This project provides an installation script for implementing DHH's Omarchy configuration on top of CachyOS. Omarchy is an 'opinionated' desktop setup, based on Hyprland that emphasizes simplicity and productivity, while CachyOS offers a performance-optimized Arch Linux distribution.

## 2. What This Script Does and Does Not Do

This installation script does the following three things:

  1) Prompts for and fetches your preferred version of Omarchy (Stable tags or Bleeding Edge)
  2) Makes adjustments to the Omarchy install scripts to support installation on CachyOS
  3) Launches the installation of Omarchy on an already setup CachyOS system
  4) Detects your GPU vendor and dispatches accordingly: on NVIDIA systems it detects and respects whatever driver CachyOS already has installed; on AMD systems it installs the AMDGPU driver profile plus ROCm/VA-API packages

The CachyOS patches this script applies are tested against the version pinned as `TESTED_OMARCHY_REF` in `bin/fetch-omarchy.sh` (currently `v3.8.4`). Selecting any other version prompts for explicit confirmation, and every patch is verified against the actual file contents at patch time; if a pattern doesn't match, the installer aborts loudly instead of half-applying. Omarchy v4.0.0+ changed its install architecture (no `install.sh`; it installs via Arch packages from an ISO/chroot instead) and is not yet supported by this project.

This script does not:

 1) Install CachyOS or any other Linux operating system
 2) Partition, format, or encrypt hard disks
 3) Install or configure a boot loader
 5) Install or configure a login display manager

All of the above need to be done when you install CachyOS. 

## 3. Important Notes

This script (and README.md) is intended primarily for the experienced Arch Linux user. The author of this README.md assumes the reader is comfortable using a shell/command line and is familiar with Arch specific terms such as AUR.

The philosophy behind this script is to produce a strong and stable blend of CachyOS and Omarchy that changes as little as possible between the two. This script does not add software or make configuration changes outside of what CachyOS or Omarchy provide as default, except when such software or configurations provided by CachyOS and Omarchy are in conflict. In these cases, the script will choose the following:

1. AUR helper: CachyOS uses Paru by default while Omarchy uses Yay. This script opts for Yay and will install it if not already installed.

2. Shell: CachyOS uses the Fish shell by default while Omarchy uses Bash. This script will keep Fish as the default interactive shell.

3. TLDR implementation: CachyOS installs Tealdeer by default, which is a TLDR implementation written in Rust. This script will preserve use of Tealdeer.

4. Mise and zoxide: Omarchy only wires up Mise activation for Bash, and only installs zoxide (a base package) without initializing it for any shell but Bash. This script activates both for the Fish shell by writing `~/.config/fish/conf.d/omarchy-on-cachyos.fish`, which survives upstream changes to Omarchy's own activation scripts.

5. Login System: As a distribution, Omarchy skips installation of a login display manager. Instead, Hyprland autostarts and password protection is provided upon boot by the LUKS full disk encryption service. This script, however, assumes a display manager is installed. (Note: this script does not install a display manager, but also does not configure Hyprland to start automatically if a display manager is not installed.)

6. Full Disk Encryption: As a distribution, Omarchy automatically turns on full disk encryption via LUKS. This script, however, leaves this decision up to the user. CachyOS can be installed with or without full disk encryption, and this script will install Omarchy on either setup.

7. GPU Drivers: *This script detects your GPU vendor and dispatches accordingly. On NVIDIA systems, it detects and respects whatever NVIDIA driver CachyOS already has installed rather than pinning or downgrading a specific series. On AMD systems, it installs the AMDGPU driver profile via CachyOS's* `chwd` *tool along with ROCm and VA-API packages. On hybrid NVIDIA+AMD systems, the NVIDIA path wins (see the detection order in* `bin/gpu-detect.sh`*). Intel-only systems are left untouched.*

## 4. Pre-Requisites

IMPORTANT: This script does not install CachyOS. You must do that separately (and first.) This script is intended to be run on a fresh installation of CachyOS with the following configuration choices made: (Note, for information on installing CachyOS, please refer to https://www.cachyos.org.) 

1. File System: You must choose BTRFS as the file system and Snapper as the snapshot manager. This aligns with CachyOS's default recommendation for most systems, and is required for Omarchy to properly function.

2. Shell: You must choose Fish as the default shell for this installation script to work properly. (This is the default CachyOS shell choice.)

3. Desktop Environment to Install: You can install a minimal system with no desktop environment or you can choose to install the CachyOS Hyprland Desktop Environment. If you have CachyOS install Hyprland, it will also install SDDM as the login display manager by default. Do not install GNOME or KDE.

4. Graphics Drivers: 

5. This script detects your GPU vendor (`bin/gpu-detect.sh`) and dispatches setup accordingly (`bin/gpu-setup.sh`). On NVIDIA systems, it detects and respects whatever driver CachyOS already has installed rather than pinning or downgrading to a specific series. On AMD systems, it installs the AMDGPU driver profile via CachyOS `chwd`, plus the ROCm runtime and VA-API packages (`bin/amd-rocm.sh`) — VA-API only, since Mesa dropped VDPAU support upstream. On hybrid NVIDIA+AMD systems, the NVIDIA path wins (see the detection order in `bin/gpu-detect.sh`). Intel-only systems are left untouched by this script.

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

## 5. Installation Instructions

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

## 6. Statement of Lack of Warranty

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Use this script at your own risk. Always backup your system and important data before running installation scripts.

## 7. How to Contribute

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
