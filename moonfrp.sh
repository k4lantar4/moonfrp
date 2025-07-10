#!/bin/bash

# MoonFRP - Advanced FRP Management Script
# Version: 1.0.1
# Author: MoonFRP Team
# Description: Modular FRP configuration and service management tool

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
MOONFRP_VERSION="1.0.1"
MOONFRP_REPO_URL="https://api.github.com/repos/k4lantar4/moonfrp/releases/latest"
MOONFRP_SCRIPT_URL="https://raw.githubusercontent.com/k4lantar4/moonfrp/main/moonfrp.sh"
MOONFRP_INSTALL_PATH="/usr/bin/moonfrp"

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

# Signal handler for Ctrl+C
signal_handler() {
    echo -e "\n${YELLOW}[CTRL+C] Operation cancelled, returning to main menu...${NC}"
    sleep 1
    # Set flag to break out of current operation
    CTRL_C_PRESSED=true
    return 130  # Standard exit code for SIGINT
}

# Global flag for Ctrl+C detection
CTRL_C_PRESSED=false

# Setup signal trapping
setup_signal_handlers() {
    trap signal_handler SIGINT
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
        
        echo -e "\n${CYAN}0. Back${NC}"
        
        echo -e "\n${YELLOW}Enter your choice [0-4] (default: 1):${NC} "
        read -r choice
        
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
    
    local services=($(systemctl list-units --type=service --state=active | grep -E "(frpc|frps)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "\n${YELLOW}No active FRP services found${NC}"
        read -p "Press Enter to continue..."
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
    read -p "Press Enter to continue..."
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

# Generate random token
generate_token() {
    openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '=+/' | cut -c1-32
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
            echo -e "\n${YELLOW}Found existing FRP client configurations.${NC}"
            echo -e "${CYAN}Choose action:${NC}"
            echo "1. Backup and remove existing configs"
            echo "2. Keep existing configs (may cause conflicts)"
            echo "3. Cancel operation"
            
            read -p "Enter choice [1-3]: " choice
            
            case "$choice" in
                1)
                    cleanup_old_configs "backup"
                    rm -f "$CONFIG_DIR"/frpc_*.toml
                    log "INFO" "Removed existing client configurations"
                    ;;
                2)
                    log "WARN" "Keeping existing configs - conflicts may occur"
                    ;;
                3)
                    log "INFO" "Operation cancelled by user"
                    return 1
                    ;;
                *)
                    log "ERROR" "Invalid choice"
                    return 1
                    ;;
            esac
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
    
    # Validate inputs
    if ! validate_port "$bind_port"; then
        log "ERROR" "Invalid bind port: $bind_port"
        return 1
    fi
    
    if [[ -n "$dashboard_port" ]] && ! validate_port "$dashboard_port"; then
        log "ERROR" "Invalid dashboard port: $dashboard_port"
        return 1
    fi
    
    # Create simple and clean configuration file based on official FRP format
    cat > "$CONFIG_DIR/frps.toml" << EOF
# MoonFRP Server Configuration
# Generated on $(date)

# Basic server settings
bindPort = $bind_port

# Authentication
auth.method = "token"
auth.token = "$token"

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

    # Add remaining settings
    cat >> "$CONFIG_DIR/frps.toml" << EOF
# Logging
log.to = "$LOG_DIR/frps.log"
log.level = "info"
log.maxDays = 7

# Basic port range for client connections
allowPorts = [
    { start = 1000, end = 65535 }
]
EOF
    
    # Verify configuration file was created successfully
    if [[ -f "$CONFIG_DIR/frps.toml" && -s "$CONFIG_DIR/frps.toml" ]]; then
        log "INFO" "Generated simple frps.toml configuration"
        if [[ -n "$dashboard_port" ]]; then
            log "INFO" "Dashboard: http://server-ip:$dashboard_port (User: $dashboard_user, Pass: $dashboard_password)"
        fi
        log "INFO" "Token: $token"
        log "INFO" "Allowed ports: 1000-65535"
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
    
    local config_file="$CONFIG_DIR/frpc_${ip_suffix}.toml"
    local timestamp=$(date +%s)
    
    # Create simple and clean client configuration based on official FRP format
    cat > "$config_file" << EOF
# MoonFRP Client Configuration for IP ending with $ip_suffix
# Generated on $(date)

