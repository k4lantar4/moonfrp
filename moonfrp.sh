#!/bin/bash

# MoonFRP - Advanced FRP Management Script
# Version: 1.0.5
# Author: MoonFRP Team
# Description: Modular FRP configuration and service management tool
#
# Performance Notes:
# - Server settings in frps.toml:
#   * maxPortsPerClient: Limit ports per client (default: 10)
#   * userConnTimeout: Maximum wait time for connections (default: 10s)
#   * transport.maxPoolCount: Limit connection pool size (default: 5)
#   * transport.quic.maxIncomingStreams: Limit QUIC streams (default: 100)
#
# - Client settings in frpc.toml:
#   * loginFailExit: Exit on login failure (default: true)
#   * transport.poolCount: Connection pool size (default: 5)
#   * transport.dialServerKeepalive: Keep-alive interval (default: 300s)
#   * transport.bandwidthLimit: Bandwidth limit (default: "10MB")

# Use safer bash settings, but allow for graceful error handling
set -uo pipefail

# Performance optimizations
export TERM=${TERM:-xterm}
export SYSTEMD_COLORS=0
export SYSTEMD_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRP_VERSION="0.63.0"
FRP_ARCH="linux_amd64"
FRP_DIR="/opt/frp"
CONFIG_DIR="/etc/frp"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log/frp"
TEMP_DIR="/tmp/moonfrp"

# MoonFRP Repository Settings
MOONFRP_VERSION="1.1.0"
MOONFRP_REPO_URL="https://api.github.com/repos/k4lantar4/moonfrp/releases/latest"
MOONFRP_SCRIPT_URL="https://raw.githubusercontent.com/k4lantar4/moonfrp/main/moonfrp.sh"
MOONFRP_INSTALL_PATH="/usr/local/bin/moonfrp"

# Global variables for template and proxy configuration
SELECTED_PROXY_TYPE=""
SELECTED_PROXY_NAME=""
TEMPLATE_PORTS=""
TEMPLATE_NAME=""
TEMPLATE_DESCRIPTION=""
TEMPLATE_PROXY_TYPE=""
CUSTOM_DOMAINS=""

# Create required directories
create_directories() {
    local dirs=("$FRP_DIR" "$CONFIG_DIR" "$LOG_DIR" "$TEMP_DIR")
    for dir in "${dirs[@]}"; do
        [[ ! -d "$dir" ]] && mkdir -p "$dir"
    done
}

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    # Safe logging to file
    if [[ -d "$LOG_DIR" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_DIR/moonfrp.log" 2>/dev/null || true
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    echo -e "${RED}[ERROR]${NC} Script failed at line $line_number with exit code $exit_code"
    # Don't exit immediately, just log the error
    return 0
}

# Only trap errors for critical functions, not the entire script
# trap 'handle_error $LINENO' ERR

# Menu depth tracking for proper Ctrl+C handling
MENU_DEPTH=0
MENU_STACK=()

# Signal handler for Ctrl+C
signal_handler() {
    echo -e "\n${YELLOW}[CTRL+C] Operation cancelled...${NC}"
    
    # If we're in main menu (depth 0), exit gracefully
    if [[ $MENU_DEPTH -eq 0 ]]; then
        echo -e "${GREEN}Exiting MoonFRP. Goodbye! 🚀${NC}"
        cleanup_and_exit
    else
        # In submenu, return to previous menu
        echo -e "${CYAN}Returning to previous menu...${NC}"
        sleep 1
        CTRL_C_PRESSED=true
        return 130  # Standard exit code for SIGINT
    fi
}

# Global flag for Ctrl+C detection
CTRL_C_PRESSED=false

# Setup signal trapping
setup_signal_handlers() {
    trap signal_handler SIGINT
}

# Enter a submenu (increase depth)
enter_submenu() {
    local menu_name="$1"
    ((MENU_DEPTH++))
    MENU_STACK+=("$menu_name")
    CTRL_C_PRESSED=false
}

# Exit a submenu (decrease depth)
exit_submenu() {
    if [[ $MENU_DEPTH -gt 0 ]]; then
        ((MENU_DEPTH--))
        unset MENU_STACK[-1]
    fi
    CTRL_C_PRESSED=false
}

# Function to check if Ctrl+C was pressed during input
check_ctrl_c() {
    if [[ "$CTRL_C_PRESSED" == "true" ]]; then
        CTRL_C_PRESSED=false
        return 1  # Return to main menu
    fi
    return 0
}

# Enhanced read function that handles Ctrl+C properly
safe_read() {
    local prompt="$1"
    local var_name="$2"
    local default_value="${3:-}"
    
    # Reset Ctrl+C flag
    CTRL_C_PRESSED=false
    
    # Use regular read but check for Ctrl+C interrupt
    if read -r $var_name; then
        # Input received successfully
        local input_value=$(eval echo \$$var_name)
        if [[ -z "$input_value" && -n "$default_value" ]]; then
            eval $var_name="$default_value"
        fi
        return 0
    else
        # Read was interrupted (likely by Ctrl+C)
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            return 1  # Ctrl+C was pressed
        fi
        return 0  # Normal completion
    fi
}

# Safe read with automatic Ctrl+C handling for menus
safe_read_menu() {
    local prompt="$1"
    local var_name="$2"
    local default_value="${3:-}"
    
    echo -e "$prompt"
    read -r $var_name
    
    # Check for Ctrl+C after read
    if [[ "$CTRL_C_PRESSED" == "true" ]]; then
        CTRL_C_PRESSED=false
        return 1
    fi
    
    # Apply default value if needed
    local input_value=$(eval echo \$$var_name)
    if [[ -z "$input_value" && -n "$default_value" ]]; then
        eval $var_name="$default_value"
    fi
    
    return 0
}

# Enhanced read function with Ctrl+C handling and return to menu
safe_read_with_return() {
    local prompt="$1"
    local var_name="$2"
    local default_value="${3:-}"
    
    echo -e "$prompt"
    read -r $var_name
    
    # Check for Ctrl+C after read
    if [[ "$CTRL_C_PRESSED" == "true" ]]; then
        CTRL_C_PRESSED=false
        echo -e "${CYAN}Returning to menu...${NC}"
        return 1  # Signal to return to menu
    fi
    
    # Apply default value if needed
    local input_value=$(eval echo \$$var_name)
    if [[ -z "$input_value" && -n "$default_value" ]]; then
        eval $var_name="$default_value"
    fi
    
    return 0
}

# Wrapper function for read operations in configuration functions
read_with_ctrl_c_check() {
    local prompt="$1"
    local var_name="$2"
    local default_value="${3:-}"
    
    echo -e "$prompt"
    read -r $var_name
    
    # Check for Ctrl+C and return to menu if detected
    if [[ "$CTRL_C_PRESSED" == "true" ]]; then
        CTRL_C_PRESSED=false
        echo -e "${CYAN}Returning to menu...${NC}"
        return 1
    fi
    
    # Apply default value if needed
    local input_value=$(eval echo \$$var_name)
    if [[ -z "$input_value" && -n "$default_value" ]]; then
        eval $var_name="$default_value"
    fi
    
    return 0
}

# Quick help for common errors
show_quick_help() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         MoonFRP Quick Help           ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    echo -e "\n${RED}❌ Common Error: 'proxy already exists'${NC}"
    echo -e "${CYAN}Solution:${NC}"
    echo -e "  1. Stop all FRP services: ${GREEN}systemctl stop moonfrp-*${NC}"
    echo -e "  2. Remove old configs: ${GREEN}rm -f /etc/frp/frpc_*.toml${NC}"
    echo -e "  3. Use MoonFRP menu option 6 → 5 → 2 to reset configs"
    echo -e "  4. Recreate configurations with unique names"
    
    echo -e "\n${RED}❌ Common Error: 'port unavailable'${NC}"
    echo -e "${CYAN}Solution:${NC}"
    echo -e "  1. Check server allowPorts config: ${GREEN}/etc/frp/frps.toml${NC}"
    echo -e "  2. Ensure port range includes your ports (1000-65535)"
    echo -e "  3. Check if port is already used: ${GREEN}netstat -tlnp | grep :PORT${NC}"
    echo -e "  4. Try different ports or free the conflicting ones"
    
    echo -e "\n${RED}❌ Common Error: 'connection refused'${NC}"
    echo -e "${CYAN}Solution:${NC}"
    echo -e "  1. Verify server is running: ${GREEN}systemctl status moonfrp-server${NC}"
    echo -e "  2. Check firewall allows port 7000: ${GREEN}ufw allow 7000/tcp${NC}"
    echo -e "  3. Verify server IP and token match client config"
    echo -e "  4. Test connection: ${GREEN}nc -z SERVER_IP 7000${NC}"
    
    echo -e "\n${RED}❌ Common Error: 'authentication failed'${NC}"
    echo -e "${CYAN}Solution:${NC}"
    echo -e "  1. Ensure server and client tokens match exactly"
    echo -e "  2. Check server config: ${GREEN}/etc/frp/frps.toml${NC}"
    echo -e "  3. Check client config: ${GREEN}/etc/frp/frpc_*.toml${NC}"
    echo -e "  4. Regenerate token if needed"
    
    echo -e "\n${RED}❌ Common Error: 'HTTP 503 - Web Panel'${NC}"
    echo -e "${CYAN}Solution:${NC}"
    echo -e "  1. Check if FRP server is running: ${GREEN}systemctl status moonfrp-server${NC}"
    echo -e "  2. Verify dashboard port in config: ${GREEN}/etc/frp/frps.toml${NC}"
    echo -e "  3. Check firewall allows dashboard port: ${GREEN}ufw allow 7500/tcp${NC}"
    echo -e "  4. Use menu option 6 → 8 for web panel diagnostics"
    echo -e "  5. Try restarting: ${GREEN}systemctl status moonfrp-server${NC}"
    
    echo -e "\n${YELLOW}💡 Pro Tips:${NC}"
    echo -e "  • Use menu option 6 for detailed diagnostics"
    echo -e "  • Check logs: ${GREEN}journalctl -u moonfrp-* -f${NC}"
    echo -e "  • Backup configs before changes"
    echo -e "  • Use unique proxy names with timestamps"
    echo -e "  • Web panel usually runs on port 7500"
    
    read -p "Press Enter to continue..."
}

# Input validation functions
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            [[ $i -gt 255 ]] && return 1
        done
        return 0
    fi
    return 1
}

validate_port() {
    local port="$1"
    [[ $port =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]
}

validate_ports_list() {
    local ports="$1"
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        validate_port "$port" || return 1
    done
    return 0
}

validate_ips_list() {
    local ips="$1"
    IFS=',' read -ra IP_ARRAY <<< "$ips"
    for ip in "${IP_ARRAY[@]}"; do
        ip=$(echo "$ip" | tr -d ' ')
        validate_ip "$ip" || return 1
    done
    return 0
}

# Enhanced validation for domain names
validate_domain() {
    local domain="$1"
    
    # Basic domain validation regex
    if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] && 
       [[ ! "$domain" =~ \.\. ]] && 
       [[ ! "$domain" =~ ^- ]] && 
       [[ ! "$domain" =~ -$ ]] &&
       [[ ${#domain} -le 253 ]]; then
        return 0
    else
        return 1
    fi
}

# Proxy type selection menu
select_proxy_type() {
    while true; do
        # Check for Ctrl+C signal
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return 1
        fi
        
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║        Proxy Type Selection          ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        echo -e "\n${CYAN}Select Proxy Type:${NC}"
        echo -e "${GREEN}1. TCP${NC} ${YELLOW}(Basic port forwarding - Default)${NC}"
        echo -e "   • Direct port-to-port mapping"
        echo -e "   • Suitable for: SSH, databases, custom apps"
        echo -e "   • Example: local:22 → remote:22"
        
        echo -e "\n${GREEN}2. HTTP${NC} ${YELLOW}(Web services with domain names)${NC}"
        echo -e "   • Domain-based routing via Host header"
        echo -e "   • Suitable for: websites, web APIs, dev servers"
        echo -e "   • Example: myapp.example.com → local:3000"
        
        echo -e "\n${GREEN}3. HTTPS${NC} ${YELLOW}(Secure web services with SSL)${NC}"
        echo -e "   • Encrypted domain-based routing"
        echo -e "   • Suitable for: production websites, secure APIs"
        echo -e "   • Example: secure.example.com → local:443"
        
        echo -e "\n${GREEN}4. UDP${NC} ${YELLOW}(Games, DNS, streaming)${NC}"
        echo -e "   • UDP protocol forwarding"
        echo -e "   • Suitable for: game servers, DNS, video streaming"
        echo -e "   • Example: local:25565 → remote:25565"
        
        echo -e "\n${GREEN}5. TCPMUX${NC} ${YELLOW}(TCP multiplexing over HTTP CONNECT)${NC}"
        echo -e "   • HTTP CONNECT based TCP multiplexing"
        echo -e "   • Suitable for: HTTP proxy tunneling, corporate firewalls"
        echo -e "   • Example: tunnel1.example.com → local:8080"
        
        echo -e "\n${GREEN}6. STCP${NC} ${YELLOW}(Secret TCP - P2P secure tunneling)${NC}"
        echo -e "   • Secure point-to-point TCP tunneling"
        echo -e "   • Suitable for: private services, secure remote access"
        echo -e "   • Requires: secret key authentication"
        
        echo -e "\n${GREEN}7. SUDP${NC} ${YELLOW}(Secret UDP - P2P secure tunneling)${NC}"
        echo -e "   • Secure point-to-point UDP tunneling"
        echo -e "   • Suitable for: private games, secure UDP services"
        echo -e "   • Requires: secret key authentication"
        
        echo -e "\n${GREEN}8. TCPMUX-Direct${NC} ${YELLOW}(TCP-like access with TCPMUX benefits)${NC}"
        echo -e "   • Provides TCP-like access while maintaining TCPMUX benefits"
        echo -e "   • Suitable for: corporate firewalls, secure remote access"
        echo -e "   • Requires: secret key authentication"
        
        echo -e "\n${GREEN}9. XTCP${NC} ${YELLOW}(P2P TCP - Direct peer-to-peer connection)${NC}"
        echo -e "   • True P2P TCP connection with NAT traversal"
        echo -e "   • Suitable for: gaming, real-time applications, direct access"
        echo -e "   • Features: NAT hole punching, fallback options"
        
        echo -e "\n${GREEN}10. Plugin System${NC} ${YELLOW}(Unix sockets, HTTP/SOCKS5 proxy, Static files)${NC}"
        echo -e "   • Unix domain socket forwarding"
        echo -e "   • HTTP/SOCKS5 proxy server functionality"
        echo -e "   • Static file server with authentication"
        
        echo -e "\n${CYAN}0. Back${NC}"
        
        echo -e "\n${YELLOW}Enter your choice [0-10] (default: 1):${NC} "
        read -r choice
        
        # Check for Ctrl+C after read
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return 1
        fi
        
        # Default to TCP if no input
        [[ -z "$choice" ]] && choice=1
        
        case $choice in
            1) 
                SELECTED_PROXY_TYPE="tcp"
                SELECTED_PROXY_NAME="TCP"
                return 0
                ;;
            2) 
                SELECTED_PROXY_TYPE="http"
                SELECTED_PROXY_NAME="HTTP"
                return 0
                ;;
            3) 
                SELECTED_PROXY_TYPE="https"
                SELECTED_PROXY_NAME="HTTPS"
                return 0
                ;;
            4) 
                SELECTED_PROXY_TYPE="udp"
                SELECTED_PROXY_NAME="UDP"
                return 0
                ;;
            5) 
                SELECTED_PROXY_TYPE="tcpmux"
                SELECTED_PROXY_NAME="TCPMUX"
                return 0
                ;;
            6) 
                SELECTED_PROXY_TYPE="stcp"
                SELECTED_PROXY_NAME="STCP"
                return 0
                ;;
            7) 
                SELECTED_PROXY_TYPE="sudp"
                SELECTED_PROXY_NAME="SUDP"
                return 0
                ;;
            8) 
                SELECTED_PROXY_TYPE="tcpmux-direct"
                SELECTED_PROXY_NAME="TCPMUX-Direct"
                return 0
                ;;
            9) 
                SELECTED_PROXY_TYPE="xtcp"
                SELECTED_PROXY_NAME="XTCP"
                return 0
                ;;
            10) 
                # Call plugin selection submenu
                if select_plugin_type; then
                    return 0
                else
                    continue
                fi
                ;;
            0) 
                return 1
                ;;
            *) 
                log "WARN" "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Plugin type selection menu
select_plugin_type() {
    while true; do
        # Check for Ctrl+C signal
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return 1
        fi
        
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║        Plugin Type Selection        ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        echo -e "\n${CYAN}Select Plugin Type:${NC}"
        echo -e "${GREEN}1. Unix Domain Socket${NC} ${YELLOW}(Forward to Unix socket)${NC}"
        echo -e "   • Connect to Unix domain sockets"
        echo -e "   • Suitable for: Docker API, system sockets"
        echo -e "   • Example: /var/run/docker.sock"
        
        echo -e "\n${GREEN}2. HTTP Proxy${NC} ${YELLOW}(HTTP proxy server)${NC}"
        echo -e "   • Create HTTP proxy server"
        echo -e "   • Suitable for: web browsing, API access"
        echo -e "   • Features: username/password authentication"
        
        echo -e "\n${GREEN}3. SOCKS5 Proxy${NC} ${YELLOW}(SOCKS5 proxy server)${NC}"
        echo -e "   • Create SOCKS5 proxy server"
        echo -e "   • Suitable for: general TCP/UDP proxying"
        echo -e "   • Features: username/password authentication"
        
        echo -e "\n${GREEN}4. Static File Server${NC} ${YELLOW}(Serve static files)${NC}"
        echo -e "   • Serve static files over HTTP"
        echo -e "   • Suitable for: file sharing, web hosting"
        echo -e "   • Features: authentication, path stripping"
        
        echo -e "\n${GREEN}5. HTTPS2HTTP${NC} ${YELLOW}(HTTPS to HTTP converter)${NC}"
        echo -e "   • Convert HTTPS requests to HTTP"
        echo -e "   • Suitable for: SSL termination, legacy services"
        echo -e "   • Features: certificate handling, header rewriting"
        
        echo -e "\n${GREEN}6. HTTP2HTTPS${NC} ${YELLOW}(HTTP to HTTPS converter)${NC}"
        echo -e "   • Convert HTTP requests to HTTPS"
        echo -e "   • Suitable for: SSL wrapping, secure backends"
        echo -e "   • Features: certificate handling, header rewriting"
        
        echo -e "\n${CYAN}0. Back${NC}"
        
        echo -e "\n${YELLOW}Enter your choice [0-6] (default: 1):${NC} "
        read -r choice
        
        # Check for Ctrl+C after read
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return 1
        fi
        
        # Default to Unix Domain Socket if no input
        [[ -z "$choice" ]] && choice=1
        
        case $choice in
            1) 
                SELECTED_PROXY_TYPE="plugin_unix_socket"
                SELECTED_PROXY_NAME="Unix Domain Socket"
                return 0
                ;;
            2) 
                SELECTED_PROXY_TYPE="plugin_http_proxy"
                SELECTED_PROXY_NAME="HTTP Proxy"
                return 0
                ;;
            3) 
                SELECTED_PROXY_TYPE="plugin_socks5"
                SELECTED_PROXY_NAME="SOCKS5 Proxy"
                return 0
                ;;
            4) 
                SELECTED_PROXY_TYPE="plugin_static_file"
                SELECTED_PROXY_NAME="Static File Server"
                return 0
                ;;
            5) 
                SELECTED_PROXY_TYPE="plugin_https2http"
                SELECTED_PROXY_NAME="HTTPS2HTTP"
                return 0
                ;;
            6) 
                SELECTED_PROXY_TYPE="plugin_http2https"
                SELECTED_PROXY_NAME="HTTP2HTTPS"
                return 0
                ;;
            0) 
                return 1
                ;;
            *) 
                log "WARN" "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Domain input for HTTP/HTTPS proxies
get_custom_domains() {
    local ports="$1"
    local domains=""
    
    echo -e "\n${CYAN}Domain Configuration for ${SELECTED_PROXY_NAME} Proxy:${NC}"
    echo -e "${YELLOW}You can specify custom domains for your services.${NC}"
    echo -e "${YELLOW}Leave empty to use auto-generated domains.${NC}"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    local domain_list=()
    
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        echo -e "\n${CYAN}Domain for service on port $port:${NC}"
        echo -e "${GREEN}Examples:${NC}"
        echo -e "  • myapp.example.com"
        echo -e "  • api.mydomain.org"
        echo -e "  • subdomain.yourdomain.net"
        
        read -p "Custom domain (or press Enter for auto): " domain
        
        if [[ -n "$domain" ]]; then
            # Basic domain validation
            if validate_domain "$domain"; then
                domain_list+=("$domain")
                echo -e "${GREEN}✅ Domain set: $domain → localhost:$port${NC}"
            else
                echo -e "${RED}❌ Invalid domain format. Using auto-generated domain.${NC}"
                domain_list+=("app${port}.moonfrp.local")
            fi
        else
            domain_list+=("app${port}.moonfrp.local")
            echo -e "${YELLOW}Using auto-generated: app${port}.moonfrp.local${NC}"
        fi
    done
    
    # Join domains with commas
    local IFS=','
    CUSTOM_DOMAINS="${domain_list[*]}"
    
    echo -e "\n${CYAN}📋 Domain Summary:${NC}"
    for i in "${!PORT_ARRAY[@]}"; do
        echo -e "  ${GREEN}${domain_list[$i]}${NC} → localhost:${PORT_ARRAY[$i]}"
    done
}

# Enhanced FRP configuration validation
validate_frp_config() {
    local config_file="$1"
    local validation_failed=false
    
    log "INFO" "Validating FRP configuration: $config_file"
    
    # Check if file exists
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check if frpc binary exists for validation
    if [[ ! -f "$FRP_DIR/frpc" ]]; then
        log "WARN" "FRP client binary not found, skipping syntax validation"
    else
        # Syntax validation using frpc verify
        if ! "$FRP_DIR/frpc" verify -c "$config_file" >/dev/null 2>&1; then
            log "ERROR" "Configuration syntax error in $config_file"
            validation_failed=true
        else
            log "INFO" "✅ Configuration syntax is valid"
        fi
    fi
    
    # Check for common configuration issues
    local server_addr=$(grep "serverAddr" "$config_file" | head -1 | cut -d'"' -f2)
    local server_port=$(grep "serverPort" "$config_file" | head -1 | cut -d'=' -f2 | tr -d ' ')
    
    if [[ -n "$server_addr" && -n "$server_port" ]]; then
        log "INFO" "Testing server connectivity: $server_addr:$server_port"
        if ! timeout 3 nc -z "$server_addr" "$server_port" 2>/dev/null; then
            log "WARN" "⚠️  Cannot connect to server $server_addr:$server_port"
            validation_failed=true
        else
            log "INFO" "✅ Server connectivity confirmed"
        fi
    fi
    
    # Check for port conflicts across all configurations
    check_global_port_conflicts "$config_file"
    local conflict_result=$?
    if [[ $conflict_result -ne 0 ]]; then
        validation_failed=true
    fi
    
    # Check for proxy name conflicts
    check_global_proxy_conflicts "$config_file"
    local name_conflict_result=$?
    if [[ $name_conflict_result -ne 0 ]]; then
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        log "ERROR" "❌ Configuration validation failed"
        return 1
    else
        log "INFO" "✅ Configuration validation passed"
        return 0
    fi
}

# Check for port conflicts across all FRP configurations
check_global_port_conflicts() {
    local new_config_file="$1"
    local conflicts_found=false
    
    # Extract ports from new configuration
    local new_ports=()
    while IFS= read -r line; do
        if [[ $line =~ remotePort\ *=\ *([0-9]+) ]]; then
            new_ports+=("${BASH_REMATCH[1]}")
        fi
    done < "$new_config_file"
    
    # Check against all existing configurations
    for existing_config in "$CONFIG_DIR"/frpc_*.toml; do
        [[ ! -f "$existing_config" ]] && continue
        [[ "$existing_config" == "$new_config_file" ]] && continue
        
        while IFS= read -r line; do
            if [[ $line =~ remotePort\ *=\ *([0-9]+) ]]; then
                local existing_port="${BASH_REMATCH[1]}"
                
                for new_port in "${new_ports[@]}"; do
                    if [[ "$new_port" == "$existing_port" ]]; then
                        log "ERROR" "❌ Port conflict: $new_port already used in $existing_config"
                        conflicts_found=true
                    fi
                done
            fi
        done < "$existing_config"
    done
    
    # Check against system ports
    for port in "${new_ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            log "WARN" "⚠️  Port $port is in use by system process"
        fi
    done
    
    [[ "$conflicts_found" == "true" ]] && return 1 || return 0
}

