#!/bin/bash

# MoonFRP - Advanced FRP Management Script
# Version: 1.0.0
# Author: MoonFRP Team
# Description: Modular FRP configuration and service management tool

# Use safer bash settings, but allow for graceful error handling
set -uo pipefail

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
    echo -e "\n${YELLOW}[CTRL+C] Returning to main menu...${NC}"
    sleep 1
    # Don't call main_menu recursively, just continue the loop
    return
}

trap signal_handler SIGINT

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

# Generate random token
generate_token() {
    openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '=+/' | cut -c1-32
}

# Generate frps.toml configuration
generate_frps_config() {
    local token="${1:-$(generate_token)}"
    local bind_port="${2:-7000}"
    local dashboard_port="${3:-7500}"
    local dashboard_user="${4:-admin}"
    local dashboard_password="${5:-$(generate_token | cut -c1-12)}"
    
    cat > "$CONFIG_DIR/frps.toml" << EOF
# MoonFRP Server Configuration
# Generated on $(date)

# Basic server settings
bindAddr = "0.0.0.0"
bindPort = $bind_port

# Authentication
auth.method = "token"
auth.token = "$token"

# Dashboard settings
webServer.addr = "0.0.0.0"
webServer.port = $dashboard_port
webServer.user = "$dashboard_user"
webServer.password = "$dashboard_password"

# Logging
log.to = "$LOG_DIR/frps.log"
log.level = "info"
log.maxDays = 7

# HTTP/HTTPS proxy settings
vhostHTTPPort = 80
vhostHTTPSPort = 443

# Transport settings
transport.tls.enable = true
transport.maxPoolCount = 10

# Performance settings
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90

# Additional settings
allowPorts = [
    { start = 2000, end = 3000 },
    { start = 3001, end = 4000 },
    { start = 5000, end = 5500 }
]

# Subdomain settings
subdomainHost = "frp.local"
EOF

    log "INFO" "Generated frps.toml configuration"
    log "INFO" "Dashboard: http://server-ip:$dashboard_port (User: $dashboard_user, Pass: $dashboard_password)"
    log "INFO" "Token: $token"
}

# Generate frpc.toml configuration for multiple IPs
generate_frpc_config() {
    local server_ip="$1"
    local server_port="$2"
    local token="$3"
    local client_ips="$4"
    local ports="$5"
    local ip_suffix="$6"
    
    local config_file="$CONFIG_DIR/frpc_${ip_suffix}.toml"
    
    cat > "$config_file" << EOF
# MoonFRP Client Configuration for IP ending with $ip_suffix
# Generated on $(date)

# Server settings
serverAddr = "$server_ip"
serverPort = $server_port

# Authentication
auth.method = "token"
auth.token = "$token"

# Logging
log.to = "$LOG_DIR/frpc_${ip_suffix}.log"
log.level = "info"
log.maxDays = 7

# Transport settings
transport.tls.enable = true
transport.poolCount = 5
transport.protocol = "tcp"

# Client settings
user = "moonfrp_${ip_suffix}"

# Admin web server (optional)
webServer.addr = "127.0.0.1"
webServer.port = $((7400 + ip_suffix))
webServer.user = "admin"
webServer.password = "admin"

EOF

    # Add proxy configurations for each port
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        cat >> "$config_file" << EOF
[[proxies]]
name = "tcp_${port}_${ip_suffix}"
type = "tcp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port
transport.useEncryption = false
transport.useCompression = false

EOF
    done
    
    log "INFO" "Generated frpc configuration: $config_file"
}

# Create systemd service file
create_systemd_service() {
    local service_name="$1"
    local service_type="$2"  # frps or frpc
    local config_file="$3"
    local ip_suffix="${4:-}"
    
    local service_file="$SERVICE_DIR/${service_name}.service"
    local description="MoonFRP ${service_type^^} Service"
    
    if [[ -n "$ip_suffix" ]]; then
        description="$description (IP suffix: $ip_suffix)"
    fi
    
    cat > "$service_file" << EOF
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

    systemctl daemon-reload
    log "INFO" "Created systemd service: $service_name"
}

