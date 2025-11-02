#!/bin/bash

#==============================================================================
# MoonFRP User Interface
# Version: 2.0.0
# Description: User interface and menu system for MoonFRP
#==============================================================================

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-services.sh"

#==============================================================================
# UI FUNCTIONS
#==============================================================================

# Show header
show_header() {
    local title="$1"
    local subtitle="${2:-}"
    
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC} $(printf "%-34s" "$title") ${PURPLE}║${NC}"
    if [[ -n "$subtitle" ]]; then
        echo -e "${PURPLE}║${NC} $(printf "%-34s" "$subtitle") ${PURPLE}║${NC}"
    fi
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo
}

# Show system status
show_system_status() {
    echo -e "${CYAN}System Status:${NC}"
    echo
    
    # FRP Installation Status
    if check_frp_installation; then
        local frp_version=$(get_frp_version)
        echo -e "${GREEN}✓${NC} FRP $frp_version installed"
    else
        echo -e "${RED}✗${NC} FRP not installed"
    fi
    
    # MoonFRP Version
    echo -e "${GREEN}✓${NC} MoonFRP v$MOONFRP_VERSION"
    
    # Service Status
    echo
    echo -e "${CYAN}Service Status:${NC}"
    list_frp_services
    
    # Configuration Status
    echo
    echo -e "${CYAN}Configuration Status:${NC}"
    if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
        echo -e "${GREEN}✓${NC} Server configuration exists"
    else
        echo -e "${GRAY}○${NC} No server configuration"
    fi
    
    local client_configs=($(find "$CONFIG_DIR" -name "frpc*.toml" -type f | wc -l))
    if [[ $client_configs -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} $client_configs client configuration(s) exist"
    else
        echo -e "${GRAY}○${NC} No client configurations"
    fi
    
    local visitor_configs=($(find "$CONFIG_DIR" -name "visitor*.toml" -type f | wc -l))
    if [[ $visitor_configs -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} $visitor_configs visitor configuration(s) exist"
    else
        echo -e "${GRAY}○${NC} No visitor configurations"
    fi
}

# Quick setup wizard
quick_setup_wizard() {
    show_header "MoonFRP Quick Setup" "Configuration Wizard"
    
    echo -e "${CYAN}This wizard will help you quickly set up MoonFRP.${NC}"
    echo -e "${CYAN}You can press Ctrl+C at any time to cancel.${NC}"
    echo
    
    # Check if FRP is installed
    if ! check_frp_installation; then
        echo -e "${YELLOW}FRP is not installed. Installing now...${NC}"
        install_frp
        if [[ $? -ne 0 ]]; then
            log "ERROR" "Failed to install FRP"
            return 1
        fi
    fi
    
    # Setup type selection
    echo -e "${YELLOW}What would you like to set up?${NC}"
    echo "1. Server (frps) - Run on Iran server"
    echo "2. Client (frpc) - Connect to Iran server"
    echo "3. Multi-IP Client - Connect to multiple servers"
    echo "0. Cancel"
    echo
    
    safe_read "Enter your choice" "setup_type" "1"
    
    case "$setup_type" in
        1)
            quick_server_setup
            ;;
        2)
            quick_client_setup
            ;;
        3)
            quick_multi_ip_setup
            ;;
        0)
            log "INFO" "Setup cancelled"
            return 0
            ;;
        *)
            log "ERROR" "Invalid choice"
            return 1
            ;;
    esac
}

# Quick server setup
quick_server_setup() {
    show_header "Quick Server Setup" "Iran Server Configuration"
    
    echo -e "${CYAN}Setting up FRP server for Iran server...${NC}"
    echo
    
    # Generate server configuration
    local auth_token=$(generate_server_config)
    
    # Setup service
    setup_server_service
    
    # Start service
    start_service "$SERVER_SERVICE"
    
    echo
    echo -e "${GREEN}Server setup complete!${NC}"
    echo -e "${GREEN}Configuration:${NC} $CONFIG_DIR/frps.toml"
    echo -e "${GREEN}Auth Token:${NC} $auth_token"
    echo -e "${GREEN}Dashboard:${NC} http://$DEFAULT_SERVER_BIND_ADDR:$DEFAULT_SERVER_DASHBOARD_PORT"
    echo -e "${GREEN}Username:${NC} $DEFAULT_SERVER_DASHBOARD_USER"
    echo -e "${GREEN}Password:${NC} $(grep 'webServer.password' "$CONFIG_DIR/frps.toml" | cut -d'"' -f2)"
    echo
    echo -e "${YELLOW}Save the auth token - you'll need it for client configurations!${NC}"
    
    read -p "Press Enter to continue..."
}