# Check for proxy name conflicts across all FRP configurations
check_global_proxy_conflicts() {
    local new_config_file="$1"
    local conflicts_found=false
    
    # Extract proxy names from new configuration
    local new_names=()
    while IFS= read -r line; do
        if [[ $line =~ name\ *=\ *\"([^\"]+)\" ]]; then
            new_names+=("${BASH_REMATCH[1]}")
        fi
    done < "$new_config_file"
    
    # Check against all existing configurations
    for existing_config in "$CONFIG_DIR"/frpc_*.toml; do
        [[ ! -f "$existing_config" ]] && continue
        [[ "$existing_config" == "$new_config_file" ]] && continue
        
        while IFS= read -r line; do
            if [[ $line =~ name\ *=\ *\"([^\"]+)\" ]]; then
                local existing_name="${BASH_REMATCH[1]}"
                
                for new_name in "${new_names[@]}"; do
                    if [[ "$new_name" == "$existing_name" ]]; then
                        log "ERROR" "❌ Proxy name conflict: '$new_name' already exists in $existing_config"
                        conflicts_found=true
                    fi
                done
            fi
        done < "$existing_config"
    done
    
    [[ "$conflicts_found" == "true" ]] && return 1 || return 0
}

# Performance monitoring for FRP proxies
monitor_proxy_performance() {
    local proxy_name="$1"
    local admin_port="${2:-7400}"
    
    log "INFO" "Monitoring performance for proxy: $proxy_name"
    
    # Try to get stats from FRP dashboard API
    local api_url="http://127.0.0.1:$admin_port/api/proxy/$proxy_name"
    
    if command -v curl >/dev/null 2>&1; then
        local response=$(curl -s --connect-timeout 3 "$api_url" 2>/dev/null)
        
        if [[ -n "$response" ]] && echo "$response" | grep -q "name"; then
            echo -e "${CYAN}📊 Performance Stats for $proxy_name:${NC}"
            
            # Parse JSON response (basic parsing without jq)
            local status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            local today_in=$(echo "$response" | grep -o '"today_in":[0-9]*' | cut -d':' -f2)
            local today_out=$(echo "$response" | grep -o '"today_out":[0-9]*' | cut -d':' -f2)
            local cur_conns=$(echo "$response" | grep -o '"cur_conns":[0-9]*' | cut -d':' -f2)
            
            [[ -n "$status" ]] && echo -e "  Status: ${GREEN}$status${NC}"
            [[ -n "$today_in" ]] && echo -e "  Today In: ${CYAN}$(format_bytes $today_in)${NC}"
            [[ -n "$today_out" ]] && echo -e "  Today Out: ${CYAN}$(format_bytes $today_out)${NC}"
            [[ -n "$cur_conns" ]] && echo -e "  Active Connections: ${YELLOW}$cur_conns${NC}"
        else
            log "WARN" "Unable to retrieve performance data for $proxy_name"
        fi
    else
        log "WARN" "curl not available for performance monitoring"
    fi
}

# Format bytes to human readable format
format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0
    
    [[ -z "$bytes" || "$bytes" == "0" ]] && echo "0 B" && return
    
    while [[ $bytes -gt 1024 && $unit_index -lt ${#units[@]} ]]; do
        bytes=$((bytes / 1024))
        ((unit_index++))
    done
    
    echo "$bytes ${units[$unit_index]}"
}

# Monitor all active proxies
monitor_all_proxies() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         Proxy Performance            ║${NC}"
    echo -e "${PURPLE}║           Monitoring                 ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}🔍 Scanning for active FRP services...${NC}"
    
    local services=($(systemctl list-units --type=service --state=active --no-legend --plain | grep -E "(frpc|frps)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "\n${YELLOW}No active FRP services found${NC}"
        return
    fi
    
    echo -e "\n${GREEN}Found ${#services[@]} active service(s):${NC}"
    
    for service in "${services[@]}"; do
        echo -e "\n${CYAN}📈 Service: $service${NC}"
        
        # Get service status
        local status=$(systemctl is-active "$service" 2>/dev/null)
        local status_color="$RED"
        [[ "$status" == "active" ]] && status_color="$GREEN"
        
        echo -e "  Status: ${status_color}$status${NC}"
        
        # Get configuration file
        local config_file=""
        if [[ "$service" =~ frpc ]]; then
            local suffix=$(echo "$service" | grep -o '[0-9]\+$')
            [[ -n "$suffix" ]] && config_file="$CONFIG_DIR/frpc_${suffix}.toml"
        elif [[ "$service" =~ frps ]]; then
            config_file="$CONFIG_DIR/frps.toml"
        fi
        
        if [[ -f "$config_file" ]]; then
            echo -e "  Config: ${CYAN}$config_file${NC}"
            
            # Show proxy count
            local proxy_count=$(grep -c "^\[\[proxies\]\]" "$config_file" 2>/dev/null || echo "0")
            echo -e "  Proxies: ${YELLOW}$proxy_count${NC}"
            
            # Get recent log entries
            echo -e "  ${YELLOW}Recent activity:${NC}"
            if journalctl -u "$service" -n 3 --no-pager --since "10 minutes ago" -q 2>/dev/null | head -3; then
                :
            else
                echo -e "    ${GRAY}No recent activity${NC}"
            fi
        else
            echo -e "  ${RED}Configuration file not found${NC}"
        fi
        
        # Connection test for client services
        if [[ "$service" =~ frpc && -f "$config_file" ]]; then
            local server_addr=$(grep "serverAddr" "$config_file" | head -1 | cut -d'"' -f2)
            local server_port=$(grep "serverPort" "$config_file" | head -1 | cut -d'=' -f2 | tr -d ' ')
            
            if [[ -n "$server_addr" && -n "$server_port" ]]; then
                echo -e -n "  Server Test: "
                if timeout 2 nc -z "$server_addr" "$server_port" 2>/dev/null; then
                    echo -e "${GREEN}✅ Connected${NC}"
                else
                    echo -e "${RED}❌ Failed${NC}"
                fi
            fi
        fi
        
        echo -e "  ${GRAY}────────────────────────────────────${NC}"
    done
    
    echo -e "\n${YELLOW}💡 Tip: Use 'journalctl -u SERVICE_NAME -f' for real-time logs${NC}"
}

# Configuration templates for different use cases
get_config_template() {
    local template_type="$1"
    
    while true; do
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║      Configuration Templates        ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        echo -e "\n${CYAN}Available Templates:${NC}"
        echo -e "${GREEN}1. SSH Server${NC} ${YELLOW}(Port 22)${NC}"
        echo -e "   • Secure remote shell access"
        echo -e "   • Port: 22 → 22"
        
        echo -e "\n${GREEN}2. Web Development${NC} ${YELLOW}(Port 3000, 8080)${NC}"
        echo -e "   • Development servers (React, Node.js, etc.)"
        echo -e "   • Ports: 3000,8080 → 3000,8080"
        
        echo -e "\n${GREEN}3. Database Server${NC} ${YELLOW}(MySQL, PostgreSQL)${NC}"
        echo -e "   • MySQL: 3306 → 3306"
        echo -e "   • PostgreSQL: 5432 → 5432"
        
        echo -e "\n${GREEN}4. Game Server${NC} ${YELLOW}(Minecraft, CS)${NC}"
        echo -e "   • Minecraft: 25565 → 25565"
        echo -e "   • Counter-Strike: 27015 → 27015"
        
        echo -e "\n${GREEN}5. Web Server${NC} ${YELLOW}(HTTP/HTTPS)${NC}"
        echo -e "   • HTTP: 80 → 80"
        echo -e "   • HTTPS: 443 → 443"
        
        echo -e "\n${GREEN}6. Remote Desktop${NC} ${YELLOW}(RDP, VNC)${NC}"
        echo -e "   • RDP: 3389 → 3389"
        echo -e "   • VNC: 5900 → 5900"
        
        echo -e "\n${GREEN}7. File Transfer${NC} ${YELLOW}(FTP, SFTP)${NC}"
        echo -e "   • FTP: 21 → 21"
        echo -e "   • SFTP: 22 → 22"
        
        echo -e "\n${GREEN}8. Custom Ports${NC} ${YELLOW}(Manual configuration)${NC}"
        echo -e "   • Specify your own ports"
        
        echo -e "\n${GREEN}9. Advanced Protocols${NC} ${YELLOW}(TCPMUX, STCP, SUDP)${NC}"
        echo -e "   • Modern tunneling protocols"
        echo -e "   • Secure P2P connections"
        
        echo -e "\n${CYAN}0. Back${NC}"
        
        echo -e "\n${YELLOW}Select template [0-8]:${NC} "
        read -r template_choice
        
        case $template_choice in
            1)
                TEMPLATE_PORTS="22"
                TEMPLATE_NAME="SSH Server"
                TEMPLATE_DESCRIPTION="Secure Shell remote access"
                TEMPLATE_PROXY_TYPE="tcp"
                return 0
                ;;
            2)
                TEMPLATE_PORTS="3000,8080"
                TEMPLATE_NAME="Web Development"
                TEMPLATE_DESCRIPTION="Development servers (React, Node.js, etc.)"
                TEMPLATE_PROXY_TYPE="http"
                return 0
                ;;
            3)
                echo -e "\n${CYAN}Select Database Type:${NC}"
                echo "1. MySQL (Port 3306)"
                echo "2. PostgreSQL (Port 5432)"
                echo "3. Both MySQL & PostgreSQL"
                read -p "Choice [1-3]: " db_choice
                
                case $db_choice in
                    1) TEMPLATE_PORTS="3306" ;;
                    2) TEMPLATE_PORTS="5432" ;;
                    3) TEMPLATE_PORTS="3306,5432" ;;
                    *) continue ;;
                esac
                
                TEMPLATE_NAME="Database Server"
                TEMPLATE_DESCRIPTION="Database server access"
                TEMPLATE_PROXY_TYPE="tcp"
                return 0
                ;;
            4)
                echo -e "\n${CYAN}Select Game Server Type:${NC}"
                echo "1. Minecraft (Port 25565)"
                echo "2. Counter-Strike (Port 27015)"
                echo "3. Custom Game Port"
                read -p "Choice [1-3]: " game_choice
                
                case $game_choice in
                    1) TEMPLATE_PORTS="25565" ;;
                    2) TEMPLATE_PORTS="27015" ;;
                    3) 
                        read -p "Enter custom game port: " custom_port
                        if validate_port "$custom_port"; then
                            TEMPLATE_PORTS="$custom_port"
                        else
                            log "ERROR" "Invalid port number"
                            continue
                        fi
                        ;;
                    *) continue ;;
                esac
                
                TEMPLATE_NAME="Game Server"
                TEMPLATE_DESCRIPTION="Game server access"
                TEMPLATE_PROXY_TYPE="tcp"
                return 0
                ;;
            5)
                TEMPLATE_PORTS="80,443"
                TEMPLATE_NAME="Web Server"
                TEMPLATE_DESCRIPTION="HTTP/HTTPS web server"
                TEMPLATE_PROXY_TYPE="http"
                return 0
                ;;
            6)
                echo -e "\n${CYAN}Select Remote Desktop Type:${NC}"
                echo "1. Windows RDP (Port 3389)"
                echo "2. VNC (Port 5900)"
                echo "3. Both RDP & VNC"
                read -p "Choice [1-3]: " rdp_choice
                
                case $rdp_choice in
                    1) TEMPLATE_PORTS="3389" ;;
                    2) TEMPLATE_PORTS="5900" ;;
                    3) TEMPLATE_PORTS="3389,5900" ;;
                    *) continue ;;
                esac
                
                TEMPLATE_NAME="Remote Desktop"
                TEMPLATE_DESCRIPTION="Remote desktop access"
                TEMPLATE_PROXY_TYPE="tcp"
                return 0
                ;;
            7)
                TEMPLATE_PORTS="21,22"
                TEMPLATE_NAME="File Transfer"
                TEMPLATE_DESCRIPTION="FTP/SFTP file transfer"
                TEMPLATE_PROXY_TYPE="tcp"
                return 0
                ;;
            8)
                echo -e "\n${CYAN}Custom Port Configuration:${NC}"
                read -p "Enter ports (comma-separated, e.g., 1111,2222,3333): " custom_ports
                
                if ! validate_ports_list "$custom_ports"; then
                    log "ERROR" "Invalid port format"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                TEMPLATE_PORTS="$custom_ports"
                TEMPLATE_NAME="Custom Configuration"
                TEMPLATE_DESCRIPTION="Custom port configuration"
                TEMPLATE_PROXY_TYPE="tcp"
                return 0
                ;;
            9)
                echo -e "\n${CYAN}Advanced Protocol Selection:${NC}"
                echo "1. TCPMUX (HTTP CONNECT multiplexing)"
                echo "2. STCP (Secure TCP P2P)"
                echo "3. SUDP (Secure UDP P2P)"
                echo "4. XTCP (P2P TCP with NAT traversal)"
                
                read -p "Choose protocol [1-4]: " proto_choice
                case $proto_choice in
                    1)
                        TEMPLATE_PORTS="8080,8081,8082"
                        TEMPLATE_NAME="TCPMUX Tunneling"
                        TEMPLATE_DESCRIPTION="HTTP CONNECT based TCP multiplexing"
                        TEMPLATE_PROXY_TYPE="tcpmux"
                        ;;
                    2)
                        TEMPLATE_PORTS="2222,3333,4444"
                        TEMPLATE_NAME="STCP Secure Tunneling"
                        TEMPLATE_DESCRIPTION="Secure TCP P2P tunneling"
                        TEMPLATE_PROXY_TYPE="stcp"
                        ;;
                    3)
                        TEMPLATE_PORTS="5555,6666,7777"
                        TEMPLATE_NAME="SUDP Secure Tunneling"
                        TEMPLATE_DESCRIPTION="Secure UDP P2P tunneling"
                        TEMPLATE_PROXY_TYPE="sudp"
                        ;;
                    4)
                        TEMPLATE_PORTS="8888,9999,10000"
                        TEMPLATE_NAME="XTCP P2P Tunneling"
                        TEMPLATE_DESCRIPTION="P2P TCP with NAT traversal"
                        TEMPLATE_PROXY_TYPE="xtcp"
                        ;;
                    *)
                        log "WARN" "Invalid choice"
                        continue
                        ;;
                esac
                return 0
                ;;
            0)
                return 1
                ;;
            *)
                log "WARN" "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Show template summary and confirmation
confirm_template_configuration() {
    echo -e "\n${CYAN}📋 Template Configuration Summary:${NC}"
    echo -e "${GREEN}Template:${NC} $TEMPLATE_NAME"
    echo -e "${GREEN}Description:${NC} $TEMPLATE_DESCRIPTION"
    echo -e "${GREEN}Proxy Type:${NC} $TEMPLATE_PROXY_TYPE"
    echo -e "${GREEN}Ports:${NC} $TEMPLATE_PORTS"
    
    # Show port mapping
    echo -e "\n${CYAN}Port Mapping:${NC}"
    IFS=',' read -ra PORT_ARRAY <<< "$TEMPLATE_PORTS"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        echo -e "  ${YELLOW}$port${NC} → ${GREEN}$port${NC}"
    done
    
    echo -e "\n${YELLOW}Continue with this template? (Y/n):${NC} "
    read -r confirm_template
    
    if [[ "$confirm_template" =~ ^[Nn]$ ]]; then
        return 1
    else
        return 0
    fi
}

# Generate random token (shorter and more user-friendly)
generate_token() {
    # Generate a shorter 12-character token for easier management
    openssl rand -hex 6 2>/dev/null || head -c 12 /dev/urandom | base64 | tr -d '=+/' | cut -c1-12
}

# Check for existing proxy names and ports
check_proxy_conflicts() {
    local config_dir="$1"
    local new_proxy_name="$2"
    local new_port="$3"
    
    if [[ ! -d "$config_dir" ]]; then
        return 0  # No conflicts if config dir doesn't exist
    fi
    
    # Check for proxy name conflicts
    for config_file in "$config_dir"/frpc_*.toml; do
        [[ ! -f "$config_file" ]] && continue
        
        if grep -q "name = \"$new_proxy_name\"" "$config_file" 2>/dev/null; then
            log "WARN" "Proxy name conflict detected: $new_proxy_name in $config_file"
            return 1
        fi
    done
    
    # Check for port conflicts
    for config_file in "$config_dir"/frpc_*.toml; do
        [[ ! -f "$config_file" ]] && continue
        
        if grep -q "remotePort = $new_port" "$config_file" 2>/dev/null; then
            log "WARN" "Port conflict detected: $new_port in $config_file"
            return 2
        fi
    done
    
    return 0
}

# Clean up old/conflicting configurations
cleanup_old_configs() {
    local action="$1"
    
    case "$action" in
        "backup")
            local backup_dir="/etc/frp/backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_dir"
            
            for config_file in "$CONFIG_DIR"/frpc_*.toml; do
                [[ -f "$config_file" ]] && cp "$config_file" "$backup_dir/"
            done
            
            log "INFO" "Backed up existing configurations to: $backup_dir"
            ;;
        "remove")
            echo -e "\n${YELLOW}⚠️  Existing FRP client configurations found.${NC}"
            echo -e "${CYAN}Remove existing configurations? (Y/n):${NC} "
            read -r remove_choice
            
            if [[ ! "$remove_choice" =~ ^[Nn]$ ]]; then
                # Backup first
                cleanup_old_configs "backup"
                # Remove old configs
                rm -f "$CONFIG_DIR"/frpc_*.toml
                log "INFO" "Removed existing client configurations"
            else
                log "WARN" "Keeping existing configs - conflicts may occur"
            fi
            ;;
    esac
    
    return 0
}

# Validate server connection
validate_server_connection() {
    local server_ip="$1"
    local server_port="$2"
    
    log "INFO" "Validating connection to $server_ip:$server_port..."
    
    if timeout 5 nc -z "$server_ip" "$server_port" 2>/dev/null; then
        log "INFO" "✅ Server connection successful"
        return 0
    else
        log "WARN" "❌ Cannot connect to server $server_ip:$server_port"
        log "WARN" "Please ensure:"
        log "WARN" "  1. Server is running and accessible"
        log "WARN" "  2. Firewall allows connection to port $server_port"
        log "WARN" "  3. Network connectivity is available"
        return 1
    fi
}

# Generate frps.toml configuration
generate_frps_config() {
    local token="${1:-$(generate_token)}"
    local bind_port="${2:-7000}"
    local dashboard_port="${3:-}"
    local dashboard_user="${4:-}"
    local dashboard_password="${5:-}"
    local enable_kcp="${6:-true}"
    local enable_quic="${7:-false}"
    local custom_subdomain="${8:-moonfrp.local}"
    local max_clients="${9:-50}"
    
    # Validate inputs
    if ! validate_port "$bind_port"; then
        log "ERROR" "Invalid bind port: $bind_port"
        return 1
    fi
    
    if [[ -n "$dashboard_port" ]] && ! validate_port "$dashboard_port"; then
        log "ERROR" "Invalid dashboard port: $dashboard_port"
        return 1
    fi
    
    # Create complete and advanced configuration file based on official FRP v0.63.0 format
    cat > "$CONFIG_DIR/frps.toml" << EOF
# MoonFRP Server Configuration
# Generated on $(date)
# Compatible with FRP v0.63.0

bindAddr = "0.0.0.0"
bindPort = $bind_port

auth.method = "token"
auth.token = "$token"

log.to = "$LOG_DIR/frps.log"
log.level = "warn"
log.maxDays = 2
log.disablePrintColor = false

vhostHTTPPort = 80
vhostHTTPSPort = 443
vhostHTTPTimeout = 60

tcpmuxHTTPConnectPort = 5002
tcpmuxPassthrough = false

transport.maxPoolCount = 50
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 5
transport.heartbeatTimeout = 90
transport.tcpKeepalive = 300

transport.tls.force = false

subDomainHost = "$custom_subdomain"

maxPortsPerClient = 0
userConnTimeout = 10

allowPorts = [
    { start = 1000, end = 65535 }
]

detailedErrorsToClient = false
enablePrometheus = true
udpPacketSize = 1500
natholeAnalysisDataReserveHours = 168

EOF

    # Add dashboard settings only if enabled
    if [[ -n "$dashboard_port" && -n "$dashboard_user" && -n "$dashboard_password" ]]; then
        cat >> "$CONFIG_DIR/frps.toml" << EOF
# Dashboard settings
webServer.addr = "0.0.0.0"
webServer.port = $dashboard_port
webServer.user = "$dashboard_user"
webServer.password = "$dashboard_password"

EOF
    fi

    # Add KCP support if enabled
    if [[ "$enable_kcp" == "true" ]]; then
        cat >> "$CONFIG_DIR/frps.toml" << EOF
# 🚀 KCP Protocol support (UDP-based, better for poor networks)
kcpBindPort = $bind_port
# KCP can use same port as main bind port

EOF
    fi

    # Add QUIC support if enabled
    if [[ "$enable_quic" == "true" ]]; then
        local quic_port=$((bind_port + 1))
        cat >> "$CONFIG_DIR/frps.toml" << EOF
# 🚀 QUIC Protocol support (modern, encrypted UDP)
quicBindPort = $quic_port

# QUIC Protocol advanced options
transport.quic.keepalivePeriod = 10
transport.quic.maxIdleTimeout = 30
transport.quic.maxIncomingStreams = 100

EOF
    fi

    # Add SSH Tunnel Gateway support (optional advanced feature)
    cat >> "$CONFIG_DIR/frps.toml" << EOF
# SSH Tunnel Gateway (disabled by default)
# Uncomment to enable SSH gateway on port 2200
# sshTunnelGateway.bindPort = 2200
# sshTunnelGateway.privateKeyFile = "/home/frp-user/.ssh/id_rsa"
# sshTunnelGateway.autoGenPrivateKeyPath = ""
# sshTunnelGateway.authorizedKeysFile = "/home/frp-user/.ssh/authorized_keys"

EOF
    
    # Verify configuration file was created successfully
    if [[ -f "$CONFIG_DIR/frps.toml" && -s "$CONFIG_DIR/frps.toml" ]]; then
        log "INFO" "Generated advanced frps.toml configuration with full protocol support"
        if [[ -n "$dashboard_port" ]]; then
            log "INFO" "Dashboard: http://server-ip:$dashboard_port (User: $dashboard_user, Pass: $dashboard_password)"
        fi
        log "INFO" "Token: $token"
        log "INFO" "Main Port: $bind_port (TCP/FRP Protocol)"
        log "INFO" "HTTP Port: 80, HTTPS Port: 443"
        log "INFO" "TCPMUX Port: 5002 (HTTP CONNECT multiplexing)"
        [[ "$enable_kcp" == "true" ]] && log "INFO" "KCP Port: $bind_port (UDP-based protocol)"
        [[ "$enable_quic" == "true" ]] && log "INFO" "QUIC Port: $((bind_port + 1)) (Modern encrypted UDP)"
        log "INFO" "Allowed ports: 1000-65535 (extended ranges)"
        log "WARN" "🔥 CRITICAL: Configure firewall to allow these ports:"
        log "WARN" "   • Main: $bind_port (TCP)"
        log "WARN" "   • HTTP/HTTPS: 80, 443 (TCP)"
        log "WARN" "   • TCPMUX: 5002 (TCP)"
        [[ "$enable_kcp" == "true" ]] && log "WARN" "   • KCP: $bind_port (UDP)"
        [[ "$enable_quic" == "true" ]] && log "WARN" "   • QUIC: $((bind_port + 1)) (UDP)"
        log "WARN" "   • Client ports: 1000-65535 (TCP/UDP)"
        return 0
    else
        log "ERROR" "Configuration file was not created or is empty"
        return 1
    fi
}

# Generate frpc.toml configuration for multiple IPs and proxy types
generate_frpc_config() {
    local server_ip="$1"
    local server_port="$2"
    local token="$3"
    local client_ips="$4"
    local ports="$5"
    local ip_suffix="$6"
    local proxy_type="${7:-tcp}"  # Default to TCP if not specified
    local custom_domains="${8:-}" # For HTTP/HTTPS proxies
    local transport_protocol="${9:-tcp}" # Transport protocol: tcp/kcp/quic/websocket/wss
    
    local config_file="$CONFIG_DIR/frpc_${ip_suffix}.toml"
    local timestamp=$(date +%s)
    
    # Create complete and advanced client configuration based on official FRP v0.63.0 format
    cat > "$config_file" << EOF
# MoonFRP Client Configuration for IP ending with $ip_suffix
# Generated on $(date)
# Compatible with FRP v0.63.0

serverAddr = "$server_ip"
serverPort = $server_port

auth.method = "token"
auth.token = "$token"

log.to = "$LOG_DIR/frpc_${ip_suffix}.log"
log.level = "warn"
log.maxDays = 2
log.disablePrintColor = false

transport.poolCount = 10
transport.protocol = "$transport_protocol"
transport.heartbeatTimeout = 90
transport.heartbeatInterval = 5
transport.dialServerTimeout = 5
transport.dialServerKeepalive = 300
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 5

transport.tls.enable = false

loginFailExit = true

user = "moonfrp_${ip_suffix}_${timestamp}"

udpPacketSize = 1500

EOF

    # Add feature gates for advanced features
    local needs_feature_gates=false
    case "$proxy_type" in
        "plugin_virtual_net")
            needs_feature_gates=true
            ;;
    esac
    
    if [[ "$needs_feature_gates" == "true" ]]; then
        cat >> "$config_file" << EOF
# Feature gates for experimental features
featureGates = { VirtualNet = true }

# Virtual network address configuration
virtualNet.address = "100.86.1.1/24"

EOF
    fi

    # Add protocol-specific settings
    case "$transport_protocol" in
        "kcp")
            cat >> "$config_file" << EOF
# KCP Protocol specific settings
# Note: Server must have KCP enabled (kcpBindPort configured)
# KCP provides better performance over poor network conditions

EOF
            ;;
        "quic")
            cat >> "$config_file" << EOF
# QUIC Protocol specific settings
# Note: Server must have QUIC enabled (quicBindPort configured)
transport.quic.keepalivePeriod = 10
transport.quic.maxIdleTimeout = 30
transport.quic.maxIncomingStreams = 100

EOF
            ;;
        "websocket")
            cat >> "$config_file" << EOF
# WebSocket Protocol specific settings
# Useful for bypassing firewalls that block other protocols

EOF
            ;;
        "wss")
            cat >> "$config_file" << EOF
# WebSocket Secure (WSS) Protocol specific settings
# Encrypted WebSocket over TLS

EOF
            ;;
    esac

    # Bandwidth management flag (will be passed from caller)
    local enable_bandwidth="${9:-false}"

    # Add proxy configurations based on type
    case "$proxy_type" in
        "tcp")
            generate_tcp_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp"
            ;;
        "http")
            generate_http_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp" "$custom_domains" "false"
            ;;
        "https")
            generate_http_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp" "$custom_domains" "true"
            ;;
        "udp")
            generate_udp_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp"
            ;;
        "tcpmux")
            generate_tcpmux_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp" "$custom_domains"
            ;;
        "stcp")
            generate_stcp_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp"
            ;;
        "sudp")
            generate_sudp_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp"
            ;;
        "tcpmux-direct")
            generate_tcpmux_direct_proxies "$config_file" "$ports" "$ip_suffix" "$timestamp"
            ;;
        "xtcp")
            generate_xtcp_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp"
            ;;
        "plugin_"*)
            generate_plugin_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp" "$proxy_type"
            ;;
        *)
            log "WARN" "Unknown proxy type: $proxy_type, defaulting to TCP"
            generate_tcp_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp"
            ;;
    esac
    
    # Generate visitor configuration for STCP/XTCP proxies
    if [[ "$proxy_type" == "stcp" || "$proxy_type" == "xtcp" ]]; then
        local secret_key="moonfrp-${proxy_type}-${ip_suffix}-${timestamp}"
        local visitor_config=$(generate_visitor_config "$server_ip" "$server_port" "$token" "$config_file" "$secret_key" "$proxy_type" "$ports" "$ip_suffix" "$transport_protocol")
        log "INFO" "Generated visitor configuration: $visitor_config"
    fi
    
    # Verify configuration was created successfully
    if [[ -f "$config_file" && -s "$config_file" ]]; then
        log "INFO" "Generated frpc configuration: $config_file (Type: $proxy_type)"
        return 0
    else
        log "ERROR" "Failed to generate configuration file or file is empty: $config_file"
        return 1
    fi
}

# Global bandwidth configuration (set during initial setup)
GLOBAL_BANDWIDTH_PROFILE=""
GLOBAL_BANDWIDTH_IN=""
GLOBAL_BANDWIDTH_OUT=""

# Global transport protocol configuration
GLOBAL_TRANSPORT_PROTOCOL="tcp"

# Configure transport protocol globally
configure_transport_protocol() {
    echo -e "\n${CYAN}🚀 Transport Protocol Selection:${NC}"
    echo -e "${YELLOW}Choose the transport protocol for client connections${NC}"
    echo "1. TCP (Default) - Standard reliable connection"
    echo "2. KCP - UDP-based, better for poor networks"
    echo "3. QUIC - Modern encrypted UDP, low latency"
    echo "4. WebSocket - HTTP-based, firewall-friendly"
    echo "5. WSS - Secure WebSocket over TLS"
    
    read -p "Select transport protocol [1-5] (default: 1): " protocol_choice
    [[ -z "$protocol_choice" ]] && protocol_choice=1
    
    case $protocol_choice in
        1)
            GLOBAL_TRANSPORT_PROTOCOL="tcp"
            log "INFO" "Selected TCP protocol (reliable, standard)"
            ;;
        2)
            GLOBAL_TRANSPORT_PROTOCOL="kcp"
            log "INFO" "Selected KCP protocol (UDP-based, better for poor networks)"
            log "WARN" "⚠️  Server must have KCP enabled (kcpBindPort configured)"
            ;;
        3)
            GLOBAL_TRANSPORT_PROTOCOL="quic"
            log "INFO" "Selected QUIC protocol (modern encrypted UDP)"
            log "WARN" "⚠️  Server must have QUIC enabled (quicBindPort configured)"
            ;;
        4)
            GLOBAL_TRANSPORT_PROTOCOL="websocket"
            log "INFO" "Selected WebSocket protocol (HTTP-based, firewall-friendly)"
            ;;
        5)
            GLOBAL_TRANSPORT_PROTOCOL="wss"
            log "INFO" "Selected WSS protocol (secure WebSocket over TLS)"
            ;;
        *)
            log "WARN" "Invalid choice, using TCP (default)"
            GLOBAL_TRANSPORT_PROTOCOL="tcp"
            ;;
    esac
    
    echo -e "\n${GREEN}✅ Transport protocol configured: $GLOBAL_TRANSPORT_PROTOCOL${NC}"
    
    # Show protocol-specific warnings
    case $GLOBAL_TRANSPORT_PROTOCOL in
        "kcp"|"quic")
            echo -e "${YELLOW}📝 Note: Make sure the server has $GLOBAL_TRANSPORT_PROTOCOL protocol enabled${NC}"
            ;;
        "websocket"|"wss")
            echo -e "${YELLOW}📝 Note: WebSocket protocols are useful for bypassing restrictive firewalls${NC}"
            ;;
    esac
}

# Configure bandwidth limits globally
configure_global_bandwidth() {
    echo -e "\n${CYAN}🚀 Bandwidth Management (Optional):${NC}"
    echo -e "${YELLOW}Configure bandwidth limits for better performance control${NC}"
    echo "1. No limits (Default)"
    echo "2. Light usage (1MB/s in, 500KB/s out)"
    echo "3. Medium usage (5MB/s in, 2MB/s out)"
    echo "4. Heavy usage (10MB/s in, 5MB/s out)"
    echo "5. Custom limits"
    
    read -p "Select bandwidth profile [1-5] (default: 1): " bw_choice
    [[ -z "$bw_choice" ]] && bw_choice=1
    
    case $bw_choice in
        1)
            GLOBAL_BANDWIDTH_PROFILE="none"
            ;;
        2)
            GLOBAL_BANDWIDTH_PROFILE="light"
            GLOBAL_BANDWIDTH_IN="1MB"
            GLOBAL_BANDWIDTH_OUT="500KB"
            ;;
        3)
            GLOBAL_BANDWIDTH_PROFILE="medium"
            GLOBAL_BANDWIDTH_IN="5MB"
            GLOBAL_BANDWIDTH_OUT="2MB"
            ;;
        4)
            GLOBAL_BANDWIDTH_PROFILE="heavy"
            GLOBAL_BANDWIDTH_IN="10MB"
            GLOBAL_BANDWIDTH_OUT="5MB"
            ;;
        5)
            GLOBAL_BANDWIDTH_PROFILE="custom"
            echo -e "\n${CYAN}Custom Bandwidth Configuration:${NC}"
            read -p "Incoming bandwidth limit (e.g., 2MB, 500KB): " GLOBAL_BANDWIDTH_IN
            read -p "Outgoing bandwidth limit (e.g., 1MB, 200KB): " GLOBAL_BANDWIDTH_OUT
            
            if [[ -z "$GLOBAL_BANDWIDTH_IN" || -z "$GLOBAL_BANDWIDTH_OUT" ]]; then
                log "WARN" "Invalid bandwidth values, using no limits"
                GLOBAL_BANDWIDTH_PROFILE="none"
            fi
            ;;
        *)
            log "WARN" "Invalid choice, using no limits"
            GLOBAL_BANDWIDTH_PROFILE="none"
            ;;
    esac
    
    if [[ "$GLOBAL_BANDWIDTH_PROFILE" != "none" ]]; then
        log "INFO" "Bandwidth profile selected: $GLOBAL_BANDWIDTH_PROFILE"
        [[ -n "$GLOBAL_BANDWIDTH_IN" ]] && log "INFO" "Incoming limit: $GLOBAL_BANDWIDTH_IN"
        [[ -n "$GLOBAL_BANDWIDTH_OUT" ]] && log "INFO" "Outgoing limit: $GLOBAL_BANDWIDTH_OUT"
    fi
}

# Apply bandwidth limits to proxy configuration
apply_bandwidth_limits() {
    local config_file="$1"
    local proxy_name="$2"
    
    if [[ "$GLOBAL_BANDWIDTH_PROFILE" == "none" ]]; then
        return 0
    fi
    
    # Add bandwidth limiting configuration
    cat >> "$config_file" << EOF
# Bandwidth limits for $proxy_name (Profile: $GLOBAL_BANDWIDTH_PROFILE)
transport.bandwidthLimit = "$GLOBAL_BANDWIDTH_IN"
transport.bandwidthLimitMode = "client"

EOF
    
    log "INFO" "Applied bandwidth limits to $proxy_name: $GLOBAL_BANDWIDTH_IN"
}

# Generate simple TCP proxy configurations
generate_tcp_proxies_simple() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="tcp-${port}-${ip_suffix}"
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "tcp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port

# Health check configuration
healthCheck.type = "tcp"
healthCheck.timeoutSeconds = 5
healthCheck.maxFailed = 3
healthCheck.intervalSeconds = 30

# Load balancing configuration
loadBalancer.group = "moonfrp_group_${port}"
loadBalancer.groupKey = "moonfrp_${port}_static"

# Metadata for monitoring
metadatas.port = "$port"
metadatas.ip_suffix = "$ip_suffix"
metadatas.created = "$(date)"

EOF
    done
}

