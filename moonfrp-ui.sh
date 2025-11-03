#!/bin/bash

#==============================================================================
# MoonFRP User Interface
# Version: 2.0.0
# Description: User interface and menu system for MoonFRP
#==============================================================================

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-index.sh"
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
    
    check_and_update_index 2>/dev/null || true
    
    # Use indexed queries with fallback
    local server_count=0
    local client_count=0
    local server_result
    if server_result=$(query_configs_by_type "server" 2>/dev/null); then
        [[ -n "$server_result" ]] && server_count=$(echo "$server_result" | wc -l)
    else
        [[ -f "$CONFIG_DIR/frps.toml" ]] && server_count=1
    fi
    
    local client_result
    if client_result=$(query_configs_by_type "client" 2>/dev/null); then
        [[ -n "$client_result" ]] && client_count=$(echo "$client_result" | wc -l)
    else
        client_count=$(find "$CONFIG_DIR" -name "frpc*.toml" -type f 2>/dev/null | wc -l)
    fi
    
    if [[ $server_count -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} $server_count server configuration(s) exist"
    else
        echo -e "${GRAY}○${NC} No server configuration"
    fi
    
    if [[ $client_count -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} $client_count client configuration(s) exist"
    else
        echo -e "${GRAY}○${NC} No client configurations"
    fi
    
    local visitor_configs=($(find "$CONFIG_DIR" -name "visitor*.toml" -type f 2>/dev/null | wc -l))
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
        
        # Display cached status (Story 3.1)
        display_cached_status
        echo
        
        echo -e "${CYAN}Main Menu:${NC}"
        echo "1. Quick Setup"
        echo "2. Service Management"
        echo "3. Configuration Management"
        echo "4. System Status"
        echo "5. Search & Filter"
        echo "6. Advanced Tools"
        echo "7. Download & Install FRP v$FRP_VERSION"
        echo "r. Refresh Status"
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
                show_config_details
                ;;
            5)
                search_filter_menu
                ;;
            6)
                advanced_tools_menu
                ;;
            7)
                show_header "Install FRP" "Download & Install FRP v$FRP_VERSION"
                install_frp
                read -p "Press Enter to continue..."
                ;;
            r|R)
                # Manual refresh (Story 3.1)
                refresh_status_cache_sync
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
        echo "3. Tag Management"
        echo "4. Backup Configurations"
        echo "5. Restore Configurations"
        echo "6. Update MoonFRP"
        echo "7. Uninstall MoonFRP"
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
                tag_management_menu
                ;;
            4)
                backup_configurations
                read -p "Press Enter to continue..."
                ;;
            5)
                restore_configurations
                read -p "Press Enter to continue..."
                ;;
            6)
                update_moonfrp
                read -p "Press Enter to continue..."
                ;;
            7)
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

#==============================================================================
# ENHANCED CONFIG DETAILS VIEW (Story 3.3)
#==============================================================================

