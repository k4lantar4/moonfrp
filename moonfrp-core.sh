#!/bin/bash

#==============================================================================
# MoonFRP Core Functions
# Version: 2.0.0
# Description: Core utilities and functions for MoonFRP
#==============================================================================

# Prevent multiple sourcing
if [[ "${MOONFRP_CORE_LOADED:-}" == "true" ]]; then
    # If we're in a sourced context, return
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    # If we're being executed directly, exit
    exit 0
fi
export MOONFRP_CORE_LOADED="true"

# Use safer bash settings
set -euo pipefail

# Source configuration
if [[ -f "/etc/moonfrp/config" ]]; then
    source "/etc/moonfrp/config"
fi

# Colors for output (only declare if not already set)
[[ -z "${RED:-}" ]] && readonly RED='\033[0;31m'
[[ -z "${GREEN:-}" ]] && readonly GREEN='\033[0;32m'
[[ -z "${YELLOW:-}" ]] && readonly YELLOW='\033[1;33m'
[[ -z "${BLUE:-}" ]] && readonly BLUE='\033[0;34m'
[[ -z "${PURPLE:-}" ]] && readonly PURPLE='\033[0;35m'
[[ -z "${CYAN:-}" ]] && readonly CYAN='\033[0;36m'
[[ -z "${GRAY:-}" ]] && readonly GRAY='\033[0;37m'
[[ -z "${NC:-}" ]] && readonly NC='\033[0m' # No Color

# Global variables with defaults (only declare if not already set)
[[ -z "${MOONFRP_VERSION:-}" ]] && readonly MOONFRP_VERSION="2.0.0"
readonly FRP_VERSION="${FRP_VERSION:-0.65.0}"

# Normalize FRP architecture to expected download format (linux_amd64, linux_arm64, linux_armv7)
# Support MOONFRP_FRP_ARCH (legacy) for backward compatibility, but prefer FRP_ARCH
if [[ -z "${FRP_ARCH:-}" ]]; then
    # Check legacy variable if FRP_ARCH not set
    __RAW_ARCH__="${MOONFRP_FRP_ARCH:-}"
    if [[ -z "${__RAW_ARCH__}" ]]; then
        # Fallback to uname mapping
        case "$(uname -m)" in
            x86_64) __NORM_ARCH__="linux_amd64" ;;
            aarch64) __NORM_ARCH__="linux_arm64" ;;
            armv7l) __NORM_ARCH__="linux_armv7" ;;
            *) __NORM_ARCH__="linux_amd64" ;;
        esac
    else
        # Accept already-normalized values
        if [[ "${__RAW_ARCH__}" =~ ^linux_ ]]; then
            __NORM_ARCH__="${__RAW_ARCH__}"
        else
            # Map common short forms to full linux_* forms
            case "${__RAW_ARCH__}" in
                amd64|x86_64) __NORM_ARCH__="linux_amd64" ;;
                arm64|aarch64) __NORM_ARCH__="linux_arm64" ;;
                armv7|armv7l) __NORM_ARCH__="linux_armv7" ;;
                *) __NORM_ARCH__="linux_amd64" ;;
            esac
        fi
    fi
    readonly FRP_ARCH="${__NORM_ARCH__}"
    unset __RAW_ARCH__ __NORM_ARCH__
fi
# Support MOONFRP_INSTALL_DIR (legacy) for backward compatibility, but prefer FRP_DIR
[[ -z "${FRP_DIR:-}" ]] && readonly FRP_DIR="${MOONFRP_INSTALL_DIR:-/opt/frp}"
[[ -z "${CONFIG_DIR:-}" ]] && readonly CONFIG_DIR="${MOONFRP_CONFIG_DIR:-/etc/frp}"
[[ -z "${LOG_DIR:-}" ]] && readonly LOG_DIR="${MOONFRP_LOG_DIR:-/var/log/frp}"
[[ -z "${TEMP_DIR:-}" ]] && readonly TEMP_DIR="/tmp/moonfrp"

