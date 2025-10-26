#!/bin/bash

#==============================================================================
# MoonFRP Core Functions
# Version: 2.0.0
# Description: Core utilities and functions for MoonFRP
#==============================================================================

# Use safer bash settings
set -euo pipefail

# Source configuration
if [[ -f "/etc/moonfrp/config" ]]; then
    source "/etc/moonfrp/config"
fi

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m' # No Color

# Global variables with defaults
readonly MOONFRP_VERSION="2.0.0"
readonly FRP_VERSION="${MOONFRP_FRP_VERSION:-0.65.0}"
readonly FRP_ARCH="${MOONFRP_FRP_ARCH:-linux_amd64}"
readonly FRP_DIR="${MOONFRP_INSTALL_DIR:-/opt/frp}"
readonly CONFIG_DIR="${MOONFRP_CONFIG_DIR:-/etc/frp}"
readonly LOG_DIR="${MOONFRP_LOG_DIR:-/var/log/frp}"
readonly TEMP_DIR="/tmp/moonfrp"

# Service names
readonly SERVER_SERVICE="moonfrp-server"
readonly CLIENT_SERVICE_PREFIX="moonfrp-client"

# Configuration defaults
readonly DEFAULT_SERVER_BIND_ADDR="${MOONFRP_SERVER_BIND_ADDR:-0.0.0.0}"
readonly DEFAULT_SERVER_BIND_PORT="${MOONFRP_SERVER_BIND_PORT:-7000}"
readonly DEFAULT_SERVER_AUTH_TOKEN="${MOONFRP_SERVER_AUTH_TOKEN:-}"
readonly DEFAULT_SERVER_DASHBOARD_PORT="${MOONFRP_SERVER_DASHBOARD_PORT:-7500}"
readonly DEFAULT_SERVER_DASHBOARD_USER="${MOONFRP_SERVER_DASHBOARD_USER:-admin}"
readonly DEFAULT_SERVER_DASHBOARD_PASSWORD="${MOONFRP_SERVER_DASHBOARD_PASSWORD:-}"

readonly DEFAULT_CLIENT_SERVER_ADDR="${MOONFRP_CLIENT_SERVER_ADDR:-}"
readonly DEFAULT_CLIENT_SERVER_PORT="${MOONFRP_CLIENT_SERVER_PORT:-7000}"
readonly DEFAULT_CLIENT_AUTH_TOKEN="${MOONFRP_CLIENT_AUTH_TOKEN:-}"
readonly DEFAULT_CLIENT_USER="${MOONFRP_CLIENT_USER:-}"

readonly DEFAULT_TLS_ENABLE="${MOONFRP_TLS_ENABLE:-true}"
readonly DEFAULT_TLS_FORCE="${MOONFRP_TLS_FORCE:-false}"
readonly DEFAULT_AUTH_METHOD="${MOONFRP_AUTH_METHOD:-token}"
readonly DEFAULT_MAX_POOL_COUNT="${MOONFRP_MAX_POOL_COUNT:-5}"
readonly DEFAULT_POOL_COUNT="${MOONFRP_POOL_COUNT:-5}"
readonly DEFAULT_TCP_MUX="${MOONFRP_TCP_MUX:-true}"
readonly DEFAULT_HEARTBEAT_INTERVAL="${MOONFRP_HEARTBEAT_INTERVAL:-30}"
readonly DEFAULT_HEARTBEAT_TIMEOUT="${MOONFRP_HEARTBEAT_TIMEOUT:-90}"

readonly DEFAULT_LOG_LEVEL="${MOONFRP_LOG_LEVEL:-info}"
readonly DEFAULT_LOG_MAX_DAYS="${MOONFRP_LOG_MAX_DAYS:-7}"
readonly DEFAULT_LOG_DISABLE_COLOR="${MOONFRP_LOG_DISABLE_COLOR:-false}"

# Multi-IP configuration
readonly SERVER_IPS="${MOONFRP_SERVER_IPS:-}"
readonly SERVER_PORTS="${MOONFRP_SERVER_PORTS:-}"
readonly CLIENT_PORTS="${MOONFRP_CLIENT_PORTS:-}"

