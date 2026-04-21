#!/usr/bin/env bash
# =============================================================================
# build.sh — Custom SteamOS ISO Builder with NVIDIA Support
# =============================================================================
# Automates the process of building a SteamOS-based Arch ISO with NVIDIA
# drivers (nvidia-dkms) pre-baked into the image and initramfs.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROFILE_DIR="${SCRIPT_DIR}/profile"
readonly BUILD_DIR="${SCRIPT_DIR}/build"
readonly OUT_DIR="${SCRIPT_DIR}/out"
readonly LOG_DIR="${SCRIPT_DIR}/logs"
readonly LOG_FILE="${LOG_DIR}/build_$(date +%Y%m%d_%H%M%S).log"
readonly MIN_DISK_GB=20
readonly ISO_NAME="custom-steamosiso"

# Colour codes (only when stdout is a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''
fi

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
_log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '[%s] [%s] %s\n' "${ts}" "${level}" "${msg}" | tee -a "${LOG_FILE}"
}

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; _log INFO  "$*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; _log OK    "$*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; _log WARN  "$*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; _log ERROR "$*"; }
die()     { error "$*"; exit 1; }

banner() {
    echo -e "${BOLD}${CYAN}"
    cat <<'EOF'
  ____  _                  ___  ____    ___  ____   ___
 / ___|| |_ ___  __ _ _ __|_ _|/ ___|  |_ _|/ ___| / _ \
 \___ \| __/ _ \/ _` | '_ \| |\___ \   | | \___ \| | | |
  ___) | ||  __/ (_| | | | | | ___) |  | |  ___) | |_| |
 |____/ \__\___|\__,_|_| |_|___|____/  |___|____/ \___/

        Custom SteamOS ISO — NVIDIA Edition Builder
EOF
    echo -e "${RESET}"
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "This script must be run as root. Use: sudo ${BASH_SOURCE[0]}"
    fi
}

check_arch() {
    if ! grep -qi 'arch\|manjaro\|endeavour\|garuda' /etc/os-release 2>/dev/null; then
        warn "Non-Arch-based host detected. Build environment may be incompatible."
    fi
}

check_disk_space() {
    info "Checking available disk space (minimum ${MIN_DISK_GB} GB required)..."
    local available_kb
    available_kb=$(df -k "${SCRIPT_DIR}" | awk 'NR==2 {print $4}')
    local available_gb=$(( available_kb / 1024 / 1024 ))

    if (( available_gb < MIN_DISK_GB )); then
        die "Insufficient disk space: ${available_gb} GB available, ${MIN_DISK_GB} GB required."
    fi
    success "Disk space OK: ${available_gb} GB available."
}

check_dependencies() {
    info "Checking build dependencies..."
    local missing=()
    local deps=(mkarchiso pacman mksquashfs xorriso)

    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            missing+=("${dep}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        warn "Missing tools: ${missing[*]}. Attempting to install..."
        install_dependencies
    else
        success "All build dependencies present."
    fi
}

# ---------------------------------------------------------------------------
# Dependency installation
# ---------------------------------------------------------------------------
install_dependencies() {
    info "Installing build dependencies via pacman..."
    local packages=(
        archiso
        arch-install-scripts
        libisoburn
        squashfs-tools
        dosfstools
        mtools
    )

    if ! pacman -Sy --noconfirm --needed "${packages[@]}" >> "${LOG_FILE}" 2>&1; then
        die "Failed to install build dependencies. Check ${LOG_FILE} for details."
    fi
    success "Build dependencies installed."
}

# ---------------------------------------------------------------------------
# Workspace management
# ---------------------------------------------------------------------------
prepare_workspace() {
    info "Preparing build workspace..."
    mkdir -p "${BUILD_DIR}" "${OUT_DIR}" "${LOG_DIR}"

    if [[ -d "${BUILD_DIR}/work" ]]; then
        warn "Stale build workspace detected. Cleaning..."
        rm -rf "${BUILD_DIR}/work"
        success "Stale workspace cleaned."
    fi
    success "Workspace ready."
}

clean_workspace() {
    info "Cleaning all build artifacts..."
    rm -rf "${BUILD_DIR}" "${OUT_DIR}"
    success "Workspace cleaned."
}

# ---------------------------------------------------------------------------
# Profile validation
# ---------------------------------------------------------------------------
validate_profile() {
    info "Validating ISO profile at ${PROFILE_DIR}..."
    local required_files=(
        "profiledef.sh"
        "packages.x86_64"
        "airootfs/etc/mkinitcpio.conf"
    )

    for f in "${required_files[@]}"; do
        if [[ ! -f "${PROFILE_DIR}/${f}" ]]; then
            die "Missing required profile file: ${PROFILE_DIR}/${f}"
        fi
    done
    success "Profile validation passed."
}

# ---------------------------------------------------------------------------
# ISO build
# ---------------------------------------------------------------------------
build_iso() {
    info "Starting mkarchiso build — this will take a while..."
    info "Build log: ${LOG_FILE}"

    if ! mkarchiso \
        -v \
        -w "${BUILD_DIR}/work" \
        -o "${OUT_DIR}" \
        "${PROFILE_DIR}" >> "${LOG_FILE}" 2>&1; then
        die "mkarchiso failed. Check ${LOG_FILE} for details."
    fi

    local iso_file
    iso_file=$(find "${OUT_DIR}" -maxdepth 1 -name "*.iso" | head -n1)
    if [[ -z "${iso_file}" ]]; then
        die "Build completed but no ISO found in ${OUT_DIR}."
    fi

    local iso_size
    iso_size=$(du -sh "${iso_file}" | cut -f1)
    success "ISO built successfully: ${iso_file} (${iso_size})"
}

generate_checksums() {
    info "Generating SHA256 checksums..."
    local iso_file
    iso_file=$(find "${OUT_DIR}" -maxdepth 1 -name "*.iso" | head -n1)
    sha256sum "${iso_file}" > "${iso_file}.sha256"
    success "Checksum written to ${iso_file}.sha256"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND]

Commands:
  build     Build the custom SteamOS ISO (default)
  clean     Remove all build artifacts and output
  deps      Install build dependencies only
  validate  Validate the ISO profile without building

Options:
  -h, --help   Show this help message

Examples:
  sudo $(basename "$0") build
  sudo $(basename "$0") clean
  sudo $(basename "$0") deps
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
    local command="${1:-build}"

    mkdir -p "${LOG_DIR}"
    banner

    case "${command}" in
        build)
            check_root
            check_arch
            check_disk_space
            check_dependencies
            prepare_workspace
            validate_profile
            build_iso
            generate_checksums
            success "Build complete. Output: ${OUT_DIR}/"
            ;;
        clean)
            check_root
            clean_workspace
            ;;
        deps)
            check_root
            install_dependencies
            ;;
        validate)
            validate_profile
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

main "$@"