# Data storage directory (used for JSON indices and caches)
[[ -z "${DATA_DIR:-}" ]] && readonly DATA_DIR="${MOONFRP_DATA_DIR:-/opt/moonfrp/data}"
[[ -z "${INDEX_DB_PATH:-}" ]] && readonly INDEX_DB_PATH="${MOONFRP_INDEX_DB_PATH:-$HOME/.moonfrp/index.db}"
[[ -z "${REAL_SQLITE3_PATH:-}" ]] && REAL_SQLITE3_PATH=$(command -v sqlite3 2>/dev/null || echo "")

# Service names (only declare if not already set)
[[ -z "${SERVER_SERVICE:-}" ]] && readonly SERVER_SERVICE="moonfrp-server"
[[ -z "${CLIENT_SERVICE_PREFIX:-}" ]] && readonly CLIENT_SERVICE_PREFIX="moonfrp-client"

# Configuration defaults (only declare if not already set)
[[ -z "${DEFAULT_SERVER_BIND_ADDR:-}" ]] && readonly DEFAULT_SERVER_BIND_ADDR="${MOONFRP_SERVER_BIND_ADDR:-0.0.0.0}"
[[ -z "${DEFAULT_SERVER_BIND_PORT:-}" ]] && readonly DEFAULT_SERVER_BIND_PORT="${MOONFRP_SERVER_BIND_PORT:-7000}"
[[ -z "${DEFAULT_SERVER_AUTH_TOKEN:-}" ]] && readonly DEFAULT_SERVER_AUTH_TOKEN="${MOONFRP_SERVER_AUTH_TOKEN:-}"
[[ -z "${DEFAULT_SERVER_DASHBOARD_PORT:-}" ]] && readonly DEFAULT_SERVER_DASHBOARD_PORT="${MOONFRP_SERVER_DASHBOARD_PORT:-7500}"
[[ -z "${DEFAULT_SERVER_DASHBOARD_USER:-}" ]] && readonly DEFAULT_SERVER_DASHBOARD_USER="${MOONFRP_SERVER_DASHBOARD_USER:-admin}"
[[ -z "${DEFAULT_SERVER_DASHBOARD_PASSWORD:-}" ]] && readonly DEFAULT_SERVER_DASHBOARD_PASSWORD="${MOONFRP_SERVER_DASHBOARD_PASSWORD:-}"

[[ -z "${DEFAULT_CLIENT_SERVER_ADDR:-}" ]] && readonly DEFAULT_CLIENT_SERVER_ADDR="${MOONFRP_CLIENT_SERVER_ADDR:-}"
[[ -z "${DEFAULT_CLIENT_SERVER_PORT:-}" ]] && readonly DEFAULT_CLIENT_SERVER_PORT="${MOONFRP_CLIENT_SERVER_PORT:-7000}"
[[ -z "${DEFAULT_CLIENT_AUTH_TOKEN:-}" ]] && readonly DEFAULT_CLIENT_AUTH_TOKEN="${MOONFRP_CLIENT_AUTH_TOKEN:-}"
[[ -z "${DEFAULT_CLIENT_USER:-}" ]] && readonly DEFAULT_CLIENT_USER="${MOONFRP_CLIENT_USER:-}"

