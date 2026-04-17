#!/bin/bash
set -e

# 1. Get AMD GPU ID
GPU_ID=$(lspci -nn -d 1002: | grep -E "VGA|3D" | head -n1 | grep -oP '(?<=\[1002:)[0-9a-fA-F]{4}(?=\])')

if [[ -z "$GPU_ID" ]]; then
    echo "No AMD GPU found. Skipping."
    exit 0
fi

echo "[*] Found AMD GPU ID: $GPU_ID"

# 2. Remove conflicting packages
echo "[*] Removing conflicting NVIDIA packages..."
sudo pacman -Rdd --noconfirm libxnvctrl linux-cachyos-nvidia-open linux-cachyos-lts-nvidia-open nvidia-open-dkms 2>/dev/null || true

# 3. Install AMD driver profile via chwd
echo "[*] Installing AMD AMDGPU driver profile..."
sudo chwd -a amd-gpu 2>/dev/null || true

# 4. Install ROCm stack
echo "[*] Installing ROCm packages..."
sudo pacman -S --needed --noconfirm rocm-core rocm-hip-runtime rocm-hip-sdk rocm-smi rocm-libs libva-mesa-driver libva-vdpau-driver

# 5. Install VA-API utils
sudo pacman -S --needed --noconfirm libva-utils

# 6. Add AMD ROCm environment variables for UWSM
cat >>$HOME/.config/uwsm/env <<'EOF'

# AMD ROCm
export LIBVA_DRIVER_NAME=radeonsi
export GBM_BACKEND=radeonsi
export HIP_VISIBLE_DEVICES=0
export ROCM_HOME=/opt/rocm
export PATH=$ROCM_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_HOME/lib:$LD_LIBRARY_PATH
export VDPAU_DRIVER=radeonsi
EOF