# Server connection settings
serverAddr = "$server_ip"
serverPort = $server_port

# Authentication
auth.method = "token"
auth.token = "$token"

# Logging (optional)
log.to = "$LOG_DIR/frpc_${ip_suffix}.log"
log.level = "info"
log.maxDays = 7

EOF

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
        *)
            log "WARN" "Unknown proxy type: $proxy_type, defaulting to TCP"
            generate_tcp_proxies_simple "$config_file" "$ports" "$ip_suffix" "$timestamp"
            ;;
    esac
    
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

EOF
    done
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
            # Invalidate services cache
            CACHED_SERVICES=()
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
    log "INFO" "Stopped and disabled service: $service_name"
}

restart_service() {
    local service_name="$1"
    systemctl restart "$service_name"
    log "INFO" "Restarted service: $service_name"
}

get_service_status() {
    local service_name="$1"
    systemctl is-active "$service_name" 2>/dev/null || echo "inactive"
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
    
    # Get latest version from GitHub API
    local latest_info=""
    if latest_info=$(curl -s "$MOONFRP_REPO_URL" 2>/dev/null); then
        local latest_version=$(echo "$latest_info" | grep '"tag_name"' | head -n1 | cut -d'"' -f4 | sed 's/^v//')
        
        if [[ -n "$latest_version" ]]; then
            log "INFO" "Current version: v$MOONFRP_VERSION"
            log "INFO" "Latest version: v$latest_version"
            
            if [[ "$latest_version" != "$MOONFRP_VERSION" ]]; then
                return 0  # Update available
            else
                return 1  # Already up to date
            fi
        else
            log "WARN" "Could not parse version information"
            return 2  # Error parsing
        fi
    else
        log "WARN" "Could not connect to GitHub API"
        return 3  # Connection error
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
            ;;
        2)
            echo -e "\n${RED}❌ Error parsing version information${NC}"
            echo -e "${YELLOW}You can still force update if needed${NC}"
            echo -e "\n${YELLOW}Force update anyway? (y/N):${NC} "
            read -r force_update
            
            if [[ "$force_update" =~ ^[Yy]$ ]]; then
                perform_moonfrp_update
            fi
            ;;
        3)
            echo -e "\n${RED}❌ Cannot connect to GitHub repository${NC}"
            echo -e "${YELLOW}Please check your internet connection${NC}"
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
            # Make executable
            chmod +x "$temp_script"
            
            # Replace current script
            mv "$temp_script" "$MOONFRP_INSTALL_PATH"
            
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
    alias systemctl='systemctl --no-pager --quiet'
}

# List all FRP services with caching
# List all FRP services with caching
list_frp_services() {
    echo -e "\n${CYAN}=== FRP Services Status ===${NC}"
    
    # Cache services list for 5 seconds to improve performance
    local current_time=$(date +%s)
    if [[ ${#CACHED_SERVICES[@]} -eq 0 ]] || [[ $((current_time - SERVICES_CACHE_TIME)) -gt 5 ]]; then
        # More comprehensive service detection
        CACHED_SERVICES=($(systemctl list-units --type=service --all 2>/dev/null | \
            grep -E "(moonfrp|frp)" | \
            grep -v "@" | \
            awk '{print $1}' | \
            sed 's/\.service//' | \
            grep -v "^$" || echo ""))
        SERVICES_CACHE_TIME=$current_time
    fi
    
    local services=("${CACHED_SERVICES[@]}")
    
    # Filter out empty entries
    local filtered_services=()
    for service in "${services[@]}"; do
        [[ -n "$service" && "$service" != " " ]] && filtered_services+=("$service")
    done
    
    if [[ ${#filtered_services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        return
    fi
    
    printf "%-20s %-10s %-15s\n" "Service" "Status" "Type"
    printf "%-20s %-10s %-15s\n" "-------" "------" "----"
    
    for service in "${filtered_services[@]}"; do
        [[ -z "$service" ]] && continue
        
        local status=$(get_service_status "$service")
        local type="Unknown"
        
        if [[ "$service" =~ (frps|moonfrp-server) ]]; then
            type="Server"
        elif [[ "$service" =~ (frpc|moonfrp-client) ]]; then
            type="Client"
        elif [[ "$service" =~ moonfrp ]]; then
            type="MoonFRP"
        fi
        
        local status_color="$RED"
        [[ "$status" == "active" ]] && status_color="$GREEN"
        
        printf "%-20s ${status_color}%-10s${NC} %-15s\n" "$service" "$status" "$type"
    done
}

# Service management menu
service_management_menu() {
    while true; do
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
        echo "8. Remove All Services"
        echo "0. Back to Main Menu"
        
        echo -e "\n${YELLOW}Enter your choice [0-8]:${NC} "
        read -r choice
        
        case $choice in
            1) manage_service_action "start" ;;
            2) manage_service_action "stop" ;;
            3) manage_service_action "restart" ;;
            4) manage_service_action "status" ;;
            5) manage_service_action "logs" ;;
            6) manage_service_action "reload" ;;
            7) remove_single_service ;;
            8) remove_all_services ;;
            0) return ;;
            *) log "WARN" "Invalid choice. Please try again." ;;
        esac
    done
}