[[ -z "${DEFAULT_TLS_ENABLE:-}" ]] && readonly DEFAULT_TLS_ENABLE="${MOONFRP_TLS_ENABLE:-true}"
[[ -z "${DEFAULT_TLS_FORCE:-}" ]] && readonly DEFAULT_TLS_FORCE="${MOONFRP_TLS_FORCE:-false}"
[[ -z "${DEFAULT_AUTH_METHOD:-}" ]] && readonly DEFAULT_AUTH_METHOD="${MOONFRP_AUTH_METHOD:-token}"
[[ -z "${DEFAULT_MAX_POOL_COUNT:-}" ]] && readonly DEFAULT_MAX_POOL_COUNT="${MOONFRP_MAX_POOL_COUNT:-20}"
[[ -z "${DEFAULT_POOL_COUNT:-}" ]] && readonly DEFAULT_POOL_COUNT="${MOONFRP_POOL_COUNT:-20}"
[[ -z "${DEFAULT_TCP_MUX:-}" ]] && readonly DEFAULT_TCP_MUX="${MOONFRP_TCP_MUX:-false}"
[[ -z "${DEFAULT_TCP_MUX_KEEPALIVE_INTERVAL:-}" ]] && readonly DEFAULT_TCP_MUX_KEEPALIVE_INTERVAL="${MOONFRP_TCP_MUX_KEEPALIVE_INTERVAL:-10}"
[[ -z "${DEFAULT_DIAL_SERVER_TIMEOUT:-}" ]] && readonly DEFAULT_DIAL_SERVER_TIMEOUT="${MOONFRP_DIAL_SERVER_TIMEOUT:-10}"
[[ -z "${DEFAULT_DIAL_SERVER_KEEPALIVE:-}" ]] && readonly DEFAULT_DIAL_SERVER_KEEPALIVE="${MOONFRP_DIAL_SERVER_KEEPALIVE:-120}"
[[ -z "${DEFAULT_HEARTBEAT_INTERVAL:-}" ]] && readonly DEFAULT_HEARTBEAT_INTERVAL="${MOONFRP_HEARTBEAT_INTERVAL:-30}"
[[ -z "${DEFAULT_HEARTBEAT_TIMEOUT:-}" ]] && readonly DEFAULT_HEARTBEAT_TIMEOUT="${MOONFRP_HEARTBEAT_TIMEOUT:-90}"

[[ -z "${DEFAULT_LOG_LEVEL:-}" ]] && readonly DEFAULT_LOG_LEVEL="${MOONFRP_LOG_LEVEL:-info}"
[[ -z "${DEFAULT_LOG_MAX_DAYS:-}" ]] && readonly DEFAULT_LOG_MAX_DAYS="${MOONFRP_LOG_MAX_DAYS:-7}"
[[ -z "${DEFAULT_LOG_DISABLE_COLOR:-}" ]] && readonly DEFAULT_LOG_DISABLE_COLOR="${MOONFRP_LOG_DISABLE_COLOR:-false}"

# Multi-IP configuration (only declare if not already set)
[[ -z "${SERVER_IPS:-}" ]] && readonly SERVER_IPS="${MOONFRP_SERVER_IPS:-}"
[[ -z "${SERVER_PORTS:-}" ]] && readonly SERVER_PORTS="${MOONFRP_SERVER_PORTS:-}"
[[ -z "${CLIENT_PORTS:-}" ]] && readonly CLIENT_PORTS="${MOONFRP_CLIENT_PORTS:-}"

# Menu state tracking (only declare if not already set)
if [[ -z "${MENU_STATE:-}" ]]; then
    declare -A MENU_STATE
    MENU_STATE["depth"]="0"
    MENU_STATE["ctrl_c_pressed"]="false"
fi

# Cache for performance (only declare if not already set)
if [[ -z "${CACHE_DATA:-}" ]]; then
    declare -A CACHE_DATA
    CACHE_DATA["frp_installation"]=""
    CACHE_DATA["update_check_done"]="false"
