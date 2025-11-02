#!/bin/bash

#==============================================================================
# MoonFRP Installation Script (Refactored)
# Version: 2.0.0
# Description: One-command installation with environment variable support
#==============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables
readonly MOONFRP_VERSION="2.0.0"
readonly INSTALL_DIR="/usr/local/bin"
readonly SCRIPT_NAME="moonfrp"
readonly REPO_URL="https://raw.githubusercontent.com/k4lantar4/moonfrp/main"
readonly TEMP_DIR="/tmp/moonfrp-install"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[$timestamp] [INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[$timestamp] [DEBUG]${NC} $message" ;;
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
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) log "ERROR" "Unsupported architecture: $ARCH"; exit 1 ;;
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
    local dirs=("/opt/frp" "/etc/frp" "/var/log/frp" "/etc/moonfrp" "$TEMP_DIR")
    
    for dir in "${dirs[@]}"; do
        [[ ! -d "$dir" ]] && mkdir -p "$dir"
    done
    
    log "INFO" "Created required directories"
}

# Download and install MoonFRP
install_moonfrp() {
    log "INFO" "Downloading MoonFRP v$MOONFRP_VERSION..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Download all required files
    local files=("moonfrp-core.sh" "moonfrp-config.sh" "moonfrp-services.sh" "moonfrp-ui.sh" "moonfrp.sh")
    
    for file in "${files[@]}"; do
        local url="$REPO_URL/$file"
        local temp_file="$TEMP_DIR/$file"
        
        if ! curl -fsSL "$url" -o "$temp_file"; then
            log "ERROR" "Failed to download $file"
            exit 1
        fi
        
        chmod +x "$temp_file"
    done
    
    # Create main script
    cat > "$TEMP_DIR/$SCRIPT_NAME" << 'EOF'
#!/bin/bash
# MoonFRP Main Script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/moonfrp.sh" "$@"
EOF
    
    chmod +x "$TEMP_DIR/$SCRIPT_NAME"
    
    # Ensure installation directory exists
    mkdir -p "$INSTALL_DIR"
    
    # Install all files
    for file in "${files[@]}"; do
        cp "$TEMP_DIR/$file" "$INSTALL_DIR/"
    done
    cp "$TEMP_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Create symlink for global access
    ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "/usr/bin/$SCRIPT_NAME"
    
    log "INFO" "MoonFRP installed to $INSTALL_DIR"
}

# Create configuration file
create_config_file() {
    local config_file="/etc/moonfrp/config"
    
    # Normalize ARCH to FRP format
    local frp_arch="$ARCH"
    case "$frp_arch" in
        amd64) frp_arch="linux_amd64" ;;
        arm64) frp_arch="linux_arm64" ;;
        armv7) frp_arch="linux_armv7" ;;
        *) frp_arch="linux_amd64" ;;
    esac
    
    cat > "$config_file" << EOF
# MoonFRP Configuration
# Generated on $(date)

# FRP Version
MOONFRP_FRP_VERSION="${MOONFRP_FRP_VERSION:-0.65.0}"
MOONFRP_FRP_ARCH="${MOONFRP_FRP_ARCH:-$frp_arch}"

# Installation Directories
MOONFRP_INSTALL_DIR="/opt/frp"
MOONFRP_CONFIG_DIR="/etc/frp"
MOONFRP_LOG_DIR="/var/log/frp"

# Server Configuration
MOONFRP_SERVER_BIND_ADDR="${MOONFRP_SERVER_BIND_ADDR:-0.0.0.0}"
MOONFRP_SERVER_BIND_PORT="${MOONFRP_SERVER_BIND_PORT:-7000}"
MOONFRP_SERVER_AUTH_TOKEN="${MOONFRP_SERVER_AUTH_TOKEN:-}"
MOONFRP_SERVER_DASHBOARD_PORT="${MOONFRP_SERVER_DASHBOARD_PORT:-7500}"
MOONFRP_SERVER_DASHBOARD_USER="${MOONFRP_SERVER_DASHBOARD_USER:-admin}"
MOONFRP_SERVER_DASHBOARD_PASSWORD="${MOONFRP_SERVER_DASHBOARD_PASSWORD:-}"

# Client Configuration
MOONFRP_CLIENT_SERVER_ADDR="${MOONFRP_CLIENT_SERVER_ADDR:-}"
MOONFRP_CLIENT_SERVER_PORT="${MOONFRP_CLIENT_SERVER_PORT:-7000}"
MOONFRP_CLIENT_AUTH_TOKEN="${MOONFRP_CLIENT_AUTH_TOKEN:-}"
MOONFRP_CLIENT_USER="${MOONFRP_CLIENT_USER:-}"

# Security Settings
MOONFRP_TLS_ENABLE="${MOONFRP_TLS_ENABLE:-true}"
MOONFRP_TLS_FORCE="${MOONFRP_TLS_FORCE:-false}"
MOONFRP_AUTH_METHOD="${MOONFRP_AUTH_METHOD:-token}"