# Quick client setup
quick_client_setup() {
    show_header "Quick Client Setup" "Foreign Client Configuration"
    
    echo -e "${CYAN}Setting up FRP client to connect to Iran server...${NC}"
    echo
    
    local server_addr server_port auth_token client_user local_ports
    
    safe_read "Iran server IP address" "server_addr" ""
    while ! validate_ip "$server_addr"; do
        log "ERROR" "Invalid IP address"
        safe_read "Iran server IP address" "server_addr" ""
    done
    
    safe_read "Server port" "server_port" "$DEFAULT_SERVER_BIND_PORT"
    while ! validate_port "$server_port"; do
        log "ERROR" "Invalid port number"
        safe_read "Server port" "server_port" "$DEFAULT_SERVER_BIND_PORT"
    done
    
    safe_read "Auth token" "auth_token" ""
    safe_read "Client username" "client_user" "moonfrp"
    safe_read "Local ports to proxy (comma-separated)" "local_ports" "8080,8081"
    
    # Generate client configuration
    generate_client_config "$server_addr" "$server_port" "$auth_token" "$client_user" "" "$local_ports"
    
    # Setup service
    setup_client_service ""
    
    # Start service
    start_service "${CLIENT_SERVICE_PREFIX}"
    
    echo
    echo -e "${GREEN}Client setup complete!${NC}"
    echo -e "${GREEN}Configuration:${NC} $CONFIG_DIR/frpc.toml"
    echo -e "${GREEN}Service:${NC} ${CLIENT_SERVICE_PREFIX}"
    
    read -p "Press Enter to continue..."
}

# Quick multi-IP setup
quick_multi_ip_setup() {
    show_header "Quick Multi-IP Setup" "Multiple Server Configuration"
    
    echo -e "${CYAN}Setting up FRP clients for multiple Iran servers...${NC}"
    echo
    
    local server_ips server_ports client_ports auth_token
    
    safe_read "Server IPs (comma-separated)" "server_ips" ""
    safe_read "Server ports (comma-separated)" "server_ports" "7000,7000,7000"
    safe_read "Client ports (comma-separated)" "client_ports" "8080,8081,8082"
    safe_read "Auth token" "auth_token" ""
    
    # Generate multi-IP configurations
    generate_multi_ip_configs "$server_ips" "$server_ports" "$client_ports" "$auth_token"
    
    # Setup all services
    setup_all_services
    
    # Start all services
    start_all_services
    
    echo
    echo -e "${GREEN}Multi-IP setup complete!${NC}"
    echo -e "${GREEN}Configurations:${NC} $CONFIG_DIR/frpc_*.toml"
    
    read -p "Press Enter to continue..."
}