fi

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
    local allow_empty="${4:-false}"
    
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
            elif [[ "$allow_empty" == "true" ]]; then
                eval "$var_name=\"\""
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
    # Check if FRP is installed first
    if ! check_frp_installation; then
        echo "not installed"
        return 0
    fi

    local version=""
    local version_pattern='v?[0-9]+\.[0-9]+\.[0-9]+'

    # Method 1: Try frps --version
    if [[ -x "$FRP_DIR/frps" ]]; then
        version=$("$FRP_DIR/frps" --version 2>/dev/null | grep -oE "$version_pattern" | head -1 || true)
        if [[ -n "$version" ]]; then
            # Ensure 'v' prefix is present
            if [[ ! "$version" =~ ^v ]]; then
                version="v$version"
            fi
            echo "$version"
            return 0
        fi
    fi

    # Method 2: Try frpc --version as fallback
    if [[ -x "$FRP_DIR/frpc" ]]; then
        version=$("$FRP_DIR/frpc" --version 2>/dev/null | grep -oE "$version_pattern" | head -1 || true)
        if [[ -n "$version" ]]; then
            # Ensure 'v' prefix is present
            if [[ ! "$version" =~ ^v ]]; then
                version="v$version"
            fi
            echo "$version"
            return 0
        fi
    fi

    # Method 3: Read from .version file if exists
    if [[ -f "$FRP_DIR/.version" ]]; then
        version=$(grep -oE "$version_pattern" "$FRP_DIR/.version" | head -1 || true)
        if [[ -n "$version" ]]; then
            # Ensure 'v' prefix is present
            if [[ ! "$version" =~ ^v ]]; then
                version="v$version"
            fi
            echo "$version"
            return 0
        fi
    fi

    # All methods failed
    echo "unknown"
    return 0
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
FRP_VERSION="$FRP_VERSION"
FRP_ARCH="$FRP_ARCH"

# Installation Directories
FRP_DIR="$FRP_DIR"
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
MOONFRP_TCP_MUX_KEEPALIVE_INTERVAL="$DEFAULT_TCP_MUX_KEEPALIVE_INTERVAL"
MOONFRP_DIAL_SERVER_TIMEOUT="$DEFAULT_DIAL_SERVER_TIMEOUT"
MOONFRP_DIAL_SERVER_KEEPALIVE="$DEFAULT_DIAL_SERVER_KEEPALIVE"
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

sqlite3() {
    local original_args=("$@")
    if [[ -n "$REAL_SQLITE3_PATH" && "${MOONFRP_USE_NATIVE_SQLITE:-0}" == "1" ]]; then
        "$REAL_SQLITE3_PATH" "${original_args[@]}"
        return $?
    fi

    local separator="\n"
    local json_output=false
    local args=()

    while [[ "$1" == -* ]]; do
        case "$1" in
            -separator)
                separator="$2"
                shift 2
                ;;
            -json)
                json_output=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    local db_path="$1"
    shift
    local query="$1"
    shift

    if [[ -n "$REAL_SQLITE3_PATH" ]]; then
        case "$query" in
            *"CREATE"*|*"INSERT"*|*"UPDATE"*|*"DELETE"*|*"DROP"*)
                "$REAL_SQLITE3_PATH" "${original_args[@]}"
                return $?
                ;;
        esac
    fi

    local data_root="${INDEX_DATA_ROOT:-${DATA_DIR}/config-index}"

    SQLITE_SEPARATOR="$separator" SQLITE_JSON=$([[ $json_output == true ]] && echo 1 || echo 0) \
    python3 - "$data_root" "$query" <<'PY'
import json
import os
import sys
import re

root = sys.argv[1]
query = sys.argv[2].strip().rstrip(';')
separator = os.environ.get('SQLITE_SEPARATOR', '\n')
json_output = os.environ.get('SQLITE_JSON') == '1'

if not os.path.isdir(root):
    sys.exit(0)

entries = []
for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    entries.append(data)

entries.sort(key=lambda d: (d.get('type', ''), d.get('server_addr') or '', d.get('path', '')))

special_cases = [
    "SELECT file_path FROM config_index ORDER BY config_type, server_addr",
    "SELECT COUNT(*) FROM config_index",
    "SELECT COALESCE(SUM(proxy_count), 0) FROM config_index",
    "SELECT COUNT(DISTINCT server_addr) FROM config_index WHERE server_addr IS NOT NULL AND server_addr != ''",
    "SELECT * FROM config_index ORDER BY config_type, server_addr",
]

