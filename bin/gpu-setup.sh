#!/bin/bash
set -e

GPU_TYPE=$(bash ./bin/gpu-detect.sh)

case "$GPU_TYPE" in
    nvidia)
        echo "[*] NVIDIA GPU detected, running nvidia.sh..."
        bash ./bin/nvidia.sh
        ;;
    amd)
        echo "[*] AMD GPU detected, running amd-rocm.sh..."
        bash ./bin/amd-rocm.sh
        ;;
    none)
        echo "[*] No GPU detected, skipping GPU setup."
        exit 0
        ;;
esac