# Generate simple HTTP/HTTPS proxy configurations
generate_http_proxies_simple() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    local custom_domains="$5"
    local enable_https="$6"
    
    local proxy_type="http"
    [[ "$enable_https" == "true" ]] && proxy_type="https"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    IFS=',' read -ra DOMAIN_ARRAY <<< "$custom_domains"
    
    local port_index=0
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="${proxy_type}-${port}-${ip_suffix}"
        local domain=""
        
        # Use corresponding domain if available, otherwise generate default
        if [[ $port_index -lt ${#DOMAIN_ARRAY[@]} ]] && [[ -n "${DOMAIN_ARRAY[$port_index]}" ]]; then
            domain="${DOMAIN_ARRAY[$port_index]}"
            domain=$(echo "$domain" | tr -d ' ')
        else
            domain="app${port}.moonfrp.local"
        fi
        
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "$proxy_type"
localIP = "127.0.0.1"
localPort = $port
customDomains = ["$domain"]
# Optional: Use subdomain instead of customDomains
# subdomain = "app$port"
# Optional: Location-based routing
# locations = ["/", "/api", "/admin"]

# Health check configuration for HTTP/HTTPS
healthCheck.type = "http"
healthCheck.path = "/health"
healthCheck.timeoutSeconds = 5
healthCheck.maxFailed = 3
healthCheck.intervalSeconds = 30
healthCheck.httpHeaders = [
    { name = "User-Agent", value = "MoonFRP-HealthCheck" },
    { name = "X-Health-Check", value = "true" }
]

# Load balancing configuration
loadBalancer.group = "moonfrp_web_group_${port}"
loadBalancer.groupKey = "moonfrp_web_${port}_static"

# HTTP-specific headers

# HTTP header management
hostHeaderRewrite = "localhost"
requestHeaders.set.X-Forwarded-Proto = "$proxy_type"
requestHeaders.set.X-Forwarded-For = "\$remote_addr"
requestHeaders.set.X-Real-IP = "\$remote_addr"
# Optional: Additional request headers
# requestHeaders.set.X-Custom-Header = "value"

# Optional: Response header management
# responseHeaders.set.X-Powered-By = "MoonFRP"
# responseHeaders.set.X-Frame-Options = "DENY"

# Optional: HTTP authentication
# httpUser = "admin"
# httpPassword = "secure_password"

# Optional: Route by HTTP user
# routeByHTTPUser = "specific_user"

# Metadata for monitoring
metadatas.port = "$port"
metadatas.domain = "$domain"
metadatas.ip_suffix = "$ip_suffix"
metadatas.protocol = "$proxy_type"
metadatas.created = "$(date)"

EOF
        
        ((port_index++))
    done
}

# Generate simple UDP proxy configurations
generate_udp_proxies_simple() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="udp-${port}-${ip_suffix}"
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "udp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port

# Note: UDP doesn't support health checks, but we add metadata for monitoring
# Load balancing configuration
loadBalancer.group = "moonfrp_udp_group_${port}"
loadBalancer.groupKey = "moonfrp_udp_${port}_static"

# UDP-specific settings

# Metadata for monitoring
metadatas.port = "$port"
metadatas.ip_suffix = "$ip_suffix"
metadatas.protocol = "udp"
metadatas.created = "$(date)"

EOF
    done
}

# Generate TCPMUX proxy configurations
generate_tcpmux_proxies_simple() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    local custom_domains="$5"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    IFS=',' read -ra DOMAIN_ARRAY <<< "$custom_domains"
    
    local port_index=0
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="tcpmux-${port}-${ip_suffix}"
        local domain=""
        
        # Use corresponding domain if available, otherwise generate unique default
        if [[ $port_index -lt ${#DOMAIN_ARRAY[@]} ]] && [[ -n "${DOMAIN_ARRAY[$port_index]}" ]]; then
            domain="${DOMAIN_ARRAY[$port_index]}"
            domain=$(echo "$domain" | tr -d ' ')
        else
            # Create unique domain per IP+Port combination to avoid conflicts
            domain="p${port}-ip${ip_suffix}.moonfrp.local"
        fi
        
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "tcpmux"
multiplexer = "httpconnect"
localIP = "127.0.0.1"
localPort = $port
customDomains = ["$domain"]

EOF
        
        ((port_index++))
    done
    
    # Add usage instructions for TCPMUX
    cat >> "$config_file" << EOF
# TCPMUX Usage Instructions:
# 
# Method 1: HTTP CONNECT Proxy (Recommended)
# Configure your application to use HTTP CONNECT proxy:
# Proxy Server: SERVER_IP:5002
# Target: DOMAIN_NAME:80 (e.g., p9016-ip1.moonfrp.local:80)
#
# Method 2: SSH ProxyCommand
# ssh -o 'ProxyCommand socat - PROXY:SERVER_IP:%h:%p,proxyport=5002' user@p9016-ip1.moonfrp.local
#
# Method 3: Browser/Application Proxy Settings
# HTTP Proxy: SERVER_IP:5002
# Then access: http://p9016-ip1.moonfrp.local/
#
# Method 4: curl with proxy
# curl -x http://SERVER_IP:5002 http://p9016-ip1.moonfrp.local/

EOF
}

# Generate TCPMUX-Direct proxy configurations (TCP-like access with TCPMUX benefits)
generate_tcpmux_direct_proxies() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="tcpmux-direct-${port}-${ip_suffix}"
        # Use a predictable domain pattern for direct access
        local domain="direct-${port}-${ip_suffix}.moonfrp.local"
        
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "tcpmux"
multiplexer = "httpconnect"
localIP = "127.0.0.1"
localPort = $port
customDomains = ["$domain"]

EOF
    done
    
    # Add comprehensive usage instructions for TCPMUX-Direct
    cat >> "$config_file" << EOF
# TCPMUX-Direct Usage Instructions:
# This configuration provides TCP-like access while maintaining TCPMUX benefits
#
# 🚀 Quick Access Methods:
#
# 1. VMess/V2Ray Configuration:
# {
#   "outbounds": [{
#     "protocol": "vmess",
#     "settings": {
#       "vnext": [{
#         "address": "SERVER_IP",
#         "port": 5002,
#         "users": [{"id": "your-uuid", "security": "auto"}]
#       }]
#     },
#     "streamSettings": {
#       "network": "tcp",
#       "tcpSettings": {
#         "header": {
#           "type": "http",
#           "request": {
#             "method": "CONNECT",
#             "path": ["/"],
#             "headers": {
#               "Host": ["direct-PORT-${ip_suffix}.moonfrp.local:80"]
#             }
#           }
#         }
#       }
#     }
#   }]
# }
#
# 2. SSH Tunnel:
# ssh -o 'ProxyCommand socat - PROXY:SERVER_IP:%h:%p,proxyport=5002' user@direct-PORT-${ip_suffix}.moonfrp.local
#
# 3. Application Proxy Settings:
# HTTP Proxy: SERVER_IP:5002
# Target: direct-PORT-${ip_suffix}.moonfrp.local:80
#
# 4. Browser Access (for web services):
# Set proxy: SERVER_IP:5002
# Visit: http://direct-PORT-${ip_suffix}.moonfrp.local/
#
# 5. Command Line Tools:
# curl -x http://SERVER_IP:5002 http://direct-PORT-${ip_suffix}.moonfrp.local/
# wget -e use_proxy=yes -e http_proxy=SERVER_IP:5002 http://direct-PORT-${ip_suffix}.moonfrp.local/

EOF
}

# Generate STCP proxy configurations
generate_stcp_proxies_simple() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    
    # Generate a unique secret key for this configuration
    local secret_key="moonfrp-${ip_suffix}-${timestamp}"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="stcp-${port}-${ip_suffix}"
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "stcp"
secretKey = "$secret_key"
localIP = "127.0.0.1"
localPort = $port
# Allow all users to connect (use specific users for better security)
allowUsers = ["*"]
# Optional: Limit to specific users for better security
# allowUsers = ["user1", "user2"]

EOF
    done
    
    # Add visitor configuration comment for user reference
    cat >> "$config_file" << EOF
# To connect to STCP proxies, use a visitor configuration like this:
# [[visitors]]
# name = "stcp_visitor"
# type = "stcp"
# serverName = "stcp-PORT-${ip_suffix}"
# secretKey = "$secret_key"
# bindAddr = "127.0.0.1"
# bindPort = LOCAL_PORT
#
# 🚀 Auto-generated visitor configuration available!
# Check: $CONFIG_DIR/frpc_visitor_${ip_suffix}.toml

EOF
}

# Generate SUDP proxy configurations
generate_sudp_proxies_simple() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    
    # Generate a unique secret key for this configuration
    local secret_key="moonfrp-udp-${ip_suffix}-${timestamp}"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="sudp-${port}-${ip_suffix}"
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "sudp"
secretKey = "$secret_key"
localIP = "127.0.0.1"
localPort = $port
# Allow all users to connect (use specific users for better security)
allowUsers = ["*"]

EOF
    done
    
    # Add visitor configuration comment for user reference
    cat >> "$config_file" << EOF
# To connect to SUDP proxies, use a visitor configuration like this:
# [[visitors]]
# name = "sudp_visitor"
# type = "sudp"
# serverName = "sudp-PORT-${ip_suffix}"
# secretKey = "$secret_key"
# bindAddr = "127.0.0.1"
# bindPort = LOCAL_PORT

EOF
}

# Generate XTCP proxy configurations (P2P with NAT traversal)
generate_xtcp_proxies_simple() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    
    # Generate a unique secret key for this configuration
    local secret_key="moonfrp-xtcp-${ip_suffix}-${timestamp}"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="xtcp-${port}-${ip_suffix}"
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "xtcp"
secretKey = "$secret_key"
localIP = "127.0.0.1"
localPort = $port
# Allow all users to connect (use specific users for better security)
allowUsers = ["*"]
# Optional: Limit to specific users for better security
# allowUsers = ["user1", "user2"]

EOF
    done
    
    # Add visitor configuration comment for user reference
    cat >> "$config_file" << EOF

EOF
}

# Generate Plugin proxy configurations
generate_plugin_proxies_simple() {
    local config_file="$1"
    local ports="$2"
    local ip_suffix="$3"
    local timestamp="$4"
    local plugin_type="$5"
    
    # Extract plugin name from type
    local plugin_name="${plugin_type#plugin_}"
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local unique_name="plugin-${plugin_name}-${port}-${ip_suffix}"
        
        # Base proxy configuration
        cat >> "$config_file" << EOF
[[proxies]]
name = "$unique_name"
type = "tcp"
remotePort = $port
# Plugin configuration overrides localIP and localPort
[proxies.plugin]
EOF
        
        # Plugin-specific configuration
        case "$plugin_name" in
            "unix_socket")
                cat >> "$config_file" << EOF
type = "unix_domain_socket"
unixPath = "/var/run/docker.sock"
EOF
                ;;
            "http_proxy")
                cat >> "$config_file" << EOF
type = "http_proxy"
httpUser = "moonfrp"
httpPassword = "$(generate_token | cut -c1-12)"
EOF
                ;;
            "socks5")
                cat >> "$config_file" << EOF
type = "socks5"
username = "moonfrp"
password = "$(generate_token | cut -c1-12)"
EOF
                ;;
            "static_file")
                cat >> "$config_file" << EOF
type = "static_file"
localPath = "/var/www/html"
stripPrefix = "static"
httpUser = "moonfrp"
httpPassword = "$(generate_token | cut -c1-12)"
EOF
                ;;
            "https2http")
                cat >> "$config_file" << EOF
type = "https2http"
localAddr = "127.0.0.1:80"
crtPath = "/etc/ssl/certs/server.crt"
keyPath = "/etc/ssl/private/server.key"
hostHeaderRewrite = "127.0.0.1"
requestHeaders.set.x-from-where = "frp"
EOF
                ;;
            "http2https")
                cat >> "$config_file" << EOF
type = "http2https"
localAddr = "127.0.0.1:443"
hostHeaderRewrite = "127.0.0.1"
requestHeaders.set.x-from-where = "frp"
EOF
                ;;
            "virtual_net")
                cat >> "$config_file" << EOF
type = "virtual_net"
# Virtual network IP address for this client
destinationIP = "100.86.0.$(($port % 254 + 1))"
EOF
                ;;
        esac
        
        cat >> "$config_file" << EOF

EOF
    done
    
    # Add plugin-specific usage instructions
    cat >> "$config_file" << EOF
# Plugin Configuration Instructions for $plugin_name:
#
EOF
    
    case "$plugin_name" in
        "unix_socket")
            cat >> "$config_file" << EOF
# Unix Domain Socket Plugin:
# • Forwards TCP connections to Unix domain sockets
# • Default socket: /var/run/docker.sock
# • Change unixPath to your desired socket path
# • Useful for Docker API, system services
#
# Example usage:
# curl http://SERVER_IP:$port/version
# (for Docker API version endpoint)
EOF
            ;;
        "http_proxy")
            cat >> "$config_file" << EOF
# HTTP Proxy Plugin:
# • Creates an HTTP proxy server
# • Configure your applications to use SERVER_IP:$port as HTTP proxy
# • Authentication: username=moonfrp, password=generated
# • Supports HTTP CONNECT method for HTTPS tunneling
#
# Example usage:
# curl -x http://moonfrp:password@SERVER_IP:$port http://example.com
# export http_proxy=http://moonfrp:password@SERVER_IP:$port
EOF
            ;;
        "socks5")
            cat >> "$config_file" << EOF
# SOCKS5 Proxy Plugin:
# • Creates a SOCKS5 proxy server
# • Supports both TCP and UDP traffic
# • Configure your applications to use SERVER_IP:$port as SOCKS5 proxy
# • Authentication: username=moonfrp, password=generated
#
# Example usage:
# curl --socks5 moonfrp:password@SERVER_IP:$port http://example.com
# ssh -o ProxyCommand="socat - SOCKS5:moonfrp:password@SERVER_IP:$port" user@target
EOF
            ;;
        "static_file")
            cat >> "$config_file" << EOF
# Static File Server Plugin:
# • Serves static files over HTTP
# • Default directory: /var/www/html
# • URL prefix 'static' is stripped from paths
# • Authentication: username=moonfrp, password=generated
#
# Example usage:
# Place files in /var/www/html/
# Access via: http://SERVER_IP:$port/filename.html
# With auth: curl -u moonfrp:password http://SERVER_IP:$port/filename.html
EOF
            ;;
        "https2http")
            cat >> "$config_file" << EOF
# HTTPS2HTTP Plugin:
# • Terminates HTTPS connections and forwards as HTTP
# • Requires SSL certificate files
# • Default backend: 127.0.0.1:80
# • Update crtPath and keyPath to your certificate files
#
# Example usage:
# Configure domain to point to SERVER_IP
# Access via: https://yourdomain.com (terminates SSL, forwards to local:80)
EOF
            ;;
        "http2https")
            cat >> "$config_file" << EOF
# HTTP2HTTPS Plugin:
# • Receives HTTP requests and forwards as HTTPS
# • Default backend: 127.0.0.1:443
# • Useful for SSL wrapping legacy services
#
# Example usage:
# Access via: http://SERVER_IP:$port (forwards to secure backend)
EOF
            ;;
        "virtual_net")
            cat >> "$config_file" << EOF
# Virtual Network Plugin:
# • Creates a virtual network between clients
# • Allows direct IP communication between clients
# • Requires enabling VirtualNet feature gate
# • Each client gets a unique IP in the virtual network
#
# Setup Instructions:
# 1. Enable feature gate in client config: featureGates = { VirtualNet = true }
# 2. Configure virtual network address: virtualNet.address = "100.86.1.1/24"
# 3. Use assigned IP for communication: 100.86.0.X
#
# Example usage:
# ping 100.86.0.1  # Ping another client in virtual network
# ssh user@100.86.0.2  # SSH to another client
# curl http://100.86.0.3:8080  # HTTP request to another client
EOF
            ;;
    esac
    
    cat >> "$config_file" << EOF

EOF
}

# Generate visitor configuration for STCP/XTCP proxies
generate_visitor_config() {
    local server_ip="$1"
    local server_port="$2"
    local token="$3"
    local config_file="$4"
    local secret_key="$5"
    local proxy_type="$6"  # stcp or xtcp
    local ports="$7"
    local ip_suffix="$8"
    local transport_protocol="${9:-tcp}"  # Transport protocol
    
    local visitor_config_file="$CONFIG_DIR/frpc_visitor_${ip_suffix}.toml"
    
    # Create visitor configuration
    cat > "$visitor_config_file" << EOF
# MoonFRP Visitor Configuration for IP ending with $ip_suffix
# Generated on $(date)
# This configuration allows you to connect to ${proxy_type^^} proxies

serverAddr = "$server_ip"
serverPort = $server_port

auth.method = "token"
auth.token = "$token"

loginFailExit = true

log.to = "$LOG_DIR/frpc_visitor_${ip_suffix}.log"
log.level = "warn"
log.maxDays = 2
log.disablePrintColor = false

transport.poolCount = 10
transport.protocol = "$transport_protocol"
transport.heartbeatTimeout = 90
transport.heartbeatInterval = 5
transport.dialServerTimeout = 5
transport.dialServerKeepalive = 300
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 5

transport.tls.force = false

user = "moonfrp_${ip_suffix}_$(date +%s)"

udpPacketSize = 1500

EOF

    # Add protocol-specific settings for visitor
    case "$transport_protocol" in
        "kcp")
            cat >> "$visitor_config_file" << EOF
EOF
            ;;
        "quic")
            cat >> "$visitor_config_file" << EOF
EOF
            ;;
        "websocket")
            cat >> "$visitor_config_file" << EOF
EOF
            ;;
        "wss")
            cat >> "$visitor_config_file" << EOF
EOF
            ;;
    esac

    # Generate visitor configurations for each port
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    local visitor_port=8000
    
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        local server_name="${proxy_type}-${port}-${ip_suffix}"
        local visitor_name="${proxy_type}_visitor_${port}_${ip_suffix}"
        
        # Use port-specific bind ports to avoid conflicts
        local bind_port
        case "$port" in
            "2096") bind_port=8096 ;;  # X-UI
            "9005") bind_port=8005 ;;  # Xray
            "22")   bind_port=8022 ;;  # SSH
            "3389") bind_port=8389 ;;  # RDP
            "5900") bind_port=8900 ;;  # VNC
            *) bind_port=$((8000 + (port % 1000))) ;;  # Dynamic assignment
        esac
        
        cat >> "$visitor_config_file" << EOF
[[visitors]]
name = "$visitor_name"
type = "$proxy_type"
serverName = "$server_name"
secretKey = "$secret_key"
bindAddr = "127.0.0.1"
bindPort = $bind_port
EOF
        
        # Add XTCP-specific options
        if [[ "$proxy_type" == "xtcp" ]]; then
            cat >> "$visitor_config_file" << EOF
keepTunnelOpen = true
maxRetriesAnHour = 8
minRetryInterval = 90
fallbackTo = "stcp_${server_name}"
fallbackTimeoutMs = 1000
EOF
        fi

        # Add STCP-specific options
        if [[ "$proxy_type" == "stcp" ]]; then
            cat >> "$visitor_config_file" << EOF
# STCP options - Secure tunneling settings
# Optional: Enable specific user connections only
# serverUser = "specific_user"
EOF
        fi
        
        cat >> "$visitor_config_file" << EOF

EOF
    done
    
    # Add usage instructions
    cat >> "$visitor_config_file" << EOF
# ${proxy_type^^} Visitor Configuration Instructions:
#
# This configuration file allows you to connect to ${proxy_type^^} proxies running on another machine.
# 
# 🚀 How to use:
# 1. Install FRP client on the machine where you want to access the services
# 2. Copy this configuration file to the client machine
# 3. Run: frpc -c $visitor_config_file
# 4. Access services via the local bind ports listed above
#
# 📋 Service Access:
EOF
    
    # Add service access information
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        
        # Use same port mapping logic as above
        local bind_port
        case "$port" in
            "2096") bind_port=8096 ;;  # X-UI
            "9005") bind_port=8005 ;;  # Xray
            "22")   bind_port=8022 ;;  # SSH
            "3389") bind_port=8389 ;;  # RDP
            "5900") bind_port=8900 ;;  # VNC
            *) bind_port=$((8000 + (port % 1000))) ;;  # Dynamic assignment
        esac
        
        cat >> "$visitor_config_file" << EOF
# • Access service on port $port via: localhost:$bind_port
EOF
    done
    
    cat >> "$visitor_config_file" << EOF
#
# 🔧 Examples:
EOF
    
    case "$proxy_type" in
        "stcp")
            cat >> "$visitor_config_file" << EOF
# • SSH: ssh -p 8022 user@localhost (if port 22 is configured)
# • HTTP: curl http://localhost:8096 (if port 2096 is configured)
# • X-UI Panel: http://localhost:8096 (access X-UI on port 2096)
# • Database: connect to localhost:BIND_PORT instead of remote host
EOF
            ;;
        "xtcp")
            cat >> "$visitor_config_file" << EOF
# • SSH: ssh -p 8022 user@localhost (P2P direct connection)
# • HTTP: curl http://localhost:8096 (P2P direct connection)
# • X-UI Panel: http://localhost:8096 (direct P2P access to X-UI)
# • Gaming: connect to localhost:BIND_PORT (low latency P2P)
# • Note: XTCP provides direct P2P connection when possible
EOF
            ;;
    esac
    
    cat >> "$visitor_config_file" << EOF
#
# 🔍 Troubleshooting:
# • Check logs: tail -f $LOG_DIR/frpc_visitor_${ip_suffix}.log
# • Verify server is running and accessible
# • Ensure secret key matches between server and visitor
# • For XTCP: Check NAT traversal capability
EOF
    
    echo "$visitor_config_file"
}

# Create systemd service file
create_systemd_service() {
    local service_name="$1"
    local service_type="$2"  # frps or frpc
    local config_file="$3"
    local ip_suffix="${4:-}"
    
    # Validate inputs
    if [[ -z "$service_name" || -z "$service_type" || -z "$config_file" ]]; then
        log "ERROR" "Missing required parameters for service creation"
        return 1
    fi
    
    # Check if FRP binary exists
    if [[ ! -f "$FRP_DIR/$service_type" ]]; then
        log "ERROR" "FRP binary not found: $FRP_DIR/$service_type"
        log "ERROR" "Please install FRP first using menu option 3"
        return 1
    fi
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    local service_file="$SERVICE_DIR/${service_name}.service"
    local description="MoonFRP ${service_type^^} Service"
    
    if [[ -n "$ip_suffix" ]]; then
        description="$description (IP suffix: $ip_suffix)"
    fi
    
    # Create service file
    if cat > "$service_file" << EOF
[Unit]
Description=$description
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$FRP_DIR/$service_type -c $config_file
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    then
        # Reload systemd daemon
        if systemctl daemon-reload; then
            # Clear all performance caches
            clear_performance_caches
            log "INFO" "Created systemd service: $service_name"
            return 0
        else
            log "ERROR" "Failed to reload systemd daemon"
            return 1
        fi
    else
        log "ERROR" "Failed to create service file: $service_file"
        return 1
    fi
}

# Clear all performance caches
clear_performance_caches() {
    CACHED_SERVICES=()
    SERVICES_CACHE_TIME=0
    SERVICE_STATUS_CACHE=()
    SERVICE_STATUS_CACHE_TIME=0
    log "DEBUG" "Performance caches cleared"
}

# Service management functions
start_service() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        log "ERROR" "Service name is required"
        return 1
    fi
    
    # Check if service file exists
    if [[ ! -f "$SERVICE_DIR/${service_name}.service" ]]; then
        log "ERROR" "Service file not found: $SERVICE_DIR/${service_name}.service"
        return 1
    fi
    
    # Start service
    if systemctl start "$service_name"; then
        log "INFO" "Started service: $service_name"
        
        # Clear caches after service change
        clear_performance_caches
        
        # Enable service
        if systemctl enable "$service_name"; then
            log "INFO" "Enabled service: $service_name"
            return 0
        else
            log "WARN" "Service started but failed to enable: $service_name"
            return 0  # Still consider this success as service is running
        fi
    else
        log "ERROR" "Failed to start service: $service_name"
        return 1
    fi
}

stop_service() {
    local service_name="$1"
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    # Clear caches after service change
    clear_performance_caches
    log "INFO" "Stopped and disabled service: $service_name"
}

restart_service() {
    local service_name="$1"
    systemctl restart "$service_name"
    # Clear caches after service change
    clear_performance_caches
    log "INFO" "Restarted service: $service_name"
}

# Improved service status with caching
declare -A SERVICE_STATUS_CACHE
SERVICE_STATUS_CACHE_TIME=0

get_service_status() {
    local service_name="$1"
    local current_time=$(date +%s)
    
    # Use cached status if available and not expired (5 seconds)
    if [[ -n "${SERVICE_STATUS_CACHE[$service_name]}" ]] && [[ $((current_time - SERVICE_STATUS_CACHE_TIME)) -lt 5 ]]; then
        echo "${SERVICE_STATUS_CACHE[$service_name]}"
        return
    fi
    
    # Get fresh status and cache it
    local status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
    SERVICE_STATUS_CACHE[$service_name]="$status"
    SERVICE_STATUS_CACHE_TIME=$current_time
    
    echo "$status"
}

# Check if FRP is already installed
check_frp_installation() {
    if [[ -f "$FRP_DIR/frps" ]] && [[ -f "$FRP_DIR/frpc" ]]; then
        return 0  # Already installed
    else
        return 1  # Not installed
    fi
}

# Download and install FRP
download_and_install_frp() {
    # Check if already installed
    if check_frp_installation; then
        echo -e "\n${YELLOW}FRP is already installed!${NC}"
        echo -e "${CYAN}Current installation:${NC}"
        echo -e "  frps: $FRP_DIR/frps"
        echo -e "  frpc: $FRP_DIR/frpc"
        echo -e "\n${YELLOW}Do you want to reinstall? (y/N):${NC} "
        read -r reinstall
        
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            log "INFO" "Installation cancelled by user"
            return 0
        fi
        
        log "INFO" "Proceeding with reinstallation..."
    fi
    
    local download_url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_${FRP_ARCH}.tar.gz"
    local temp_file="$TEMP_DIR/frp_${FRP_VERSION}_${FRP_ARCH}.tar.gz"
    
    log "INFO" "Downloading FRP v$FRP_VERSION..."
    
    if ! curl -L -o "$temp_file" "$download_url"; then
        log "ERROR" "Failed to download FRP"
        return 1
    fi
    
    log "INFO" "Extracting FRP..."
    tar -xzf "$temp_file" -C "$TEMP_DIR"
    
    # Copy binaries
    cp "$TEMP_DIR/frp_${FRP_VERSION}_${FRP_ARCH}/frps" "$FRP_DIR/"
    cp "$TEMP_DIR/frp_${FRP_VERSION}_${FRP_ARCH}/frpc" "$FRP_DIR/"
    
    # Set permissions
    chmod +x "$FRP_DIR/frps" "$FRP_DIR/frpc"
    
    # Cleanup
    rm -rf "$TEMP_DIR/frp_${FRP_VERSION}_${FRP_ARCH}"
    rm -f "$temp_file"
    
    # Invalidate cache
    FRP_INSTALLATION_STATUS="installed"
    
    log "INFO" "FRP v$FRP_VERSION installed successfully"
}

# Install from local archive
install_from_local() {
    # Check if already installed
    if check_frp_installation; then
        echo -e "\n${YELLOW}FRP is already installed!${NC}"
        echo -e "${CYAN}Current installation:${NC}"
        echo -e "  frps: $FRP_DIR/frps"
        echo -e "  frpc: $FRP_DIR/frpc"
        echo -e "\n${YELLOW}Do you want to reinstall from local archive? (y/N):${NC} "
        read -r reinstall
        
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            log "INFO" "Installation cancelled by user"
            return 0
        fi
        
        log "INFO" "Proceeding with reinstallation from local archive..."
    fi
    
    local archive_path="/root/frp_${FRP_VERSION}_${FRP_ARCH}.tar.gz"
    
    if [[ ! -f "$archive_path" ]]; then
        log "ERROR" "Local archive not found: $archive_path"
        return 1
    fi
    
    log "INFO" "Installing FRP from local archive..."
    
    tar -xzf "$archive_path" -C "$TEMP_DIR"
    
    # Copy binaries
    cp "$TEMP_DIR/frp_${FRP_VERSION}_${FRP_ARCH}/frps" "$FRP_DIR/"
    cp "$TEMP_DIR/frp_${FRP_VERSION}_${FRP_ARCH}/frpc" "$FRP_DIR/"
    
    # Set permissions
    chmod +x "$FRP_DIR/frps" "$FRP_DIR/frpc"
    
    # Cleanup
    rm -rf "$TEMP_DIR/frp_${FRP_VERSION}_${FRP_ARCH}"
    
    # Invalidate cache
    FRP_INSTALLATION_STATUS="installed"
    
    log "INFO" "FRP installed from local archive successfully"
}

# Check for MoonFRP updates
check_moonfrp_updates() {
    log "INFO" "Checking for MoonFRP updates..."
    
    # Since no releases are published, we'll check the script file directly
    # Download the latest script and compare versions
    local temp_script="/tmp/moonfrp_check_$(date +%s).sh"
    
    if curl -fsSL "$MOONFRP_SCRIPT_URL" -o "$temp_script" 2>/dev/null; then
        # Verify download
        if [[ -f "$temp_script" ]] && [[ -s "$temp_script" ]]; then
            # Extract version from downloaded script
            local remote_version=""
            if grep -q "MOONFRP_VERSION=" "$temp_script"; then
                remote_version=$(grep "MOONFRP_VERSION=" "$temp_script" | head -1 | cut -d'"' -f2)
            fi
            
            # Clean up temp file
            rm -f "$temp_script"
            
            if [[ -n "$remote_version" ]]; then
                log "INFO" "Current version: v$MOONFRP_VERSION"
                log "INFO" "Remote version: v$remote_version"
                
                # Compare versions
                if [[ "$remote_version" != "$MOONFRP_VERSION" ]]; then
                    return 0  # Update available
                else
                    return 1  # Already up to date
                fi
            else
                log "WARN" "Could not extract version from remote script"
                return 2  # Error parsing
            fi
        else
            log "WARN" "Downloaded file is empty or invalid"
            rm -f "$temp_script"
            return 3  # Download error
        fi
    else
        log "WARN" "Could not download script from repository"
        return 4  # Connection error
    fi
}

# Update MoonFRP script
update_moonfrp_script() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         MoonFRP Updater              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}🔍 Checking for updates...${NC}"
    
    local update_status=0
    check_moonfrp_updates
    update_status=$?
    
    case $update_status in
        0)
            # Update available
            echo -e "\n${GREEN}🎉 New version available!${NC}"
            echo -e "${YELLOW}Do you want to update MoonFRP? (y/N):${NC} "
            read -r confirm_update
            
            if [[ "$confirm_update" =~ ^[Yy]$ ]]; then
                perform_moonfrp_update
            else
                log "INFO" "Update cancelled by user"
            fi
            ;;
        1)
            echo -e "\n${GREEN}✅ MoonFRP is already up to date!${NC}"
            echo -e "${CYAN}Current version: v$MOONFRP_VERSION${NC}"
            echo -e "\n${YELLOW}Force update anyway? (Y/n):${NC} "
            read -r force_update
            
            # Default to Y if user just presses Enter
            if [[ -z "$force_update" ]] || [[ "$force_update" =~ ^[Yy]$ ]]; then
                perform_moonfrp_update
            else
                log "INFO" "Update cancelled by user"
            fi
            ;;
        2)
            echo -e "\n${RED}❌ Error extracting version from remote script${NC}"
            echo -e "${YELLOW}The remote script may have a different format${NC}"
            echo -e "\n${YELLOW}Force update anyway? (y/N):${NC} "
            read -r force_update
            
            if [[ "$force_update" =~ ^[Yy]$ ]]; then
                perform_moonfrp_update
            fi
            ;;
        3)
            echo -e "\n${RED}❌ Downloaded file is empty or invalid${NC}"
            echo -e "${YELLOW}There may be an issue with the repository${NC}"
            echo -e "\n${YELLOW}Force update anyway? (y/N):${NC} "
            read -r force_update
            
            if [[ "$force_update" =~ ^[Yy]$ ]]; then
                perform_moonfrp_update
            fi
            ;;
        4)
            echo -e "\n${RED}❌ Cannot connect to GitHub repository${NC}"
            echo -e "${YELLOW}Please check your internet connection${NC}"
            echo -e "${YELLOW}Repository: https://github.com/k4lantar4/moonfrp${NC}"
            echo -e "\n${YELLOW}Force update anyway? (y/N):${NC} "
            read -r force_update
            
            if [[ "$force_update" =~ ^[Yy]$ ]]; then
                perform_moonfrp_update
            fi
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