# Install FRP
install_frp() {
    log "INFO" "Installing FRP v$FRP_VERSION..."
    
    # Determine architecture (prefer environment/CONFIG-provided FRP_ARCH)
    local arch="${FRP_ARCH:-}"
    if [[ -z "$arch" ]]; then
        arch=$(uname -m)
        case $arch in
            x86_64) arch="linux_amd64" ;;
            aarch64) arch="linux_arm64" ;;
            armv7l) arch="linux_armv7" ;;
            *) log "ERROR" "Unsupported architecture: $arch"; return 1 ;;
        esac
    fi
    
    # Download URL
    local download_url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_${arch}.tar.gz"
    local temp_file="$TEMP_DIR/frp_${FRP_VERSION}_${arch}.tar.gz"
    
    # Download FRP
    if ! curl -fsSL "$download_url" -o "$temp_file"; then
        log "ERROR" "Failed to download FRP"
        return 1
    fi
    
    # Extract FRP
    if ! tar -xzf "$temp_file" -C "$TEMP_DIR"; then
        log "ERROR" "Failed to extract FRP"
        return 1
    fi
    
    # Install binaries
    cp "$TEMP_DIR/frp_${FRP_VERSION}_${arch}/frps" "$FRP_DIR/"
    cp "$TEMP_DIR/frp_${FRP_VERSION}_${arch}/frpc" "$FRP_DIR/"
    chmod +x "$FRP_DIR/frps" "$FRP_DIR/frpc"
    
    # Cleanup
    rm -rf "$TEMP_DIR/frp_${FRP_VERSION}_${arch}"
    rm -f "$temp_file"
    
    log "INFO" "FRP v$FRP_VERSION installed successfully"
    return 0
}

# Main menu
main_menu() {
    while true; do
        if [[ "${MENU_STATE["ctrl_c_pressed"]}" == "true" ]]; then
            MENU_STATE["ctrl_c_pressed"]="false"
            return
        fi
        
        show_header "MoonFRP" "Advanced FRP Management Tool"
        
        # Lightweight status summary (2-state)
        echo -e "${CYAN}Status:${NC}"
        if check_frp_installation; then
            echo -e "  FRP: ${GREEN}Active${NC} ($(get_frp_version))"
        else
            echo -e "  FRP: ${RED}Inactive${NC}"
        fi
        # Server service simple state
        if systemctl list-unit-files | grep -q "${SERVER_SERVICE}\.service"; then
            if systemctl is-active --quiet "${SERVER_SERVICE}"; then
                echo -e "  Server: ${GREEN}Active${NC}"
            else
                echo -e "  Server: ${RED}Inactive${NC}"
            fi
        fi
        echo
        
        echo -e "${CYAN}Main Menu:${NC}"
        echo "1. Quick Setup"
        echo "2. Service Management"
        echo "3. Configuration Management"
        echo "4. System Status"
        echo "5. Advanced Tools"
        echo "6. Download & Install FRP v$FRP_VERSION"
        echo "0. Exit"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1)
                quick_setup_wizard
                ;;
            2)
                service_management_menu
                ;;
            3)
                config_wizard
                ;;
            4)
                show_system_status
                read -p "Press Enter to continue..."
                ;;
            5)
                advanced_tools_menu
                ;;
            6)
                show_header "Install FRP" "Download & Install FRP v$FRP_VERSION"
                install_frp
                read -p "Press Enter to continue..."
                ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                log "ERROR" "Invalid choice"
                ;;
        esac
    done
}

# Advanced tools menu
advanced_tools_menu() {
    while true; do
        if [[ "${MENU_STATE["ctrl_c_pressed"]}" == "true" ]]; then
            MENU_STATE["ctrl_c_pressed"]="false"
            return
        fi
        
        show_header "Advanced Tools" "System Utilities"
        
        echo -e "${CYAN}Advanced Tools:${NC}"
        echo "1. Health Check"
        echo "2. View Logs"
        echo "3. Backup Configurations"
        echo "4. Restore Configurations"
        echo "5. Update MoonFRP"
        echo "6. Uninstall MoonFRP"
        echo "0. Back to Main Menu"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1)
                health_check
                read -p "Press Enter to continue..."
                ;;
            2)
                view_logs_menu
                ;;
            3)
                backup_configurations
                read -p "Press Enter to continue..."
                ;;
            4)
                restore_configurations
                read -p "Press Enter to continue..."
                ;;
            5)
                update_moonfrp
                read -p "Press Enter to continue..."
                ;;
            6)
                uninstall_moonfrp
                read -p "Press Enter to continue..."
                ;;
            0)
                return
                ;;
            *)
                log "ERROR" "Invalid choice"
                ;;
        esac
    done
}

