#!/usr/bin/env bash
# =============================================================================
# nvidia-check.sh — Post-boot NVIDIA driver health check
# Runs automatically on first login via /etc/profile.d/ or shell rc.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'

check_nvidia_loaded() {
    if lsmod | grep -q '^nvidia '; then
        echo -e "${GREEN}[OK]${RESET} nvidia kernel module loaded."
    else
        echo -e "${RED}[FAIL]${RESET} nvidia kernel module NOT loaded."
        echo "       Run: sudo modprobe nvidia"
        return 1
    fi
}

check_drm_modeset() {
    local val
    val=$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo "N/A")
    if [[ "${val}" == "Y" ]]; then
        echo -e "${GREEN}[OK]${RESET} nvidia_drm modeset=1 (DRM KMS active)."
    else
        echo -e "${YELLOW}[WARN]${RESET} nvidia_drm modeset=${val} — Wayland may not work correctly."
    fi
}

check_nvidia_smi() {
    if command -v nvidia-smi &>/dev/null; then
        echo -e "${GREEN}[OK]${RESET} nvidia-smi found. GPU info:"
        nvidia-smi --query-gpu=name,driver_version,memory.total \
                   --format=csv,noheader,nounits | \
            awk -F',' '{ printf "       GPU: %s | Driver: %s | VRAM: %s MiB\n", $1, $2, $3 }'
    else
        echo -e "${RED}[FAIL]${RESET} nvidia-smi not found. nvidia-utils may not be installed."
    fi
}

echo "=== Custom SteamOS ISO — NVIDIA Driver Check ==="
check_nvidia_loaded
check_drm_modeset
check_nvidia_smi
echo "================================================="
