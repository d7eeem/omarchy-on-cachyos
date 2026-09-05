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

# 5. Session environment for ROCm. ~/.config/uwsm/env is the user's own file
# (often dotfile-managed), so it is never appended to. uwsm also sources
# ~/.config/uwsm/env.d/* (uwsm(1) CONFIGURATION: "uwsm/env, uwsm/env.d/*"),
# which gives this script a file it owns outright and can rewrite on re-runs.
# OMOCACHY_SKIP_USER_CONFIGS=1 (install-omarchy-quattro.sh --skip-user-configs)
# means $HOME is off limits: print the lines for the user to place themselves.
GPU_ENV_FILE="$HOME/.config/uwsm/env.d/50-omocachy-gpu"
GPU_ENV_CONTENT='# Written by omocachy bin/amd-rocm.sh (AMD ROCm)
export LIBVA_DRIVER_NAME=radeonsi
export ROCM_HOME=/opt/rocm
export PATH=$ROCM_HOME/bin:$PATH'
if [[ ${OMOCACHY_SKIP_USER_CONFIGS:-0} == 1 ]]; then
    echo "[*] --skip-user-configs: not writing $GPU_ENV_FILE. Recommended session environment (add to your own uwsm env or env.d file):"
    printf '%s\n' "$GPU_ENV_CONTENT"
else
    mkdir -p "$(dirname "$GPU_ENV_FILE")"
    printf '%s\n' "$GPU_ENV_CONTENT" >"$GPU_ENV_FILE"
    echo "[*] AMD ROCm session environment written to $GPU_ENV_FILE"
fi