# Show enhanced config details with server grouping
show_config_details() {
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║$(printf "%63s" "MoonFRP Configuration Summary")║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    local db_path="$HOME/.moonfrp/index.db"
    
    # Check if index exists
    if [[ ! -f "$db_path" ]]; then
        log "ERROR" "Config index not found. Please initialize index first."
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Query index for all configs
    local configs
    configs=($(sqlite3 "$db_path" "SELECT file_path FROM config_index ORDER BY config_type, server_addr" 2>/dev/null || echo ""))
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No configurations found in index.${NC}"
        echo
        read -p "Press Enter to continue..."
        return 0
    fi
    
    # Group by server IP
    declare -A server_groups
    
    for config in "${configs[@]}"; do
        local escaped_path=$(printf '%s\n' "$config" | sed "s/'/''/g")
        local server_addr
        server_addr=$(sqlite3 "$db_path" "SELECT server_addr FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
        
        if [[ -z "$server_addr" ]]; then
            server_addr="server"
        fi
        
        server_groups["$server_addr"]+="$config "
    done
    
    # Display grouped configs (sorted by server IP)
    local sorted_servers
    sorted_servers=($(printf '%s\n' "${!server_groups[@]}" | sort))
    
    for server_ip in "${sorted_servers[@]}"; do
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}🖥️  Server: $server_ip${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local configs_for_server
        configs_for_server=(${server_groups[$server_ip]})
        
        for config in "${configs_for_server[@]}"; do
            display_config_summary "$config" "$db_path"
        done
        
        echo
    done
    
    # Overall statistics
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📊 Overall Statistics${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local total_configs
    total_configs=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index" 2>/dev/null || echo "0")
    local total_proxies
    total_proxies=$(sqlite3 "$db_path" "SELECT COALESCE(SUM(proxy_count), 0) FROM config_index" 2>/dev/null || echo "0")
    local unique_servers
    unique_servers=$(sqlite3 "$db_path" "SELECT COUNT(DISTINCT server_addr) FROM config_index WHERE server_addr IS NOT NULL AND server_addr != ''" 2>/dev/null || echo "0")
    
    echo "  Total Configs: $total_configs"
    echo "  Total Proxies: $total_proxies"
    echo "  Unique Servers: $unique_servers"
    echo
    
    # Export options menu
    echo -e "${CYAN}Options:${NC}"
    echo "1. Export to text file"
    echo "2. Export to JSON"
    echo "3. Export to YAML"
    echo "4. Run connection tests"
    echo "0. Back"
    echo
    
    safe_read "Enter your choice" "choice" "0"
    
    case "$choice" in
        1)
            export_config_summary "text"
            ;;
        2)
            export_config_summary "json"
            ;;
        3)
            export_config_summary "yaml"
            ;;
        4)
            # Check if run_connection_tests_all exists (Story 3.4)
            if command -v run_connection_tests_all &>/dev/null || type run_connection_tests_all &>/dev/null 2>&1; then
                run_connection_tests_all
            else
                log "WARN" "Connection testing not available. Story 3.4 not yet implemented."
                read -p "Press Enter to continue..."
            fi
            ;;
        0)
            return
            ;;
        *)
            log "ERROR" "Invalid choice"
            ;;
    esac
}

