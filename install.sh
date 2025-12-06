#!/usr/bin/env bash
# =============================================================================
#  MuxM Installation Script
#  Installs dependencies for muxm video remuxing tool
#  Supports: Ubuntu/Debian, Fedora/RHEL, Arch Linux
# =============================================================================
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

say()  { printf "${GREEN}▶${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "${RED}✖${NC} %s\n" "$*" >&2; }
info() { printf "${BLUE}ℹ${NC} %s\n" "$*"; }

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
    else
        SUDO="sudo"
        info "Some commands will require sudo privileges."
    fi
}

# Detect OS/Distribution
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_ID_LIKE="${ID_LIKE:-}"
        OS_VERSION="${VERSION_ID:-}"
        OS_NAME="${PRETTY_NAME:-$OS_ID}"
    else
        err "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    # Normalize to package manager type
    case "$OS_ID" in
        ubuntu|debian|pop|linuxmint|elementary)
            PKG_MANAGER="apt"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            PKG_MANAGER="dnf"
            ;;
        arch|manjaro|endeavouros)
            PKG_MANAGER="pacman"
            ;;
        *)
            # Check ID_LIKE for derivatives
            if [[ "$OS_ID_LIKE" == *"debian"* ]] || [[ "$OS_ID_LIKE" == *"ubuntu"* ]]; then
                PKG_MANAGER="apt"
            elif [[ "$OS_ID_LIKE" == *"fedora"* ]] || [[ "$OS_ID_LIKE" == *"rhel"* ]]; then
                PKG_MANAGER="dnf"
            elif [[ "$OS_ID_LIKE" == *"arch"* ]]; then
                PKG_MANAGER="pacman"
            else
                err "Unsupported distribution: $OS_NAME"
                err "Supported: Ubuntu/Debian, Fedora/RHEL, Arch Linux and derivatives"
                exit 1
            fi
            ;;
    esac

    say "Detected: $OS_NAME (using $PKG_MANAGER)"
}

# Detect GPU type
detect_gpu() {
    GPU_TYPE="none"
    GPU_NAME=""

    # Check for NVIDIA GPU
    if lspci 2>/dev/null | grep -qi 'nvidia'; then
        GPU_TYPE="nvidia"
        GPU_NAME=$(lspci | grep -i 'nvidia' | grep -iE 'vga|3d' | head -1 | sed 's/.*: //')
    # Check for AMD GPU
    elif lspci 2>/dev/null | grep -qi 'amd.*radeon\|amd.*graphics\|ati.*radeon'; then
        GPU_TYPE="amd"
        GPU_NAME=$(lspci | grep -iE 'amd.*radeon|amd.*graphics|ati.*radeon' | head -1 | sed 's/.*: //')
    # Check for Intel integrated graphics
    elif lspci 2>/dev/null | grep -qi 'intel.*graphics\|intel.*uhd\|intel.*iris'; then
        GPU_TYPE="intel"
        GPU_NAME=$(lspci | grep -iE 'intel.*graphics|intel.*uhd|intel.*iris' | head -1 | sed 's/.*: //')
    fi

    if [[ "$GPU_TYPE" != "none" ]]; then
        say "Detected GPU: $GPU_NAME"
    else
        warn "No dedicated GPU detected (or lspci not available)"
    fi
}

# Check if NVIDIA drivers are installed
check_nvidia_driver() {
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            NVIDIA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
            say "NVIDIA driver already installed: v$NVIDIA_VERSION"
            return 0
        fi
    fi
    return 1
}

# Check if NVENC is available in ffmpeg
check_nvenc() {
    if command -v ffmpeg &>/dev/null; then
        # Avoid SIGPIPE with pipefail by capturing output first
        local encoders
        encoders=$(ffmpeg -encoders 2>&1)
        if echo "$encoders" | grep -q "hevc_nvenc"; then
            say "NVENC encoder available in ffmpeg"
            return 0
        fi
    fi
    return 1
}

# Check if VAAPI is available (AMD/Intel)
check_vaapi() {
    if command -v ffmpeg &>/dev/null; then
        local encoders
        encoders=$(ffmpeg -encoders 2>&1)
        if echo "$encoders" | grep -q "hevc_vaapi"; then
            say "VAAPI encoder available in ffmpeg"
            return 0
        fi
    fi
    return 1
}