# Service management functions
start_service() {
    local service_name="$1"
    systemctl start "$service_name"
    systemctl enable "$service_name"
    log "INFO" "Started and enabled service: $service_name"
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
    
    log "INFO" "FRP installed from local archive successfully"
}

# List all FRP services
list_frp_services() {
    echo -e "\n${CYAN}=== FRP Services Status ===${NC}"
    
    local services=($(systemctl list-units --type=service --all | grep -E "(frps|frpc)" | awk '{print $1}' | sed 's/\.service//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No FRP services found${NC}"
        return
    fi
    
    printf "%-20s %-10s %-15s\n" "Service" "Status" "Type"
    printf "%-20s %-10s %-15s\n" "-------" "------" "----"
    
    for service in "${services[@]}"; do
        local status=$(get_service_status "$service")
        local type="Unknown"
        
        if [[ "$service" =~ frps ]]; then
            type="Server"
        elif [[ "$service" =~ frpc ]]; then
            type="Client"
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
        echo "0. Back to Main Menu"
        
        echo -e "\n${YELLOW}Enter your choice [0-6]:${NC} "
        read -r choice
        
        case $choice in
            1) manage_service_action "start" ;;
            2) manage_service_action "stop" ;;
            3) manage_service_action "restart" ;;
            4) manage_service_action "status" ;;
            5) manage_service_action "logs" ;;
            6) manage_service_action "reload" ;;
            0) return ;;
            *) log "WARN" "Invalid choice. Please try again." ;;
        esac
    done
}

# Service action handler
manage_service_action() {
    local action="$1"
    
    echo -e "\n${CYAN}Available services:${NC}"
    local services=($(systemctl list-units --type=service --all | grep -E "(frps|frpc)" | awk '{print $1}' | sed 's/\.service//'))
    
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
    echo -e "${GREEN}=== Iran Server Configuration ===${NC}"
    
    local token=$(generate_token)
    local bind_port dashboard_port dashboard_user dashboard_password
    
    echo -e "\n${CYAN}Server Settings:${NC}"
    read -p "Bind Port (default: 7000): " bind_port
    [[ -z "$bind_port" ]] && bind_port=7000
    
    read -p "Dashboard Port (default: 7500): " dashboard_port
    [[ -z "$dashboard_port" ]] && dashboard_port=7500
    
    read -p "Dashboard Username (default: admin): " dashboard_user
    [[ -z "$dashboard_user" ]] && dashboard_user="admin"
    
    read -p "Dashboard Password (default: auto-generated): " dashboard_password
    [[ -z "$dashboard_password" ]] && dashboard_password=$(generate_token | cut -c1-12)
    
    # Generate configuration
    generate_frps_config "$token" "$bind_port" "$dashboard_port" "$dashboard_user" "$dashboard_password"
    
    # Create systemd service
    create_systemd_service "moonfrp-server" "frps" "$CONFIG_DIR/frps.toml"
    
    # Start service
    start_service "moonfrp-server"
    
    echo -e "\n${GREEN}✅ Iran server configuration created successfully!${NC}"
    echo -e "${CYAN}Service:${NC} moonfrp-server"
    echo -e "${CYAN}Config:${NC} $CONFIG_DIR/frps.toml"
    echo -e "${CYAN}Dashboard:${NC} http://YOUR-SERVER-IP:$dashboard_port"
    echo -e "${CYAN}Username:${NC} $dashboard_user"
    echo -e "${CYAN}Password:${NC} $dashboard_password"
    echo -e "${CYAN}Token:${NC} $token"
    
    read -p "Press Enter to continue..."
}