# Service action handler
manage_service_action() {
    local action="$1"
    
    echo -e "\n${CYAN}Available services:${NC}"
    local services=($(systemctl list-units --type=service --all | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    local i=1
    for service in "${services[@]}"; do
        echo "$i. $service"
        ((i++))
    done
    
    echo -e "\n${YELLOW}Select service number:${NC} "
    read -r service_num
    
    if [[ ! "$service_num" =~ ^[0-9]+$ ]] || [[ $service_num -lt 1 ]] || [[ $service_num -gt ${#services[@]} ]]; then
        log "ERROR" "Invalid service number"
        read -p "Press Enter to continue..."
        return
    fi
    
    local selected_service="${services[$((service_num-1))]}"
    
    case "$action" in
        "start")
            start_service "$selected_service"
            ;;
        "stop")
            stop_service "$selected_service"
            ;;
        "restart")
            restart_service "$selected_service"
            ;;
        "status")
            echo -e "\n${CYAN}Service Status:${NC}"
            systemctl status "$selected_service"
            ;;
        "logs")
            echo -e "\n${CYAN}Service Logs:${NC}"
            journalctl -u "$selected_service" -n 50 --no-pager
            ;;
        "reload")
            systemctl reload "$selected_service" 2>/dev/null || systemctl restart "$selected_service"
            log "INFO" "Reloaded service: $selected_service"
            ;;
    esac
    
    read -p "Press Enter to continue..."
}

# Configuration creation menu
config_creation_menu() {
    while true; do
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║       Configuration Creator          ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        echo -e "\n${CYAN}Select Server Location:${NC}"
        echo "1. Iran (Server Configuration)"
        echo "2. Foreign (Client Configuration)"
        echo "0. Back to Main Menu"
        
        echo -e "\n${YELLOW}Enter your choice [0-2] (default: 1):${NC} "
        read -r choice
        
        # Default to Iran if no input
        [[ -z "$choice" ]] && choice=1
        
        case $choice in
            1) create_iran_server_config ;;
            2) create_foreign_client_config ;;
            0) return ;;
            *) log "WARN" "Invalid choice. Please try again." ;;
        esac
    done
}