# Install base dependencies
install_base_deps() {
    say "Installing base dependencies (ffmpeg, ffprobe)..."

    case "$PKG_MANAGER" in
        apt)
            $SUDO apt-get update
            $SUDO apt-get install -y ffmpeg pciutils
            # gpac/MP4Box is optional fallback - try both package names
            if ! $SUDO apt-get install -y gpac 2>/dev/null; then
                if ! $SUDO apt-get install -y gpac-tools 2>/dev/null; then
                    warn "MP4Box (gpac) not available - skipping (optional fallback muxer)"
                fi
            fi
            ;;
        dnf)
            # Enable RPM Fusion for ffmpeg
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                info "Enabling RPM Fusion repository..."
                $SUDO dnf install -y \
                    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
                    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            fi
            $SUDO dnf install -y ffmpeg pciutils
            $SUDO dnf install -y gpac 2>/dev/null || warn "MP4Box (gpac) not available - skipping (optional)"
            ;;
        pacman)
            $SUDO pacman -Sy --noconfirm ffmpeg pciutils
            $SUDO pacman -Sy --noconfirm gpac 2>/dev/null || warn "MP4Box (gpac) not available - skipping (optional)"
            ;;
    esac

    say "Base dependencies installed"
}

# Install NVIDIA drivers
install_nvidia_driver() {
    say "Installing NVIDIA drivers..."

    case "$PKG_MANAGER" in
        apt)
            $SUDO apt-get update
            # Install recommended driver
            if command -v ubuntu-drivers &>/dev/null; then
                info "Using ubuntu-drivers to install recommended NVIDIA driver..."
                $SUDO ubuntu-drivers install
            else
                # Fallback to manual installation
                info "Installing nvidia-driver package..."
                $SUDO apt-get install -y nvidia-driver-535
            fi
            ;;
        dnf)
            # NVIDIA drivers from RPM Fusion
            if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
                $SUDO dnf install -y \
                    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            fi
            $SUDO dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
            ;;
        pacman)
            $SUDO pacman -Sy --noconfirm nvidia nvidia-utils
            ;;
    esac

    warn "NVIDIA driver installed. A REBOOT is required before NVENC will work!"
    NEEDS_REBOOT=1
}

# Install AMD/Intel VAAPI support
install_vaapi() {
    say "Installing VAAPI support for $GPU_TYPE..."

    case "$PKG_MANAGER" in
        apt)
            $SUDO apt-get update
            if [[ "$GPU_TYPE" == "intel" ]]; then
                $SUDO apt-get install -y intel-media-va-driver vainfo
            else
                # AMD
                $SUDO apt-get install -y mesa-va-drivers vainfo
            fi
            ;;
        dnf)
            if [[ "$GPU_TYPE" == "intel" ]]; then
                $SUDO dnf install -y intel-media-driver libva-utils
            else
                # AMD
                $SUDO dnf install -y mesa-va-drivers libva-utils
            fi
            ;;
        pacman)
            if [[ "$GPU_TYPE" == "intel" ]]; then
                $SUDO pacman -Sy --noconfirm intel-media-driver libva-utils
            else
                # AMD
                $SUDO pacman -Sy --noconfirm mesa libva-mesa-driver libva-utils
            fi
            ;;
    esac

    say "VAAPI support installed"
}

# Verify installation
verify_install() {
    say "Verifying installation..."
    local errors=0

    # Check ffmpeg
    if command -v ffmpeg &>/dev/null; then
        FFMPEG_VERSION=$(ffmpeg -version | head -1)
        say "✓ ffmpeg: $FFMPEG_VERSION"
    else
        err "✗ ffmpeg not found"
        errors=$((errors + 1))
    fi

    # Check ffprobe
    if command -v ffprobe &>/dev/null; then
        say "✓ ffprobe: installed"
    else
        err "✗ ffprobe not found"
        errors=$((errors + 1))
    fi

    # Check MP4Box
    if command -v MP4Box &>/dev/null; then
        MP4BOX_VERSION=$(MP4Box -version 2>&1 | head -1)
        say "✓ MP4Box: $MP4BOX_VERSION"
    else
        warn "⚠ MP4Box not found (optional, fallback muxer)"
    fi

    # Check hardware encoding
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        if check_nvenc; then
            say "✓ NVENC: available"
        else
            if [[ "${NEEDS_REBOOT:-0}" == "1" ]]; then
                warn "⚠ NVENC: will be available after reboot"
            else
                warn "⚠ NVENC: not available (driver issue?)"
            fi
        fi
    elif [[ "$GPU_TYPE" == "amd" ]] || [[ "$GPU_TYPE" == "intel" ]]; then
        if check_vaapi; then
            say "✓ VAAPI: available"
        else
            warn "⚠ VAAPI: not available"
        fi
    fi

    return $errors
}

