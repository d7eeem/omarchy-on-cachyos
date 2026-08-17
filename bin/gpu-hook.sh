#!/bin/bash
# Installed as install/config/hardware/nvidia.sh by omarchy-on-cachyos.
# Delegates to the vendor-dispatching setup bundled alongside it.
set -e
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$HOOK_DIR/omarchy-on-cachyos/gpu-setup.sh"