# Display individual config summary
display_config_summary() {
    local config="$1"
    local db_path="${2:-$HOME/.moonfrp/index.db}"
    
    if [[ ! -f "$config" ]]; then
        return 1
    fi
    
    local escaped_path=$(printf '%s\n' "$config" | sed "s/'/''/g")
    
    local config_type
    config_type=$(sqlite3 "$db_path" "SELECT config_type FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
    local server_addr
    server_addr=$(sqlite3 "$db_path" "SELECT server_addr FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
    local server_port
    server_port=$(sqlite3 "$db_path" "SELECT server_port FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
    local bind_port
    bind_port=$(sqlite3 "$db_path" "SELECT bind_port FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
    local proxy_count
    proxy_count=$(sqlite3 "$db_path" "SELECT COALESCE(proxy_count, 0) FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "0")
    
    # Get auth token from TOML file (masked)
    local auth_token
    auth_token=$(get_toml_value "$config" "auth.token" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    
    local config_name
    config_name=$(basename "$config" .toml)
    
    # Get service status
    local service_name="moonfrp-${config_name}"
    local service_status
    if systemctl list-unit-files | grep -q "${service_name}\.service"; then
        service_status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
    else
        service_status="inactive"
    fi
    
    # Status icon
    local status_icon
    case "$service_status" in
        active)
            status_icon="${GREEN}●${NC}"
            ;;
        failed)
            status_icon="${RED}●${NC}"
            ;;
        *)
            status_icon="${GRAY}○${NC}"
            ;;
    esac
    
    echo "  $status_icon $config_name"
    echo "     Type: $config_type"
    
    if [[ "$config_type" == "client" ]]; then
        if [[ -n "$server_addr" ]] && [[ -n "$server_port" ]]; then
            echo "     Server: $server_addr:$server_port"
        elif [[ -n "$server_addr" ]]; then
            echo "     Server: $server_addr"
        fi
        if [[ "$proxy_count" -gt 0 ]]; then
            echo "     Proxies: $proxy_count"
        fi
    elif [[ "$config_type" == "server" ]]; then
        if [[ -n "$bind_port" ]]; then
            echo "     Bind Port: $bind_port"
        fi
    fi
    
    # Masked token display
    if [[ -n "$auth_token" ]] && [[ ${#auth_token} -gt 12 ]]; then
        local token_display="${auth_token:0:8}...${auth_token: -4}"
        echo "     Token: $token_display"
    elif [[ -n "$auth_token" ]]; then
        echo "     Token: ${auth_token:0:8}..."
    fi
    
    # Tags (from Story 2.3)
    if command -v list_config_tags &>/dev/null || type list_config_tags &>/dev/null 2>&1; then
        local tags
        tags=$(list_config_tags "$config" 2>/dev/null || echo "")
        if [[ -n "$tags" ]]; then
            # Format tags as comma-separated key:value pairs
            # list_config_tags returns colon-separated pairs on multiple lines
            local formatted_tags
            formatted_tags=$(echo "$tags" | awk -F: '{if(NR>1) printf ","; printf "%s:%s", $1, $2}' 2>/dev/null | head -c 100 || echo "")
            if [[ -n "$formatted_tags" ]]; then
                echo "     Tags: $formatted_tags"
            fi
        fi
    fi
}

# Export config summary to file
export_config_summary() {
    local format="$1"
    local output_dir="$HOME/.moonfrp"
    local output_file="$output_dir/config-summary.${format}"
    
    mkdir -p "$output_dir"
    
    case "$format" in
        text)
            # Regenerate content without interactive menu
            {
                echo "MoonFRP Configuration Summary"
                echo "Generated: $(date)"
                echo ""
                
                local db_path="$HOME/.moonfrp/index.db"
                if [[ -f "$db_path" ]]; then
                    local configs
                    configs=($(sqlite3 "$db_path" "SELECT file_path FROM config_index ORDER BY config_type, server_addr" 2>/dev/null || echo ""))
                    
                    if [[ ${#configs[@]} -gt 0 ]]; then
                        declare -A server_groups
                        
                        for config in "${configs[@]}"; do
                            local escaped_path=$(printf '%s\n' "$config" | sed "s/'/''/g")
                            local server_addr
                            server_addr=$(sqlite3 "$db_path" "SELECT server_addr FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
                            
                            if [[ -z "$server_addr" ]]; then
                                server_addr="server"
                            fi
                            
                            server_groups["$server_addr"]+="$config "
                        done
                        
                        local sorted_servers
                        sorted_servers=($(printf '%s\n' "${!server_groups[@]}" | sort))
                        
                        for server_ip in "${sorted_servers[@]}"; do
                            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                            echo "🖥️  Server: $server_ip"
                            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                            
                            local configs_for_server
                            configs_for_server=(${server_groups[$server_ip]})
                            
                            for config in "${configs_for_server[@]}"; do
                                display_config_summary "$config" "$db_path" | sed 's/\x1b\[[0-9;]*m//g'
                            done
                            
                            echo ""
                        done
                        
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        echo "📊 Overall Statistics"
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        
                        local total_configs
                        total_configs=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index" 2>/dev/null || echo "0")
                        local total_proxies
                        total_proxies=$(sqlite3 "$db_path" "SELECT COALESCE(SUM(proxy_count), 0) FROM config_index" 2>/dev/null || echo "0")
                        local unique_servers
                        unique_servers=$(sqlite3 "$db_path" "SELECT COUNT(DISTINCT server_addr) FROM config_index WHERE server_addr IS NOT NULL AND server_addr != ''" 2>/dev/null || echo "0")
                        
                        echo "  Total Configs: $total_configs"
                        echo "  Total Proxies: $total_proxies"
                        echo "  Unique Servers: $unique_servers"
                    fi
                fi
            } > "$output_file"
            ;;
        json)
            # JSON export using sqlite3 -json flag
            local db_path="$HOME/.moonfrp/index.db"
            if [[ -f "$db_path" ]]; then
                sqlite3 "$db_path" -json "SELECT * FROM config_index ORDER BY config_type, server_addr" > "$output_file" 2>/dev/null || echo "[]" > "$output_file"
            else
                echo "[]" > "$output_file"
            fi
            ;;
        yaml)
            # YAML export with server grouping
            local db_path="$HOME/.moonfrp/index.db"
            {
                echo "---"
                echo "# MoonFRP Configuration Summary"
                echo "# Generated: $(date)"
                echo ""
                
                if [[ -f "$db_path" ]]; then
                    local configs
                    configs=($(sqlite3 "$db_path" "SELECT file_path FROM config_index ORDER BY config_type, server_addr" 2>/dev/null || echo ""))
                    
                    if [[ ${#configs[@]} -gt 0 ]]; then
                        declare -A server_groups
                        
                        # Group configs by server
                        for config in "${configs[@]}"; do
                            local escaped_path=$(printf '%s\n' "$config" | sed "s/'/''/g")
                            local server_addr
                            server_addr=$(sqlite3 "$db_path" "SELECT server_addr FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
                            
                            if [[ -z "$server_addr" ]]; then
                                server_addr="server"
                            fi
                            
                            server_groups["$server_addr"]+="$config "
                        done
                        
                        # Sort servers for consistent output
                        local sorted_servers
                        sorted_servers=($(printf '%s\n' "${!server_groups[@]}" | sort))
                        
                        echo "servers:"
                        
                        for server_ip in "${sorted_servers[@]}"; do
                            echo "  - server_ip: \"$server_ip\""
                            echo "    configs:"
                            
                            local configs_for_server
                            configs_for_server=(${server_groups[$server_ip]})
                            
                            for config in "${configs_for_server[@]}"; do
                                local escaped_path=$(printf '%s\n' "$config" | sed "s/'/''/g")
                                
                                local config_type
                                config_type=$(sqlite3 "$db_path" "SELECT config_type FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
                                local server_addr
                                server_addr=$(sqlite3 "$db_path" "SELECT server_addr FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
                                local server_port
                                server_port=$(sqlite3 "$db_path" "SELECT server_port FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
                                local bind_port
                                bind_port=$(sqlite3 "$db_path" "SELECT bind_port FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "")
                                local proxy_count
                                proxy_count=$(sqlite3 "$db_path" "SELECT COALESCE(proxy_count, 0) FROM config_index WHERE file_path='$escaped_path'" 2>/dev/null || echo "0")
                                
                                local config_name
                                config_name=$(basename "$config" .toml)
                                
                                # Get auth token from TOML file (masked)
                                local auth_token
                                auth_token=$(get_toml_value "$config" "auth.token" 2>/dev/null | sed 's/["'\'']//g' || echo "")
                                local token_masked=""
                                if [[ -n "$auth_token" ]] && [[ ${#auth_token} -gt 12 ]]; then
                                    token_masked="${auth_token:0:8}...${auth_token: -4}"
                                elif [[ -n "$auth_token" ]]; then
                                    token_masked="${auth_token:0:8}..."
                                fi
                                
                                # Get service status
                                local service_name="moonfrp-${config_name}"
                                local service_status="inactive"
                                if systemctl list-unit-files 2>/dev/null | grep -q "${service_name}\.service"; then
                                    service_status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
                                fi
                                
                                echo "      - name: \"$config_name\""
                                echo "        type: \"$config_type\""
                                
                                if [[ "$config_type" == "client" ]]; then
                                    if [[ -n "$server_addr" ]]; then
                                        echo "        server_addr: \"$server_addr\""
                                    fi
                                    if [[ -n "$server_port" ]]; then
                                        echo "        server_port: $server_port"
                                    fi
                                    if [[ "$proxy_count" -gt 0 ]]; then
                                        echo "        proxy_count: $proxy_count"
                                    fi
                                elif [[ "$config_type" == "server" ]]; then
                                    if [[ -n "$bind_port" ]]; then
                                        echo "        bind_port: $bind_port"
                                    fi
                                fi
                                
                                if [[ -n "$token_masked" ]]; then
                                    echo "        token_masked: \"$token_masked\""
                                fi
                                
                                echo "        service_status: \"$service_status\""
                                
                                # Get tags (from Story 2.3)
                                if command -v list_config_tags &>/dev/null || type list_config_tags &>/dev/null 2>&1; then
                                    local tags
                                    tags=$(list_config_tags "$config" 2>/dev/null || echo "")
                                    if [[ -n "$tags" ]]; then
                                        echo "        tags:"
                                        # Convert tags to YAML list format
                                        echo "$tags" | while IFS= read -r tag_line; do
                                            if [[ -n "$tag_line" ]] && [[ "$tag_line" =~ ^([^:]+):(.+)$ ]]; then
                                                echo "          - \"$tag_line\""
                                            fi
                                        done
                                    fi
                                fi
                                
                                echo ""
                            done
                        done
                        
                        # Overall statistics
                        local total_configs
                        total_configs=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index" 2>/dev/null || echo "0")
                        local total_proxies
                        total_proxies=$(sqlite3 "$db_path" "SELECT COALESCE(SUM(proxy_count), 0) FROM config_index" 2>/dev/null || echo "0")
                        local unique_servers
                        unique_servers=$(sqlite3 "$db_path" "SELECT COUNT(DISTINCT server_addr) FROM config_index WHERE server_addr IS NOT NULL AND server_addr != ''" 2>/dev/null || echo "0")
                        
                        echo "statistics:"
                        echo "  total_configs: $total_configs"
                        echo "  total_proxies: $total_proxies"
                        echo "  unique_servers: $unique_servers"
                    else
                        echo "servers: []"
                        echo "statistics:"
                        echo "  total_configs: 0"
                        echo "  total_proxies: 0"
                        echo "  unique_servers: 0"
                    fi
                else
                    echo "servers: []"
                    echo "statistics:"
                    echo "  total_configs: 0"
                    echo "  total_proxies: 0"
                    echo "  unique_servers: 0"
                fi
            } > "$output_file"
            ;;
        *)
            log "ERROR" "Unsupported export format: $format"
            return 1
            ;;
    esac
    
    log "INFO" "Config summary exported: $output_file"
    read -p "Press Enter to continue..."
}

#==============================================================================
# CACHED STATUS DISPLAY (Story 3.1)
#==============================================================================

# Cache management
# STATUS_CACHE is a global associative array for in-memory cache
# File-based cache persists across processes in $HOME/.moonfrp/
declare -A STATUS_CACHE

# Initialize STATUS_CACHE if not already initialized
# Cache structure: timestamp, data, ttl, refreshing
# TTL is configurable via STATUS_CACHE_TTL environment variable (default: 5 seconds)
init_status_cache() {
    if [[ -z "${STATUS_CACHE["timestamp"]:-}" ]]; then
        STATUS_CACHE["timestamp"]=0
        STATUS_CACHE["data"]=""
        # TTL is configurable via environment variable or config value, default to 5 seconds
        # Prefer STATUS_CACHE_TTL, fallback to MOONFRP_STATUS_TTL if provided in sourced config
        local __ttl__="${STATUS_CACHE_TTL:-${MOONFRP_STATUS_TTL:-5}}"
        # Ensure ttl is a positive integer; fallback to 5 if invalid
        if [[ ! "$__ttl__" =~ ^[0-9]+$ ]] || [[ "$__ttl__" -le 0 ]]; then
            __ttl__=5
        fi
        STATUS_CACHE["ttl"]="$__ttl__"
        STATUS_CACHE["refreshing"]="false"
    fi
    
    # Ensure cache directory exists
    mkdir -p "$HOME/.moonfrp"
    
    # Load from file cache if available and in-memory cache is empty
    local cache_file="$HOME/.moonfrp/status.cache"
    local timestamp_file="$HOME/.moonfrp/status.cache.timestamp"
    
    if [[ -f "$cache_file" ]] && [[ -f "$timestamp_file" ]]; then
        local file_timestamp=$(cat "$timestamp_file" 2>/dev/null || echo "0")
        if [[ -z "${STATUS_CACHE["data"]}" ]] || [[ "${STATUS_CACHE["timestamp"]}" -lt "$file_timestamp" ]]; then
            STATUS_CACHE["data"]=$(cat "$cache_file" 2>/dev/null || echo "")
            STATUS_CACHE["timestamp"]="$file_timestamp"
        fi
    fi
}

# Get cached status - returns JSON string
# Checks cache age vs TTL, returns fresh cache or triggers refresh
get_cached_status() {
    init_status_cache
    
    # Check for background refresh errors
    local error_file="$HOME/.moonfrp/status.cache.error"
    if [[ -f "$error_file" ]]; then
        local error_msg=$(cat "$error_file" 2>/dev/null || echo "Unknown error")
        log "WARN" "Background cache refresh failed: $error_msg"
        rm -f "$error_file" 2>/dev/null || true
        STATUS_CACHE["refreshing"]="false"
        # Continue with stale cache or trigger sync refresh if no cache available
    fi
    
    # Check if background refresh completed and update in-memory cache from files
    local cache_file="$HOME/.moonfrp/status.cache"
    local timestamp_file="$HOME/.moonfrp/status.cache.timestamp"
    if [[ -f "$cache_file" ]] && [[ -f "$timestamp_file" ]]; then
        local file_timestamp=$(cat "$timestamp_file" 2>/dev/null || echo "0")
        # Update in-memory cache if file cache is newer
        if [[ "$file_timestamp" -gt "${STATUS_CACHE["timestamp"]:-0}" ]]; then
            STATUS_CACHE["data"]=$(cat "$cache_file" 2>/dev/null || echo "")
            STATUS_CACHE["timestamp"]="$file_timestamp"
            STATUS_CACHE["refreshing"]="false"
        fi
    fi
    
    local now=$(date +%s)
    local cache_age=$((now - ${STATUS_CACHE["timestamp"]:-0}))
    
    # Return cache if fresh
    if [[ $cache_age -lt ${STATUS_CACHE["ttl"]} ]] && [[ -n "${STATUS_CACHE["data"]}" ]]; then
        echo "${STATUS_CACHE["data"]}"
        return 0
    fi
    
    # Cache stale - refresh in background if not already refreshing
    if [[ "${STATUS_CACHE["refreshing"]}" == "false" ]]; then
        refresh_status_cache_background
    fi
    
    # Return stale cache while refreshing (better than blocking)
    if [[ -n "${STATUS_CACHE["data"]}" ]]; then
        echo "${STATUS_CACHE["data"]}"
        return 0
    fi
    
    # First run - must load synchronously
    refresh_status_cache_sync
    echo "${STATUS_CACHE["data"]}"
}

# Synchronous cache refresh (blocking, first load only)
refresh_status_cache_sync() {
    init_status_cache
    
    STATUS_CACHE["refreshing"]="false"
    
    local status_json=$(generate_quick_status)
    if [[ -n "$status_json" ]]; then
        STATUS_CACHE["data"]="$status_json"
        STATUS_CACHE["timestamp"]=$(date +%s)
        STATUS_CACHE["refreshing"]="false"
        
        # Update file cache
        local cache_file="$HOME/.moonfrp/status.cache"
        local timestamp_file="$HOME/.moonfrp/status.cache.timestamp"
        echo "$status_json" > "$cache_file"
        echo "${STATUS_CACHE["timestamp"]}" > "$timestamp_file"
    fi
}

# Background cache refresh (non-blocking)
refresh_status_cache_background() {
    init_status_cache
    
    # Don't start new refresh if already refreshing
    if [[ "${STATUS_CACHE["refreshing"]}" == "true" ]]; then
        return 0
    fi
    
    STATUS_CACHE["refreshing"]="true"
    
    # Spawn background process to generate status (truly non-blocking)
    local timestamp_file="$HOME/.moonfrp/status.cache.timestamp"
    local cache_file="$HOME/.moonfrp/status.cache"
    local error_file="$HOME/.moonfrp/status.cache.error"
    
    (
        # Source required functions in background process
        local source_error=false
        source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh" 2>>"$error_file" || source_error=true
        source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-index.sh" 2>>"$error_file" || source_error=true
        
        if [[ "$source_error" == "true" ]]; then
            echo "ERROR: Failed to source required scripts for background refresh" >> "$error_file"
            exit 1
        fi
        
        # Generate status in background
        local status_json=$(generate_quick_status 2>>"$error_file")
        local generate_exit_code=$?
        
        if [[ $generate_exit_code -ne 0 ]] || [[ -z "$status_json" ]]; then
            echo "ERROR: generate_quick_status failed or returned empty result (exit code: $generate_exit_code)" >> "$error_file"
            exit 1
        fi
        
        local timestamp=$(date +%s)
        
        # Write to temporary files first (atomic update)
        local tmp_json=$(mktemp "$HOME/.moonfrp/status_refresh_json_XXXXXX" 2>/dev/null || echo "/tmp/moonfrp_status_$$.json")
        local tmp_ts=$(mktemp "$HOME/.moonfrp/status_refresh_ts_XXXXXX" 2>/dev/null || echo "/tmp/moonfrp_status_$$.ts")
        
        echo "$status_json" > "$tmp_json"
        echo "$timestamp" > "$tmp_ts"
        
        # Atomic move to final cache files
        mv -f "$tmp_json" "$cache_file" 2>/dev/null || true
        mv -f "$tmp_ts" "$timestamp_file" 2>/dev/null || true
        
        # Cleanup any remaining temp files and error file on success
        rm -f "$tmp_json" "$tmp_ts" "$error_file" 2>/dev/null || true
        
        # Signal completion by removing refreshing flag (via file)
        # In-memory cache will be updated on next get_cached_status() call
    ) &
    
    # Return immediately - background process updates files asynchronously
    # In-memory cache will be updated on next get_cached_status() call when files are read
    return 0
}

# Generate quick status using optimized queries (returns JSON)
generate_quick_status() {
    local db_path="$HOME/.moonfrp/index.db"
    local total_configs=0
    local total_proxies=0
    local frp_version=""
    local active_services=0
    local failed_services=0
    local inactive_services=0
    
    # Query SQLite index for config counts (fast)
    if [[ -f "$db_path" ]] && command -v sqlite3 >/dev/null 2>&1; then
        total_configs=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index;" 2>/dev/null || echo "0")
        total_proxies=$(sqlite3 "$db_path" "SELECT COALESCE(SUM(proxy_count), 0) FROM config_index;" 2>/dev/null || echo "0")
    else
        # Fallback to query_total_proxy_count if available
        if command -v query_total_proxy_count >/dev/null 2>&1; then
            total_proxies=$(query_total_proxy_count 2>/dev/null || echo "0")
        fi
    fi
    
    # Batch systemctl query for service status
    local services_output
    services_output=$(systemctl list-units --type=service --all --no-pager --no-legend 2>/dev/null | grep -E "moonfrp-(server|client|visitor)" || true)
    
    if [[ -n "$services_output" ]]; then
        while IFS= read -r line; do
            local status=$(echo "$line" | awk '{print $3}')
            case "$status" in
                active|running)
                    ((active_services++))
                    ;;
                failed)
                    ((failed_services++))
                    ;;
                inactive|dead)
                    ((inactive_services++))
                    ;;
            esac
        done <<< "$services_output"
    fi
    
    # Get FRP version (cached)
    frp_version=$(get_frp_version_cached)
    
    # Format as JSON (simple JSON without jq dependency)
    local json_output="{\"frp_version\":\"$frp_version\",\"total_configs\":$total_configs,\"total_proxies\":$total_proxies,\"active_services\":$active_services,\"failed_services\":$failed_services,\"inactive_services\":$inactive_services}"
    
    # Validate JSON structure (basic validation - check for required fields and basic JSON syntax)
    if command -v jq >/dev/null 2>&1; then
        # Use jq to validate JSON if available
        if ! echo "$json_output" | jq empty >/dev/null 2>&1; then
            log "ERROR" "generate_quick_status: Invalid JSON generated"
            echo "{\"frp_version\":\"unknown\",\"total_configs\":0,\"total_proxies\":0,\"active_services\":0,\"failed_services\":0,\"inactive_services\":0}"
            return 1
        fi
    else
        # Basic validation: check for required JSON structure
        if [[ ! "$json_output" =~ \"frp_version\" ]] || [[ ! "$json_output" =~ \"total_configs\" ]] || [[ ! "$json_output" =~ \"total_proxies\" ]]; then
            log "ERROR" "generate_quick_status: JSON missing required fields"
            echo "{\"frp_version\":\"unknown\",\"total_configs\":0,\"total_proxies\":0,\"active_services\":0,\"failed_services\":0,\"inactive_services\":0}"
            return 1
        fi
        # Basic JSON syntax check: must start with { and end with }
        if [[ ! "$json_output" =~ ^\{ ]] || [[ ! "$json_output" =~ \}$ ]]; then
            log "ERROR" "generate_quick_status: Invalid JSON syntax"
            echo "{\"frp_version\":\"unknown\",\"total_configs\":0,\"total_proxies\":0,\"active_services\":0,\"failed_services\":0,\"inactive_services\":0}"
            return 1
        fi
    fi
    
    echo "$json_output"
}

# Cached FRP version retrieval (1 hour TTL)
get_frp_version_cached() {
    local cache_file="$HOME/.moonfrp/frp_version.cache"
    local cache_timestamp_file="$HOME/.moonfrp/frp_version.cache.timestamp"
    local ttl=3600  # 1 hour in seconds
    
    mkdir -p "$HOME/.moonfrp"
    
    # Check if cache file exists and is fresh
    if [[ -f "$cache_file" ]] && [[ -f "$cache_timestamp_file" ]]; then
        local cache_timestamp=$(cat "$cache_timestamp_file" 2>/dev/null || echo "0")
        local now=$(date +%s)
        local cache_age=$((now - cache_timestamp))
        
        if [[ $cache_age -lt $ttl ]]; then
            # Cache is fresh, return cached version
            cat "$cache_file" 2>/dev/null || echo "unknown"
            return 0
        fi
    fi
    
    # Cache is stale or doesn't exist, refresh
    local version=$(get_frp_version 2>/dev/null || echo "unknown")
    
    # Update cache
    echo "$version" > "$cache_file"
    echo "$(date +%s)" > "$cache_timestamp_file"
    
    echo "$version"
}

# Display cached status in menu
display_cached_status() {
    local status_json=$(get_cached_status)
    local now=$(date +%s)
    local cache_age=$((now - ${STATUS_CACHE["timestamp"]:-0}))
    local is_stale=false
    local is_refreshing=false
    
    # Check if cache is stale or refreshing
    if [[ $cache_age -ge ${STATUS_CACHE["ttl"]:-5} ]]; then
        is_stale=true
    fi
    if [[ "${STATUS_CACHE["refreshing"]:-false}" == "true" ]]; then
        is_refreshing=true
    fi
    
    # Parse JSON - try jq first, fallback to grep
    local frp_version=""
    local total_configs=0
    local total_proxies=0
    local active_services=0
    local failed_services=0
    local inactive_services=0
    
    if command -v jq >/dev/null 2>&1; then
        frp_version=$(echo "$status_json" | jq -r '.frp_version // "unknown"' 2>/dev/null || echo "unknown")
        total_configs=$(echo "$status_json" | jq -r '.total_configs // 0' 2>/dev/null || echo "0")
        total_proxies=$(echo "$status_json" | jq -r '.total_proxies // 0' 2>/dev/null || echo "0")
        active_services=$(echo "$status_json" | jq -r '.active_services // 0' 2>/dev/null || echo "0")
        failed_services=$(echo "$status_json" | jq -r '.failed_services // 0' 2>/dev/null || echo "0")
        inactive_services=$(echo "$status_json" | jq -r '.inactive_services // 0' 2>/dev/null || echo "0")
    else
        # Fallback to grep-based parsing (portable, no Perl regex required)
        frp_version=$(echo "$status_json" | grep -o '"frp_version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"frp_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1 || echo "unknown")
        total_configs=$(echo "$status_json" | grep -o '"total_configs"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$' || echo "0")
        total_proxies=$(echo "$status_json" | grep -o '"total_proxies"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$' || echo "0")
        active_services=$(echo "$status_json" | grep -o '"active_services"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$' || echo "0")
        failed_services=$(echo "$status_json" | grep -o '"failed_services"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$' || echo "0")
        inactive_services=$(echo "$status_json" | grep -o '"inactive_services"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$' || echo "0")
    fi
    
    # Display formatted status
    echo -e "${CYAN}Status:${NC}"
    
    if [[ "$frp_version" != "unknown" ]] && [[ "$frp_version" != "not installed" ]]; then
        echo -e "  FRP: ${GREEN}Active${NC} ($frp_version)"
    else
        echo -e "  FRP: ${RED}Inactive${NC}"
    fi
    
    if [[ $total_configs -gt 0 ]]; then
        echo -e "  Configs: ${GREEN}$total_configs${NC} (Proxies: $total_proxies)"
    else
        echo -e "  Configs: ${GRAY}0${NC}"
    fi
    
    local service_status=""
    if [[ $active_services -gt 0 ]]; then
        service_status="${GREEN}$active_services active${NC}"
    fi
    if [[ $failed_services -gt 0 ]]; then
        [[ -n "$service_status" ]] && service_status="$service_status, "
        service_status="${service_status}${RED}$failed_services failed${NC}"
    fi
    if [[ $inactive_services -gt 0 ]]; then
        [[ -n "$service_status" ]] && service_status="$service_status, "
        service_status="${service_status}${GRAY}$inactive_services inactive${NC}"
    fi
    
    if [[ -n "$service_status" ]]; then
        echo -e "  Services: $service_status"
    fi
    
    # Show staleness/refreshing indicator
    if [[ "$is_refreshing" == "true" ]]; then
        echo -e "  ${YELLOW}⟳ Refreshing...${NC}"
    elif [[ "$is_stale" == "true" ]]; then
        echo -e "  ${YELLOW}⚠ Stale data${NC}"
    fi
}

# Export functions
export -f show_header show_system_status quick_setup_wizard
export -f quick_server_setup quick_client_setup quick_multi_ip_setup
export -f install_frp main_menu advanced_tools_menu view_logs_menu
export -f backup_configurations restore_configurations update_moonfrp uninstall_moonfrp
export -f show_config_details display_config_summary export_config_summary
export -f get_cached_status refresh_status_cache_sync refresh_status_cache_background
export -f generate_quick_status get_frp_version_cached display_cached_status init_status_cache