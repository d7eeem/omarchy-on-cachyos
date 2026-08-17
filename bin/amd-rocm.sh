#!/bin/bash
set -e

# 1. Get AMD GPU ID
GPU_ID=$(lspci -nn -d 1002: | grep -E "VGA|3D" | head -n1 | grep -oP '(?<=\[1002:)[0-9a-fA-F]{4}(?=\])')

if [[ -z "$GPU_ID" ]]; then
    echo "No AMD GPU found. Skipping."
    exit 0
fi

echo "[*] Found AMD GPU ID: $GPU_ID"

# 2. Leftover NVIDIA packages are inert on an AMD-only machine; forced
# removal risks breaking hybrid AMD+NVIDIA systems, and chwd's amd profile
# needs no removals (see plan 007).

# 3. Install AMD driver profile via chwd
echo "[*] Installing AMD AMDGPU driver profile..."
sudo chwd -i amd

# 4. Install ROCm runtime + VA-API utils
echo "[*] Installing ROCm and VA-API packages..."
sudo pacman -S --needed --noconfirm rocm-core rocm-hip-runtime rocm-smi-lib libva-utils

# 5. Add AMD ROCm environment variables for UWSM
mkdir -p "$HOME/.config/uwsm"
if ! grep -q '^# AMD ROCm$' "$HOME/.config/uwsm/env" 2>/dev/null; then
    cat >>"$HOME/.config/uwsm/env" <<'EOF'

# AMD ROCm
export LIBVA_DRIVER_NAME=radeonsi
export ROCM_HOME=/opt/rocm
export PATH=$ROCM_HOME/bin:$PATH
EOF
    echo "[*] AMD ROCm environment variables written to ~/.config/uwsm/env"
else
    echo "[*] AMD ROCm environment variables already present."
fi