# Create Iran server configuration
create_iran_server_config() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        Iran Server Setup            ║${NC}"
    echo -e "${PURPLE}║     (frps Configuration)             ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    
    local token dashboard_user dashboard_password
    local bind_port=7000
    local dashboard_port=7500
    local enable_dashboard="y"
    
    echo -e "\n${CYAN}🌐 Server Configuration${NC}"
    echo -e "${GRAY}This will create the FRP server configuration for Iran location${NC}"
    
    # Authentication Token
    echo -e "\n${CYAN}🔐 Authentication Settings:${NC}"
    echo -e "${YELLOW}Generate random token automatically? (Y/n):${NC} "
    read -r auto_token
    
    if [[ "$auto_token" =~ ^[Nn]$ ]]; then
        while true; do
            echo -e "${CYAN}Enter custom authentication token (minimum 8 characters):${NC} "
            read -r token
            if [[ ${#token} -ge 8 ]]; then
                break
            else
                echo -e "${RED}❌ Token must be at least 8 characters long${NC}"
            fi
        done
    else
        token=$(generate_token)
        echo -e "${GREEN}✅ Generated secure token: ${token:0:8}...${NC}"
    fi
    
    # Bind Port Configuration
    echo -e "\n${CYAN}🚪 Port Configuration:${NC}"
    while true; do
        echo -e "${CYAN}FRP Server Port (default: 7000):${NC} "
        read -r user_bind_port
        
        if [[ -z "$user_bind_port" ]]; then
            bind_port=7000
            break
        elif validate_port "$user_bind_port"; then
            bind_port="$user_bind_port"
            break
        else
            echo -e "${RED}❌ Invalid port number. Please enter a port between 1-65535${NC}"
        fi
    done
    echo -e "${GREEN}✅ FRP Server Port: $bind_port${NC}"
    
    # Dashboard Configuration
    echo -e "\n${CYAN}📊 Web Dashboard Settings:${NC}"
    echo -e "${YELLOW}Enable web dashboard for monitoring? (Y/n):${NC} "
    read -r enable_dashboard
    
    if [[ ! "$enable_dashboard" =~ ^[Nn]$ ]]; then
        # Dashboard Port
        while true; do
            echo -e "${CYAN}Dashboard Port (default: 7500):${NC} "
            read -r user_dashboard_port
            
            if [[ -z "$user_dashboard_port" ]]; then
                dashboard_port=7500
                break
            elif validate_port "$user_dashboard_port"; then
                if [[ "$user_dashboard_port" == "$bind_port" ]]; then
                    echo -e "${RED}❌ Dashboard port cannot be the same as FRP server port${NC}"
                else
                    dashboard_port="$user_dashboard_port"
                    break
                fi
            else
                echo -e "${RED}❌ Invalid port number${NC}"
            fi
        done
        
        # Dashboard Credentials
        echo -e "${CYAN}Dashboard Username (default: admin):${NC} "
        read -r dashboard_user
        [[ -z "$dashboard_user" ]] && dashboard_user="admin"
        
        echo -e "${CYAN}Dashboard Password (leave empty for auto-generated):${NC} "
        read -r dashboard_password
        [[ -z "$dashboard_password" ]] && dashboard_password=$(generate_token | cut -c1-12)
        
        echo -e "${GREEN}✅ Dashboard enabled on port $dashboard_port${NC}"
    else
        dashboard_port=""
        dashboard_user=""
        dashboard_password=""
        echo -e "${YELLOW}⚠️  Dashboard disabled${NC}"
    fi
    
    # Port Conflict Check
    echo -e "\n${CYAN}🔍 System Check:${NC}"
    local conflicts=0
    
    # Check FRP port
    if netstat -tlnp 2>/dev/null | grep -q ":$bind_port "; then
        echo -e "${RED}❌ Port $bind_port is already in use${NC}"
        ((conflicts++))
    else
        echo -e "${GREEN}✅ Port $bind_port is available${NC}"
    fi
    
    # Check dashboard port if enabled
    if [[ -n "$dashboard_port" ]] && netstat -tlnp 2>/dev/null | grep -q ":$dashboard_port "; then
        echo -e "${RED}❌ Dashboard port $dashboard_port is already in use${NC}"
        ((conflicts++))
    elif [[ -n "$dashboard_port" ]]; then
        echo -e "${GREEN}✅ Dashboard port $dashboard_port is available${NC}"
    fi
    
    # Handle conflicts
    if [[ $conflicts -gt 0 ]]; then
        echo -e "\n${YELLOW}⚠️  Port conflicts detected. Continue anyway? (y/N):${NC} "
        read -r continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log "INFO" "Configuration cancelled due to port conflicts"
            read -p "Press Enter to continue..."
            return
        fi
    fi
    
    # Configuration Summary
    echo -e "\n${CYAN}📋 Configuration Summary:${NC}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${GRAY}│${NC} ${GREEN}FRP Server Port:${NC} $bind_port"
    echo -e "${GRAY}│${NC} ${GREEN}Authentication Token:${NC} ${token:0:8}..."
    if [[ -n "$dashboard_port" ]]; then
        echo -e "${GRAY}│${NC} ${GREEN}Dashboard:${NC} Enabled on port $dashboard_port"
        echo -e "${GRAY}│${NC} ${GREEN}Dashboard User:${NC} $dashboard_user"
        echo -e "${GRAY}│${NC} ${GREEN}Dashboard Pass:${NC} ${dashboard_password:0:4}..."
    else
        echo -e "${GRAY}│${NC} ${YELLOW}Dashboard:${NC} Disabled"
    fi
    echo -e "${GRAY}└─────────────────────────────────────────────────┘${NC}"
    
    echo -e "\n${YELLOW}Proceed with this configuration? (Y/n):${NC} "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log "INFO" "Configuration cancelled by user"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Generate configuration
    echo -e "\n${CYAN}🔧 Generating server configuration...${NC}"
    if generate_frps_config "$token" "$bind_port" "$dashboard_port" "$dashboard_user" "$dashboard_password"; then
        echo -e "${GREEN}✅ Server configuration generated successfully${NC}"
        
        # Verify config file was created
        if [[ -f "$CONFIG_DIR/frps.toml" && -s "$CONFIG_DIR/frps.toml" ]]; then
            echo -e "${GREEN}✅ Configuration file verified: $CONFIG_DIR/frps.toml${NC}"
        else
            echo -e "${RED}❌ Configuration file not found or empty${NC}"
            read -p "Press Enter to continue..."
            return
        fi
        
        # Create systemd service
        echo -e "\n${CYAN}🔧 Creating systemd service...${NC}"
        if create_systemd_service "moonfrp-server" "frps" "$CONFIG_DIR/frps.toml"; then
            echo -e "${GREEN}✅ Service created: moonfrp-server${NC}"
        else
            echo -e "${RED}❌ Failed to create service${NC}"
            read -p "Press Enter to continue..."
            return
        fi
        
        # Start service
        echo -e "\n${CYAN}🚀 Starting service: moonfrp-server${NC}"
        if start_service "moonfrp-server"; then
            echo -e "${GREEN}✅ Service started successfully${NC}"
            
            # Wait a moment and check service status
            sleep 3
            local service_status=$(get_service_status "moonfrp-server")
            if [[ "$service_status" == "active" ]]; then
                echo -e "${GREEN}✅ Service is running properly${NC}"
            else
                echo -e "${YELLOW}⚠️  Service status: $service_status${NC}"
                echo -e "${CYAN}Checking logs for errors...${NC}"
                journalctl -u moonfrp-server -n 5 --no-pager
            fi
        else
            echo -e "${RED}❌ Failed to start service${NC}"
            echo -e "${CYAN}Checking logs for errors...${NC}"
            journalctl -u moonfrp-server -n 10 --no-pager
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
        echo -e "${GREEN}• Service Name:${NC} moonfrp-server"
        echo -e "${GREEN}• Configuration:${NC} $CONFIG_DIR/frps.toml"
        echo -e "${GREEN}• Service Status:${NC} $(get_service_status "moonfrp-server")"
        
        # Get server IP information
        local primary_ip=$(hostname -I | awk '{print $1}')
        local public_ips=""
        for ip in $(hostname -I); do
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                if [[ ! $ip =~ ^10\. ]] && 
                   [[ ! $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && 
                   [[ ! $ip =~ ^192\.168\. ]] && 
                   [[ ! $ip =~ ^127\. ]]; then
                    [[ -z "$public_ips" ]] && public_ips="$ip" || public_ips="$public_ips,$ip"
                fi
            fi
        done
        [[ -z "$public_ips" ]] && public_ips="$primary_ip"
        
        echo -e "\n${CYAN}🌐 Connection Information:${NC}"
        echo -e "${GREEN}• Server IP:${NC} $primary_ip"
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
        echo -e "     ${YELLOW}• Server IP: $primary_ip${NC}"
        echo -e "     ${YELLOW}• Server Port: $bind_port${NC}"
        echo -e "     ${YELLOW}• Token: $token${NC}"
        
        echo -e "\n${CYAN}🔧 Management Commands:${NC}"
        echo -e "  • Check status: ${GREEN}systemctl status moonfrp-server${NC}"
        echo -e "  • View logs: ${GREEN}journalctl -u moonfrp-server -f${NC}"
        echo -e "  • Restart: ${GREEN}systemctl restart moonfrp-server${NC}"
        
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
        
        local proxy_choice=""
        while true; do
            echo -e "${CYAN}Choose proxy type [1-4] (default: 1):${NC} "
            read -r proxy_choice
            [[ -z "$proxy_choice" ]] && proxy_choice=1
            
            case $proxy_choice in
                1) proxy_type="tcp"; echo -e "${GREEN}✅ TCP proxy selected${NC}"; break ;;
                2) proxy_type="http"; echo -e "${GREEN}✅ HTTP proxy selected${NC}"; break ;;
                3) proxy_type="https"; echo -e "${GREEN}✅ HTTPS proxy selected${NC}"; break ;;
                4) proxy_type="udp"; echo -e "${GREEN}✅ UDP proxy selected${NC}"; break ;;
                *) echo -e "${RED}❌ Please enter 1, 2, 3, or 4${NC}" ;;
            esac
        done
    fi
    
    # Custom domains for HTTP/HTTPS
    local custom_domains=""
    if [[ "$proxy_type" == "http" || "$proxy_type" == "https" ]]; then
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
    echo -e "${GRAY}│${NC} ${GREEN}Ports:${NC} $ports"
    if [[ -n "$custom_domains" ]]; then
        echo -e "${GRAY}│${NC} ${GREEN}Domains:${NC} $custom_domains"
    fi
    echo -e "${GRAY}└─────────────────────────────────────────────────┘${NC}"
    
    echo -e "\n${YELLOW}Proceed with this configuration? (Y/n):${NC} "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log "INFO" "Configuration cancelled by user"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Check for existing configurations
    if ls "$CONFIG_DIR"/frpc_*.toml 1> /dev/null 2>&1; then
        echo -e "\n${YELLOW}⚠️  Existing client configurations detected${NC}"
        echo -e "${CYAN}What would you like to do?${NC}"
        echo "1. Keep existing and add new configurations"
        echo "2. Remove all existing configurations first"
        echo "3. Cancel operation"
        
        local cleanup_choice=""
        while true; do
            echo -e "${YELLOW}Enter choice [1-3]:${NC} "
            read -r cleanup_choice
            
            case $cleanup_choice in
                1) break ;;
                2) 
                    if cleanup_old_configs "remove"; then
                        echo -e "${GREEN}✅ Existing configurations removed${NC}"
                        break
                    else
                        read -p "Press Enter to continue..."
                        return
                    fi
                    ;;
                3) 
                    log "INFO" "Operation cancelled by user"
                    read -p "Press Enter to continue..."
                    return
                    ;;
                *) echo -e "${RED}❌ Please enter 1, 2, or 3${NC}" ;;
            esac
        done
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
        if generate_frpc_config "$ip" "$server_port" "$token" "$ip" "$ports" "$ip_suffix" "$proxy_type" "$custom_domains"; then
            echo -e "${GREEN}✅ Configuration generated${NC}"
            
            # Validate the generated configuration
            if validate_frp_config "$CONFIG_DIR/frpc_${ip_suffix}.toml"; then
                echo -e "${GREEN}✅ Configuration validation passed${NC}"
            else
                echo -e "${YELLOW}⚠️  Configuration validation failed, but proceeding...${NC}"
            fi
            
            # Create systemd service
            if create_systemd_service "moonfrp-client-$ip_suffix" "frpc" "$CONFIG_DIR/frpc_${ip_suffix}.toml" "$ip_suffix"; then
                echo -e "${GREEN}✅ Service created: moonfrp-client-$ip_suffix${NC}"
            else
                echo -e "${RED}❌ Failed to create service${NC}"
                ((failed_count++))
                continue
            fi
            
            # Start service
            if start_service "moonfrp-client-$ip_suffix"; then
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
            local service_name="moonfrp-client-$ip_suffix"
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
            esac
        done
        
        echo -e "\n${CYAN}🔧 Management Commands:${NC}"
        echo -e "  • Check all services: ${GREEN}systemctl status moonfrp-client-*${NC}"
        echo -e "  • View logs: ${GREEN}journalctl -u moonfrp-client-* -f${NC}"
        echo -e "  • Restart all: ${GREEN}systemctl restart moonfrp-client-*${NC}"
        echo -e "  • Stop all: ${GREEN}systemctl stop moonfrp-client-*${NC}"
        
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