# Performance Settings
MOONFRP_MAX_POOL_COUNT="${MOONFRP_MAX_POOL_COUNT:-5}"
MOONFRP_POOL_COUNT="${MOONFRP_POOL_COUNT:-5}"
MOONFRP_TCP_MUX="${MOONFRP_TCP_MUX:-true}"
MOONFRP_HEARTBEAT_INTERVAL="${MOONFRP_HEARTBEAT_INTERVAL:-30}"
MOONFRP_HEARTBEAT_TIMEOUT="${MOONFRP_HEARTBEAT_TIMEOUT:-90}"

# Logging Settings
MOONFRP_LOG_LEVEL="${MOONFRP_LOG_LEVEL:-info}"
MOONFRP_LOG_MAX_DAYS="${MOONFRP_LOG_MAX_DAYS:-7}"
MOONFRP_LOG_DISABLE_COLOR="${MOONFRP_LOG_DISABLE_COLOR:-false}"

# Multi-IP Configuration
MOONFRP_SERVER_IPS="${MOONFRP_SERVER_IPS:-}"
MOONFRP_SERVER_PORTS="${MOONFRP_SERVER_PORTS:-}"
MOONFRP_CLIENT_PORTS="${MOONFRP_CLIENT_PORTS:-}"
EOF
    
    log "INFO" "Created configuration file: $config_file"
}

# Install FRP binaries
install_frp_binaries() {
    # Source config to get FRP_VERSION and FRP_ARCH
    local config_file="/etc/moonfrp/config"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    fi
    
    local frp_version="${MOONFRP_FRP_VERSION:-0.65.0}"
    
    # Determine architecture (use normalized value from config or detect)
    local frp_arch="${MOONFRP_FRP_ARCH:-}"
    if [[ -z "$frp_arch" ]]; then
        case "$ARCH" in
            amd64) frp_arch="linux_amd64" ;;
            arm64) frp_arch="linux_arm64" ;;
            armv7) frp_arch="linux_armv7" ;;
            *) frp_arch="linux_amd64" ;;
        esac
    fi
    
    local frp_dir="/opt/frp"
    
    log "INFO" "Installing FRP v$frp_version ($frp_arch)..."
    
    # Download URL
    local download_url="https://github.com/fatedier/frp/releases/download/v${frp_version}/frp_${frp_version}_${frp_arch}.tar.gz"
    local temp_file="$TEMP_DIR/frp_${frp_version}_${frp_arch}.tar.gz"
    
    # Download FRP
    if ! curl -fsSL "$download_url" -o "$temp_file"; then
        log "ERROR" "Failed to download FRP from: $download_url"
        log "WARN" "You can install FRP later by running: moonfrp (then select option 6)"
        return 1
    fi
    
    # Extract FRP
    if ! tar -xzf "$temp_file" -C "$TEMP_DIR"; then
        log "ERROR" "Failed to extract FRP archive"
        return 1
    fi
    
    # Install binaries
    cp "$TEMP_DIR/frp_${frp_version}_${frp_arch}/frps" "$frp_dir/"
    cp "$TEMP_DIR/frp_${frp_version}_${frp_arch}/frpc" "$frp_dir/"
    chmod +x "$frp_dir/frps" "$frp_dir/frpc"
    
    # Cleanup extracted files
    rm -rf "$TEMP_DIR/frp_${frp_version}_${frp_arch}"
    rm -f "$temp_file"
    
    log "INFO" "FRP v$frp_version installed successfully to $frp_dir"
    return 0
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
    echo -e "  Command: $SCRIPT_NAME"
    echo
    echo -e "${CYAN}Quick Start:${NC}"
    echo -e "  1. Run: ${GREEN}$SCRIPT_NAME${NC}"
    echo -e "  2. Choose 'Quick Setup' for easy configuration"
    echo -e "  3. Or use command line: $SCRIPT_NAME setup server"
    echo
    if [[ -x "/opt/frp/frps" && -x "/opt/frp/frpc" ]]; then
        echo -e "${GREEN}✓${NC} FRP binaries installed and ready"
    else
        echo -e "${YELLOW}⚠${NC} FRP binaries not installed - run $SCRIPT_NAME to install them"
    fi
    echo
    echo -e "${CYAN}Environment Variables:${NC}"
    echo -e "  Set configuration via environment variables:"
    echo -e "  MOONFRP_SERVER_BIND_PORT=7000 $SCRIPT_NAME setup server"
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
    echo -e "${PURPLE}║         Version $MOONFRP_VERSION              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo
    
    log "INFO" "Starting MoonFRP installation..."
    
    check_root
    detect_system
    check_dependencies
    create_directories
    install_moonfrp
    create_config_file
    install_frp_binaries
    
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