# Create foreign client configuration
create_foreign_client_config() {
    clear
    echo -e "${GREEN}=== Foreign Client Configuration ===${NC}"
    
    local server_ips server_port token ports
    
    echo -e "\n${CYAN}Server Connection Settings:${NC}"
    read -p "Iran Server IPs (comma-separated, e.g., 1.1.1.1,2.2.2.2): " server_ips
    
    if [[ -z "$server_ips" ]]; then
        log "ERROR" "Server IPs are required"
        read -p "Press Enter to continue..."
        return
    fi
    
    if ! validate_ips_list "$server_ips"; then
        log "ERROR" "Invalid IP address format"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Server Port (default: 7000): " server_port
    [[ -z "$server_port" ]] && server_port=7000
    
    if ! validate_port "$server_port"; then
        log "ERROR" "Invalid port number"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Authentication Token: " token
    if [[ -z "$token" ]]; then
        log "ERROR" "Authentication token is required"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Ports to forward (comma-separated, e.g., 1111,2222,3333): " ports
    if [[ -z "$ports" ]]; then
        log "ERROR" "Ports are required"
        read -p "Press Enter to continue..."
        return
    fi
    
    if ! validate_ports_list "$ports"; then
        log "ERROR" "Invalid port format"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Process each IP
    IFS=',' read -ra IP_ARRAY <<< "$server_ips"
    local config_count=0
    
    for ip in "${IP_ARRAY[@]}"; do
        ip=$(echo "$ip" | tr -d ' ')
        local ip_suffix=$(echo "$ip" | cut -d'.' -f4)
        
        log "INFO" "Creating configuration for IP: $ip (suffix: $ip_suffix)"
        
        # Generate client configuration
        generate_frpc_config "$ip" "$server_port" "$token" "$ip" "$ports" "$ip_suffix"
        
        # Create systemd service
        create_systemd_service "moonfrp-client-$ip_suffix" "frpc" "$CONFIG_DIR/frpc_${ip_suffix}.toml" "$ip_suffix"
        
        # Start service
        start_service "moonfrp-client-$ip_suffix"
        
        ((config_count++))
    done
    
    echo -e "\n${GREEN}✅ Created $config_count client configurations successfully!${NC}"
    echo -e "${CYAN}Services created:${NC}"
    
    for ip in "${IP_ARRAY[@]}"; do
        ip=$(echo "$ip" | tr -d ' ')
        local ip_suffix=$(echo "$ip" | cut -d'.' -f4)
        echo -e "  - moonfrp-client-$ip_suffix (IP: $ip)"
    done
    
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
    local services=($(systemctl list-units --type=service --all | grep -E "(frps|frpc)" | awk '{print $1}' | sed 's/\.service//'))
    
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
    local services=($(systemctl list-units --type=service --all | grep -E "(frps|frpc)" | awk '{print $1}' | sed 's/\.service//'))
    
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
    if [[ "$service_name" =~ frps ]]; then
        [[ -f "$CONFIG_DIR/frps.toml" ]] && rm -f "$CONFIG_DIR/frps.toml"
    elif [[ "$service_name" =~ frpc ]]; then
        local config_pattern="$CONFIG_DIR/frpc_*.toml"
        for config_file in $config_pattern; do
            [[ -f "$config_file" ]] && rm -f "$config_file"
        done
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    log "INFO" "Removed service: $service_name"
}

# Main menu
main_menu() {
    while true; do
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║            MoonFRP                   ║${NC}"
        echo -e "${PURPLE}║    Advanced FRP Management Tool     ║${NC}"
        echo -e "${PURPLE}║          Version 1.0.0              ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        
        # Show FRP installation status
        if check_frp_installation; then
            echo -e "\n${GREEN}✅ FRP Status: Installed${NC}"
        else
            echo -e "\n${RED}❌ FRP Status: Not Installed${NC}"
        fi
        
        echo -e "\n${CYAN}Main Menu:${NC}"
        echo "1. Create FRP Configuration"
        echo "2. Service Management"
        echo "3. Download & Install FRP v$FRP_VERSION"
        echo "4. Install from Local Archive"
        echo "5. Remove Services"
        echo "0. Exit"
        
        echo -e "\n${YELLOW}Enter your choice [0-5]:${NC} "
        read -r choice
        
        case $choice in
            1) config_creation_menu ;;
            2) service_management_menu ;;
            3) download_and_install_frp ;;
            4) install_from_local ;;
            5) service_removal_menu ;;
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

# Initialize script
init() {
    check_root
    check_dependencies
    create_directories
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