# Remove single service
remove_single_service() {
    local services=($(systemctl list-units --type=service --all | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
    
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
        log "ERROR" "Invalid service number"
        read -p "Press Enter to continue..."
        return
    fi
    
    local selected_service="${services[$((service_num-1))]}"
    
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

# Remove all services
remove_all_services() {
    local services=($(systemctl list-units --type=service --all | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "\n${RED}Are you sure you want to remove ALL FRP services? This cannot be undone! (y/N):${NC} "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for service in "${services[@]}"; do
            remove_service "$service"
        done
        log "INFO" "All FRP services removed successfully"
    else
        log "INFO" "Service removal cancelled"
    fi
    
    read -p "Press Enter to continue..."
}

# Remove service function
remove_service() {
    local service_name="$1"
    
    # Stop and disable service
    stop_service "$service_name"
    
    # Remove service file
    local service_file="$SERVICE_DIR/${service_name}.service"
    [[ -f "$service_file" ]] && rm -f "$service_file"
    
    # Remove configuration file
    if [[ "$service_name" =~ (frps|moonfrps) ]]; then
        [[ -f "$CONFIG_DIR/frps.toml" ]] && rm -f "$CONFIG_DIR/frps.toml"
    elif [[ "$service_name" =~ (frpc|moonfrpc) ]]; then
        local config_pattern="$CONFIG_DIR/frpc_*.toml"
        for config_file in $config_pattern; do
            [[ -f "$config_file" ]] && rm -f "$config_file"
        done
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    # Invalidate services cache
    CACHED_SERVICES=()
    
    log "INFO" "Removed service: $service_name"
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
    
    while true; do
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
        echo "0. Exit"
        
        # Show performance info in debug mode
        if [[ "${DEBUG:-}" == "1" ]]; then
            echo -e "\n${GRAY}[Debug] Menu load time: $(date +%T) | Services cached: ${#CACHED_SERVICES[@]} | FRP status: $FRP_INSTALLATION_STATUS${NC}"
        fi
        
        echo -e "\n${YELLOW}Enter your choice [0-7]:${NC} "
        read -r choice
        
        case $choice in
            1) config_creation_menu ;;
            2) service_management_menu ;;
            3) download_and_install_frp ;;
            4) install_from_local ;;
            5) troubleshooting_menu ;;
            6) update_moonfrp_script ;;
            7) show_about_info ;;
            0) 
                echo -e "\n${GREEN}Thank you for using MoonFRP! 🚀${NC}"
                cleanup_and_exit
                ;;
            *) log "WARN" "Invalid choice. Please try again." ;;
        esac
        
        # Pause after each action (except menu navigation)
        [[ "$choice" =~ ^[3-4]$ ]] && read -p "Press Enter to continue..."
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