# Make muxm executable and optionally install to PATH
setup_muxm() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ ! -f "$script_dir/muxm" ]]; then
        warn "muxm script not found in $script_dir"
        return 1
    fi

    # Make scripts executable
    chmod +x "$script_dir/muxm"
    say "Made muxm executable"

    if [[ -f "$script_dir/muxm-pipeline" ]]; then
        chmod +x "$script_dir/muxm-pipeline"
        say "Made muxm-pipeline executable"
    fi

    if [[ -f "$script_dir/muxm-batch" ]]; then
        chmod +x "$script_dir/muxm-batch"
        say "Made muxm-batch executable"
    fi

    # Ask about installing to PATH
    echo ""
    read -rp "Install muxm scripts to /usr/local/bin (requires sudo)? [Y/n] " install_choice
    install_choice="${install_choice:-Y}"

    if [[ "$install_choice" =~ ^[Yy] ]]; then
        install_to_path "$script_dir"
    else
        info "Skipping PATH installation."
        info "You can run directly: $script_dir/muxm --help"
        info "Or add to PATH: export PATH=\"\$PATH:$script_dir\""
    fi
}

# Install scripts to /usr/local/bin
install_to_path() {
    local script_dir="$1"
    local install_dir="/usr/local/bin"
    local scripts=("muxm" "muxm-pipeline" "muxm-batch")

    say "Installing scripts to $install_dir..."

    for script in "${scripts[@]}"; do
        if [[ -f "$script_dir/$script" ]]; then
            if $SUDO cp "$script_dir/$script" "$install_dir/$script"; then
                $SUDO chmod +x "$install_dir/$script"
                say "Installed: $install_dir/$script"
            else
                err "Failed to install $script"
            fi
        fi
    done

    # Verify installation
    if command -v muxm &>/dev/null; then
        say "✓ muxm is now available in PATH"
    else
        warn "muxm not found in PATH - you may need to restart your shell"
    fi
}

# Main installation flow
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              MuxM Dependency Installer                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    NEEDS_REBOOT=0

    check_root
    detect_os

    # Ask about GPU acceleration
    echo ""
    read -rp "Do you want to set up GPU hardware acceleration? [Y/n] " gpu_choice
    gpu_choice="${gpu_choice:-Y}"

    if [[ "$gpu_choice" =~ ^[Yy] ]]; then
        detect_gpu
        INSTALL_GPU=1
    else
        INSTALL_GPU=0
        GPU_TYPE="none"
    fi

    echo ""
    say "Installation plan:"
    echo "  • ffmpeg (video processing)"
    echo "  • ffprobe (media analysis)"
    echo "  • MP4Box/gpac (optional fallback muxer)"
    if [[ "$INSTALL_GPU" == "1" ]] && [[ "$GPU_TYPE" != "none" ]]; then
        case "$GPU_TYPE" in
            nvidia) echo "  • NVIDIA drivers + NVENC support" ;;
            amd)    echo "  • AMD VAAPI drivers" ;;
            intel)  echo "  • Intel VAAPI drivers" ;;
        esac
    fi
    echo ""

    read -rp "Proceed with installation? [Y/n] " proceed
    proceed="${proceed:-Y}"

    if [[ ! "$proceed" =~ ^[Yy] ]]; then
        info "Installation cancelled."
        exit 0
    fi

    echo ""

    # Install base dependencies
    install_base_deps

    # Handle GPU-specific installation
    if [[ "$INSTALL_GPU" == "1" ]] && [[ "$GPU_TYPE" != "none" ]]; then
        echo ""
        case "$GPU_TYPE" in
            nvidia)
                if check_nvidia_driver; then
                    info "NVIDIA driver already installed, skipping driver installation."
                else
                    install_nvidia_driver
                fi
                ;;
            amd|intel)
                install_vaapi
                ;;
        esac
    fi

    echo ""
    setup_muxm

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    verify_install
    echo "════════════════════════════════════════════════════════════════"

    if [[ "$NEEDS_REBOOT" == "1" ]]; then
        echo ""
        warn "╔════════════════════════════════════════════════════════════════╗"
        warn "║  REBOOT REQUIRED for GPU drivers to activate!                  ║"
        warn "║  Run 'nvidia-smi' after reboot to verify driver installation.  ║"
        warn "╚════════════════════════════════════════════════════════════════╝"
    fi

    echo ""
    say "Installation complete!"
}

main "$@"