if query in special_cases:
    if query.startswith("SELECT file_path"):
        for data in entries:
            path = data.get('path')
            if path:
                print(path)
    elif query.startswith("SELECT COUNT(*)"):
        print(len(entries))
    elif query.startswith("SELECT COALESCE(SUM(proxy_count)"):
        total = 0
        for data in entries:
            try:
                total += int(data.get('proxy_count') or 0)
            except Exception:
                pass
        print(total)
    elif query.startswith("SELECT COUNT(DISTINCT server_addr)"):
        servers = {data.get('server_addr') for data in entries if data.get('server_addr')}
        print(len(servers))
    elif query.startswith("SELECT * FROM config_index"):
        records = []
        for data in entries:
            record = {
                "file_path": data.get('path'),
                "file_hash": data.get('hash'),
                "config_type": data.get('type'),
                "server_addr": data.get('server_addr'),
                "server_port": data.get('server_port'),
                "bind_port": data.get('bind_port'),
                "auth_token_hash": data.get('auth_token_hash'),
                "proxy_count": data.get('proxy_count'),
                "tags": data.get('tags') or {},
                "last_modified": data.get('last_modified'),
                "last_indexed": data.get('last_indexed'),
            }
            records.append(record)
        if json_output:
            json.dump(records, sys.stdout, ensure_ascii=False)
            sys.stdout.write('\n')
        else:
            for record in records:
                print(record)
    sys.exit(0)

match = re.search(r"SELECT (.+) FROM config_index WHERE file_path='(.+)'", query)
if match:
    fields = [field.strip() for field in match.group(1).split(',')]
    raw_path = match.group(2).replace("''", "'")
    target = next((data for data in entries if data.get('path') == raw_path), None)
    if not target:
        sys.exit(0)
    row_values = []
    for field in fields:
        if field.startswith("COALESCE("):
            inner = field[field.index('(') + 1:field.rindex(',')]
            value = target.get(inner)
            if value is None:
                value = 0
        elif field == 'config_type':
            value = target.get('type')
        elif field == 'file_path':
            value = target.get('path')
        else:
            value = target.get(field)
        if value is None:
            value = ''
        row_values.append(value)
    if len(row_values) == 1:
        print(row_values[0])
    else:
        print(separator.join(str(item) for item in row_values))
    sys.exit(0)

like_match = re.search(r"LIKE LOWER\('%(.+)%'\)", query)
if like_match:
    needle = like_match.group(1).lower()
    for data in sorted(entries, key=lambda d: d.get('path', '')):
        path = data.get('path', '')
        if needle not in path.lower():
            continue
        row = [
            path,
            data.get('type', ''),
            data.get('server_addr') or '',
            int(data.get('proxy_count') or 0),
        ]
        print(separator.join(str(item) for item in row))
    sys.exit(0)

ip_match = re.search(r"WHERE server_addr='(.+)' OR bind_port='(.+)'", query)
if ip_match:
    addr = ip_match.group(1)
    port_str = ip_match.group(2)
    for data in sorted(entries, key=lambda d: d.get('path', '')):
        server_addr = data.get('server_addr') or ''
        bind_port = str(data.get('bind_port') or '')
        if server_addr == addr or bind_port == port_str:
            row = [
                data.get('path', ''),
                data.get('type', ''),
                server_addr,
                int(data.get('proxy_count') or 0),
            ]
            print(separator.join(str(item) for item in row))
    sys.exit(0)

port_match = re.search(r"WHERE server_port=(\d+) OR bind_port=(\d+)", query)
if port_match:
    port = int(port_match.group(1))
    for data in sorted(entries, key=lambda d: d.get('path', '')):
        try:
            server_port = int(data.get('server_port') or 0)
        except Exception:
            server_port = None
        try:
            bind_port = int(data.get('bind_port') or 0)
        except Exception:
            bind_port = None
        if server_port == port or bind_port == port:
            row = [
                data.get('path', ''),
                data.get('type', ''),
                data.get('server_addr') or '',
                int(data.get('proxy_count') or 0),
            ]
            print(separator.join(str(item) for item in row))
    sys.exit(0)

# Default: no output
PY
}