# View logs menu
view_logs_menu() {
    show_header "View Logs" "Service Log Viewer"
    
    echo -e "${CYAN}Available Services:${NC}"
    local services=($(systemctl list-unit-files | grep -E "(moonfrp-server|moonfrp-client|moonfrp-visitor)" | awk '{print $1}' | sed 's/.service$//'))
    
    if [[ ${#services[@]} -eq 0 ]]; then
        echo -e "${GRAY}No MoonFRP services found${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    for i in "${!services[@]}"; do
        echo "$((i+1)). ${services[i]}"
    done
    echo "0. Back"
    echo
    
    safe_read "Select service" "choice" "0"
    
    if [[ "$choice" -ge 1 && "$choice" -le ${#services[@]} ]]; then
        local service_name="${services[$((choice-1))]}"
        view_service_logs "$service_name"
    fi
    
    read -p "Press Enter to continue..."
}

# Backup configurations
backup_configurations() {
    show_header "Backup Configurations" "Create Configuration Backup"
    
    local backup_dir="$CONFIG_DIR/backups"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$backup_dir/moonfrp_backup_$timestamp.tar.gz"
    
    mkdir -p "$backup_dir"
    
    if tar -czf "$backup_file" -C "$CONFIG_DIR" .; then
        log "INFO" "Configuration backup created: $backup_file"
    else
        log "ERROR" "Failed to create backup"
    fi
}

# Restore configurations
restore_configurations() {
    show_header "Restore Configurations" "Restore from Backup"
    
    local backup_dir="$CONFIG_DIR/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR" "No backup directory found"
        return 1
    fi
    
    local backups=($(find "$backup_dir" -name "moonfrp_backup_*.tar.gz" -type f | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log "ERROR" "No backups found"
        return 1
    fi
    
    echo -e "${CYAN}Available Backups:${NC}"
    for i in "${!backups[@]}"; do
        local backup_name=$(basename "${backups[i]}")
        local backup_date=$(stat -c %y "${backups[i]}" | cut -d' ' -f1)
        echo "$((i+1)). $backup_name ($backup_date)"
    done
    echo "0. Cancel"
    echo
    
    safe_read "Select backup" "choice" "0"
    
    if [[ "$choice" -ge 1 && "$choice" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((choice-1))]}"
        
        echo -e "${RED}This will overwrite current configurations!${NC}"
        safe_read "Are you sure? (yes/no)" "confirm" "no"
        
        if [[ "$confirm" == "yes" ]]; then
            if tar -xzf "$selected_backup" -C "$CONFIG_DIR"; then
                log "INFO" "Configuration restored from: $selected_backup"
            else
                log "ERROR" "Failed to restore backup"
            fi
        fi
    fi
}

# Update MoonFRP
update_moonfrp() {
    show_header "Update MoonFRP" "Check for Updates"
    
    log "INFO" "Checking for updates..."
    
    # This would typically check GitHub for new releases
    # For now, just show current version
    echo -e "${GREEN}Current version: v$MOONFRP_VERSION${NC}"
    echo -e "${GRAY}Update functionality will be implemented in future versions${NC}"
}

# Uninstall MoonFRP
uninstall_moonfrp() {
    show_header "Uninstall MoonFRP" "Remove MoonFRP Completely"
    
    echo -e "${RED}This will completely remove MoonFRP and all its components!${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    echo
    
    safe_read "Are you sure you want to uninstall? (yes/no)" "confirm" "no"
    
    if [[ "$confirm" == "yes" ]]; then
        log "INFO" "Uninstalling MoonFRP..."
        
        # Stop and remove all services
        remove_all_services
        
        # Remove directories
        rm -rf "$FRP_DIR" "$CONFIG_DIR" "$LOG_DIR" "/etc/moonfrp"
        
        # Remove binaries
        rm -f "/usr/local/bin/moonfrp" "/usr/bin/moonfrp"
        
        log "INFO" "MoonFRP has been completely uninstalled"
    else
        log "INFO" "Uninstall cancelled"
    fi
}

# Export functions
export -f show_header show_system_status quick_setup_wizard
export -f quick_server_setup quick_client_setup quick_multi_ip_setup
export -f install_frp main_menu advanced_tools_menu view_logs_menu
export -f backup_configurations restore_configurations update_moonfrp uninstall_moonfrp