# Main execution
main() {
    init
    main_menu
}

# Run main function
main "$@" 

# Troubleshooting and diagnostics menu
troubleshooting_menu() {
    while true; do
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
        
        case $choice in
            1) check_all_proxy_conflicts ;;
            2) check_all_port_conflicts ;;
            3) validate_all_connections ;;
            4) view_service_logs_menu ;;
            5) fix_common_issues ;;
            6) generate_diagnostic_report ;;
            7) show_quick_help ;;
            8) fix_web_panel_issues ;;
            9) monitor_all_proxies ;;
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
    
    read -p "Press Enter to continue..."
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
    
    read -p "Press Enter to continue..."
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
    echo -e "  Success rate: $(( (servers_checked - servers_failed) * 100 / servers_checked ))%"
    
    read -p "Press Enter to continue..."
}

# View service logs
view_service_logs_menu() {
    clear
    echo -e "${CYAN}📋 Service Logs Viewer${NC}"
    
    local services=($(systemctl list-units --type=service --all | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        read -p "Press Enter to continue..."
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
    
    read -p "Press Enter to continue..."
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
            local services=($(systemctl list-units --type=service --all | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'))
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
    
    read -p "Press Enter to continue..."
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
        systemctl list-units --type=service --all | grep -E "(moonfrp|frp)" || echo "No FRP services found"
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
        for service in $(systemctl list-units --type=service --all | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//'); do
            echo "--- $service ---"
            journalctl -u "$service" -n 5 --no-pager 2>/dev/null || echo "No logs found"
            echo
        done
        
    } > "$report_file"
    
    log "INFO" "Diagnostic report saved to: $report_file"
    echo -e "\n${CYAN}Report preview:${NC}"
    head -30 "$report_file"
    echo -e "\n${YELLOW}... (truncated, see full report in file)${NC}"
    
    read -p "Press Enter to continue..."
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
    local services=($(systemctl list-units --type=service --all 2>/dev/null | grep -E "(moonfrp|frp)" | awk '{print $1}' | sed 's/\.service//' || echo ""))
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
        read -p "Press Enter to continue..."
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
    
    read -p "Press Enter to continue..."
} 