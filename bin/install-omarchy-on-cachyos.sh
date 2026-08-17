#!/bin/bash
set -euo pipefail

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

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "Error: git is not installed. Please install git before running this script."
    exit 1
fi

# Fetch Omarchy from repo
echo "Fetching Omarchy source..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OMARCHY_DIR="$REPO_DIR/omarchy"
export OMARCHY_DIR

if [ -f "$SCRIPT_DIR/fetch-omarchy.sh" ]; then
    chmod +x "$SCRIPT_DIR/fetch-omarchy.sh"
    "$SCRIPT_DIR/fetch-omarchy.sh"
else
    # Fallback if script is missing
    echo "fetch-omarchy.sh not found, falling back to default clone..."
    git clone https://github.com/basecamp/omarchy "$OMARCHY_DIR"
fi

if [ ! -d "$OMARCHY_DIR" ]; then
    echo "Error: Failed to fetch Omarchy source at $OMARCHY_DIR"
    exit 1
fi

# Check if yay is installed
if ! command -v yay &> /dev/null; then
    echo "yay is not installed. Installing yay..."

    # Install dependencies for building yay
    sudo pacman -S --needed --noconfirm git base-devel

    # Clone and build yay
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)

    # Clean up
    rm -rf /tmp/yay

    if ! command -v yay &> /dev/null; then
        echo "Error: Failed to install yay."
        exit 1
    fi

    echo "yay has been successfully installed."
else
    echo "yay is already installed."
fi

# Receive the Omarchy signing key
sudo pacman-key --recv-keys F0134EE680CAC571

# Locally sign and trust the key
sudo pacman-key --lsign-key F0134EE680CAC571

# Add omarchy repository to pacman.conf (skip if already present)
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
    echo -e "\n[omarchy]\nSigLevel = Required DatabaseOptional\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
else
    echo "Omarchy repository already present in pacman.conf, skipping."
fi
sudo pacman -Syu

# Remove CachyOS SDDM config
if [ -f /etc/sddm.conf ]; then
    echo "Removing /etc/sddm.conf"
    sudo rm /etc/sddm.conf
fi

# Prompt user for username
echo ""
echo "Please enter your username:"
read -r OMARCHY_USER_NAME
export OMARCHY_USER_NAME

# Prompt user for email address
echo ""
echo "Please enter your email address:"
read -r OMARCHY_USER_EMAIL
export OMARCHY_USER_EMAIL

# Make adjustments to Omarchy install scripts to support CachyOS
echo ""
echo "Making adjustments to Omarchy install scripts to support CachyOS..."

# Navigate to Omarchy install scripts
cd "$OMARCHY_DIR"

# Omarchy v4.0.0+ removed install.sh entirely (package/ISO-based install
# architecture), which this repo's clone-and-patch approach cannot support.
test -f install.sh || { echo "Error: this Omarchy version has no install.sh (v4+ changed its install architecture and is not supported yet). Re-run and select the tested v3.8.4 release." >&2; exit 1; }

# Remove tldr installation to prevent conflict with tealdeer install.
patch_or_die install/omarchy-base.packages '^tldr$' '/^tldr$/d'

# Remove pacman.sh from preflight/all.sh to prevent conflict with cachyos packages
patch_or_die install/preflight/all.sh 'preflight/pacman\.sh' '/run_logged \$OMARCHY_INSTALL\/preflight\/pacman\.sh/d'

# Replace upstream nvidia.sh with a GPU dispatcher
# (NVIDIA: respect existing CachyOS drivers; AMD: Mesa/ROCm setup — see bin/gpu-setup.sh)
test -d install/config/hardware || { echo "PATCH FAILED: install/config/hardware missing." >&2; exit 1; }
mkdir -p install/config/hardware/omarchy-on-cachyos
cp "$SCRIPT_DIR/gpu-detect.sh" "$SCRIPT_DIR/gpu-setup.sh" "$SCRIPT_DIR/nvidia.sh" "$SCRIPT_DIR/amd-rocm.sh" \
   install/config/hardware/omarchy-on-cachyos/
chmod +x install/config/hardware/omarchy-on-cachyos/*.sh
cp "$SCRIPT_DIR/gpu-hook.sh" install/config/hardware/nvidia.sh
chmod +x install/config/hardware/nvidia.sh

# Remove plymouth.sh source line from install.sh
patch_or_die install/login/all.sh 'login/plymouth\.sh' '/run_logged \$OMARCHY_INSTALL\/login\/plymouth\.sh/d'

# Remove limine-snapper.sh source line from install.sh
patch_or_die install/login/all.sh 'login/limine-snapper\.sh' '/run_logged \$OMARCHY_INSTALL\/login\/limine-snapper\.sh/d'

# Remove pacman.sh from post-install/all.sh to prevent conflict with cachyos packages
patch_or_die install/post-install/all.sh 'post-install/pacman\.sh' '/run_logged \$OMARCHY_INSTALL\/post-install\/pacman\.sh/d'

# Disable wpa_supplicant and configure NetworkManager to use iwd backend.
# CachyOS enables wpa_supplicant by default, which conflicts with omarchy's iwd,
# causing WiFi to appear connected but have no IP or connectivity.
test -f install/config/hardware/network.sh || { echo "PATCH FAILED: network.sh missing." >&2; exit 1; }
cat >> install/config/hardware/network.sh << 'NETEOF'

# Disable wpa_supplicant to prevent conflict with iwd
sudo systemctl disable --now wpa_supplicant.service 2>/dev/null

# Configure NetworkManager to use iwd as its WiFi backend
if ! grep -q "wifi.backend=iwd" /etc/NetworkManager/NetworkManager.conf 2>/dev/null; then
  sudo tee -a /etc/NetworkManager/NetworkManager.conf > /dev/null << EOF

[device]
wifi.backend=iwd
EOF
fi
NETEOF

# Pin walker to the omarchy repo so CachyOS doesn't override it with an
# incompatible version that breaks compatibility with elephant.
test -f install/config/walker-elephant.sh || { echo "PATCH FAILED: walker-elephant.sh missing." >&2; exit 1; }
sed -i '1a\
# Pin walker to omarchy repo to prevent CachyOS version conflict\
if ! grep -q "^IgnorePkg.*walker" /etc/pacman.conf 2>/dev/null; then\
  if grep -q "^IgnorePkg" /etc/pacman.conf; then\
    sudo sed -i '"'"'s/^IgnorePkg = \\(.*\\)/IgnorePkg = \\1 walker/'"'"' /etc/pacman.conf\
  else\
    sudo sed -i '"'"'/^\\[options\\]/a IgnorePkg = walker'"'"' /etc/pacman.conf\
  fi\
fi\
' install/config/walker-elephant.sh
grep -q "IgnorePkg.*walker" install/config/walker-elephant.sh || { echo "PATCH FAILED: walker pin not applied." >&2; exit 1; }

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

# Pause and prompt for acknowledgment to begin installation
echo ""
echo "The following adjustments have been completed."
echo " 1. Added Omarchy repo to pacman.conf"
echo " 2. Removed tldr from omarchy-base.packages to avoid conflict with tealdeer on CachyOS."
echo " 3. Disabled further Omarchy changes to pacman.conf, preserving CachyOS settings."
echo " 4. Replaced nvidia.sh with a GPU dispatcher (NVIDIA: respect existing CachyOS drivers; AMD: Mesa/ROCm setup)."
echo " 5. Removed plymouth.sh from install.sh to avoid conflict with CachyOS login display manager installation."
echo " 6. Removed limine-snapper.sh from install.sh to avoid conflict with CachyOS boot loader installation."
echo " 7. Removed /etc/sddm.conf to avoid conflict with Omarchy UWSM session autologin."
echo " 8. Disabled wpa_supplicant and configured NetworkManager to use iwd backend."
echo " 9. Pinned walker to omarchy repo to prevent CachyOS version conflict."
echo "10. Added mise and zoxide integration for the fish shell."
echo ""
echo "IMPORTANT: If you installed CachyOS without a desktop environment, you will not have a display manager installed."
echo "If this is the case, you will need to run the following command after this installation script is complete:"
echo " 1.) ~/.local/share/omarchy/install/login/plymouth.sh"  
echo ""
echo "The above script will modify your boot to start Omarchy's Hyprland desktop automatically."
echo ""
echo "Press Enter to begin the installation of Omarchy..."
read -r

# Run the modified install.sh script 
chmod +x install.sh
./install.sh
