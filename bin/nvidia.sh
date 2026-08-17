#!/bin/bash
set -e

# --- NVIDIA Configuration for Omarchy on CachyOS ---
# Philosophy: detect and use whatever NVIDIA driver CachyOS has installed.
# Only install a driver if none is present. Never downgrade or force-replace.

# Exit early if no NVIDIA GPU is present
if ! lspci -nn -d 10de: | grep -qE "VGA|3D"; then
    echo "[*] No NVIDIA GPU found. Skipping."
    exit 0
fi

GPU_NAME=$(lspci -d 10de: | grep -E "VGA|3D" | head -n1 | sed 's/.*: //')
echo "[*] NVIDIA GPU detected: $GPU_NAME"

# Determine if a working NVIDIA driver is already installed
# Covers all chwd NVIDIA profiles: nvidia-open-dkms (+ its fallback raw dkms
# package "nvidia-open-dkms"), and the versioned proprietary branches
# nvidia-580xx-{dkms,utils} / nvidia-470xx-{dkms,utils}. "nvidia-utils" (or
# its versioned equivalent) is always present regardless of whether the
# kernel modules come from a per-kernel precompiled package
# (linux-cachyos-nvidia-open) or a raw dkms package, so matching on the
# utils/dkms package name alone is sufficient.
NVIDIA_DRIVER=$(pacman -Qq | grep -E '^nvidia(-open)?(-[0-9]+xx)?-(dkms|utils)$' | head -n1 || true)

if [[ -n "$NVIDIA_DRIVER" ]]; then
    DRIVER_VERSION=$(pacman -Q "$NVIDIA_DRIVER" 2>/dev/null | awk '{print $2}')
    echo "[*] Active NVIDIA driver found: $NVIDIA_DRIVER $DRIVER_VERSION"
    echo "[*] Respecting existing CachyOS driver installation."
else
    echo "[!] No NVIDIA driver detected — installing via chwd..."
    # chwd's -a/--autoconfigure takes at most one PCI classid and defaults to
    # "any" (all PCI+USB classes) when bare, which would also configure
    # unrelated hardware (e.g. fingerprint readers). Scope it to the same
    # PCI classes this script already gates on above (VGA / 3D controller),
    # so only GPU profiles are touched. chwd itself still picks the correct
    # NVIDIA profile variant (open-dkms/580xx/470xx/nouveau) via its own
    # device-id matching.
    for gpu_class_id in 0300 0302; do
        sudo chwd -a "$gpu_class_id"
    done
    echo "[*] Driver installed via CachyOS hardware detection."
fi

# Ensure VA-API utils are present for hardware video acceleration
sudo pacman -S --needed --noconfirm libva-utils

# Apply NVIDIA environment variables for UWSM/Hyprland
mkdir -p "$HOME/.config/uwsm"
if ! grep -q "GBM_BACKEND=nvidia-drm" "$HOME/.config/uwsm/env" 2>/dev/null; then
    cat >>"$HOME/.config/uwsm/env" <<'EOF'

# NVIDIA
export LIBVA_DRIVER_NAME=nvidia
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export NVD_BACKEND=direct
export MOZ_DISABLE_RDD_SANDBOX=1
export CUDA_DISABLE_PERF_BOOST=1
EOF
    echo "[*] NVIDIA environment variables written to ~/.config/uwsm/env"
else
    echo "[*] NVIDIA environment variables already present."
fi

echo "[*] NVIDIA configuration complete."