# Menu state tracking
declare -A MENU_STATE
MENU_STATE["depth"]="0"
MENU_STATE["ctrl_c_pressed"]="false"

# Cache for performance
declare -A CACHE_DATA
CACHE_DATA["frp_installation"]=""
CACHE_DATA["update_check_done"]="false"

#==============================================================================
# CORE FUNCTIONS
#==============================================================================

# Centralized logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "DEBUG") echo -e "${GRAY}[$timestamp] [DEBUG]${NC} $message" ;;
        "INFO")  echo -e "${GREEN}[$timestamp] [INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
        *)       echo -e "${GRAY}[$timestamp] [LOG]${NC} $message" ;;
    esac
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR" "Operation failed at line $line_number with exit code $exit_code"
    return $exit_code
}

# Signal handler for Ctrl+C
signal_handler() {
    log "WARN" "Operation interrupted by user"
    MENU_STATE["ctrl_c_pressed"]="true"
    exit 130
}

# Setup signal handlers
setup_signal_handlers() {
    trap 'signal_handler' INT TERM
}

# Create required directories
create_directories() {
    local dirs=("$FRP_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TEMP_DIR" "/etc/moonfrp")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log "DEBUG" "Created directory: $dir"
        fi
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        log "INFO" "Please run: sudo $0"
        exit 1
    fi
}

# Check system dependencies
check_dependencies() {
    local deps=("curl" "tar" "systemctl" "openssl")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing dependencies: ${missing_deps[*]}"
        log "INFO" "Please install missing dependencies and try again"
        exit 1
    fi
}

# Generate secure token
generate_token() {
    local length="${1:-32}"
    openssl rand -hex $((length/2))
}

# Validate IP address
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a ip_parts=($ip)
        for part in "${ip_parts[@]}"; do
            if ((part > 255)); then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ $port =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)); then
        return 0
    else
        return 1
    fi
}

# Safe read function with Ctrl+C handling
safe_read() {
    local prompt="$1"
    local var_name="$2"
    local default_value="${3:-}"
    
    while true; do
        if [[ -n "$default_value" ]]; then
            echo -n -e "${CYAN}$prompt${NC} [${GREEN}$default_value${NC}]: "
        else
            echo -n -e "${CYAN}$prompt${NC}: "
        fi
        
        if read -r input; then
            if [[ -n "$input" ]]; then
                eval "$var_name=\"$input\""
            elif [[ -n "$default_value" ]]; then
                eval "$var_name=\"$default_value\""
            else
                log "WARN" "Input cannot be empty"
                continue
            fi
            break
        else
            if [[ "${MENU_STATE["ctrl_c_pressed"]}" == "true" ]]; then
                MENU_STATE["ctrl_c_pressed"]="false"
                return 1
            fi
        fi
    done
}

# Check if FRP is installed
check_frp_installation() {
    if [[ -x "$FRP_DIR/frps" && -x "$FRP_DIR/frpc" ]]; then
        return 0
    else
        return 1
    fi
}

# Get FRP version
get_frp_version() {
    if check_frp_installation; then
        "$FRP_DIR/frps" --version 2>/dev/null | head -1 | grep -o 'v[0-9.]*' || echo "unknown"
    else
        echo "not installed"
    fi
}

# Check service status
get_service_status() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo "active"
    elif systemctl is-failed --quiet "$service_name" 2>/dev/null; then
        echo "failed"
    else
        echo "inactive"
    fi
}

# Format bytes for display
format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0
    
    while ((bytes >= 1024 && unit_index < 4)); do
        bytes=$((bytes / 1024))
        ((unit_index++))
    done
    
    echo "${bytes}${units[$unit_index]}"
}