# Perform the actual update
perform_moonfrp_update() {
    log "INFO" "Starting MoonFRP update process..."
    
    # Check if current installation exists
    if [[ ! -f "$MOONFRP_INSTALL_PATH" ]]; then
        log "WARN" "Current installation not found at: $MOONFRP_INSTALL_PATH"
        log "INFO" "Proceeding with fresh installation..."
        MOONFRP_INSTALL_PATH="/usr/local/bin/moonfrp"
        # Create directory if it doesn't exist
        mkdir -p "$(dirname "$MOONFRP_INSTALL_PATH")"
    fi
    
    # Create backup directory
    local backup_dir="/tmp/moonfrp_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup current script if it exists
    if [[ -f "$MOONFRP_INSTALL_PATH" ]]; then
        cp "$MOONFRP_INSTALL_PATH" "$backup_dir/moonfrp_old.sh"
        log "INFO" "Current script backed up to: $backup_dir/moonfrp_old.sh"
    fi
    
    # Download new version
    log "INFO" "Downloading latest MoonFRP script..."
    
    local temp_script="$TEMP_DIR/moonfrp_new.sh"
    
    if curl -fsSL "$MOONFRP_SCRIPT_URL" -o "$temp_script"; then
        # Verify download
        if [[ -f "$temp_script" ]] && [[ -s "$temp_script" ]]; then
            # Basic validation - check if it's a valid bash script
            if head -1 "$temp_script" | grep -q "#!/bin/bash"; then
                # Check if it contains MoonFRP signatures
                if grep -q "MoonFRP" "$temp_script" && grep -q "MOONFRP_VERSION" "$temp_script"; then
                    log "INFO" "Downloaded script validated successfully"
                    
                    # Make executable
                    chmod +x "$temp_script"
                    
                    # Replace current script
                    mv "$temp_script" "$MOONFRP_INSTALL_PATH"
                else
                    log "ERROR" "Downloaded file doesn't appear to be a valid MoonFRP script"
                    [[ -f "$temp_script" ]] && rm -f "$temp_script"
                    return 1
                fi
            else
                log "ERROR" "Downloaded file is not a valid bash script"
                [[ -f "$temp_script" ]] && rm -f "$temp_script"
                return 1
            fi
            
            # Update symlinks if they exist
            [[ -L "/usr/bin/moonfrp" ]] && ln -sf "$MOONFRP_INSTALL_PATH" "/usr/bin/moonfrp"
            
            echo -e "\n${GREEN}✅ MoonFRP updated successfully!${NC}"
            echo -e "${CYAN}Backup location: $backup_dir${NC}"
            
            # Try to get the new version from the updated script
            local new_version=""
            if new_version=$(grep '^MOONFRP_VERSION=' "$MOONFRP_INSTALL_PATH" 2>/dev/null | cut -d'"' -f2); then
                echo -e "${GREEN}Updated to version: v$new_version${NC}"
            fi
            
            echo -e "\n${YELLOW}Changes will take effect on next run${NC}"
            echo -e "${CYAN}Run 'moonfrp' to start the updated version${NC}"
            
            log "INFO" "MoonFRP update completed successfully"
            
            # Show option to restart
            echo -e "\n${YELLOW}Restart MoonFRP now with updated version? (y/N):${NC} "
            read -r restart_now
            
            if [[ "$restart_now" =~ ^[Yy]$ ]]; then
                echo -e "\n${GREEN}🚀 Restarting MoonFRP...${NC}"
                sleep 2
                exec "$MOONFRP_INSTALL_PATH"
            fi
            
        else
            log "ERROR" "Downloaded file is invalid or empty"
            [[ -f "$temp_script" ]] && rm -f "$temp_script"
            return 1
        fi
    else
        log "ERROR" "Failed to download new version"
        return 1
    fi
}

# Check and notify about updates at startup
check_updates_at_startup() {
    local update_status=0
    check_moonfrp_updates >/dev/null 2>&1
    update_status=$?
    
    if [[ $update_status -eq 0 ]]; then
        echo -e "\n${YELLOW}🔔 Update Available!${NC} ${GREEN}A new version of MoonFRP is available${NC}"
        echo -e "${CYAN}   Use menu option 6 to update${NC}"
    fi
}

# Cache for service list
CACHED_SERVICES=()
SERVICES_CACHE_TIME=0

# Fast loading spinner for operations
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinner='|/-\'
    
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 3); do
            echo -ne "\r${CYAN}Loading ${spinner:$i:1}${NC}"
            sleep $delay
        done
    done
    echo -ne "\r"
}

# Optimized system check functions
optimize_systemctl_calls() {
    # Reduce systemctl timeout for faster responses
    export SYSTEMD_COLORS=0
    export SYSTEMCTL_TIMEOUT=3
    # Create faster aliases for systemctl commands
    alias systemctl='timeout 3 systemctl --no-pager --quiet'
    alias journalctl='timeout 3 journalctl --no-pager --quiet'
    
    # Optimize systemd settings for better performance
    export SYSTEMD_PAGER=""
    export SYSTEMD_LESS=""
}

# List all FRP services with caching
list_frp_services() {
    echo -e "\n${CYAN}=== FRP Services Status ===${NC}"
    
    # Improved caching with longer duration for better performance
    local current_time=$(date +%s)
    if [[ ${#CACHED_SERVICES[@]} -eq 0 ]] || [[ $((current_time - SERVICES_CACHE_TIME)) -gt 10 ]]; then
        # Much faster service detection with optimized grep
        local all_services
        all_services=$(systemctl list-units --type=service --no-legend --plain 2>/dev/null | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//')
        
        # Filter and cache results
        CACHED_SERVICES=()
        if [[ -n "$all_services" ]]; then
            while IFS= read -r service; do
                [[ -n "$service" && "$service" != " " ]] && CACHED_SERVICES+=("$service")
            done <<< "$all_services"
        fi
        
        SERVICES_CACHE_TIME=$current_time
    fi
    
    local services=("${CACHED_SERVICES[@]}")
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        return
    fi
    
    # Batch get all service statuses at once for better performance
    local status_output
    status_output=$(systemctl is-active "${services[@]}" 2>/dev/null || true)
    
    # Convert to array
    local statuses=()
    while IFS= read -r status; do
        statuses+=("$status")
    done <<< "$status_output"
    
    printf "%-20s %-12s %-15s\n" "Service" "Status" "Type"
    printf "%-20s %-12s %-15s\n" "-------" "------" "----"
    
    for i in "${!services[@]}"; do
        local service="${services[$i]}"
        local status="${statuses[$i]:-inactive}"
        local type="Unknown"
        
        # Determine service type
        if [[ "$service" =~ (frps|moonfrps) ]]; then
            type="Server"
        elif [[ "$service" =~ (frpc|moonfrpc) ]]; then
            type="Client"
        elif [[ "$service" =~ moonfrp ]]; then
            type="MoonFRP"
        fi
        
        # Clean up status text and limit length
        local clean_status="$status"
        if [[ ${#clean_status} -gt 10 ]]; then
            clean_status="${clean_status:0:10}"
        fi
        
        # Color status
        local status_color="$RED"
        case "$status" in
            "active") status_color="$GREEN" ;;
            "inactive") status_color="$RED" ;;
            "activating") status_color="$YELLOW" ;;
            "deactivating") status_color="$YELLOW" ;;
            "failed") status_color="$RED" ;;
            *) status_color="$GRAY" ;;
        esac
        
        printf "%-20s ${status_color}%-12s${NC} %-15s\n" "$service" "$clean_status" "$type"
    done
}

# Service management menu
service_management_menu() {
    while true; do
        # Check for Ctrl+C signal
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║        Service Management            ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        list_frp_services
        
        echo -e "\n${CYAN}Service Management Options:${NC}"
        echo "1. Start Service"
        echo "2. Stop Service"
        echo "3. Restart Service"
        echo "4. View Service Status"
        echo "5. View Service Logs"
        echo "6. Reload Service"
        echo "7. Remove Service"
        echo "8. 🕐 Setup Cron Job (Auto-restart)"
        echo "9. Real-time Status Monitor"
        echo "10. Current Configuration Summary"
        echo "11. 🔧 Modify Server Configuration"
        echo "0. Back to Main Menu"
        
        echo -e "\n${YELLOW}Enter your choice [0-11]:${NC} "
        read -r choice
        
        # Check for Ctrl+C after read
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        case $choice in
            1) manage_service_action "start" ;;
            2) manage_service_action "stop" ;;
            3) manage_service_action "restart" ;;
            4) manage_service_action "status" ;;
            5) manage_service_action "logs" ;;
            6) manage_service_action "reload" ;;
            7) remove_service_menu ;;
            8) setup_cron_job ;;
            9) real_time_status_monitor ;;
            10) show_current_config_summary ;;
            11) modify_server_configuration ;;
            0) return ;;
            *) log "WARN" "Invalid choice. Please try again." ;;
        esac
    done
}

# Enhanced service status display
show_enhanced_service_status() {
    local selected_service="$1"
    
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                            🔍 Enhanced Service Status                                ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}📋 Service: ${YELLOW}$selected_service${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Basic service information
    local status=$(systemctl is-active "$selected_service" 2>/dev/null || echo "inactive")
    local enabled=$(systemctl is-enabled "$selected_service" 2>/dev/null || echo "disabled")
    local uptime=$(systemctl show "$selected_service" -p ActiveEnterTimestamp --value 2>/dev/null)
    
    echo -e "\n${CYAN}🔧 Service Information:${NC}"
    echo -e "  Status: $([ "$status" == "active" ] && echo "${GREEN}🟢 Active${NC}" || echo "${RED}🔴 Inactive${NC}")"
    echo -e "  Enabled: $([ "$enabled" == "enabled" ] && echo "${GREEN}✅ Enabled${NC}" || echo "${YELLOW}⚠️  Disabled${NC}")"
    
    if [[ "$status" == "active" && -n "$uptime" ]]; then
        local uptime_formatted=$(date -d "$uptime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
        echo -e "  Started: ${GREEN}$uptime_formatted${NC}"
    fi
    
    # Memory and CPU usage
    local memory_usage=$(systemctl show "$selected_service" -p MemoryCurrent --value 2>/dev/null)
    if [[ -n "$memory_usage" && "$memory_usage" != "18446744073709551615" ]]; then
        local memory_mb=$((memory_usage / 1024 / 1024))
        echo -e "  Memory: ${YELLOW}${memory_mb}MB${NC}"
    fi
    
    # Configuration file information
    local config_file=""
    local service_type=""
    
    if [[ "$selected_service" =~ moonfrps ]]; then
        config_file="$CONFIG_DIR/frps.toml"
        service_type="server"
    elif [[ "$selected_service" =~ moonfrpc ]]; then
        local ip_suffix=$(echo "$selected_service" | grep -o '[0-9]\+$')
        if [[ -n "$ip_suffix" ]]; then
            config_file="$CONFIG_DIR/frpc_${ip_suffix}.toml"
            service_type="client"
        fi
    fi
    
    if [[ -f "$config_file" ]]; then
        echo -e "\n${CYAN}📄 Configuration:${NC}"
        echo -e "  File: ${GREEN}$config_file${NC}"
        echo -e "  Size: ${YELLOW}$(ls -lh "$config_file" | awk '{print $5}')${NC}"
        echo -e "  Modified: ${YELLOW}$(stat -c '%y' "$config_file" | cut -d'.' -f1)${NC}"
        
        # Extract key configuration details
        if [[ "$service_type" == "server" ]]; then
            local bind_port=$(grep "bindPort" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            local dashboard_port=$(grep "webServer.port" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            local token=$(grep "auth.token" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            
            echo -e "  Bind Port: ${GREEN}${bind_port:-"Not set"}${NC}"
            echo -e "  Dashboard: ${GREEN}${dashboard_port:-"Disabled"}${NC}"
            echo -e "  Token: ${GREEN}${token:0:8}...${NC}"
            
        elif [[ "$service_type" == "client" ]]; then
            local server_addr=$(grep "serverAddr" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            local server_port=$(grep "serverPort" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            local proxy_count=$(grep -c "^\[\[proxies\]\]" "$config_file" 2>/dev/null || echo "0")
            
            echo -e "  Server: ${GREEN}${server_addr:-"Not set"}:${server_port:-"Not set"}${NC}"
            echo -e "  Proxies: ${GREEN}$proxy_count${NC}"
        fi
    fi
    
    # Connection and port status
    if [[ "$status" == "active" ]]; then
        echo -e "\n${CYAN}🌐 Connection Status:${NC}"
        
        if [[ "$service_type" == "server" && -f "$config_file" ]]; then
            local bind_port=$(grep "bindPort" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            local dashboard_port=$(grep "webServer.port" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            
            if [[ -n "$bind_port" ]]; then
                if netstat -tuln 2>/dev/null | grep -q ":$bind_port "; then
                    echo -e "  Main Port $bind_port: ${GREEN}🟢 Listening${NC}"
                else
                    echo -e "  Main Port $bind_port: ${RED}🔴 Not listening${NC}"
                fi
            fi
            
            if [[ -n "$dashboard_port" ]]; then
                if netstat -tuln 2>/dev/null | grep -q ":$dashboard_port "; then
                    echo -e "  Dashboard Port $dashboard_port: ${GREEN}🟢 Listening${NC}"
                else
                    echo -e "  Dashboard Port $dashboard_port: ${RED}🔴 Not listening${NC}"
                fi
            fi
            
        elif [[ "$service_type" == "client" && -f "$config_file" ]]; then
            local server_addr=$(grep "serverAddr" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            local server_port=$(grep "serverPort" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            
            if [[ -n "$server_addr" && -n "$server_port" ]]; then
                if timeout 3 bash -c "echo >/dev/tcp/$server_addr/$server_port" 2>/dev/null; then
                    echo -e "  Server Connection: ${GREEN}🟢 Connected${NC}"
                else
                    echo -e "  Server Connection: ${RED}🔴 Failed${NC}"
                fi
            fi
            
            # Check proxy ports
            local proxy_names=($(grep "name = " "$config_file" 2>/dev/null | awk '{print $3}' | tr -d '"'))
            local proxy_ports=($(grep "remotePort = " "$config_file" 2>/dev/null | awk '{print $3}' | tr -d '"'))
            
            if [[ ${#proxy_names[@]} -gt 0 ]]; then
                echo -e "  Proxy Status:"
                for i in "${!proxy_names[@]}"; do
                    local proxy_name="${proxy_names[$i]}"
                    local proxy_port="${proxy_ports[$i]}"
                    if [[ -n "$proxy_port" ]]; then
                        if netstat -tuln 2>/dev/null | grep -q ":$proxy_port "; then
                            echo -e "    ${proxy_name}: ${GREEN}🟢 Port $proxy_port active${NC}"
                        else
                            echo -e "    ${proxy_name}: ${YELLOW}🟡 Port $proxy_port inactive${NC}"
                        fi
                    else
                        echo -e "    ${proxy_name}: ${BLUE}🔵 No port specified${NC}"
                    fi
                done
            fi
        fi
    fi
    
    # Recent logs and activity
    echo -e "\n${CYAN}📊 Recent Activity:${NC}"
    local log_count=$(journalctl -u "$selected_service" -n 5 --no-pager -q 2>/dev/null | wc -l)
    if [[ $log_count -gt 0 ]]; then
        echo -e "  Recent entries: ${GREEN}$log_count${NC}"
        echo -e "  Latest logs:"
        journalctl -u "$selected_service" -n 3 --no-pager --since "10 minutes ago" -o short-precise 2>/dev/null | \
            sed 's/^/    /' | head -3
    else
        echo -e "  ${YELLOW}No recent activity${NC}"
    fi
    
    # Log level information
    if [[ -f "$config_file" ]]; then
        local log_level=$(grep "log.level" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
        local log_file=$(grep "log.to" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
        
        if [[ -n "$log_level" || -n "$log_file" ]]; then
            echo -e "\n${CYAN}📝 Logging Configuration:${NC}"
            echo -e "  Level: ${GREEN}${log_level:-"info (default)"}${NC}"
            echo -e "  Output: ${GREEN}${log_file:-"systemd journal"}${NC}"
        fi
    fi
    
    # Quick actions menu
    echo -e "\n${CYAN}🔧 Quick Actions:${NC}"
    echo -e "  ${GREEN}1.${NC} View real-time logs"
    echo -e "  ${GREEN}2.${NC} Restart service"
    echo -e "  ${GREEN}3.${NC} Change log level"
    echo -e "  ${GREEN}4.${NC} Test connections"
    echo -e "  ${GREEN}5.${NC} View full systemctl status"
    echo -e "  ${GREEN}0.${NC} Back to service management"
    
    echo -e "\n${YELLOW}Select action [0-5]:${NC} "
    read -r action_choice
    
    case "$action_choice" in
        1)
            echo -e "\n${CYAN}📋 Real-time logs (Press Ctrl+C to stop):${NC}"
            journalctl -u "$selected_service" -f --output=short-precise
            ;;
        2)
            echo -e "\n${CYAN}🔄 Restarting service...${NC}"
            if systemctl restart "$selected_service"; then
                echo -e "${GREEN}✅ Service restarted successfully${NC}"
            else
                echo -e "${RED}❌ Failed to restart service${NC}"
            fi
            sleep 2
            ;;
        3)
            change_log_level "$selected_service" "$config_file"
            ;;
        4)
            test_service_connections "$selected_service" "$config_file"
            ;;
        5)
            echo -e "\n${CYAN}📊 Full systemctl status:${NC}"
            systemctl status "$selected_service" --no-pager
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

# Change log level for FRP service
change_log_level() {
    local service_name="$1"
    local config_file="$2"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}❌ Configuration file not found${NC}"
        return 1
    fi
    
    echo -e "\n${CYAN}📝 Change Log Level${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local current_level=$(grep "log.level" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
    echo -e "Current log level: ${GREEN}${current_level:-"info (default)"}${NC}"
    
    echo -e "\n${CYAN}Available log levels:${NC}"
    echo -e "  ${GREEN}1.${NC} trace (Most verbose - all details)"
    echo -e "  ${GREEN}2.${NC} debug (Debug information)"
    echo -e "  ${GREEN}3.${NC} info (General information) - Default"
    echo -e "  ${GREEN}4.${NC} warn (Warning messages only)"
    echo -e "  ${GREEN}5.${NC} error (Error messages only)"
    echo -e "  ${GREEN}0.${NC} Cancel"
    
    echo -e "\n${YELLOW}Select new log level [0-5]:${NC} "
    read -r level_choice
    
    local new_level=""
    case "$level_choice" in
        1) new_level="trace" ;;
        2) new_level="debug" ;;
        3) new_level="info" ;;
        4) new_level="warn" ;;
        5) new_level="error" ;;
        0) return ;;
        *) 
            echo -e "${RED}❌ Invalid choice${NC}"
            return 1
            ;;
    esac
    
    echo -e "\n${CYAN}🔧 Updating log level to: ${YELLOW}$new_level${NC}"
    
    # Backup config file
    cp "$config_file" "${config_file}.backup"
    
    # Update log level
    if grep -q "log.level" "$config_file"; then
        # Replace existing log level
        sed -i "s/log.level = .*/log.level = \"$new_level\"/" "$config_file"
    else
        # Add log level after serverPort or other configuration
        if grep -q "serverPort" "$config_file"; then
            sed -i "/serverPort = .*/a\\nlog.level = \"$new_level\"" "$config_file"
        elif grep -q "bindPort" "$config_file"; then
            sed -i "/bindPort = .*/a\\nlog.level = \"$new_level\"" "$config_file"
        else
            # Add at the end of the file
            echo -e "\nlog.level = \"$new_level\"" >> "$config_file"
        fi
    fi
    
    # Add log file if not present
    if ! grep -q "log.to" "$config_file"; then
        local log_file_path="$LOG_DIR/frp_${service_name}.log"
        if grep -q "log.level" "$config_file"; then
            sed -i "/log.level = .*/a log.to = \"$log_file_path\"" "$config_file"
        else
            echo -e "log.to = \"$log_file_path\"" >> "$config_file"
        fi
        echo -e "  Added log file: ${GREEN}$log_file_path${NC}"
    fi
    
    echo -e "${GREEN}✅ Log level updated successfully${NC}"
    
    # Ask to restart service
    echo -e "\n${YELLOW}Service restart required for changes to take effect.${NC}"
    echo -e "${YELLOW}Restart $service_name now? (y/N):${NC} "
    read -r restart_choice
    
    if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
        echo -e "\n${CYAN}🔄 Restarting service...${NC}"
        if systemctl restart "$service_name"; then
            echo -e "${GREEN}✅ Service restarted successfully${NC}"
            echo -e "${CYAN}New log level is now active${NC}"
        else
            echo -e "${RED}❌ Failed to restart service${NC}"
            echo -e "${YELLOW}Restoring backup configuration...${NC}"
            mv "${config_file}.backup" "$config_file"
        fi
    else
        echo -e "${YELLOW}⚠️  Service not restarted. Changes will take effect on next restart.${NC}"
    fi
    
    # Clean up backup if successful
    [[ -f "${config_file}.backup" ]] && rm -f "${config_file}.backup"
}

# Test service connections
test_service_connections() {
    local service_name="$1"
    local config_file="$2"
    
    echo -e "\n${CYAN}🔍 Testing Service Connections${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}❌ Configuration file not found${NC}"
        return 1
    fi
    
    # Determine service type
    local service_type=""
    if [[ "$service_name" =~ moonfrps ]]; then
        service_type="server"
    elif [[ "$service_name" =~ moonfrpc ]]; then
        service_type="client"
    fi
    
    if [[ "$service_type" == "server" ]]; then
        echo -e "\n${CYAN}🖥️  Server Connection Tests:${NC}"
        
        # Test main FRP port
        local bind_port=$(grep "bindPort" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
        if [[ -n "$bind_port" ]]; then
            echo -e "  Testing main port $bind_port..."
            if netstat -tuln 2>/dev/null | grep -q ":$bind_port "; then
                echo -e "    ${GREEN}✅ Port $bind_port is listening${NC}"
            else
                echo -e "    ${RED}❌ Port $bind_port is not listening${NC}"
            fi
        fi
        
        # Test dashboard port
        local dashboard_port=$(grep "webServer.port" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
        if [[ -n "$dashboard_port" ]]; then
            echo -e "  Testing dashboard port $dashboard_port..."
            if netstat -tuln 2>/dev/null | grep -q ":$dashboard_port "; then
                echo -e "    ${GREEN}✅ Dashboard port $dashboard_port is listening${NC}"
                
                # Test HTTP response
                if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$dashboard_port" 2>/dev/null | grep -q "200\|401"; then
                    echo -e "    ${GREEN}✅ Dashboard HTTP response OK${NC}"
                else
                    echo -e "    ${YELLOW}⚠️  Dashboard HTTP response failed${NC}"
                fi
            else
                echo -e "    ${RED}❌ Dashboard port $dashboard_port is not listening${NC}"
            fi
        fi
        
        # Test external connectivity
        echo -e "  Testing external connectivity..."
        local public_ip=$(curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || echo "Unable to determine")
        echo -e "    Public IP: ${GREEN}$public_ip${NC}"
        
    elif [[ "$service_type" == "client" ]]; then
        echo -e "\n${CYAN}📡 Client Connection Tests:${NC}"
        
        # Test server connection
        local server_addr=$(grep "serverAddr" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
        local server_port=$(grep "serverPort" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
        
        if [[ -n "$server_addr" && -n "$server_port" ]]; then
            echo -e "  Testing server connection $server_addr:$server_port..."
            if timeout 5 bash -c "echo >/dev/tcp/$server_addr/$server_port" 2>/dev/null; then
                echo -e "    ${GREEN}✅ Server connection successful${NC}"
                
                # Test with ping
                if ping -c 1 -W 2 "$server_addr" >/dev/null 2>&1; then
                    echo -e "    ${GREEN}✅ Server ping successful${NC}"
                else
                    echo -e "    ${YELLOW}⚠️  Server ping failed (may be blocked)${NC}"
                fi
            else
                echo -e "    ${RED}❌ Server connection failed${NC}"
                echo -e "    ${YELLOW}Troubleshooting server connection...${NC}"
                
                # DNS resolution test
                if nslookup "$server_addr" >/dev/null 2>&1; then
                    echo -e "    ${GREEN}✅ DNS resolution OK${NC}"
                else
                    echo -e "    ${RED}❌ DNS resolution failed${NC}"
                fi
            fi
        fi
        
        # Test local proxy ports
        echo -e "  Testing local proxy ports..."
        local proxy_names=($(grep "name = " "$config_file" 2>/dev/null | awk '{print $3}' | tr -d '"'))
        local local_ports=($(grep "localPort = " "$config_file" 2>/dev/null | awk '{print $3}' | tr -d '"'))
        
        if [[ ${#proxy_names[@]} -gt 0 ]]; then
            for i in "${!proxy_names[@]}"; do
                local proxy_name="${proxy_names[$i]}"
                local local_port="${local_ports[$i]}"
                
                if [[ -n "$local_port" ]]; then
                    echo -e "    Testing ${proxy_name} (local port $local_port)..."
                    if netstat -tuln 2>/dev/null | grep -q ":$local_port "; then
                        echo -e "      ${GREEN}✅ Local service on port $local_port is running${NC}"
                    else
                        echo -e "      ${YELLOW}⚠️  Local service on port $local_port is not running${NC}"
                    fi
                fi
            done
        fi
    fi
    
    # Authentication test
    echo -e "\n${CYAN}🔐 Authentication Test:${NC}"
    local token=$(grep "auth.token" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
    if [[ -n "$token" ]]; then
        echo -e "  Token configured: ${GREEN}${token:0:8}...${NC}"
        echo -e "  Token length: ${GREEN}${#token} characters${NC}"
        
        if [[ ${#token} -lt 8 ]]; then
            echo -e "  ${YELLOW}⚠️  Token is very short (recommended: 16+ chars)${NC}"
        fi
    else
        echo -e "  ${RED}❌ No authentication token configured${NC}"
    fi
    
    echo -e "\n${CYAN}📊 Connection Summary:${NC}"
    local status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
    echo -e "  Service Status: $([ "$status" == "active" ] && echo "${GREEN}🟢 Active${NC}" || echo "${RED}🔴 Inactive${NC}")"
    
    # Process information
    local pid=$(systemctl show "$service_name" -p MainPID --value 2>/dev/null)
    if [[ -n "$pid" && "$pid" != "0" ]]; then
        echo -e "  Process ID: ${GREEN}$pid${NC}"
        local connections=$(netstat -antp 2>/dev/null | grep "$pid" | wc -l)
        echo -e "  Active connections: ${GREEN}$connections${NC}"
         fi
}

# Enhanced service logs viewer
show_enhanced_service_logs() {
    local selected_service="$1"
    
    while true; do
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║                            📋 Enhanced Service Logs                                 ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════════════╝${NC}"
        
        echo -e "\n${CYAN}📋 Service: ${YELLOW}$selected_service${NC}"
        echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # Log statistics
        local total_logs=$(journalctl -u "$selected_service" --no-pager -q | wc -l)
        local today_logs=$(journalctl -u "$selected_service" --since today --no-pager -q | wc -l)
        local hour_logs=$(journalctl -u "$selected_service" --since "1 hour ago" --no-pager -q | wc -l)
        local error_logs=$(journalctl -u "$selected_service" --since "24 hours ago" --no-pager -q | grep -i error | wc -l)
        local warn_logs=$(journalctl -u "$selected_service" --since "24 hours ago" --no-pager -q | grep -i warn | wc -l)
        
        echo -e "\n${CYAN}📊 Log Statistics:${NC}"
        echo -e "  Total logs: ${GREEN}$total_logs${NC}"
        echo -e "  Today: ${GREEN}$today_logs${NC}"
        echo -e "  Last hour: ${GREEN}$hour_logs${NC}"
        echo -e "  Errors (24h): ${RED}$error_logs${NC}"
        echo -e "  Warnings (24h): ${YELLOW}$warn_logs${NC}"
        
        # Log file information
        local config_file=""
        if [[ "$selected_service" =~ moonfrps ]]; then
            config_file="$CONFIG_DIR/frps.toml"
        elif [[ "$selected_service" =~ moonfrpc ]]; then
            local ip_suffix=$(echo "$selected_service" | grep -o '[0-9]\+$')
            if [[ -n "$ip_suffix" ]]; then
                config_file="$CONFIG_DIR/frpc_${ip_suffix}.toml"
            fi
        fi
        
        if [[ -f "$config_file" ]]; then
            local log_file=$(grep "log.to" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            local log_level=$(grep "log.level" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            
            if [[ -n "$log_file" && -f "$log_file" ]]; then
                local file_size=$(ls -lh "$log_file" | awk '{print $5}')
                echo -e "  Log file: ${GREEN}$log_file${NC} (${YELLOW}$file_size${NC})"
            fi
            echo -e "  Log level: ${GREEN}${log_level:-"info (default)"}${NC}"
        fi
        
        echo -e "\n${CYAN}📋 Log Viewer Options:${NC}"
        echo -e "  ${GREEN}1.${NC} Recent logs (last 50 lines)"
        echo -e "  ${GREEN}2.${NC} Real-time logs (follow mode)"
        echo -e "  ${GREEN}3.${NC} Search logs"
        echo -e "  ${GREEN}4.${NC} Filter by time range"
        echo -e "  ${GREEN}5.${NC} Filter by log level"
        echo -e "  ${GREEN}6.${NC} Error analysis"
        echo -e "  ${GREEN}7.${NC} Export logs"
        echo -e "  ${GREEN}8.${NC} Clear old logs"
        echo -e "  ${GREEN}0.${NC} Back to service management"
        
        echo -e "\n${YELLOW}Select option [0-8]:${NC} "
        read -r log_choice
        
        case "$log_choice" in
            1)
                show_recent_logs "$selected_service"
                ;;
            2)
                show_realtime_logs "$selected_service"
                ;;
            3)
                search_logs "$selected_service"
                ;;
            4)
                filter_logs_by_time "$selected_service"
                ;;
            5)
                filter_logs_by_level "$selected_service"
                ;;
            6)
                analyze_errors "$selected_service"
                ;;
            7)
                export_logs "$selected_service"
                ;;
            8)
                clear_old_logs "$selected_service"
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}❌ Invalid choice${NC}"
                sleep 2
                ;;
        esac
    done
}

# Show recent logs
show_recent_logs() {
    local service_name="$1"
    
    clear
    echo -e "${CYAN}📋 Recent Logs: $service_name${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${YELLOW}How many lines to show?${NC}"
    echo -e "  ${GREEN}1.${NC} Last 20 lines"
    echo -e "  ${GREEN}2.${NC} Last 50 lines"
    echo -e "  ${GREEN}3.${NC} Last 100 lines"
    echo -e "  ${GREEN}4.${NC} Custom number"
    
    echo -e "\n${YELLOW}Select option [1-4]:${NC} "
    read -r lines_choice
    
    local lines=50
    case "$lines_choice" in
        1) lines=20 ;;
        2) lines=50 ;;
        3) lines=100 ;;
        4) 
            echo -e "${YELLOW}Enter number of lines:${NC} "
            read -r custom_lines
            if [[ "$custom_lines" =~ ^[0-9]+$ ]]; then
                lines=$custom_lines
            fi
            ;;
    esac
    
    echo -e "\n${CYAN}📋 Last $lines log entries:${NC}"
    journalctl -u "$service_name" -n "$lines" --no-pager --output=short-precise | \
        sed -E 's/(ERROR|FAILED|FAIL)/\o033[31m&\o033[0m/g' | \
        sed -E 's/(WARN|WARNING)/\o033[33m&\o033[0m/g' | \
        sed -E 's/(INFO|SUCCESS)/\o033[32m&\o033[0m/g' | \
        sed -E 's/(DEBUG|TRACE)/\o033[36m&\o033[0m/g'
    
    read -p "Press Enter to continue..."
}

# Show real-time logs
show_realtime_logs() {
    local service_name="$1"
    
    clear
    echo -e "${CYAN}📋 Real-time Logs: $service_name${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${YELLOW}Real-time log monitoring (Press Ctrl+C to stop)${NC}"
    echo -e "${GRAY}Starting in 3 seconds...${NC}"
    sleep 3
    
    # Color-coded real-time logs
    journalctl -u "$service_name" -f --output=short-precise | \
        sed -E 's/(ERROR|FAILED|FAIL)/\o033[31m&\o033[0m/g' | \
        sed -E 's/(WARN|WARNING)/\o033[33m&\o033[0m/g' | \
        sed -E 's/(INFO|SUCCESS)/\o033[32m&\o033[0m/g' | \
        sed -E 's/(DEBUG|TRACE)/\o033[36m&\o033[0m/g'
}

# Search logs
search_logs() {
    local service_name="$1"
    
    clear
    echo -e "${CYAN}🔍 Search Logs: $service_name${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${YELLOW}Enter search term:${NC} "
    read -r search_term
    
    if [[ -z "$search_term" ]]; then
        echo -e "${RED}❌ Search term cannot be empty${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "\n${CYAN}🔍 Search results for: ${YELLOW}$search_term${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local results=$(journalctl -u "$service_name" --no-pager -q | grep -i "$search_term" | wc -l)
    
    if [[ $results -eq 0 ]]; then
        echo -e "${YELLOW}No results found for '$search_term'${NC}"
    else
        echo -e "${GREEN}Found $results matches:${NC}\n"
        
        # Show search results with highlighting
        journalctl -u "$service_name" --no-pager --output=short-precise | \
            grep -i "$search_term" | \
            sed -E "s/($search_term)/\o033[43m\o033[30m&\o033[0m/gi" | \
            sed -E 's/(ERROR|FAILED|FAIL)/\o033[31m&\o033[0m/g' | \
            sed -E 's/(WARN|WARNING)/\o033[33m&\o033[0m/g' | \
            sed -E 's/(INFO|SUCCESS)/\o033[32m&\o033[0m/g' | \
            head -20
        
        if [[ $results -gt 20 ]]; then
            echo -e "\n${YELLOW}... and $((results - 20)) more results${NC}"
        fi
    fi
    
    read -p "Press Enter to continue..."
}

# Filter logs by time range
filter_logs_by_time() {
    local service_name="$1"
    
    clear
    echo -e "${CYAN}⏰ Filter by Time Range: $service_name${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${YELLOW}Select time range:${NC}"
    echo -e "  ${GREEN}1.${NC} Last 15 minutes"
    echo -e "  ${GREEN}2.${NC} Last hour"
    echo -e "  ${GREEN}3.${NC} Last 6 hours"
    echo -e "  ${GREEN}4.${NC} Today"
    echo -e "  ${GREEN}5.${NC} Yesterday"
    echo -e "  ${GREEN}6.${NC} Last 7 days"
    echo -e "  ${GREEN}7.${NC} Custom range"
    
    echo -e "\n${YELLOW}Select option [1-7]:${NC} "
    read -r time_choice
    
    local since_time=""
    local until_time=""
    
    case "$time_choice" in
        1) since_time="15 minutes ago" ;;
        2) since_time="1 hour ago" ;;
        3) since_time="6 hours ago" ;;
        4) since_time="today" ;;
        5) 
            since_time="yesterday"
            until_time="today"
            ;;
        6) since_time="7 days ago" ;;
        7)
            echo -e "${YELLOW}Enter start time (e.g., '2024-01-01 10:00'):${NC} "
            read -r start_time
            echo -e "${YELLOW}Enter end time (optional, press Enter for now):${NC} "
            read -r end_time
            
            since_time="$start_time"
            [[ -n "$end_time" ]] && until_time="$end_time"
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            read -p "Press Enter to continue..."
            return
            ;;
    esac
    
    echo -e "\n${CYAN}📋 Logs from: ${YELLOW}$since_time${NC}"
    [[ -n "$until_time" ]] && echo -e "${CYAN}Until: ${YELLOW}$until_time${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local cmd="journalctl -u $service_name --since \"$since_time\""
    [[ -n "$until_time" ]] && cmd="$cmd --until \"$until_time\""
    cmd="$cmd --no-pager --output=short-precise"
    
    eval "$cmd" | \
        sed -E 's/(ERROR|FAILED|FAIL)/\o033[31m&\o033[0m/g' | \
        sed -E 's/(WARN|WARNING)/\o033[33m&\o033[0m/g' | \
        sed -E 's/(INFO|SUCCESS)/\o033[32m&\o033[0m/g' | \
        sed -E 's/(DEBUG|TRACE)/\o033[36m&\o033[0m/g'
    
    read -p "Press Enter to continue..."
}

# Filter logs by level
filter_logs_by_level() {
    local service_name="$1"
    
    clear
    echo -e "${CYAN}🔍 Filter by Log Level: $service_name${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${YELLOW}Select log level to filter:${NC}"
    echo -e "  ${GREEN}1.${NC} Errors only"
    echo -e "  ${GREEN}2.${NC} Warnings only"
    echo -e "  ${GREEN}3.${NC} Info messages"
    echo -e "  ${GREEN}4.${NC} Debug messages"
    echo -e "  ${GREEN}5.${NC} All levels"
    
    echo -e "\n${YELLOW}Select option [1-5]:${NC} "
    read -r level_choice
    
    local filter_pattern=""
    local level_name=""
    
    case "$level_choice" in
        1) 
            filter_pattern="ERROR|FAILED|FAIL"
            level_name="Errors"
            ;;
        2) 
            filter_pattern="WARN|WARNING"
            level_name="Warnings"
            ;;
        3) 
            filter_pattern="INFO|SUCCESS"
            level_name="Info"
            ;;
        4) 
            filter_pattern="DEBUG|TRACE"
            level_name="Debug"
            ;;
        5) 
            filter_pattern=".*"
            level_name="All levels"
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            read -p "Press Enter to continue..."
            return
            ;;
    esac
    
    echo -e "\n${CYAN}📋 $level_name logs:${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local results=$(journalctl -u "$service_name" --no-pager -q | grep -iE "$filter_pattern" | wc -l)
    
    if [[ $results -eq 0 ]]; then
        echo -e "${YELLOW}No $level_name logs found${NC}"
    else
        echo -e "${GREEN}Found $results $level_name entries:${NC}\n"
        
        journalctl -u "$service_name" --no-pager --output=short-precise | \
            grep -iE "$filter_pattern" | \
            sed -E 's/(ERROR|FAILED|FAIL)/\o033[31m&\o033[0m/g' | \
            sed -E 's/(WARN|WARNING)/\o033[33m&\o033[0m/g' | \
            sed -E 's/(INFO|SUCCESS)/\o033[32m&\o033[0m/g' | \
            sed -E 's/(DEBUG|TRACE)/\o033[36m&\o033[0m/g' | \
            tail -50
    fi
    
    read -p "Press Enter to continue..."
}

# Analyze errors
analyze_errors() {
    local service_name="$1"
    
    clear
    echo -e "${CYAN}🔍 Error Analysis: $service_name${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Get error statistics
    local total_errors=$(journalctl -u "$service_name" --since "24 hours ago" --no-pager -q | grep -iE "ERROR|FAILED|FAIL" | wc -l)
    local connection_errors=$(journalctl -u "$service_name" --since "24 hours ago" --no-pager -q | grep -iE "connection|connect" | grep -iE "ERROR|FAILED|FAIL" | wc -l)
    local auth_errors=$(journalctl -u "$service_name" --since "24 hours ago" --no-pager -q | grep -iE "auth|token" | grep -iE "ERROR|FAILED|FAIL" | wc -l)
    local timeout_errors=$(journalctl -u "$service_name" --since "24 hours ago" --no-pager -q | grep -iE "timeout|timed out" | wc -l)
    
    echo -e "\n${CYAN}📊 Error Statistics (Last 24 hours):${NC}"
    echo -e "  Total errors: ${RED}$total_errors${NC}"
    echo -e "  Connection errors: ${RED}$connection_errors${NC}"
    echo -e "  Authentication errors: ${RED}$auth_errors${NC}"
    echo -e "  Timeout errors: ${RED}$timeout_errors${NC}"
    
    if [[ $total_errors -eq 0 ]]; then
        echo -e "\n${GREEN}✅ No errors found in the last 24 hours!${NC}"
    else
        echo -e "\n${CYAN}🔍 Common Error Patterns:${NC}"
        
        # Show most common error patterns
        journalctl -u "$service_name" --since "24 hours ago" --no-pager -q | \
            grep -iE "ERROR|FAILED|FAIL" | \
            awk '{for(i=6;i<=NF;i++) printf "%s ", $i; printf "\n"}' | \
            sort | uniq -c | sort -nr | head -5 | \
            while read count message; do
                echo -e "  ${RED}$count${NC}x: $message"
            done
        
        echo -e "\n${CYAN}📋 Recent Error Messages:${NC}"
        journalctl -u "$service_name" --since "1 hour ago" --no-pager --output=short-precise | \
            grep -iE "ERROR|FAILED|FAIL" | \
            sed -E 's/(ERROR|FAILED|FAIL)/\o033[31m&\o033[0m/g' | \
            tail -10
        
        echo -e "\n${CYAN}💡 Troubleshooting Suggestions:${NC}"
        if [[ $connection_errors -gt 0 ]]; then
            echo -e "  ${YELLOW}• Check network connectivity and firewall settings${NC}"
        fi
        if [[ $auth_errors -gt 0 ]]; then
            echo -e "  ${YELLOW}• Verify authentication tokens match between client and server${NC}"
        fi
        if [[ $timeout_errors -gt 0 ]]; then
            echo -e "  ${YELLOW}• Consider increasing timeout values or checking network latency${NC}"
        fi
    fi
    
    read -p "Press Enter to continue..."
}

# Export logs
export_logs() {
    local service_name="$1"
    
    clear
    echo -e "${CYAN}📤 Export Logs: $service_name${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local export_file="$LOG_DIR/${service_name}_export_${timestamp}.log"
    
    echo -e "\n${YELLOW}Select export range:${NC}"
    echo -e "  ${GREEN}1.${NC} Last 100 lines"
    echo -e "  ${GREEN}2.${NC} Last 24 hours"
    echo -e "  ${GREEN}3.${NC} All logs"
    echo -e "  ${GREEN}4.${NC} Custom range"
    
    echo -e "\n${YELLOW}Select option [1-4]:${NC} "
    read -r export_choice
    
    local cmd=""
    case "$export_choice" in
        1) cmd="journalctl -u $service_name -n 100 --no-pager" ;;
        2) cmd="journalctl -u $service_name --since '24 hours ago' --no-pager" ;;
        3) cmd="journalctl -u $service_name --no-pager" ;;
        4)
            echo -e "${YELLOW}Enter start time (e.g., '2024-01-01 10:00'):${NC} "
            read -r start_time
            echo -e "${YELLOW}Enter end time (optional):${NC} "
            read -r end_time
            
            cmd="journalctl -u $service_name --since '$start_time'"
            [[ -n "$end_time" ]] && cmd="$cmd --until '$end_time'"
            cmd="$cmd --no-pager"
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            read -p "Press Enter to continue..."
            return
            ;;
    esac
    
    echo -e "\n${CYAN}📤 Exporting logs to: ${YELLOW}$export_file${NC}"
    
    if eval "$cmd" > "$export_file"; then
        local file_size=$(ls -lh "$export_file" | awk '{print $5}')
        echo -e "${GREEN}✅ Export completed successfully${NC}"
        echo -e "  File: ${GREEN}$export_file${NC}"
        echo -e "  Size: ${GREEN}$file_size${NC}"
        echo -e "  Lines: ${GREEN}$(wc -l < "$export_file")${NC}"
        
        echo -e "\n${YELLOW}Open exported file now? (y/N):${NC} "
        read -r open_choice
        if [[ "$open_choice" =~ ^[Yy]$ ]]; then
            less "$export_file"
        fi
    else
        echo -e "${RED}❌ Export failed${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Clear old logs
clear_old_logs() {
    local service_name="$1"
    
    clear
    echo -e "${CYAN}🗑️  Clear Old Logs: $service_name${NC}"
    echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local current_size=$(journalctl -u "$service_name" --no-pager -q | wc -l)
    echo -e "\n${CYAN}Current log size: ${YELLOW}$current_size lines${NC}"
    
    echo -e "\n${YELLOW}⚠️  This will permanently delete old logs!${NC}"
    echo -e "\n${YELLOW}Select retention period:${NC}"
    echo -e "  ${GREEN}1.${NC} Keep last 24 hours"
    echo -e "  ${GREEN}2.${NC} Keep last 7 days"
    echo -e "  ${GREEN}3.${NC} Keep last 30 days"
    echo -e "  ${GREEN}4.${NC} Clear all logs"
    echo -e "  ${GREEN}0.${NC} Cancel"
    
    echo -e "\n${YELLOW}Select option [0-4]:${NC} "
    read -r clear_choice
    
    local retention_time=""
    case "$clear_choice" in
        1) retention_time="24 hours" ;;
        2) retention_time="7 days" ;;
        3) retention_time="30 days" ;;
        4) retention_time="0 seconds" ;;
        0) return ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            read -p "Press Enter to continue..."
            return
            ;;
    esac
    
    echo -e "\n${RED}⚠️  Are you sure you want to clear logs older than $retention_time? (y/N):${NC} "
    read -r confirm_clear
    
    if [[ "$confirm_clear" =~ ^[Yy]$ ]]; then
        echo -e "\n${CYAN}🗑️  Clearing old logs...${NC}"
        
        # Clear systemd journal logs
        if journalctl --vacuum-time="$retention_time" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Systemd journal logs cleared${NC}"
        else
            echo -e "${YELLOW}⚠️  Failed to clear systemd journal logs${NC}"
        fi
        
        # Clear custom log files if any
        local config_file=""
        if [[ "$service_name" =~ moonfrps ]]; then
            config_file="$CONFIG_DIR/frps.toml"
        elif [[ "$service_name" =~ moonfrpc ]]; then
            local ip_suffix=$(echo "$service_name" | grep -o '[0-9]\+$')
            if [[ -n "$ip_suffix" ]]; then
                config_file="$CONFIG_DIR/frpc_${ip_suffix}.toml"
            fi
        fi
        
        if [[ -f "$config_file" ]]; then
            local log_file=$(grep "log.to" "$config_file" 2>/dev/null | head -1 | awk '{print $3}' | tr -d '"')
            if [[ -n "$log_file" && -f "$log_file" ]]; then
                if [[ "$retention_time" == "0 seconds" ]]; then
                    > "$log_file"
                    echo -e "${GREEN}✅ Custom log file cleared${NC}"
                else
                    echo -e "${YELLOW}⚠️  Custom log file not cleared (use log rotation)${NC}"
                fi
            fi
        fi
        
        local new_size=$(journalctl -u "$service_name" --no-pager -q | wc -l)
        echo -e "\n${GREEN}✅ Log cleanup completed${NC}"
        echo -e "  Previous size: ${YELLOW}$current_size lines${NC}"
        echo -e "  Current size: ${YELLOW}$new_size lines${NC}"
        echo -e "  Cleaned: ${GREEN}$((current_size - new_size)) lines${NC}"
    else
        echo -e "${YELLOW}Operation cancelled${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# Service action handler
manage_service_action() {
    local action="$1"
    
    echo -e "\n${CYAN}Available services:${NC}"
    
    # Use cached services if available, otherwise get fresh list
    local services=("${CACHED_SERVICES[@]}")
    if [[ ${#services[@]} -eq 0 ]]; then
        # Force refresh if cache is empty
        list_frp_services >/dev/null 2>&1
        services=("${CACHED_SERVICES[@]}")
    fi
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Batch get all service statuses for better performance
    local status_output
    status_output=$(systemctl is-active "${services[@]}" 2>/dev/null || true)
    
    # Convert to array
    local statuses=()
    while IFS= read -r status; do
        statuses+=("$status")
    done <<< "$status_output"
    
    printf "%-4s %-25s %-12s %-15s\n" "No." "Service" "Status" "Type"
    printf "%-4s %-25s %-12s %-15s\n" "---" "-------" "------" "----"
    
    local i=1
    for idx in "${!services[@]}"; do
        local service="${services[$idx]}"
        local status="${statuses[$idx]:-inactive}"
        local type="Unknown"
        
        if [[ "$service" =~ (frps|moonfrps) ]]; then
            type="Server"
        elif [[ "$service" =~ (frpc|moonfrpc) ]]; then
            type="Client"
        fi
        
        # Clean up status text and limit length
        local clean_status="$status"
        if [[ ${#clean_status} -gt 10 ]]; then
            clean_status="${clean_status:0:10}"
        fi
        
        local status_color="$RED"
        case "$status" in
            "active") status_color="$GREEN" ;;
            "inactive") status_color="$RED" ;;
            "activating") status_color="$YELLOW" ;;
            "deactivating") status_color="$YELLOW" ;;
            "failed") status_color="$RED" ;;
            *) status_color="$GRAY" ;;
        esac
        
        printf "%-4s %-25s ${status_color}%-12s${NC} %-15s\n" "$i." "$service" "$clean_status" "$type"
        ((i++))
    done
    
    echo -e "\n${YELLOW}Select service number (or 'all' for all services):${NC} "
    read -r service_num
    
    if [[ "$service_num" == "all" ]]; then
        # Handle all services
        echo -e "\n${CYAN}Performing '$action' on all services...${NC}"
        for service in "${services[@]}"; do
            echo -e "${CYAN}Processing: $service${NC}"
            case "$action" in
                "start") start_service "$service" ;;
                "stop") stop_service "$service" ;;
                "restart") restart_service "$service" ;;
                "reload") systemctl reload "$service" 2>/dev/null || systemctl restart "$service" ;;
                "status"|"logs") 
                    echo -e "${YELLOW}Skipping '$action' for $service (not supported for bulk operations)${NC}"
                    ;;
            esac
        done
        
        if [[ "$action" == "stop" ]]; then
            echo -e "${CYAN}Running systemctl daemon-reload...${NC}"
            systemctl daemon-reload
        fi
        
        log "INFO" "Completed '$action' operation on all services"
        read -p "Press Enter to continue..."
        return
    fi
    
    if [[ ! "$service_num" =~ ^[0-9]+$ ]] || [[ $service_num -lt 1 ]] || [[ $service_num -gt ${#services[@]} ]]; then
        log "ERROR" "Invalid service number. Please enter a number between 1-${#services[@]} or 'all'"
        read -p "Press Enter to continue..."
        return
    fi
    
    local selected_service="${services[$((service_num-1))]}"
    if [[ -z "$selected_service" ]]; then
        log "ERROR" "Selected service is empty or invalid"
        read -p "Press Enter to continue..."
        return
    fi
    
    case "$action" in
        "start")
            echo -e "\n${CYAN}Starting service: $selected_service${NC}"
            start_service "$selected_service"
            ;;
        "stop")
            echo -e "\n${CYAN}Stopping service: $selected_service${NC}"
            stop_service "$selected_service"
            ;;
        "restart")
            echo -e "\n${CYAN}Restarting service: $selected_service${NC}"
            restart_service "$selected_service"
            ;;
        "status")
            show_enhanced_service_status "$selected_service"
            ;;
        "logs")
            show_enhanced_service_logs "$selected_service"
            ;;
        "reload")
            echo -e "\n${CYAN}Reloading service: $selected_service${NC}"
            if systemctl reload "$selected_service" 2>/dev/null; then
                echo -e "${GREEN}✅ Service reloaded successfully${NC}"
            else
                echo -e "${YELLOW}⚠️  Reload failed, attempting restart...${NC}"
                if systemctl restart "$selected_service" 2>/dev/null; then
                    echo -e "${GREEN}✅ Service restarted successfully${NC}"
                else
                    echo -e "${RED}❌ Failed to restart service${NC}"
                fi
            fi
            log "INFO" "Reloaded service: $selected_service"
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

# Modify server configuration
modify_server_configuration() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     🔧 Modify Server Configuration  ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    # Find existing server configurations
    local server_configs=()
    if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
        server_configs+=("frps.toml")
    fi
    
    if [[ ${#server_configs[@]} -eq 0 ]]; then
        echo -e "\n${YELLOW}⚠️  No existing server configurations found${NC}"
        echo -e "${CYAN}Please create a server configuration first from the main menu.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "\n${CYAN}📋 Current Server Configuration:${NC}"
    echo -e "${GREEN}✅ Configuration file: $CONFIG_DIR/frps.toml${NC}"
    
    # Show current configuration summary
    if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
        echo -e "\n${CYAN}Current Settings:${NC}"
        
        # Extract current settings
        local bind_port=$(grep "bindPort" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}')
        local token=$(grep "auth.token" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}' | tr -d '"')
        local dashboard_port=$(grep "webServer.port" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}')
        local subdomain=$(grep "subDomainHost" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}' | tr -d '"')
        local max_ports=$(grep "maxPortsPerClient" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}')
        local kcp_enabled=$(grep "kcpBindPort" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}' | wc -l)
        local quic_enabled=$(grep "quicBindPort" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}' | wc -l)
        
        echo -e "  • ${GREEN}Server Port:${NC} $bind_port"
        echo -e "  • ${GREEN}Token:${NC} ${token:0:8}..."
        [[ -n "$dashboard_port" ]] && echo -e "  • ${GREEN}Dashboard Port:${NC} $dashboard_port"
        echo -e "  • ${GREEN}Subdomain:${NC} $subdomain"
        echo -e "  • ${GREEN}Max Ports:${NC} $max_ports"
        [[ "$kcp_enabled" -gt 0 ]] && echo -e "  • ${GREEN}KCP:${NC} Enabled"
        [[ "$quic_enabled" -gt 0 ]] && echo -e "  • ${GREEN}QUIC:${NC} Enabled"
    fi
    
    echo -e "\n${CYAN}📝 Configuration Options:${NC}"
    echo "1. 🔑 Change Authentication Token"
    echo "2. 🚪 Change Server Port"
    echo "3. 📊 Modify Dashboard Settings"
    echo "4. 🚀 Advanced Protocol Settings"
    echo "5. 🏷️  Change Subdomain"
    echo "6. 📊 Client Connection Limits"
    echo "7. 🔄 Recreate Configuration (Full Reset)"
    echo "0. Back to Service Management"
    
    echo -e "\n${YELLOW}Enter your choice [0-7]:${NC} "
    read -r choice
    
    case $choice in
        1)
            # Change token
            echo -e "\n${CYAN}🔑 Change Authentication Token:${NC}"
            echo -e "${YELLOW}Generate new random token? (Y/n):${NC} "
            read -r auto_token
            
            local new_token
            if [[ "$auto_token" =~ ^[Nn]$ ]]; then
                while true; do
                    echo -e "${CYAN}Enter new token (minimum 8 characters):${NC} "
                    read -r new_token
                    if [[ ${#new_token} -ge 8 ]]; then
                        break
                    else
                        echo -e "${RED}❌ Token must be at least 8 characters${NC}"
                    fi
                done
            else
                new_token=$(generate_token)
                echo -e "${GREEN}✅ Generated new token: ${new_token:0:8}...${NC}"
            fi
            
            # Update configuration
            sed -i "s/auth.token = \".*\"/auth.token = \"$new_token\"/" "$CONFIG_DIR/frps.toml"
            echo -e "${GREEN}✅ Token updated successfully${NC}"
            
            # Restart service if running
            restart_server_services
            ;;
        2)
            # Change port
            echo -e "\n${CYAN}🚪 Change Server Port:${NC}"
            while true; do
                echo -e "${CYAN}Enter new server port:${NC} "
                read -r new_port
                
                if validate_port "$new_port"; then
                    break
                else
                    echo -e "${RED}❌ Invalid port number${NC}"
                fi
            done
            
            # Update configuration
            sed -i "s/bindPort = .*/bindPort = $new_port/" "$CONFIG_DIR/frps.toml"
            sed -i "s/kcpBindPort = .*/kcpBindPort = $new_port/" "$CONFIG_DIR/frps.toml"
            echo -e "${GREEN}✅ Server port updated to $new_port${NC}"
            
            # Restart service
            restart_server_services
            ;;
        3)
            # Dashboard settings
            echo -e "\n${CYAN}📊 Dashboard Settings:${NC}"
            echo -e "${YELLOW}Enable dashboard? (Y/n):${NC} "
            read -r enable_dash
            
            if [[ "$enable_dash" =~ ^[Nn]$ ]]; then
                # Disable dashboard
                sed -i '/webServer\./d' "$CONFIG_DIR/frps.toml"
                echo -e "${GREEN}✅ Dashboard disabled${NC}"
            else
                # Enable/modify dashboard
                echo -e "${CYAN}Dashboard port (default: 7500):${NC} "
                read -r dash_port
                [[ -z "$dash_port" ]] && dash_port="7500"
                
                echo -e "${CYAN}Dashboard username (default: admin):${NC} "
                read -r dash_user
                [[ -z "$dash_user" ]] && dash_user="admin"
                
                echo -e "${CYAN}Dashboard password (leave empty for auto-generated):${NC} "
                read -r dash_pass
                [[ -z "$dash_pass" ]] && dash_pass=$(generate_token | cut -c1-12)
                
                # Update configuration
                sed -i '/webServer\./d' "$CONFIG_DIR/frps.toml"
                cat >> "$CONFIG_DIR/frps.toml" << EOF

# Dashboard settings
webServer.addr = "0.0.0.0"
webServer.port = $dash_port
webServer.user = "$dash_user"
webServer.password = "$dash_pass"
EOF
                echo -e "${GREEN}✅ Dashboard configured on port $dash_port${NC}"
                echo -e "${GREEN}   Username: $dash_user${NC}"
                echo -e "${GREEN}   Password: $dash_pass${NC}"
            fi
            
            restart_server_services
            ;;
        4)
            # Advanced protocols
            echo -e "\n${CYAN}🚀 Advanced Protocol Settings:${NC}"
            echo -e "${YELLOW}Enable KCP protocol? (Y/n):${NC} "
            read -r kcp_choice
            
            echo -e "${YELLOW}Enable QUIC protocol? (y/N):${NC} "
            read -r quic_choice
            
            # Update KCP
            if [[ "$kcp_choice" =~ ^[Nn]$ ]]; then
                sed -i '/kcpBindPort/d' "$CONFIG_DIR/frps.toml"
                echo -e "${GREEN}✅ KCP disabled${NC}"
            else
                local server_port=$(grep "bindPort" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}')
                if ! grep -q "kcpBindPort" "$CONFIG_DIR/frps.toml"; then
                    echo "kcpBindPort = $server_port" >> "$CONFIG_DIR/frps.toml"
                fi
                echo -e "${GREEN}✅ KCP enabled${NC}"
            fi
            
            # Update QUIC
            if [[ "$quic_choice" =~ ^[Yy]$ ]]; then
                local server_port=$(grep "bindPort" "$CONFIG_DIR/frps.toml" | head -1 | awk '{print $3}')
                if ! grep -q "quicBindPort" "$CONFIG_DIR/frps.toml"; then
                    echo "quicBindPort = $((server_port + 1))" >> "$CONFIG_DIR/frps.toml"
                fi
                echo -e "${GREEN}✅ QUIC enabled${NC}"
            else
                sed -i '/quicBindPort/d' "$CONFIG_DIR/frps.toml"
                echo -e "${GREEN}✅ QUIC disabled${NC}"
            fi
            
            restart_server_services
            ;;
        5)
            # Change subdomain
            echo -e "\n${CYAN}🏷️  Change Subdomain:${NC}"
            echo -e "${CYAN}Enter new subdomain (default: moonfrp.local):${NC} "
            read -r new_subdomain
            [[ -z "$new_subdomain" ]] && new_subdomain="moonfrp.local"
            
            sed -i "s/subDomainHost = \".*\"/subDomainHost = \"$new_subdomain\"/" "$CONFIG_DIR/frps.toml"
            echo -e "${GREEN}✅ Subdomain updated to: $new_subdomain${NC}"
            
            restart_server_services
            ;;
        6)
            # Client limits
            echo -e "\n${CYAN}📊 Client Connection Limits:${NC}"
            echo -e "${CYAN}Maximum ports per client (default: 10):${NC} "
            read -r max_ports
            [[ -z "$max_ports" ]] && max_ports="10"
            
            if [[ "$max_ports" =~ ^[0-9]+$ ]]; then
                sed -i "s/maxPortsPerClient = .*/maxPortsPerClient = $max_ports/" "$CONFIG_DIR/frps.toml"
                echo -e "${GREEN}✅ Client limits updated to: $max_ports${NC}"
                
                restart_server_services
            else
                echo -e "${RED}❌ Invalid number${NC}"
            fi
            ;;
        7)
            # Full reset
            echo -e "\n${CYAN}🔄 Recreate Configuration:${NC}"
            echo -e "${YELLOW}This will delete current configuration and create a new one.${NC}"
            echo -e "${RED}⚠️  Are you sure? (y/N):${NC} "
            read -r confirm_reset
            
            if [[ "$confirm_reset" =~ ^[Yy]$ ]]; then
                # Stop services
                local services=($(systemctl list-units --type=service --all --no-legend --plain | grep moonfrps | awk '{print $1}' | sed 's/\.service//'))
                for service in "${services[@]}"; do
                    systemctl stop "$service" 2>/dev/null || true
                done
                
                # Remove config and recreate
                rm -f "$CONFIG_DIR/frps.toml"
                echo -e "${GREEN}✅ Configuration removed${NC}"
                
                # Call the main creation function
                create_iran_server_config
                return
            else
                echo -e "${YELLOW}Operation cancelled${NC}"
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

# Helper function to restart server services
restart_server_services() {
    local services=($(systemctl list-units --type=service --all --no-legend --plain | grep moonfrps | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -gt 0 ]]; then
        echo -e "\n${CYAN}🔄 Restarting server services...${NC}"
        for service in "${services[@]}"; do
            systemctl restart "$service" 2>/dev/null && echo -e "${GREEN}✅ Restarted: $service${NC}" || echo -e "${RED}❌ Failed to restart: $service${NC}"
        done
    else
        echo -e "\n${YELLOW}⚠️  No active server services found${NC}"
    fi
}

# Configuration creation menu (optimized)
config_creation_menu() {
    while true; do
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║     Quick Configuration Setup       ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        echo -e "\n${CYAN}Select Configuration Type:${NC}"
        echo -e "${GREEN}1.${NC} ${CYAN}Iran Server${NC} ${YELLOW}(Host FRP server)${NC}"
        echo -e "${GREEN}2.${NC} ${CYAN}Foreign Client${NC} ${YELLOW}(Connect to Iran server)${NC}"
        echo -e "${GREEN}0.${NC} Back to Main Menu"
        
        echo -e "\n${YELLOW}Choice [0-2]:${NC} "
        read -r choice
        
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        [[ -z "$choice" ]] && choice=1
        
        case $choice in
            1) create_iran_server_config ;;
            2) create_foreign_client_config ;;
            0) return ;;
            *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# Create Iran server configuration (streamlined)
create_iran_server_config() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         Iran Server Setup           ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    local token dashboard_user dashboard_password
    local bind_port=7000 dashboard_port=7500 enable_dashboard="y"
    
    echo -e "\n${CYAN}📝 Server Configuration${NC}"
    
    # Quick token setup
    echo -e "\n${YELLOW}Auto-generate secure token? (Y/n):${NC} "
    read -r auto_token
    
    if [[ "$CTRL_C_PRESSED" == "true" ]]; then
        CTRL_C_PRESSED=false
        return
    fi
    
    if [[ "$auto_token" =~ ^[Nn]$ ]]; then
        while true; do
            echo -e "${CYAN}Custom token (8+ chars):${NC} "
            read -r token
            if [[ "$CTRL_C_PRESSED" == "true" ]]; then
                CTRL_C_PRESSED=false
                return
            fi
            [[ ${#token} -ge 8 ]] && break
            echo -e "${RED}Too short${NC}"
        done
    else
        token=$(generate_token)
        echo -e "${GREEN}✅ Token: ${token:0:8}...${NC}"
    fi
    
    # Port setup
    echo -e "\n${CYAN}Server port (default 7000):${NC} "
    read -r user_bind_port
    if [[ "$CTRL_C_PRESSED" == "true" ]]; then
        CTRL_C_PRESSED=false
        return
    fi
    
    if [[ -n "$user_bind_port" ]] && validate_port "$user_bind_port"; then
        bind_port="$user_bind_port"
    fi
    echo -e "${GREEN}✅ Port: $bind_port${NC}"
    
    # Dashboard setup
    echo -e "\n${CYAN}Enable web dashboard? (Y/n):${NC} "
    read -r enable_dashboard
    if [[ "$CTRL_C_PRESSED" == "true" ]]; then
        CTRL_C_PRESSED=false
        return
    fi
    
    if [[ ! "$enable_dashboard" =~ ^[Nn]$ ]]; then
        echo -e "${CYAN}Dashboard port (7500):${NC} "
        read -r user_dashboard_port
        if [[ -n "$user_dashboard_port" ]] && validate_port "$user_dashboard_port" && [[ "$user_dashboard_port" != "$bind_port" ]]; then
            dashboard_port="$user_dashboard_port"
        fi
        
        echo -e "${CYAN}Username (admin):${NC} "
        read -r dashboard_user
        [[ -z "$dashboard_user" ]] && dashboard_user="admin"
        
        echo -e "${CYAN}Password (auto):${NC} "
        read -r dashboard_password
        [[ -z "$dashboard_password" ]] && dashboard_password=$(generate_token | cut -c1-12)
        
        echo -e "${GREEN}✅ Dashboard: $dashboard_user @ :$dashboard_port${NC}"
    else
        dashboard_port=""
        dashboard_user=""
        dashboard_password=""
    fi
    
    # Use optimized defaults
    local enable_kcp="true" enable_quic="false" custom_subdomain="moonfrp.local" max_clients="0"

    echo -e "\n${CYAN}📋 Summary:${NC}"
    echo -e "  Server Port: ${GREEN}$bind_port${NC}"
    echo -e "  Token: ${GREEN}${token:0:8}...${NC}"
    [[ -n "$dashboard_port" ]] && echo -e "  Dashboard: ${GREEN}$dashboard_user @ :$dashboard_port${NC}"
    echo -e "  Protocols: ${GREEN}All supported${NC}"
    
    echo -e "\n${YELLOW}Create server? (Y/n):${NC} "
    read -r confirm
    
    if [[ "$CTRL_C_PRESSED" == "true" ]]; then
        CTRL_C_PRESSED=false
        return
    fi
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Cancelled${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Generate configuration
    echo -e "\n${CYAN}🔧 Generating server configuration...${NC}"
    if generate_frps_config "$token" "$bind_port" "$dashboard_port" "$dashboard_user" "$dashboard_password" "$enable_kcp" "$enable_quic" "$custom_subdomain" "$max_clients"; then
        echo -e "${GREEN}✅ Server configuration generated successfully${NC}"
        
        # Verify config file was created
        if [[ -f "$CONFIG_DIR/frps.toml" && -s "$CONFIG_DIR/frps.toml" ]]; then
            echo -e "${GREEN}✅ Configuration file verified: $CONFIG_DIR/frps.toml${NC}"
        else
            echo -e "${RED}❌ Configuration file not found or empty${NC}"
            read -p "Press Enter to continue..."
            return
        fi
        
        # Create systemd service with improved naming
        local server_count=$(ls /etc/systemd/system/moonfrps-*.service 2>/dev/null | wc -l)
        ((server_count++))
        local server_service_name="moonfrps-${server_count}"
        
        echo -e "\n${CYAN}🔧 Creating systemd service...${NC}"
        if create_systemd_service "$server_service_name" "frps" "$CONFIG_DIR/frps.toml"; then
            echo -e "${GREEN}✅ Service created: $server_service_name${NC}"
        else
            echo -e "${RED}❌ Failed to create service${NC}"
            read -p "Press Enter to continue..."
            return
        fi
        
        # Start service
        echo -e "\n${CYAN}🚀 Starting service: $server_service_name${NC}"
        if start_service "$server_service_name"; then
            echo -e "${GREEN}✅ Service started successfully${NC}"
            
            # Wait a moment and check service status
            sleep 3
            local service_status=$(get_service_status "$server_service_name")
            if [[ "$service_status" == "active" ]]; then
                echo -e "${GREEN}✅ Service is running properly${NC}"
            else
                echo -e "${YELLOW}⚠️  Service status: $service_status${NC}"
                echo -e "${CYAN}Checking logs for errors...${NC}"
                journalctl -u "$server_service_name" -n 5 --no-pager
            fi
        else
            echo -e "${RED}❌ Failed to start service${NC}"
            echo -e "${CYAN}Checking logs for errors...${NC}"
            journalctl -u "$server_service_name" -n 10 --no-pager
            read -p "Press Enter to continue..."
            return
        fi
        
        # Enhanced success summary
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║     🎉 Server Setup Complete!       ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        echo -e "\n${GREEN}✅ Iran server configuration created successfully!${NC}"
        
        echo -e "\n${CYAN}📋 Server Information:${NC}"
        echo -e "${GREEN}• Service Name:${NC} $server_service_name"
        echo -e "${GREEN}• Configuration:${NC} $CONFIG_DIR/frps.toml"
        echo -e "${GREEN}• Service Status:${NC} $(get_service_status "$server_service_name")"
        
        # Get server IP information
        local primary_ip=$(hostname -I | awk '{print $1}')
        # Get public IPv4 addresses (exclude local, private, and IPv6)
        local public_ips=$(hostname -I | tr ' ' '\n' | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | grep -v -E '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.)' | tr '\n' ',' | sed 's/,$//')
        [[ -z "$public_ips" ]] && public_ips="$primary_ip"
        
        echo -e "\n${CYAN}🌐 Connection Information:${NC}"
        echo -e "${GREEN}• Server Public IPs:${NC} $public_ips"
        echo -e "${GREEN}• FRP Port:${NC} $bind_port"
        echo -e "${GREEN}• Auth Token:${NC} $token"
        
        if [[ -n "$dashboard_port" ]]; then
            echo -e "\n${CYAN}📊 Dashboard Access:${NC}"
            echo -e "${GREEN}• URL:${NC} http://$primary_ip:$dashboard_port"
            echo -e "${GREEN}• Username:${NC} $dashboard_user"
            echo -e "${GREEN}• Password:${NC} $dashboard_password"
        fi
        
        echo -e "\n${CYAN}💡 Next Steps:${NC}"
        echo -e "  1. Configure firewall: ${GREEN}ufw allow $bind_port/tcp${NC}"
        if [[ -n "$dashboard_port" ]]; then
            echo -e "  2. Allow dashboard: ${GREEN}ufw allow $dashboard_port/tcp${NC}"
        fi
        echo -e "  3. Share with clients:"
        echo -e "     ${YELLOW}• Server IPs: $public_ips${NC}"
        echo -e "     ${YELLOW}• Server Port: $bind_port${NC}"
        echo -e "     ${YELLOW}• Token: $token${NC}"
        
        echo -e "\n${CYAN}🔧 Management Commands:${NC}"
        echo -e "  • Check status: ${GREEN}systemctl status $server_service_name${NC}"
        echo -e "  • View logs: ${GREEN}journalctl -u $server_service_name -f${NC}"
        echo -e "  • Restart: ${GREEN}systemctl restart $server_service_name${NC}"
        
    else
        echo -e "${RED}❌ Failed to generate server configuration${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Press Enter to continue..."
}

# Create foreign client configuration
create_foreign_client_config() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║      Foreign Client Setup           ║${NC}"
    echo -e "${PURPLE}║     (frpc Configuration)             ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    local server_ips server_port token ports proxy_type="tcp"
    
    echo -e "\n${CYAN}🌍 Client Configuration${NC}"
    echo -e "${GRAY}This will create FRP client configuration for foreign location${NC}"
    
    # Server Connection Settings
    echo -e "\n${CYAN}🔗 Server Connection Settings:${NC}"
    
    # Server IP input with validation
    while true; do
        echo -e "${CYAN}Iran Server IP Address:${NC} "
        read -r server_ips
        
        # Check for Ctrl+C
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        if [[ -z "$server_ips" ]]; then
            echo -e "${RED}❌ Server IP is required${NC}"
            continue
        fi
        
        if validate_ips_list "$server_ips"; then
            echo -e "${GREEN}✅ Server IP(s) validated: $server_ips${NC}"
            break
        else
            echo -e "${RED}❌ Invalid IP address format${NC}"
            echo -e "${YELLOW}Example: 89.47.198.149 or 89.47.198.149,85.15.63.147${NC}"
        fi
    done
    
    # Server Port input with validation
    while true; do
        echo -e "${CYAN}Server Port (default: 7000):${NC} "
        read -r server_port
        [[ -z "$server_port" ]] && server_port=7000
        
        if validate_port "$server_port"; then
            echo -e "${GREEN}✅ Server Port: $server_port${NC}"
            break
        else
            echo -e "${RED}❌ Invalid port number. Please enter a port between 1-65535${NC}"
        fi
    done
    
    # Authentication Token
    while true; do
        echo -e "${CYAN}Authentication Token:${NC} "
        read -r token
        
        if [[ -z "$token" ]]; then
            echo -e "${RED}❌ Authentication token is required${NC}"
            continue
        elif [[ ${#token} -lt 8 ]]; then
            echo -e "${RED}❌ Token should be at least 8 characters for security${NC}"
            echo -e "${YELLOW}Continue anyway? (y/N):${NC} "
            read -r continue_token
            if [[ "$continue_token" =~ ^[Yy]$ ]]; then
                break
            fi
        else
            echo -e "${GREEN}✅ Authentication token validated${NC}"
            break
        fi
    done
    
    # Port Configuration Method
    echo -e "\n${CYAN}🚪 Port Configuration:${NC}"
    echo -e "${YELLOW}How would you like to configure ports?${NC}"
    echo "1. Manual port entry (Recommended)"
    echo "2. Use configuration template"
    
    local config_method=""
    while true; do
        echo -e "${CYAN}Choose method [1-2] (default: 1):${NC} "
        read -r config_method
        [[ -z "$config_method" ]] && config_method=1
        
        case $config_method in
            1|2) break ;;
            *) echo -e "${RED}❌ Please enter 1 or 2${NC}" ;;
        esac
    done
    
    case $config_method in
        1)
            # Manual port configuration
            echo -e "\n${CYAN}📝 Manual Port Configuration:${NC}"
            echo -e "${GRAY}Enter the ports you want to forward from this server${NC}"
            
            while true; do
                echo -e "${CYAN}Local ports to forward (comma-separated):${NC}"
                echo -e "${YELLOW}Example: 9005,8005,7005 or 22,80,443${NC} "
                read -r ports
                
                if [[ -z "$ports" ]]; then
                    echo -e "${RED}❌ At least one port is required${NC}"
                    continue
                fi
                
                if validate_ports_list "$ports"; then
                    echo -e "${GREEN}✅ Ports validated: $ports${NC}"
                    
                    # Show port mapping preview
                    echo -e "\n${CYAN}📋 Port Mapping Preview:${NC}"
                    IFS=',' read -ra PORT_ARRAY <<< "$ports"
                    for port in "${PORT_ARRAY[@]}"; do
                        port=$(echo "$port" | tr -d ' ')
                        echo -e "  ${YELLOW}Local:$port${NC} → ${GREEN}Remote:$port${NC}"
                    done
                    break
                else
                    echo -e "${RED}❌ Invalid port format${NC}"
                    echo -e "${YELLOW}Please use format: port1,port2,port3 (e.g., 22,80,443)${NC}"
                fi
            done
            ;;
        2)
            # Template configuration
            if get_config_template; then
                if confirm_template_configuration; then
                    ports="$TEMPLATE_PORTS"
                    proxy_type="$TEMPLATE_PROXY_TYPE"
                    echo -e "\n${GREEN}✅ Using template: $TEMPLATE_NAME${NC}"
                    echo -e "${GREEN}✅ Ports configured: $ports${NC}"
                else
                    log "INFO" "Template configuration cancelled"
                    read -p "Press Enter to continue..."
                    return
                fi
            else
                log "INFO" "Template selection cancelled"
                read -p "Press Enter to continue..."
                return
            fi
            ;;
    esac
    
    # Proxy Type Selection (if not from template)
    if [[ $config_method -eq 1 ]]; then
        echo -e "\n${CYAN}🔌 Proxy Type Selection:${NC}"
        echo -e "${YELLOW}What type of traffic will you forward?${NC}"
        echo "1. TCP (Default - for SSH, databases, games, etc.)"
        echo "2. HTTP (Web services with domain names)"
        echo "3. HTTPS (Secure web services)"
        echo "4. UDP (Games, DNS, streaming)"
        echo "5. TCPMUX (TCP multiplexing over HTTP CONNECT)"
        echo "6. STCP (Secret TCP - P2P secure tunneling)"
        echo "7. SUDP (Secret UDP - P2P secure tunneling)"
        echo "8. TCPMUX-Direct (TCP-like access with TCPMUX benefits)"
        echo "9. XTCP (P2P TCP - Direct peer-to-peer connection)"
        echo "10. Plugin System (Unix sockets, HTTP/SOCKS5 proxy, Static files)"
        
        local proxy_choice=""
        while true; do
            echo -e "${CYAN}Choose proxy type [1-10] (default: 1):${NC} "
            read -r proxy_choice
            [[ -z "$proxy_choice" ]] && proxy_choice=1
            
            case $proxy_choice in
                1) proxy_type="tcp"; echo -e "${GREEN}✅ TCP proxy selected${NC}"; break ;;
                2) proxy_type="http"; echo -e "${GREEN}✅ HTTP proxy selected${NC}"; break ;;
                3) proxy_type="https"; echo -e "${GREEN}✅ HTTPS proxy selected${NC}"; break ;;
                4) proxy_type="udp"; echo -e "${GREEN}✅ UDP proxy selected${NC}"; break ;;
                5) proxy_type="tcpmux"; echo -e "${GREEN}✅ TCPMUX proxy selected${NC}"; break ;;
                6) proxy_type="stcp"; echo -e "${GREEN}✅ STCP proxy selected${NC}"; break ;;
                7) proxy_type="sudp"; echo -e "${GREEN}✅ SUDP proxy selected${NC}"; break ;;
                8) proxy_type="tcpmux-direct"; echo -e "${GREEN}✅ TCPMUX-Direct proxy selected${NC}"; break ;;
                9) proxy_type="xtcp"; echo -e "${GREEN}✅ XTCP proxy selected${NC}"; break ;;
                10) 
                    echo -e "\n${CYAN}Plugin Type Selection:${NC}"
                    echo "1. Unix Domain Socket"
                    echo "2. HTTP Proxy"
                    echo "3. SOCKS5 Proxy"
                    echo "4. Static File Server"
                    echo "5. HTTPS2HTTP"
                    echo "6. HTTP2HTTPS"
                    echo "7. Virtual Network (VNet)"
                    read -p "Choose plugin [1-7]: " plugin_choice
                    case $plugin_choice in
                        1) proxy_type="plugin_unix_socket"; echo -e "${GREEN}✅ Unix Domain Socket plugin selected${NC}"; break ;;
                        2) proxy_type="plugin_http_proxy"; echo -e "${GREEN}✅ HTTP Proxy plugin selected${NC}"; break ;;
                        3) proxy_type="plugin_socks5"; echo -e "${GREEN}✅ SOCKS5 Proxy plugin selected${NC}"; break ;;
                        4) proxy_type="plugin_static_file"; echo -e "${GREEN}✅ Static File Server plugin selected${NC}"; break ;;
                        5) proxy_type="plugin_https2http"; echo -e "${GREEN}✅ HTTPS2HTTP plugin selected${NC}"; break ;;
                        6) proxy_type="plugin_http2https"; echo -e "${GREEN}✅ HTTP2HTTPS plugin selected${NC}"; break ;;
                        7) proxy_type="plugin_virtual_net"; echo -e "${GREEN}✅ Virtual Network plugin selected${NC}"; break ;;
                        *) echo -e "${RED}❌ Invalid plugin choice${NC}"; continue ;;
                    esac
                    break ;;
                *) echo -e "${RED}❌ Please enter 1, 2, 3, 4, 5, 6, 7, 8, 9, or 10${NC}" ;;
            esac
        done
    fi
    
    # 🚀 Transport Protocol Selection
    echo -e "\n${CYAN}🚀 Transport Protocol Configuration:${NC}"
    echo -e "${YELLOW}Select transport protocol for client connections${NC}"
    configure_transport_protocol

    # 🚀 Bandwidth Configuration
    echo -e "\n${CYAN}📊 Bandwidth Configuration:${NC}"
    echo -e "${YELLOW}Configure bandwidth limits (optional)${NC}"
    configure_global_bandwidth

    # Custom domains for HTTP/HTTPS/TCPMUX
    local custom_domains=""
    if [[ "$proxy_type" == "http" || "$proxy_type" == "https" || "$proxy_type" == "tcpmux" ]]; then
        echo -e "\n${CYAN}🌐 Domain Configuration:${NC}"
        echo -e "${YELLOW}Configure custom domains? (y/N):${NC} "
        read -r use_domains
        
        if [[ "$use_domains" =~ ^[Yy]$ ]]; then
            get_custom_domains "$ports"
            custom_domains="$CUSTOM_DOMAINS"
        fi
    fi
    
    # Configuration Summary
    echo -e "\n${CYAN}📋 Configuration Summary:${NC}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${GRAY}│${NC} ${GREEN}Server IP(s):${NC} $server_ips"
    echo -e "${GRAY}│${NC} ${GREEN}Server Port:${NC} $server_port"
    echo -e "${GRAY}│${NC} ${GREEN}Auth Token:${NC} ${token:0:8}..."
    echo -e "${GRAY}│${NC} ${GREEN}Proxy Type:${NC} $proxy_type"
    echo -e "${GRAY}│${NC} ${GREEN}Transport Protocol:${NC} $GLOBAL_TRANSPORT_PROTOCOL"
    echo -e "${GRAY}│${NC} ${GREEN}Ports:${NC} $ports"
    if [[ -n "$custom_domains" ]]; then
        echo -e "${GRAY}│${NC} ${GREEN}Domains:${NC} $custom_domains"
    fi
    if [[ "$GLOBAL_BANDWIDTH_PROFILE" != "none" ]]; then
        echo -e "${GRAY}│${NC} ${GREEN}Bandwidth Profile:${NC} $GLOBAL_BANDWIDTH_PROFILE"
    fi
    echo -e "${GRAY}└─────────────────────────────────────────────────┘${NC}"
    
    echo -e "\n${YELLOW}Proceed with this configuration? (Y/n):${NC} "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log "INFO" "Configuration cancelled by user"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Check for existing configurations and services
    local existing_clients=($(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | grep moonfrpc | awk '{print $1}' | sed 's/\.service//'))
    local existing_configs=($(ls "$CONFIG_DIR"/frpc_*.toml 2>/dev/null))
    
    if [[ ${#existing_clients[@]} -gt 0 ]] || [[ ${#existing_configs[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}⚠️  Existing client configurations detected:${NC}"
        
        if [[ ${#existing_clients[@]} -gt 0 ]]; then
            echo -e "${CYAN}Services:${NC}"
            for client in "${existing_clients[@]}"; do
                local client_status=$(systemctl is-active "$client" 2>/dev/null || echo "inactive")
                echo -e "  • $client: ${client_status}"
            done
        fi
        
        if [[ ${#existing_configs[@]} -gt 0 ]]; then
            echo -e "${CYAN}Configuration files:${NC}"
            for config in "${existing_configs[@]}"; do
                echo -e "  • $(basename "$config")"
            done
        fi
        
        echo -e "\n${CYAN}Remove all existing configurations and services? (Y/n):${NC} "
        read -r remove_existing
        
        if [[ ! "$remove_existing" =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}Removing existing configurations and services...${NC}"
            
            # Stop and remove services
            for client in "${existing_clients[@]}"; do
                systemctl stop "$client" 2>/dev/null || true
                systemctl disable "$client" 2>/dev/null || true
                rm -f "/etc/systemd/system/${client}.service"
            done
            
            # Remove config files
            for config in "${existing_configs[@]}"; do
                rm -f "$config"
            done
            
            systemctl daemon-reload
            echo -e "${GREEN}✅ Existing configurations and services removed${NC}"
        else
            echo -e "${GREEN}Keeping existing configurations...${NC}"
        fi
    fi
    
    # Server Connection Validation
    echo -e "\n${CYAN}🔍 Validating server connections...${NC}"
    IFS=',' read -ra IP_ARRAY <<< "$server_ips"
    local connection_failed=false
    
    for ip in "${IP_ARRAY[@]}"; do
        ip=$(echo "$ip" | tr -d ' ')
        echo -e "${CYAN}Testing connection to $ip:$server_port...${NC}"
        
        if validate_server_connection "$ip" "$server_port"; then
            echo -e "${GREEN}✅ Connection successful${NC}"
        else
            echo -e "${RED}❌ Connection failed${NC}"
            connection_failed=true
        fi
    done
    
    if [[ "$connection_failed" == "true" ]]; then
        echo -e "\n${YELLOW}⚠️  Some server connections failed${NC}"
        echo -e "${CYAN}This might be due to:${NC}"
        echo -e "  • Server not running or not accessible"
        echo -e "  • Firewall blocking the connection"
        echo -e "  • Incorrect IP or port"
        echo -e "\n${YELLOW}Continue anyway? (y/N):${NC} "
        read -r continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log "INFO" "Configuration cancelled due to connection issues"
            read -p "Press Enter to continue..."
            return
        fi
    fi
    
    # Process each IP with progress indicator
    echo -e "\n${CYAN}🚀 Creating configurations...${NC}"
    local config_count=0
    local failed_count=0
    local total_ips=${#IP_ARRAY[@]}
    local current_ip=0
    
    for ip in "${IP_ARRAY[@]}"; do
        ip=$(echo "$ip" | tr -d ' ')
        ((current_ip++))
        local ip_suffix=$(echo "$ip" | cut -d'.' -f4)
        
        echo -e "\n${CYAN}[$current_ip/$total_ips] Processing IP: $ip${NC}"
        
        # Generate client configuration
        if generate_frpc_config "$ip" "$server_port" "$token" "$ip" "$ports" "$ip_suffix" "$proxy_type" "$custom_domains" "$GLOBAL_TRANSPORT_PROTOCOL"; then
            echo -e "${GREEN}✅ Configuration generated${NC}"
            
            # Verbose configuration output
            echo -e "${CYAN}📋 Configuration Details:${NC}"
            echo -e "  ${GREEN}Config File:${NC} $CONFIG_DIR/frpc_${ip_suffix}.toml"
            echo -e "  ${GREEN}Server:${NC} $ip:$server_port"
            echo -e "  ${GREEN}Protocol:${NC} $proxy_type"
            echo -e "  ${GREEN}Ports:${NC} $ports"
            if [[ -n "$custom_domains" ]]; then
                echo -e "  ${GREEN}Domains:${NC} $custom_domains"
            fi
            echo -e "  ${GREEN}Service:${NC} moonfrpc-${ip_suffix}"
            echo -e "  ${GREEN}Log:${NC} $LOG_DIR/frpc_${ip_suffix}.log"
            if [[ "$proxy_type" == "stcp" || "$proxy_type" == "xtcp" ]]; then
                echo -e "  ${GREEN}Visitor Config:${NC} $CONFIG_DIR/frpc_visitor_${ip_suffix}.toml"
                echo -e "  ${GREEN}Visitor Log:${NC} $LOG_DIR/frpc_visitor_${ip_suffix}.log"
            fi
            
            # Create systemd service with new naming convention
            local client_service_name="moonfrpc-${ip_suffix}"
            if create_systemd_service "$client_service_name" "frpc" "$CONFIG_DIR/frpc_${ip_suffix}.toml" "$ip_suffix"; then
                echo -e "${GREEN}✅ Service created: $client_service_name${NC}"
            else
                echo -e "${RED}❌ Failed to create service${NC}"
                ((failed_count++))
                continue
            fi
            
            # Start service
            if start_service "$client_service_name"; then
                ((config_count++))
                echo -e "${GREEN}✅ Service started successfully${NC}"
            else
                ((failed_count++))
                echo -e "${RED}❌ Failed to start service${NC}"
            fi
        else
            ((failed_count++))
            echo -e "${RED}❌ Failed to generate configuration${NC}"
        fi
    done
    
    # Configuration Results Summary
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║    🎉 Client Setup Complete!        ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}📊 Configuration Results:${NC}"
    echo -e "${GREEN}✅ Successful:${NC} $config_count"
    echo -e "${RED}❌ Failed:${NC} $failed_count"
    echo -e "${CYAN}📋 Proxy Type:${NC} $proxy_type"
    echo -e "${CYAN}🚪 Ports:${NC} $ports"
    
    if [[ $config_count -gt 0 ]]; then
        echo -e "\n${GREEN}✅ Created $config_count client configuration(s) successfully!${NC}"
        
        # Show service status
        echo -e "\n${CYAN}📋 Service Status:${NC}"
        echo -e "${GRAY}┌─────────────────────────────────────────────────┐${NC}"
        printf "${GRAY}│${NC} %-20s %-15s %-10s ${GRAY}│${NC}\n" "Service" "Server IP" "Status"
        echo -e "${GRAY}├─────────────────────────────────────────────────┤${NC}"
        
        for ip in "${IP_ARRAY[@]}"; do
            ip=$(echo "$ip" | tr -d ' ')
            local ip_suffix=$(echo "$ip" | cut -d'.' -f4)
            local service_name="moonfrpc-$ip_suffix"
            local service_status=$(get_service_status "$service_name")
            local status_icon="❌"
            local status_color="$RED"
            
            if [[ "$service_status" == "active" ]]; then
                status_icon="✅"
                status_color="$GREEN"
            fi
            
            printf "${GRAY}│${NC} %-20s %-15s ${status_color}%-10s${NC} ${GRAY}│${NC}\n" \
                "$service_name" "$ip" "$service_status"
        done
        echo -e "${GRAY}└─────────────────────────────────────────────────┘${NC}"
        
        # Show access information
        echo -e "\n${CYAN}🌐 Access Information:${NC}"
        IFS=',' read -ra PORT_ARRAY <<< "$ports"
        
        for port in "${PORT_ARRAY[@]}"; do
            port=$(echo "$port" | tr -d ' ')
            echo -e "${GREEN}Port $port:${NC}"
            
            case "$proxy_type" in
                "tcp"|"udp")
                    echo -e "  • Access via: ${YELLOW}${IP_ARRAY[0]}:$port${NC}"
                    ;;
                "http"|"https")
                    if [[ -n "$custom_domains" ]]; then
                        IFS=',' read -ra DOMAIN_ARRAY <<< "$custom_domains"
                        local port_index=0
                        for domain in "${DOMAIN_ARRAY[@]}"; do
                            domain=$(echo "$domain" | tr -d ' ')
                            echo -e "  • Access via: ${YELLOW}$proxy_type://$domain${NC}"
                            break
                        done
                    else
                        echo -e "  • Access via: ${YELLOW}$proxy_type://app${port}.moonfrp.local${NC}"
                    fi
                    ;;
                "tcpmux")
                    if [[ -n "$custom_domains" ]]; then
                        IFS=',' read -ra DOMAIN_ARRAY <<< "$custom_domains"
                        local port_index=0
                        for domain in "${DOMAIN_ARRAY[@]}"; do
                            domain=$(echo "$domain" | tr -d ' ')
                            echo -e "  • Access via: ${YELLOW}HTTP CONNECT to $domain${NC}"
                            break
                        done
                    else
                        echo -e "  • Access via: ${YELLOW}HTTP CONNECT to tunnel${port}${NC}"
                    fi
                    ;;
                "stcp"|"sudp")
                    echo -e "  • ${YELLOW}Secure P2P tunnel - requires visitor configuration${NC}"
                    echo -e "  • Check config file for visitor setup instructions"
                    ;;
                "xtcp")
                    echo -e "  • ${YELLOW}P2P TCP with NAT traversal - requires visitor configuration${NC}"
                    echo -e "  • Direct P2P connection with automatic fallback"
                    echo -e "  • Check config file for visitor setup instructions"
                    ;;
                "plugin_"*)
                    local plugin_name="${proxy_type#plugin_}"
                    echo -e "  • ${YELLOW}Plugin: ${plugin_name}${NC}"
                    case "$plugin_name" in
                        "unix_socket") echo -e "  • Unix domain socket forwarding" ;;
                        "http_proxy") echo -e "  • HTTP proxy server with authentication" ;;
                        "socks5") echo -e "  • SOCKS5 proxy server with authentication" ;;
                        "static_file") echo -e "  • Static file server with authentication" ;;
                        "https2http") echo -e "  • HTTPS to HTTP converter" ;;
                        "http2https") echo -e "  • HTTP to HTTPS converter" ;;
                        "virtual_net") echo -e "  • Virtual network for direct client communication" ;;
                    esac
                    echo -e "  • Check config file for plugin usage instructions"
                    ;;
            esac
        done
        
        echo -e "\n${CYAN}🔧 Management Commands:${NC}"
        echo -e "  • Check all services: ${GREEN}systemctl status moonfrpc-*${NC}"
        echo -e "  • View logs: ${GREEN}journalctl -u moonfrpc-* -f${NC}"
        echo -e "  • Restart all: ${GREEN}systemctl restart moonfrpc-*${NC}"
        echo -e "  • Stop all: ${GREEN}systemctl stop moonfrpc-*${NC}"
        
        echo -e "\n${YELLOW}💡 Troubleshooting:${NC}"
        echo -e "  • Use menu option 5 for detailed diagnostics"
        echo -e "  • Verify server is running and accessible"
        echo -e "  • Check firewall settings on both ends"
        
        if [[ $failed_count -gt 0 ]]; then
            echo -e "\n${RED}⚠️  Some configurations failed:${NC}"
            echo -e "  • Check server connectivity"
            echo -e "  • Verify authentication token"
            echo -e "  • Review service logs for details"
        fi
    fi
    
    read -p "Press Enter to continue..."
}

# Service removal menu
service_removal_menu() {
    while true; do
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║        Service Removal               ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        list_frp_services
        
        echo -e "\n${CYAN}Removal Options:${NC}"
        echo "1. Remove Single Service"
        echo "2. Remove All Services"
        echo "0. Back to Main Menu"
        
        echo -e "\n${YELLOW}Enter your choice [0-2]:${NC} "
        read -r choice
        
        case $choice in
            1) remove_single_service ;;
            2) remove_all_services ;;
            0) return ;;
            *) log "WARN" "Invalid choice. Please try again." ;;
        esac
    done
}

# Remove service menu (includes both single and all)
remove_service_menu() {
    while true; do
        # Check for Ctrl+C signal
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║         Remove Services              ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        list_frp_services
        
        echo -e "\n${CYAN}Service Removal Options:${NC}"
        echo "1. Remove Single Service"
        echo "2. Remove All Services"
        echo "0. Back to Service Management"
        
        echo -e "\n${YELLOW}Enter your choice [0-2]:${NC} "
        read -r choice
        
        # Check for Ctrl+C after read
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        case $choice in
            1) remove_single_service ;;
            2) remove_all_services ;;
            0) return ;;
            *) log "WARN" "Invalid choice. Please try again." ;;
        esac
    done
}

# Remove single service
remove_single_service() {
    local services=($(systemctl list-units --type=service --all --no-legend --plain | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "\n${CYAN}Select service to remove:${NC}"
    local i=1
    for service in "${services[@]}"; do
        echo "$i. $service"
        ((i++))
    done
    
    echo -e "\n${YELLOW}Select service number:${NC} "
    read -r service_num
    
    if [[ ! "$service_num" =~ ^[0-9]+$ ]] || [[ $service_num -lt 1 ]] || [[ $service_num -gt ${#services[@]} ]]; then
        log "ERROR" "Invalid service number. Please enter a number between 1-${#services[@]}"
        read -p "Press Enter to continue..."
        return
    fi
    
    local selected_service="${services[$((service_num-1))]}"
    if [[ -z "$selected_service" ]]; then
        log "ERROR" "Selected service is empty or invalid"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "\n${RED}Are you sure you want to remove service '$selected_service'? (y/N):${NC} "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        remove_service "$selected_service"
        log "INFO" "Service '$selected_service' removed successfully"
    else
        log "INFO" "Service removal cancelled"
    fi
    
    read -p "Press Enter to continue..."
}

# Setup cron job for auto-restart services
setup_cron_job() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
    echo -e "${PURPLE}║       Setup Cron Job                ║${NC}"
    echo -e "${PURPLE}║    (Auto-restart Services)           ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    local services=($(systemctl list-units --type=service --all --no-legend --plain | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "\n${CYAN}📋 Available Services:${NC}"
    list_frp_services
    
    echo -e "\n${CYAN}Select service to setup cron job:${NC}"
    local i=1
    for service in "${services[@]}"; do
        echo "$i. $service"
        ((i++))
    done
    echo "$i. Setup for ALL services"
    
    echo -e "\n${YELLOW}Select service number:${NC} "
    read -r service_num
    
    local selected_services=()
    if [[ "$service_num" == "$i" ]]; then
        # All services
        selected_services=("${services[@]}")
        echo -e "${GREEN}✅ Selected: ALL services${NC}"
    elif [[ "$service_num" =~ ^[0-9]+$ ]] && [[ $service_num -ge 1 ]] && [[ $service_num -le ${#services[@]} ]]; then
        selected_services=("${services[$((service_num-1))]}")
        echo -e "${GREEN}✅ Selected: ${selected_services[0]}${NC}"
    else
        log "ERROR" "Invalid service number"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Select cron schedule
    echo -e "\n${CYAN}🕐 Select Auto-restart Schedule:${NC}"
    echo -e "${YELLOW}How often should the service(s) be checked and restarted if needed?${NC}"
    echo ""
    echo "1. Every 30 minutes"
    echo "2. Every 1 hour"
    echo "3. Every 2 hours"
    echo "4. Every 6 hours"
    echo "5. Every 12 hours"
    echo "6. Every 24 hours"
    echo "0. Cancel"
    
    echo -e "\n${YELLOW}Select schedule [0-6]:${NC} "
    read -r schedule_choice
    
    local cron_schedule=""
    local schedule_desc=""
    
    case $schedule_choice in
        1) 
            cron_schedule="*/30 * * * *"
            schedule_desc="Every 30 minutes"
            ;;
        2) 
            cron_schedule="0 * * * *"
            schedule_desc="Every 1 hour"
            ;;
        3) 
            cron_schedule="0 */2 * * *"
            schedule_desc="Every 2 hours"
            ;;
        4) 
            cron_schedule="0 */6 * * *"
            schedule_desc="Every 6 hours"
            ;;
        5) 
            cron_schedule="0 */12 * * *"
            schedule_desc="Every 12 hours"
            ;;
        6) 
            cron_schedule="0 0 * * *"
            schedule_desc="Every 24 hours (midnight)"
            ;;
        0)
            echo -e "${YELLOW}Cron job setup cancelled${NC}"
            read -p "Press Enter to continue..."
            return
            ;;
        *)
            log "ERROR" "Invalid schedule choice"
            read -p "Press Enter to continue..."
            return
            ;;
    esac
    
    # Show summary and confirm
    echo -e "\n${CYAN}📋 Cron Job Summary:${NC}"
    echo -e "  ${GREEN}Services:${NC} ${#selected_services[@]} service(s)"
    for svc in "${selected_services[@]}"; do
        echo -e "    • $svc"
    done
    echo -e "  ${GREEN}Schedule:${NC} $schedule_desc"
    echo -e "  ${GREEN}Cron Pattern:${NC} $cron_schedule"
    echo -e "  ${GREEN}Action:${NC} Check and restart if not active"
    
    echo -e "\n${YELLOW}⚠️  This will add entries to root's crontab${NC}"
    echo -e "${YELLOW}Create cron job(s)? (y/N):${NC} "
    read -r confirm_cron
    
    if [[ ! "$confirm_cron" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cron job setup cancelled${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Create cron job entries
    echo -e "\n${CYAN}🔧 Setting up cron job(s)...${NC}"
    
    # Create backup of current crontab
    crontab -l > /tmp/moonfrp_crontab_backup_$(date +%s) 2>/dev/null || true
    
    # Create temporary crontab file
    local temp_crontab="/tmp/moonfrp_new_crontab_$(date +%s)"
    
    # Get current crontab (excluding old MoonFRP entries)
    crontab -l 2>/dev/null | grep -v "# MoonFRP Auto-restart" > "$temp_crontab" || true
    
    # Add new entries
    echo "" >> "$temp_crontab"
    echo "# MoonFRP Auto-restart Jobs - Generated $(date)" >> "$temp_crontab"
    
    for service in "${selected_services[@]}"; do
        local cron_command="systemctl is-active $service >/dev/null || systemctl restart $service"
        echo "$cron_schedule $cron_command # MoonFRP Auto-restart: $service" >> "$temp_crontab"
        echo -e "${GREEN}✅ Added cron job for: $service${NC}"
    done
    
    # Install new crontab
    if crontab "$temp_crontab"; then
        echo -e "\n${GREEN}✅ Cron job(s) installed successfully!${NC}"
        
        # Show current MoonFRP cron jobs
        echo -e "\n${CYAN}📋 Current MoonFRP Cron Jobs:${NC}"
        crontab -l | grep "MoonFRP Auto-restart" | while read -r line; do
            echo -e "  ${YELLOW}$line${NC}"
        done
        
        echo -e "\n${CYAN}💡 Management Commands:${NC}"
        echo -e "  • View all cron jobs: ${GREEN}crontab -l${NC}"
        echo -e "  • Edit cron jobs: ${GREEN}crontab -e${NC}"
        echo -e "  • Remove all cron jobs: ${GREEN}crontab -r${NC}"
        
        log "INFO" "Cron job(s) created successfully for ${#selected_services[@]} service(s)"
    else
        echo -e "\n${RED}❌ Failed to install cron job(s)${NC}"
        log "ERROR" "Failed to install crontab"
    fi
    
    # Cleanup
    rm -f "$temp_crontab"
    
    read -p "Press Enter to continue..."
}

# Remove all services
remove_all_services() {
    local services=($(systemctl list-units --type=service --all --no-legend --plain | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "\n${RED}Are you sure you want to remove ALL FRP services? This cannot be undone! (y/N):${NC} "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "\n${CYAN}Removing all FRP services...${NC}"
        for service in "${services[@]}"; do
            remove_service "$service"
        done
        
        # Final cleanup and daemon reload
        echo -e "\n${CYAN}Performing final cleanup...${NC}"
        systemctl daemon-reload
        
        log "INFO" "All FRP services removed successfully"
    else
        log "INFO" "Service removal cancelled"
    fi
    
    read -p "Press Enter to continue..."
}

# Remove service function
remove_service() {
    local service_name="$1"
    
    # Stop and disable service with improved error handling
    echo -e "${CYAN}Stopping service: $service_name${NC}"
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    
    # Remove service file
    local service_file="$SERVICE_DIR/${service_name}.service"
    if [[ -f "$service_file" ]]; then
        rm -f "$service_file"
        echo -e "${GREEN}✅ Removed service file: $service_file${NC}"
    fi
    
    # Remove configuration file
    if [[ "$service_name" =~ (frps|moonfrps) ]]; then
        if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
            rm -f "$CONFIG_DIR/frps.toml"
            echo -e "${GREEN}✅ Removed server configuration: $CONFIG_DIR/frps.toml${NC}"
        fi
    elif [[ "$service_name" =~ (frpc|moonfrpc) ]]; then
        local config_pattern="$CONFIG_DIR/frpc_*.toml"
        for config_file in $config_pattern; do
            if [[ -f "$config_file" ]]; then
                rm -f "$config_file"
                echo -e "${GREEN}✅ Removed client configuration: $config_file${NC}"
            fi
        done
    fi
    
    # Reload systemd daemon
    echo -e "${CYAN}Reloading systemd daemon...${NC}"
    systemctl daemon-reload
    
    # Clear all performance caches
    clear_performance_caches
    
    log "INFO" "Successfully removed service: $service_name"
}

# Global cache variables for performance
FRP_INSTALLATION_STATUS=""
UPDATE_CHECK_DONE=false
LAST_UPDATE_CHECK=""

# Fast FRP installation check with caching
check_frp_installation_cached() {
    if [[ -z "$FRP_INSTALLATION_STATUS" ]]; then
        if [[ -f "$FRP_DIR/frps" ]] && [[ -f "$FRP_DIR/frpc" ]]; then
            FRP_INSTALLATION_STATUS="installed"
        else
            FRP_INSTALLATION_STATUS="not_installed"
        fi
    fi
    
    [[ "$FRP_INSTALLATION_STATUS" == "installed" ]]
}

# Check updates only once per session
check_updates_cached() {
    if [[ "$UPDATE_CHECK_DONE" == "false" ]]; then
        UPDATE_CHECK_DONE=true
        
        # Run update check in background to avoid blocking
        (
            local update_status=0
            check_moonfrp_updates >/dev/null 2>&1
            update_status=$?
            
            if [[ $update_status -eq 0 ]]; then
                LAST_UPDATE_CHECK="available"
            else
                LAST_UPDATE_CHECK="none"
            fi
        ) &
        
        # Don't wait for background process
        disown
    fi
}

# Main menu
main_menu() {
    # Initialize cached values on first run
    [[ -z "$FRP_INSTALLATION_STATUS" ]] && check_frp_installation_cached >/dev/null
    [[ "$UPDATE_CHECK_DONE" == "false" ]] && check_updates_cached
    
    # Set main menu depth
    MENU_DEPTH=0
    MENU_STACK=()
    
    # Add safety check to prevent infinite loops
    local menu_iterations=0
    local max_iterations=1000
    
    while true; do
        # Check for Ctrl+C in main menu
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            echo -e "\n${GREEN}Thank you for using MoonFRP! 🚀${NC}"
            cleanup_and_exit
        fi
        
        # Safety check
        ((menu_iterations++))
        if [[ $menu_iterations -gt $max_iterations ]]; then
            log "ERROR" "Menu exceeded maximum iterations, exiting..."
            cleanup_and_exit
        fi
        # Fast clear with optimized escape sequences
        printf '\033[2J\033[H'
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║    Advanced FRP Management Tool     ║${NC}"
        echo -e "${PURPLE}║          Version $MOONFRP_VERSION              ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        # Show FRP installation status (cached)
        if check_frp_installation_cached; then
            echo -e "\n${GREEN}✅ FRP Status: Installed${NC}"
        else
            echo -e "\n${RED}❌ FRP Status: Not Installed${NC}"
        fi
        
        # Show update notification only if available (non-blocking)
        if [[ "$LAST_UPDATE_CHECK" == "available" ]]; then
            echo -e "\n${YELLOW}🔔 Update Available!${NC} ${GREEN}A new version of MoonFRP is available${NC}"
            echo -e "${CYAN}   Use menu option 6 to update${NC}"
        fi
        
        echo -e "\n${CYAN}Main Menu:${NC}"
        echo "1. Create FRP Configuration"
        echo "2. Service Management"
        echo "3. Download & Install FRP v$FRP_VERSION"
        echo "4. Install from Local Archive"
        echo "5. Troubleshooting & Diagnostics"
        echo "6. Update MoonFRP Script"
        echo "7. About & Version Info"
        echo "8. Configuration Summary"
        echo "0. Exit"
        
        # Show performance info in debug mode
        if [[ "${DEBUG:-}" == "1" ]]; then
            echo -e "\n${GRAY}[Debug] Menu load time: $(date +%T) | Services cached: ${#CACHED_SERVICES[@]} | FRP status: $FRP_INSTALLATION_STATUS${NC}"
        fi
        
        echo -e "\n${YELLOW}Enter your choice [0-9]:${NC} "
        read -r choice
        
        case $choice in
            1) 
                enter_submenu "config_creation"
                config_creation_menu
                exit_submenu
                ;;
            2) 
                enter_submenu "service_management"
                service_management_menu
                exit_submenu
                ;;
            3) 
                enter_submenu "download_install"
                download_and_install_frp
                exit_submenu
                read -p "Press Enter to continue..."
                ;;
            4) 
                enter_submenu "install_local"
                install_from_local
                exit_submenu
                read -p "Press Enter to continue..."
                ;;
            5) 
                enter_submenu "troubleshooting"
                troubleshooting_menu
                exit_submenu
                ;;
            6) 
                enter_submenu "update_script"
                update_moonfrp_script
                exit_submenu
                read -p "Press Enter to continue..."
                ;;
            7) 
                enter_submenu "about_info"
                show_about_info
                exit_submenu
                read -p "Press Enter to continue..."
                ;;
            8) 
                enter_submenu "config_summary"
                show_current_config_summary
                exit_submenu
                read -p "Press Enter to continue..."
                ;;
            0) 
                echo -e "\n${GREEN}Thank you for using MoonFRP! 🚀${NC}"
                cleanup_and_exit
                ;;
            *) 
                log "WARN" "Invalid choice. Please try again."
                sleep 1
                ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local deps=("curl" "tar" "systemctl" "openssl")
    local optional_deps=("netstat" "nc")
    local missing_deps=()
    local missing_optional=()
    
    # Check required dependencies
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    # Check optional dependencies
    for dep in "${optional_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_optional+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        log "INFO" "Please install missing dependencies and try again"
        log "INFO" "Ubuntu/Debian: sudo apt install ${missing_deps[*]}"
        log "INFO" "CentOS/RHEL: sudo yum install ${missing_deps[*]}"
        exit 1
    fi
    
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        log "WARN" "Missing optional dependencies: ${missing_optional[*]}"
        log "WARN" "Some features may not work properly"
        log "INFO" "Install with: sudo apt install ${missing_optional[*]}"
    fi
}

# Initialize script
init() {
    check_root
    
    # Setup signal handlers first
    setup_signal_handlers
    
    # Run non-critical checks in background for faster startup
    (
        check_dependencies
        create_directories
    ) >/dev/null 2>&1 &
    
    # Apply performance optimizations
    optimize_systemctl_calls >/dev/null 2>&1
    
    # Initialize caches and flags
    FRP_INSTALLATION_STATUS=""
    UPDATE_CHECK_DONE=false
    CACHED_SERVICES=()
    CTRL_C_PRESSED=false
    
    log "INFO" "MoonFRP script initialized successfully"
}

# Cleanup and exit function
cleanup_and_exit() {
    # Clean up temporary files
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    
    # Log exit
    log "INFO" "MoonFRP session ended"
    
    # Exit gracefully
    exit 0
}

# Troubleshooting and diagnostics menu
troubleshooting_menu() {
    while true; do
        # Check for Ctrl+C signal
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║         Troubleshooting              ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        echo -e "\n${CYAN}Troubleshooting Options:${NC}"
        echo "1. Check Proxy Name Conflicts"
        echo "2. Check Port Conflicts"
        echo "3. Validate Server Connections"
        echo "4. Check Service Logs"
        echo "5. Fix Common Issues"
        echo "6. Generate Diagnostic Report"
        echo "7. Quick Help for Common Errors"
        echo "8. Fix Web Panel Issues (HTTP 503)"
        echo "9. Performance Monitoring"
        echo "0. Back to Main Menu"
        
        echo -e "\n${YELLOW}Enter your choice [0-9]:${NC} "
        read -r choice
        
        # Check for Ctrl+C after read
        if [[ "$CTRL_C_PRESSED" == "true" ]]; then
            CTRL_C_PRESSED=false
            return
        fi
        
        case $choice in
            1) check_all_proxy_conflicts; read -p "Press Enter to continue..." ;;
            2) check_all_port_conflicts; read -p "Press Enter to continue..." ;;
            3) validate_all_connections; read -p "Press Enter to continue..." ;;
            4) view_service_logs_menu; read -p "Press Enter to continue..." ;;
            5) fix_common_issues; read -p "Press Enter to continue..." ;;
            6) generate_diagnostic_report; read -p "Press Enter to continue..." ;;
            7) show_quick_help; read -p "Press Enter to continue..." ;;
            8) fix_web_panel_issues; read -p "Press Enter to continue..." ;;
            9) monitor_all_proxies; read -p "Press Enter to continue..." ;;
            0) return ;;
            *) log "WARN" "Invalid choice. Please try again." ;;
        esac
    done
}

# Check all proxy name conflicts
check_all_proxy_conflicts() {
    clear
    echo -e "${CYAN}🔍 Checking for proxy name conflicts...${NC}"
    
    local conflicts_found=false
    local proxy_names=()
    
    # Collect all proxy names
    for config_file in "$CONFIG_DIR"/frpc_*.toml; do
        [[ ! -f "$config_file" ]] && continue
        
        while IFS= read -r line; do
            if [[ $line =~ name\ =\ \"([^\"]+)\" ]]; then
                local proxy_name="${BASH_REMATCH[1]}"
                
                # Check if this name already exists
                for existing_name in "${proxy_names[@]}"; do
                    if [[ "$existing_name" == "$proxy_name" ]]; then
                        log "ERROR" "❌ Duplicate proxy name found: $proxy_name"
                        log "ERROR" "   In file: $config_file"
                        conflicts_found=true
                        break
                    fi
                done
                
                proxy_names+=("$proxy_name")
            fi
        done < "$config_file"
    done
    
    if [[ "$conflicts_found" == "false" ]]; then
        log "INFO" "✅ No proxy name conflicts found"
        echo -e "${GREEN}Total unique proxy names: ${#proxy_names[@]}${NC}"
    else
        echo -e "\n${YELLOW}💡 To fix conflicts:${NC}"
        echo -e "  1. Stop conflicting services"
        echo -e "  2. Remove duplicate configurations"
        echo -e "  3. Regenerate configurations with unique names"
    fi
}

# Check all port conflicts
check_all_port_conflicts() {
    clear
    echo -e "${CYAN}🔍 Checking for port conflicts...${NC}"
    
    local conflicts_found=false
    local used_ports=()
    
    # Check FRP configuration files
    for config_file in "$CONFIG_DIR"/frpc_*.toml; do
        [[ ! -f "$config_file" ]] && continue
        
        while IFS= read -r line; do
            if [[ $line =~ remotePort\ =\ ([0-9]+) ]]; then
                local port="${BASH_REMATCH[1]}"
                
                # Check if port is already used
                for used_port in "${used_ports[@]}"; do
                    if [[ "$used_port" == "$port" ]]; then
                        log "ERROR" "❌ Duplicate port found: $port"
                        log "ERROR" "   In file: $config_file"
                        conflicts_found=true
                        break
                    fi
                done
                
                used_ports+=("$port")
            fi
        done < "$config_file"
    done
    
    # Check system port usage
    echo -e "\n${CYAN}Checking system port usage...${NC}"
    for port in "${used_ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            log "WARN" "⚠️  Port $port is in use by system process"
        fi
    done
    
    if [[ "$conflicts_found" == "false" ]]; then
        log "INFO" "✅ No port conflicts found in FRP configurations"
        echo -e "${GREEN}Total ports configured: ${#used_ports[@]}${NC}"
    fi
}

# Validate all server connections
validate_all_connections() {
    clear
    echo -e "${CYAN}🔍 Validating all server connections...${NC}"
    
    local servers_checked=0
    local servers_failed=0
    
    for config_file in "$CONFIG_DIR"/frpc_*.toml; do
        [[ ! -f "$config_file" ]] && continue
        
        local server_addr=""
        local server_port=""
        
        while IFS= read -r line; do
            if [[ $line =~ serverAddr\ =\ \"([^\"]+)\" ]]; then
                server_addr="${BASH_REMATCH[1]}"
            elif [[ $line =~ serverPort\ =\ ([0-9]+) ]]; then
                server_port="${BASH_REMATCH[1]}"
            fi
        done < "$config_file"
        
        if [[ -n "$server_addr" && -n "$server_port" ]]; then
            ((servers_checked++))
            echo -e "\n${CYAN}Testing: $server_addr:$server_port${NC}"
            
            if ! validate_server_connection "$server_addr" "$server_port"; then
                ((servers_failed++))
            fi
        fi
    done
    
    echo -e "\n${CYAN}📊 Connection Summary:${NC}"
    echo -e "  Servers tested: $servers_checked"
    echo -e "  Failed connections: $servers_failed"
    if [[ $servers_checked -gt 0 ]]; then
        echo -e "  Success rate: $(( (servers_checked - servers_failed) * 100 / servers_checked ))%"
    else
        echo -e "  No servers found to test"
    fi
}

# View service logs
view_service_logs_menu() {
    clear
    echo -e "${CYAN}📋 Service Logs Viewer${NC}"
    
    local services=($(systemctl list-units --type=service --all --no-legend --plain | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        return
    fi
    
    echo -e "\n${CYAN}Select service to view logs:${NC}"
    local i=1
    for service in "${services[@]}"; do
        echo "$i. $service"
        ((i++))
    done
    echo "$i. View all logs"
    
    echo -e "\n${YELLOW}Select service number:${NC} "
    read -r service_num
    
    if [[ "$service_num" == "$i" ]]; then
        # View all logs
        echo -e "\n${CYAN}All FRP Service Logs:${NC}"
        for service in "${services[@]}"; do
            echo -e "\n${YELLOW}=== $service ===${NC}"
            journalctl -u "$service" -n 10 --no-pager
        done
    elif [[ "$service_num" =~ ^[0-9]+$ ]] && [[ $service_num -ge 1 ]] && [[ $service_num -le ${#services[@]} ]]; then
        local selected_service="${services[$((service_num-1))]}"
        echo -e "\n${CYAN}Logs for $selected_service:${NC}"
        journalctl -u "$selected_service" -n 50 --no-pager
    else
        log "ERROR" "Invalid service number"
    fi
}

# Fix common issues
fix_common_issues() {
    clear
    echo -e "${CYAN}🔧 Fix Common Issues${NC}"
    
    echo -e "\n${CYAN}Available fixes:${NC}"
    echo "1. Remove duplicate proxy configurations"
    echo "2. Reset all client configurations"
    echo "3. Fix service permissions"
    echo "4. Clear log files"
    echo "5. Restart all services"
    echo "0. Back"
    
    echo -e "\n${YELLOW}Select fix [0-5]:${NC} "
    read -r fix_choice
    
    case $fix_choice in
        1)
            echo -e "\n${YELLOW}This will backup and recreate all client configs. Continue? (y/N):${NC} "
            read -r confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                cleanup_old_configs "backup"
                log "INFO" "Please recreate configurations from main menu"
            fi
            ;;
        2)
            echo -e "\n${RED}This will remove ALL client configurations! Continue? (y/N):${NC} "
            read -r confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                remove_all_services
                rm -f "$CONFIG_DIR"/frpc_*.toml
                log "INFO" "All client configurations removed"
            fi
            ;;
        3)
            chmod +x "$FRP_DIR"/frp*
            chown root:root "$FRP_DIR"/frp*
            chmod 644 "$CONFIG_DIR"/*.toml 2>/dev/null || true
            log "INFO" "Fixed file permissions"
            ;;
        4)
            rm -f "$LOG_DIR"/*.log
            log "INFO" "Cleared all log files"
            ;;
        5)
            local services=($(systemctl list-units --type=service --all --no-legend --plain | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
            for service in "${services[@]}"; do
                restart_service "$service"
            done
            log "INFO" "Restarted all FRP services"
            ;;
        0)
            return
            ;;
        *)
            log "ERROR" "Invalid choice"
            ;;
    esac
}

# Generate diagnostic report
generate_diagnostic_report() {
    clear
    echo -e "${CYAN}📋 Generating diagnostic report...${NC}"
    
    local report_file="/tmp/moonfrp_diagnostic_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "MoonFRP Diagnostic Report"
        echo "Generated on: $(date)"
        echo "System: $(uname -a)"
        echo
        
        echo "=== FRP Installation ==="
        echo "FRP Directory: $FRP_DIR"
        ls -la "$FRP_DIR" 2>/dev/null || echo "FRP not installed"
        echo
        
        echo "=== Configuration Files ==="
        echo "Config Directory: $CONFIG_DIR"
        ls -la "$CONFIG_DIR" 2>/dev/null || echo "No configs found"
        echo
        
        echo "=== Services Status ==="
        systemctl list-units --type=service --all --no-legend --plain | grep -E "(moonfrp|frp)" || echo "No FRP services found"
        echo
        
        echo "=== Network Connectivity ==="
        for config_file in "$CONFIG_DIR"/frpc_*.toml; do
            [[ ! -f "$config_file" ]] && continue
            
            local server_addr=""
            local server_port=""
            
            while IFS= read -r line; do
                if [[ $line =~ serverAddr\ =\ \"([^\"]+)\" ]]; then
                    server_addr="${BASH_REMATCH[1]}"
                elif [[ $line =~ serverPort\ =\ ([0-9]+) ]]; then
                    server_port="${BASH_REMATCH[1]}"
                fi
            done < "$config_file"
            
            if [[ -n "$server_addr" && -n "$server_port" ]]; then
                echo "Testing $server_addr:$server_port"
                timeout 3 nc -z "$server_addr" "$server_port" && echo "  ✅ Connected" || echo "  ❌ Failed"
            fi
        done
        echo
        
        echo "=== Recent Logs ==="
        for service in $(systemctl list-units --type=service --all --no-legend --plain | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'); do
            echo "--- $service ---"
            journalctl -u "$service" -n 5 --no-pager 2>/dev/null || echo "No logs found"
            echo
        done
        
    } > "$report_file"
    
    log "INFO" "Diagnostic report saved to: $report_file"
    echo -e "\n${CYAN}Report preview:${NC}"
    head -30 "$report_file"
    echo -e "\n${YELLOW}... (truncated, see full report in file)${NC}"
} 

# Show about and version information
show_about_info() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         MoonFRP About & Info         ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}📋 Version Information:${NC}"
    echo -e "  MoonFRP Version: ${GREEN}v$MOONFRP_VERSION${NC}"
    echo -e "  FRP Version: ${GREEN}v$FRP_VERSION${NC}"
    echo -e "  Architecture: ${GREEN}$FRP_ARCH${NC}"
    
    echo -e "\n${CYAN}💻 System Information:${NC}"
    echo -e "  OS: ${GREEN}$(uname -s)${NC}"
    echo -e "  Kernel: ${GREEN}$(uname -r)${NC}"
    echo -e "  Architecture: ${GREEN}$(uname -m)${NC}"
    echo -e "  Hostname: ${GREEN}$(hostname)${NC}"
    
    echo -e "\n${CYAN}📁 Installation Paths:${NC}"
    echo -e "  Script Location: ${GREEN}$MOONFRP_INSTALL_PATH${NC}"
    echo -e "  FRP Binaries: ${GREEN}$FRP_DIR${NC}"
    echo -e "  Configurations: ${GREEN}$CONFIG_DIR${NC}"
    echo -e "  Log Files: ${GREEN}$LOG_DIR${NC}"
    
    echo -e "\n${CYAN}🔗 Repository Information:${NC}"
    echo -e "  GitHub: ${GREEN}https://github.com/k4lantar4/moonfrp${NC}"
    echo -e "  Issues: ${GREEN}https://github.com/k4lantar4/moonfrp/issues${NC}"
    echo -e "  Latest Releases: ${GREEN}https://github.com/k4lantar4/moonfrp/releases${NC}"
    
    echo -e "\n${CYAN}📊 Current Status:${NC}"
    
    # Check FRP installation
    if check_frp_installation; then
        echo -e "  FRP Installation: ${GREEN}✅ Installed${NC}"
        echo -e "    frps: $(ls -la $FRP_DIR/frps 2>/dev/null | awk '{print $5, $6, $7, $8}' || echo 'Not found')"
        echo -e "    frpc: $(ls -la $FRP_DIR/frpc 2>/dev/null | awk '{print $5, $6, $7, $8}' || echo 'Not found')"
    else
        echo -e "  FRP Installation: ${RED}❌ Not Installed${NC}"
    fi
    
    # Check services
    local services=($(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//' || echo ""))
    if [[ ${#services[@]} -gt 0 ]] && [[ "${services[0]}" != "" ]]; then
        echo -e "  Active Services: ${GREEN}${#services[@]} service(s)${NC}"
        for service in "${services[@]}"; do
            local status=$(get_service_status "$service")
            local status_icon="❌"
            local status_color="$RED"
            [[ "$status" == "active" ]] && status_icon="✅" && status_color="$GREEN"
            echo -e "    $status_icon $service: ${status_color}$status${NC}"
        done
    else
        echo -e "  Active Services: ${YELLOW}⚠️  No services found${NC}"
    fi
    
    # Check configurations
    local config_count=$(ls "$CONFIG_DIR"/*.toml 2>/dev/null | wc -l)
    if [[ $config_count -gt 0 ]]; then
        echo -e "  Configurations: ${GREEN}✅ $config_count file(s)${NC}"
    else
        echo -e "  Configurations: ${YELLOW}⚠️  No configurations found${NC}"
    fi
    
    # Check update status
    echo -e "\n${CYAN}🔄 Update Status:${NC}"
    local update_status=0
    check_moonfrp_updates >/dev/null 2>&1
    update_status=$?
    
    case $update_status in
        0)
            echo -e "  Status: ${YELLOW}⚠️  Update available${NC}"
            echo -e "  Action: ${GREEN}Use menu option 6 to update${NC}"
            ;;
        1)
            echo -e "  Status: ${GREEN}✅ Up to date${NC}"
            ;;
        *)
            echo -e "  Status: ${BLUE}ℹ️  Cannot check (offline)${NC}"
            ;;
    esac
    
    echo -e "\n${CYAN}ℹ️  Quick Commands:${NC}"
    echo -e "  Check logs: ${GREEN}journalctl -u moonfrp-* -f${NC}"
    echo -e "  Restart services: ${GREEN}systemctl restart moonfrp-*${NC}"
    echo -e "  Check status: ${GREEN}systemctl status moonfrp-*${NC}"
    
    echo -e "\n${YELLOW}💡 Need Help?${NC}"
    echo -e "  • Use menu option 6 for troubleshooting"
    echo -e "  • Check the GitHub repository for documentation"
    echo -e "  • Submit issues for bugs or feature requests"
    
    echo -e "\n${CYAN}📝 Recent Updates (v$MOONFRP_VERSION):${NC}"
    echo -e "  ✨ Auto-update functionality added"
    echo -e "  🔧 Advanced troubleshooting tools"
    echo -e "  🛡️ Improved proxy conflict resolution"
    echo -e "  📊 Enhanced diagnostic reporting"
    echo -e "  🚀 Better error handling and validation"
    
    echo -e "\n${GREEN}🌙 Thank you for using MoonFRP!${NC}"
    
    read -p "Press Enter to continue..."
}

# Real-time status monitor
real_time_status_monitor() {
    # Initialize monitoring
    local update_interval=2
    local iteration=0
    local last_refresh=0
    
    # Trap Ctrl+C for clean exit
    trap 'echo -e "\n${GREEN}Monitoring stopped${NC}"; read -p "Press Enter to continue..."; trap - INT; return' INT
    
    echo -e "${CYAN}🔄 Starting real-time monitoring...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit monitoring${NC}"
    sleep 1
    
    while true; do
        ((iteration++))
        local current_time=$(date +%s)
        
        # Only refresh if enough time has passed (prevent flicker)
        if [[ $((current_time - last_refresh)) -ge $update_interval ]]; then
            last_refresh=$current_time
            
            # Use more stable clear method
            printf '\033[2J\033[H'
            
            # Header with fixed position
            echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
            echo -e "${PURPLE}║        Real-time Status Monitor     ║${NC}"
            echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
            echo -e "${CYAN}📊 Live Status (Update #$iteration - Every ${update_interval}s)${NC}"
            echo -e "${GRAY}$(date)${NC}"
            echo ""
            
            # Get all services with fresh data (avoid cache issues)
            local services=($(systemctl list-units --type=service --no-legend --plain 2>/dev/null | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
            
            if [[ ${#services[@]} -eq 0 ]]; then
                echo -e "${YELLOW}⚠️  No FRP services found${NC}"
                echo ""
            fi
        
            # Services status table (stable layout)
            printf "%-25s %-12s %-15s %-20s\n" "Service" "Status" "Type" "Uptime"
            printf "%-25s %-12s %-15s %-20s\n" "-------" "------" "----" "------"
            
            if [[ ${#services[@]} -eq 0 ]]; then
                printf "%-25s %-12s %-15s %-20s\n" "No services found" "${YELLOW}N/A${NC}" "N/A" "N/A"
            else
                for service in "${services[@]}"; do
                    [[ -z "$service" ]] && continue
                    
                    # Get status efficiently
                    local status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
                    local type="Unknown"
                    local uptime="N/A"
                    
                    # Determine service type
                    if [[ "$service" =~ (frps|moonfrps) ]]; then
                        type="Server"
                    elif [[ "$service" =~ (frpc|moonfrpc) ]]; then
                        type="Client"
                    fi
                    
                    # Get uptime for active services
                    if [[ "$status" == "active" ]]; then
                        uptime=$(systemctl show -p ActiveEnterTimestamp "$service" 2>/dev/null | cut -d= -f2-)
                        if [[ -n "$uptime" && "$uptime" != "n/a" ]]; then
                            local start_time=$(date -d "$uptime" +%s 2>/dev/null || echo "0")
                            local current_time=$(date +%s)
                            local diff=$((current_time - start_time))
                            
                            if [[ $diff -gt 86400 ]]; then
                                uptime="$((diff / 86400))d"
                            elif [[ $diff -gt 3600 ]]; then
                                uptime="$((diff / 3600))h"
                            elif [[ $diff -gt 60 ]]; then
                                uptime="$((diff / 60))m"
                            else
                                uptime="${diff}s"
                            fi
                        else
                            uptime="unknown"
                        fi
                    fi
                    
                    # Color status
                    local status_color="$RED"
                    case "$status" in
                        "active") status_color="$GREEN" ;;
                        "inactive") status_color="$RED" ;;
                        "activating") status_color="$YELLOW" ;;
                        "deactivating") status_color="$YELLOW" ;;
                        "failed") status_color="$RED" ;;
                        *) status_color="$GRAY" ;;
                    esac
                    
                    printf "%-25s ${status_color}%-12s${NC} %-15s %-20s\n" \
                        "${service:0:24}" "$status" "$type" "$uptime"
                done
            fi
        
        # Configuration files status (always show)
        echo ""
        echo -e "${CYAN}📁 Configuration Files:${NC}"
        printf "%-30s %-10s %-15s\n" "File" "Size" "Modified"
        printf "%-30s %-10s %-15s\n" "----" "----" "--------"
        
        local config_found=false
        for config_file in "$CONFIG_DIR"/*.toml; do
            [[ ! -f "$config_file" ]] && continue
            
            local filename=$(basename "$config_file")
            local filesize=$(ls -lh "$config_file" | awk '{print $5}')
            local modified=$(stat -c %y "$config_file" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")
            
            printf "%-30s %-10s %-15s\n" "$filename" "$filesize" "$modified"
            config_found=true
        done
        
        if [[ "$config_found" == "false" ]]; then
            printf "%-30s %-10s %-15s\n" "No config files found" "N/A" "N/A"
        fi
        
        # Connection status for clients (always show)
        echo ""
        echo -e "${CYAN}🌐 Connection Status:${NC}"
        
        local client_found=false
        for config_file in "$CONFIG_DIR"/frpc_*.toml; do
            [[ ! -f "$config_file" ]] && continue
            
            # Skip visitor configuration files
            [[ "$config_file" =~ visitor ]] && continue
            
            local server_addr=""
            local server_port=""
            local ip_suffix=$(basename "$config_file" | sed 's/frpc_//' | sed 's/.toml//')
            
            # Extract server info
            while IFS= read -r line; do
                if [[ $line =~ serverAddr\ =\ \"([^\"]+)\" ]]; then
                    server_addr="${BASH_REMATCH[1]}"
                elif [[ $line =~ serverPort\ =\ ([0-9]+) ]]; then
                    server_port="${BASH_REMATCH[1]}"
                fi
            done < "$config_file"
            
            if [[ -n "$server_addr" && -n "$server_port" ]]; then
                # Count proxies in this config
                local proxy_count=$(grep -c "^\[\[proxies\]\]" "$config_file" 2>/dev/null || echo "0")
                
                # Get all ports from config
                local ports_in_config=()
                while IFS= read -r line; do
                    if [[ $line =~ localPort\ =\ ([0-9]+) ]]; then
                        ports_in_config+=("${BASH_REMATCH[1]}")
                    fi
                done < "$config_file"
                
                # Format ports list
                local ports_list=""
                if [[ ${#ports_in_config[@]} -gt 0 ]]; then
                    IFS=','
                    ports_list="${ports_in_config[*]}"
                    IFS=' '  # Reset IFS
                fi
                
                # Check service status
                local service_name="moonfrpc-$ip_suffix"
                local service_status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
                local status_icon="❌"
                local status_color="$RED"
                
                if [[ "$service_status" == "active" ]]; then
                    status_icon="✅"
                    status_color="$GREEN"
                fi
                
                printf "    %-15s -> %-20s [%s] " \
                    "Client-$ip_suffix" "$server_addr" "$ports_list"
                echo -e "${status_color}${status_icon}${NC}"
                client_found=true
            fi
        done
        
        if [[ "$client_found" == "false" ]]; then
            echo "    No client configurations found (Server-only mode)"
        fi
        
        # Show server dashboard info if available
        echo ""
        echo -e "${CYAN}📊 Server Dashboard:${NC}"
        
        local dashboard_found=false
        if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
            local dashboard_port=""
            local dashboard_user=""
            local bind_port=""
            
            while IFS= read -r line; do
                if [[ $line =~ webServer\.port\ =\ ([0-9]+) ]]; then
                    dashboard_port="${BASH_REMATCH[1]}"
                elif [[ $line =~ webServer\.user\ =\ \"([^\"]+)\" ]]; then
                    dashboard_user="${BASH_REMATCH[1]}"
                elif [[ $line =~ ^bindPort\ =\ ([0-9]+) ]]; then
                    bind_port="${BASH_REMATCH[1]}"
                fi
            done < "$CONFIG_DIR/frps.toml"
            
            if [[ -n "$dashboard_port" ]]; then
                echo "Dashboard: http://localhost:$dashboard_port (User: $dashboard_user)"
                echo "Server Port: $bind_port"
                dashboard_found=true
            fi
        fi
        
        if [[ "$dashboard_found" == "false" ]]; then
            echo "No server dashboard configured"
        fi
        
        # Show proxy information for active services
        echo ""
        echo -e "${CYAN}🚀 Active Proxies:${NC}"
        
        local proxy_found=false
        for config_file in "$CONFIG_DIR"/*.toml; do
            [[ ! -f "$config_file" ]] && continue
            
            local filename=$(basename "$config_file")
            local proxy_count=$(grep -c "^\[\[proxies\]\]" "$config_file" 2>/dev/null || echo "0")
            # Ensure proxy_count is a valid number
            [[ ! "$proxy_count" =~ ^[0-9]+$ ]] && proxy_count=0
            
            if [[ "$proxy_count" -gt 0 ]]; then
                printf "%-30s %s proxies\n" "$filename" "$proxy_count"
                proxy_found=true
                
                # Show proxy details
                local proxy_names=()
                while IFS= read -r line; do
                    if [[ $line =~ name\ =\ \"([^\"]+)\" ]]; then
                        proxy_names+=("${BASH_REMATCH[1]}")
                    fi
                done < "$config_file"
                
                if [[ ${#proxy_names[@]} -gt 0 ]]; then
                    local names_str=$(printf ", %s" "${proxy_names[@]}")
                    names_str=${names_str:2}  # Remove leading ", "
                    echo "  └─ Proxies: $names_str"
                fi
            fi
        done
        
        if [[ "$proxy_found" == "false" ]]; then
            echo "No active proxies found"
        fi
        
        # Show system resources
        echo ""
        echo -e "${CYAN}💻 System Resources:${NC}"
        
        # Memory usage
        local mem_info=$(free -h | grep "Mem:" | awk '{print $3 "/" $2}')
        echo "Memory: $mem_info"
        
        # CPU load
        local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ *//')
        echo "Load: $cpu_load"
        
        # Network connections
        local tcp_connections=$(ss -t state established 2>/dev/null | wc -l)
        if [[ "$tcp_connections" -gt 0 ]]; then
            ((tcp_connections--))  # Remove header line
        fi
        echo "TCP Connections: $tcp_connections"
        
        echo ""
        echo -e "${GRAY}Press Ctrl+C to exit monitoring${NC}"
        
            
            echo ""
            echo -e "${GRAY}Last update: $(date '+%H:%M:%S') | Next update in ${update_interval}s | Press Ctrl+C to exit${NC}"
        fi
        
        # Short sleep to prevent busy waiting
        sleep 0.5
    done
}

# Show current configuration summary
show_current_config_summary() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║      Configuration Summary          ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}📋 Current MoonFRP Configuration:${NC}"
    
    # Server configurations
    echo -e "\n${GREEN}🏠 Server Configurations (Iran):${NC}"
    if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
        local bind_port=""
        local token=""
        local dashboard_port=""
        
        while IFS= read -r line; do
            if [[ $line =~ ^bindPort\ =\ ([0-9]+) ]]; then
                bind_port="${BASH_REMATCH[1]}"
            elif [[ $line =~ auth\.token\ =\ \"([^\"]+)\" ]]; then
                token="${BASH_REMATCH[1]}"
            elif [[ $line =~ webServer\.port\ =\ ([0-9]+) ]]; then
                dashboard_port="${BASH_REMATCH[1]}"
            fi
        done < "$CONFIG_DIR/frps.toml"
        
        echo -e "  ${CYAN}Server Port:${NC} ${GREEN}$bind_port${NC}"
        echo -e "  ${CYAN}Auth Token:${NC} ${GREEN}${token:0:8}...${NC}"
        [[ -n "$dashboard_port" ]] && echo -e "  ${CYAN}Dashboard:${NC} ${GREEN}http://SERVER-IP:$dashboard_port${NC}"
        
        # Share with clients information - Auto-detect public IPs
        local primary_ip=$(hostname -I | awk '{print $1}')
        local public_ips=$(hostname -I | tr ' ' '\n' | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | grep -v -E '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.)' | tr '\n' ',' | sed 's/,$//')
        [[ -z "$public_ips" ]] && public_ips="$primary_ip"
        
        echo -e "\n  ${CYAN}3. Share with clients:${NC}"
        echo -e "     ${YELLOW}• Server IPs:${NC} ${GREEN}$public_ips${NC}"
        echo -e "     ${YELLOW}• Server Port:${NC} ${GREEN}$bind_port${NC}"
        echo -e "     ${YELLOW}• Token:${NC} ${GREEN}$token${NC}"
        
        # Check server status
        local server_services=($(systemctl list-units --type=service --state=active --no-legend --plain 2>/dev/null | grep moonfrps | awk '{print $1}' | sed 's/\.service//'))
        if [[ ${#server_services[@]} -gt 0 ]]; then
            echo -e "  ${CYAN}Status:${NC} ${GREEN}✅ Active (${#server_services[@]} service(s))${NC}"
        else
            echo -e "  ${CYAN}Status:${NC} ${RED}❌ Inactive${NC}"
        fi
    else
        echo -e "  ${YELLOW}No server configuration found${NC}"
    fi
    
    # Client configurations
    echo -e "\n${GREEN}🌍 Client Configurations (Foreign):${NC}"
    
    local client_configs=($(ls "$CONFIG_DIR"/frpc_*.toml 2>/dev/null))
    if [[ ${#client_configs[@]} -gt 0 ]]; then
        local all_ips=()
        local all_ports=()
        local common_token=""
        local total_proxies=0
        
        echo -e "  ${CYAN}Total Configs:${NC} ${GREEN}${#client_configs[@]}${NC}"
        
        for config_file in "${client_configs[@]}"; do
            local server_addr=""
            local server_port=""
            local token=""
            local proxy_count=0
            local ports_in_config=()
            
            while IFS= read -r line; do
                if [[ $line =~ serverAddr\ =\ \"([^\"]+)\" ]]; then
                    server_addr="${BASH_REMATCH[1]}"
                elif [[ $line =~ serverPort\ =\ ([0-9]+) ]]; then
                    server_port="${BASH_REMATCH[1]}"
                elif [[ $line =~ auth\.token\ =\ \"([^\"]+)\" ]]; then
                    token="${BASH_REMATCH[1]}"
                elif [[ $line =~ localPort\ =\ ([0-9]+) ]]; then
                    ports_in_config+=("${BASH_REMATCH[1]}")
                    ((total_proxies++))
                fi
            done < "$config_file"
            
            # Collect unique IPs and ports
            [[ -n "$server_addr" ]] && ! printf '%s\n' "${all_ips[@]}" | grep -q "^${server_addr}$" && all_ips+=("$server_addr")
            [[ -n "$server_port" ]] && ! printf '%s\n' "${all_ports[@]}" | grep -q "^${server_port}$" && all_ports+=("$server_port")
            [[ -z "$common_token" ]] && common_token="$token"
        done
        
        # Display summary
        local ips_str=$(IFS=','; echo "${all_ips[*]}")
        local ports_str=$(IFS=','; echo "${all_ports[*]}")
        
        echo -e "  ${CYAN}Server IPs:${NC} ${GREEN}$ips_str${NC}"
        echo -e "  ${CYAN}Server Ports:${NC} ${GREEN}$ports_str${NC}"
        echo -e "  ${CYAN}Auth Token:${NC} ${GREEN}${common_token:0:8}...${NC}"
        echo -e "  ${CYAN}Total Proxies:${NC} ${GREEN}$total_proxies${NC}"
        
        # Show per-config details
        echo -e "\n  ${YELLOW}Per-Configuration Details:${NC}"
        for config_file in "${client_configs[@]}"; do
            local ip_suffix=$(basename "$config_file" | sed 's/frpc_//' | sed 's/.toml//')
            local config_ports=()
            local server_ip=""
            
            while IFS= read -r line; do
                if [[ $line =~ localPort\ =\ ([0-9]+) ]]; then
                    config_ports+=("${BASH_REMATCH[1]}")
                elif [[ $line =~ serverAddr\ =\ \"([^\"]+)\" ]]; then
                    server_ip="${BASH_REMATCH[1]}"
                fi
            done < "$config_file"
            
            local ports_list=$(IFS=','; echo "${config_ports[*]}")
            local service_name="moonfrpc-$ip_suffix"
            local service_status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
            local status_icon="❌"
            local status_color="$RED"
            
            [[ "$service_status" == "active" ]] && status_icon="✅" && status_color="$GREEN"
            
            printf "    %-15s -> %-15s [%s] " \
                "Client-$ip_suffix" "$server_ip" "$ports_list"
            echo -e "${status_color}${status_icon}${NC}"
        done
        
        # Connection tests
        echo -e "\n  ${CYAN}🔗 Quick Connection Test:${NC}"
        for ip in "${all_ips[@]}"; do
            for port in "${all_ports[@]}"; do
                printf "    %-20s " "$ip:$port"
                if timeout 2 nc -z "$ip" "$port" 2>/dev/null; then
                    echo -e "${GREEN}✅ OK${NC}"
                else
                    echo -e "${RED}❌ Failed${NC}"
                fi
            done
        done
        
    else
        echo -e "  ${YELLOW}No client configurations found${NC}"
    fi
    
    # System information
    echo -e "\n${GREEN}🖥️  System Information:${NC}"
    echo -e "  ${CYAN}FRP Version:${NC} ${GREEN}v$FRP_VERSION${NC}"
    echo -e "  ${CYAN}MoonFRP Version:${NC} ${GREEN}v$MOONFRP_VERSION${NC}"
    echo -e "  ${CYAN}Config Directory:${NC} ${GREEN}$CONFIG_DIR${NC}"
    echo -e "  ${CYAN}Log Directory:${NC} ${GREEN}$LOG_DIR${NC}"
    
    # Services overview
    local active_services=$(systemctl list-units --type=service --state=active --no-legend --plain 2>/dev/null | grep -E "(moonfrps|moonfrpc)" | wc -l)
    local total_services=$(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | grep -E "(moonfrps|moonfrpc)" | wc -l)
    
    echo -e "  ${CYAN}Services:${NC} ${GREEN}$active_services active${NC} / ${YELLOW}$total_services total${NC}"
    
    echo -e "\n${YELLOW}💡 Quick Actions:${NC}"
    echo -e "  • Restart all: ${GREEN}systemctl restart moonfrp*${NC}"
    echo -e "  • Check logs: ${GREEN}journalctl -u moonfrp* -f${NC}"
    echo -e "  • Stop all: ${GREEN}systemctl stop moonfrp*${NC}"
    
    read -p "Press Enter to continue..."
}

# Fix web panel issues (HTTP 503 and similar)
fix_web_panel_issues() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       FRP Web Panel Diagnostics     ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}🔍 Diagnosing web panel issues...${NC}"
    
    # Check if frps service is running
    local server_running=false
    local dashboard_port=""
    local dashboard_user=""
    local dashboard_password=""
    
    if systemctl status moonfrp-server >/dev/null 2>&1; then
        server_running=true
        echo -e "${GREEN}✅ FRP Server service is running${NC}"
    else
        echo -e "${RED}❌ FRP Server service is NOT running${NC}"
        echo -e "${YELLOW}Attempting to start server...${NC}"
        
        if systemctl status moonfrp-server 2>/dev/null; then
            echo -e "${GREEN}✅ Server started successfully${NC}"
            server_running=true
            sleep 3
        else
            echo -e "${RED}❌ Failed to start server${NC}"
            echo -e "${CYAN}Checking server configuration...${NC}"
        fi
    fi
    
    # Read dashboard configuration from frps.toml
    if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
        echo -e "\n${CYAN}📋 Reading dashboard configuration...${NC}"
        
        while IFS= read -r line; do
            if [[ $line =~ webServer\.port\ *=\ *([0-9]+) ]]; then
                dashboard_port="${BASH_REMATCH[1]}"
            elif [[ $line =~ webServer\.user\ *=\ *\"([^\"]+)\" ]]; then
                dashboard_user="${BASH_REMATCH[1]}"
            elif [[ $line =~ webServer\.password\ *=\ *\"([^\"]+)\" ]]; then
                dashboard_password="${BASH_REMATCH[1]}"
            fi
        done < "$CONFIG_DIR/frps.toml"
        
        if [[ -n "$dashboard_port" ]]; then
            echo -e "  Dashboard Port: ${GREEN}$dashboard_port${NC}"
        else
            echo -e "  Dashboard Port: ${RED}Not configured${NC}"
            dashboard_port="7500"
        fi
        
        if [[ -n "$dashboard_user" ]]; then
            echo -e "  Dashboard User: ${GREEN}$dashboard_user${NC}"
        else
            echo -e "  Dashboard User: ${RED}Not configured${NC}"
            dashboard_user="admin"
        fi
        
        if [[ -n "$dashboard_password" ]]; then
            echo -e "  Dashboard Password: ${GREEN}$dashboard_password${NC}"
        else
            echo -e "  Dashboard Password: ${RED}Not configured${NC}"
            dashboard_password="admin"
        fi
    else
        echo -e "\n${RED}❌ Server configuration file not found: $CONFIG_DIR/frps.toml${NC}"
        echo -e "${YELLOW}Please create server configuration first${NC}"
        return
    fi
    
    # Test dashboard port accessibility
    echo -e "\n${CYAN}🔌 Testing dashboard port accessibility...${NC}"
    
    # Check if port is listening
    if netstat -tlnp 2>/dev/null | grep -q ":$dashboard_port "; then
        echo -e "${GREEN}✅ Port $dashboard_port is listening${NC}"
        
        # Test HTTP connection
        echo -e "${CYAN}🌐 Testing HTTP connection...${NC}"
        
        local test_url="http://127.0.0.1:$dashboard_port"
        local http_status=""
        
        if command -v curl >/dev/null 2>&1; then
            http_status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$test_url" 2>/dev/null || echo "000")
            
            case "$http_status" in
                "200")
                    echo -e "${GREEN}✅ HTTP 200: Dashboard is accessible${NC}"
                    ;;
                "401")
                    echo -e "${YELLOW}⚠️  HTTP 401: Authentication required (Normal)${NC}"
                    ;;
                "403")
                    echo -e "${YELLOW}⚠️  HTTP 403: Access forbidden - check credentials${NC}"
                    ;;
                "503")
                    echo -e "${RED}❌ HTTP 503: Service unavailable - server issue${NC}"
                    ;;
                "000")
                    echo -e "${RED}❌ Connection failed - service not responding${NC}"
                    ;;
                *)
                    echo -e "${YELLOW}⚠️  HTTP $http_status: Unexpected response${NC}"
                    ;;
            esac
        else
            echo -e "${YELLOW}⚠️  curl not available for HTTP testing${NC}"
        fi
        
    else
        echo -e "${RED}❌ Port $dashboard_port is NOT listening${NC}"
        echo -e "${YELLOW}Dashboard service may not be properly configured or started${NC}"
    fi
    
    # Check firewall
    echo -e "\n${CYAN}🔥 Checking firewall status...${NC}"
    
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status 2>/dev/null | grep -E "(Status: active|Status: inactive)" || echo "unknown")
        
        if [[ "$ufw_status" =~ "active" ]]; then
            echo -e "${YELLOW}⚠️  UFW firewall is active${NC}"
            
            if ufw status 2>/dev/null | grep -q "$dashboard_port"; then
                echo -e "${GREEN}✅ Port $dashboard_port is allowed in firewall${NC}"
            else
                echo -e "${RED}❌ Port $dashboard_port is NOT allowed in firewall${NC}"
                echo -e "${CYAN}Suggestion: sudo ufw allow $dashboard_port/tcp${NC}"
            fi
        else
            echo -e "${GREEN}✅ UFW firewall is inactive${NC}"
        fi
    else
        echo -e "${BLUE}ℹ️  UFW not installed, checking iptables...${NC}"
        
        if command -v iptables >/dev/null 2>&1; then
            local iptables_rules=$(iptables -L INPUT -n 2>/dev/null | grep -c "$dashboard_port" || echo "0")
            if [[ "$iptables_rules" -gt 0 ]]; then
                echo -e "${GREEN}✅ Found iptables rules for port $dashboard_port${NC}"
            else
                echo -e "${YELLOW}⚠️  No specific iptables rules found for port $dashboard_port${NC}"
            fi
        fi
    fi
    
    # Show fix options
    echo -e "\n${CYAN}🔧 Available Fixes:${NC}"
    echo "1. Restart FRP Server"
    echo "2. Regenerate Server Configuration"
    echo "3. Open Firewall Port"
    echo "4. Check Service Logs"
    echo "5. Test Dashboard Access"
    echo "6. Show Access Information"
    echo "0. Back"
    
    echo -e "\n${YELLOW}Select fix option [0-6]:${NC} "
    read -r fix_option
    
    case $fix_option in
        1)
            echo -e "\n${CYAN}🔄 Restarting FRP Server...${NC}"
            systemctl status moonfrp-server
            sleep 3
            
            if systemctl status moonfrp-server >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Server restarted successfully${NC}"
                echo -e "${CYAN}Wait 10 seconds then try accessing the dashboard${NC}"
            else
                echo -e "${RED}❌ Failed to restart server${NC}"
                echo -e "${CYAN}Check logs: journalctl -u moonfrp-server -n 20${NC}"
            fi
            ;;
        2)
            echo -e "\n${YELLOW}⚠️  This will regenerate server configuration${NC}"
            echo -e "${YELLOW}Current settings will be backed up${NC}"
            echo -e "\n${YELLOW}Continue? (y/N):${NC} "
            read -r confirm
            
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                # Backup current config
                [[ -f "$CONFIG_DIR/frps.toml" ]] && cp "$CONFIG_DIR/frps.toml" "$CONFIG_DIR/frps.toml.backup.$(date +%s)"
                
                # Regenerate config
                local new_token=$(generate_token)
                generate_frps_config "$new_token" "7000" "$dashboard_port" "$dashboard_user" "$dashboard_password"
                
                # Restart service
                systemctl status moonfrp-server
                
                echo -e "${GREEN}✅ Configuration regenerated and service restarted${NC}"
            fi
            ;;
        3)
            echo -e "\n${CYAN}🔥 Opening firewall port $dashboard_port...${NC}"
            
            if command -v ufw >/dev/null 2>&1; then
                ufw allow "$dashboard_port/tcp"
                echo -e "${GREEN}✅ UFW rule added for port $dashboard_port${NC}"
            elif command -v iptables >/dev/null 2>&1; then
                iptables -A INPUT -p tcp --dport "$dashboard_port" -j ACCEPT
                echo -e "${GREEN}✅ iptables rule added for port $dashboard_port${NC}"
                echo -e "${YELLOW}⚠️  Rule is temporary, save with: iptables-save${NC}"
            else
                echo -e "${YELLOW}⚠️  No supported firewall found${NC}"
            fi
            ;;
        4)
            echo -e "\n${CYAN}📋 Recent server logs:${NC}"
            journalctl -u moonfrp-server -n 20 --no-pager
            ;;
        5)
            echo -e "\n${CYAN}🌐 Testing dashboard access...${NC}"
            
            local server_ip=$(hostname -I | awk '{print $1}')
            local test_urls=(
                "http://127.0.0.1:$dashboard_port"
                "http://localhost:$dashboard_port"
                "http://$server_ip:$dashboard_port"
            )
            
            for url in "${test_urls[@]}"; do
                echo -e "\nTesting: $url"
                
                if command -v curl >/dev/null 2>&1; then
                    local status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "$url" 2>/dev/null || echo "000")
                    case "$status" in
                        "200"|"401") echo -e "  ${GREEN}✅ Accessible (HTTP $status)${NC}" ;;
                        "503") echo -e "  ${RED}❌ Service Unavailable (HTTP 503)${NC}" ;;
                        "000") echo -e "  ${RED}❌ Connection Failed${NC}" ;;
                        *) echo -e "  ${YELLOW}⚠️  HTTP $status${NC}" ;;
                    esac
                else
                    echo -e "  ${YELLOW}⚠️  curl not available for testing${NC}"
                fi
            done
            ;;
        6)
            local server_ip=$(hostname -I | awk '{print $1}')
            echo -e "\n${CYAN}🌐 Dashboard Access Information:${NC}"
            echo -e "${GREEN}URLs to try:${NC}"
            echo -e "  • http://127.0.0.1:$dashboard_port"
            echo -e "  • http://localhost:$dashboard_port"
            echo -e "  • http://$server_ip:$dashboard_port"
            echo -e "  • http://YOUR-PUBLIC-IP:$dashboard_port"
            echo -e "\n${GREEN}Credentials:${NC}"
            echo -e "  Username: ${CYAN}$dashboard_user${NC}"
            echo -e "  Password: ${CYAN}$dashboard_password${NC}"
            echo -e "\n${YELLOW}💡 Notes:${NC}"
            echo -e "  • Make sure firewall allows port $dashboard_port"
            echo -e "  • For public access, use your public IP"
            echo -e "  • Check server logs if still not working"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            ;;
    esac
}

# Main execution function
main() {
    init
    main_menu
}

# Run main function only if script is executed directly
# and not during testing or sourcing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ -z "${MOONFRP_TESTING:-}" ]]; then
    main "$@"
fi