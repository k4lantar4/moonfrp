#!/bin/bash

# MoonFRP Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/k4lantar4/moonfrp/main/install.sh | bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
MOONFRP_VERSION="1.0.0"
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="moonfrp"
SCRIPT_URL="https://raw.githubusercontent.com/k4lantar4/moonfrp/main/moonfrp.sh"
TEMP_DIR="/tmp/moonfrp-install"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR" "Installation failed at line $line_number with exit code $exit_code"
    cleanup
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# Cleanup function
cleanup() {
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        log "INFO" "Please run: sudo $0"
        exit 1
    fi
}

# Detect OS and architecture
detect_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log "ERROR" "Cannot detect operating system"
        exit 1
    fi
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            log "ERROR" "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    log "INFO" "Detected OS: $OS $VERSION"
    log "INFO" "Detected Architecture: $ARCH"
}

# Check dependencies
check_dependencies() {
    local deps=("curl" "tar" "systemctl")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "WARN" "Missing dependencies: ${missing_deps[*]}"
        install_dependencies "${missing_deps[@]}"
    fi
}

# Install dependencies
install_dependencies() {
    local deps=("$@")
    
    case "$OS" in
        ubuntu|debian)
            log "INFO" "Installing dependencies using apt..."
            apt-get update -qq
            apt-get install -y "${deps[@]}"
            ;;
        centos|rhel|fedora)
            log "INFO" "Installing dependencies using yum/dnf..."
            if command -v dnf &> /dev/null; then
                dnf install -y "${deps[@]}"
            else
                yum install -y "${deps[@]}"
            fi
            ;;
        *)
            log "ERROR" "Unsupported OS for automatic dependency installation: $OS"
            log "INFO" "Please manually install: ${deps[*]}"
            exit 1
            ;;
    esac
}

# Create directories
create_directories() {
    local dirs=("/opt/frp" "/etc/frp" "/var/log/frp" "$TEMP_DIR")
    
    for dir in "${dirs[@]}"; do
        [[ ! -d "$dir" ]] && mkdir -p "$dir"
    done
    
    log "INFO" "Created required directories"
}

# Download and install moonfrp script
install_moonfrp() {
    log "INFO" "Downloading MoonFRP script..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Download the script
    if ! curl -fsSL "$SCRIPT_URL" -o "$TEMP_DIR/$SCRIPT_NAME"; then
        log "ERROR" "Failed to download MoonFRP script"
        exit 1
    fi
    
    # Make it executable
    chmod +x "$TEMP_DIR/$SCRIPT_NAME"
    
    # Move to installation directory
    mv "$TEMP_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
    
    log "INFO" "MoonFRP script installed to $INSTALL_DIR/$SCRIPT_NAME"
}

# Create symlink for global access
create_symlink() {
    local symlink_path="/usr/bin/moonfrp"
    
    if [[ -L "$symlink_path" ]] || [[ -f "$symlink_path" ]]; then
        log "WARN" "Command 'moonfrp' already exists, creating alternative symlink"
        symlink_path="/usr/bin/moonfrp"
    fi
    
    ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "$symlink_path"
    log "INFO" "Created symlink: $symlink_path -> $INSTALL_DIR/$SCRIPT_NAME"
}

# Verify installation
verify_installation() {
    if [[ -x "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        log "INFO" "Installation verified successfully"
        return 0
    else
        log "ERROR" "Installation verification failed"
        return 1
    fi
}

# Display installation summary
display_summary() {
    echo
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         MoonFRP Installed            ║${NC}"
    echo -e "${PURPLE}║            Successfully              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}Installation Details:${NC}"
    echo -e "  Version: $MOONFRP_VERSION"
    echo -e "  Location: $INSTALL_DIR/$SCRIPT_NAME"
    echo -e "  Command: moonfrp"
    echo
    echo -e "${CYAN}Quick Start:${NC}"
    echo -e "  1. Run: ${GREEN}moonfrp${NC}"
    echo -e "  2. Choose option 3 to download and install FRP"
    echo -e "  3. Choose option 1 to create configurations"
    echo
    echo -e "${CYAN}Support:${NC}"
    echo -e "  Repository: https://github.com/k4lantar4/moonfrp"
    echo -e "  Issues: https://github.com/k4lantar4/moonfrp/issues"
    echo
    echo -e "${GREEN}🚀 Ready to use MoonFRP!${NC}"
}

# Main installation function
main() {
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        MoonFRP Installer             ║${NC}"
    echo -e "${PURPLE}║     Advanced FRP Management         ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo
    
    log "INFO" "Starting MoonFRP installation..."
    
    check_root
    detect_system
    check_dependencies
    create_directories
    install_moonfrp
    create_symlink
    
    if verify_installation; then
        display_summary
        cleanup
    else
        log "ERROR" "Installation failed"
        cleanup
        exit 1
    fi
}

# Run main function
main "$@" 