# Show spinner for long operations
show_spinner() {
    local pid="$1"
    local delay=0.1
    local spinstr='|/-\'
    
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Initialize MoonFRP
init() {
    setup_signal_handlers
    create_directories
    check_dependencies
    
    # Create configuration file if it doesn't exist
    if [[ ! -f "/etc/moonfrp/config" ]]; then
        create_default_config
    fi
}

# Create default configuration file
create_default_config() {
    cat > "/etc/moonfrp/config" << EOF
# MoonFRP Configuration
# Generated on $(date)

# FRP Version
MOONFRP_FRP_VERSION="$FRP_VERSION"
MOONFRP_FRP_ARCH="$FRP_ARCH"

# Installation Directories
MOONFRP_INSTALL_DIR="$FRP_DIR"
MOONFRP_CONFIG_DIR="$CONFIG_DIR"
MOONFRP_LOG_DIR="$LOG_DIR"

# Server Configuration
MOONFRP_SERVER_BIND_ADDR="$DEFAULT_SERVER_BIND_ADDR"
MOONFRP_SERVER_BIND_PORT="$DEFAULT_SERVER_BIND_PORT"
MOONFRP_SERVER_AUTH_TOKEN="$DEFAULT_SERVER_AUTH_TOKEN"
MOONFRP_SERVER_DASHBOARD_PORT="$DEFAULT_SERVER_DASHBOARD_PORT"
MOONFRP_SERVER_DASHBOARD_USER="$DEFAULT_SERVER_DASHBOARD_USER"
MOONFRP_SERVER_DASHBOARD_PASSWORD="$DEFAULT_SERVER_DASHBOARD_PASSWORD"

# Client Configuration
MOONFRP_CLIENT_SERVER_ADDR="$DEFAULT_CLIENT_SERVER_ADDR"
MOONFRP_CLIENT_SERVER_PORT="$DEFAULT_CLIENT_SERVER_PORT"
MOONFRP_CLIENT_AUTH_TOKEN="$DEFAULT_CLIENT_AUTH_TOKEN"
MOONFRP_CLIENT_USER="$DEFAULT_CLIENT_USER"

# Security Settings
MOONFRP_TLS_ENABLE="$DEFAULT_TLS_ENABLE"
MOONFRP_TLS_FORCE="$DEFAULT_TLS_FORCE"
MOONFRP_AUTH_METHOD="$DEFAULT_AUTH_METHOD"

# Performance Settings
MOONFRP_MAX_POOL_COUNT="$DEFAULT_MAX_POOL_COUNT"
MOONFRP_POOL_COUNT="$DEFAULT_POOL_COUNT"
MOONFRP_TCP_MUX="$DEFAULT_TCP_MUX"
MOONFRP_HEARTBEAT_INTERVAL="$DEFAULT_HEARTBEAT_INTERVAL"
MOONFRP_HEARTBEAT_TIMEOUT="$DEFAULT_HEARTBEAT_TIMEOUT"

# Logging Settings
MOONFRP_LOG_LEVEL="$DEFAULT_LOG_LEVEL"
MOONFRP_LOG_MAX_DAYS="$DEFAULT_LOG_MAX_DAYS"
MOONFRP_LOG_DISABLE_COLOR="$DEFAULT_LOG_DISABLE_COLOR"

# Multi-IP Configuration
MOONFRP_SERVER_IPS="$SERVER_IPS"
MOONFRP_SERVER_PORTS="$SERVER_PORTS"
MOONFRP_CLIENT_PORTS="$CLIENT_PORTS"
EOF
    
    log "INFO" "Created default configuration file: /etc/moonfrp/config"
}

# Load configuration
load_config() {
    if [[ -f "/etc/moonfrp/config" ]]; then
        source "/etc/moonfrp/config"
        log "DEBUG" "Loaded configuration from /etc/moonfrp/config"
    else
        log "WARN" "Configuration file not found, using defaults"
    fi
}

# Export all functions for use in other modules
export -f log handle_error signal_handler setup_signal_handlers
export -f create_directories check_root check_dependencies generate_token
export -f validate_ip validate_port safe_read check_frp_installation
export -f get_frp_version get_service_status format_bytes show_spinner
export -f cleanup init create_default_config load_config

# Initialize if this script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi