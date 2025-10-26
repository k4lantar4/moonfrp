#!/bin/bash

#==============================================================================
# MoonFRP Service Management
# Version: 2.0.0
# Description: Service management and monitoring for MoonFRP
#==============================================================================

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"

#==============================================================================
# SERVICE MANAGEMENT FUNCTIONS
#==============================================================================

# Create systemd service file
create_systemd_service() {
    local service_type="$1"  # server, client, visitor
    local service_name="$2"
    local config_file="$3"
    local binary_name="$4"
    local service_suffix="${5:-}"
    
    local service_file="/etc/systemd/system/${service_name}.service"
    local log_file="$LOG_DIR/${service_name}.log"
    
    cat > "$service_file" << EOF
[Unit]
Description=MoonFRP ${service_type^} Service${service_suffix}
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$FRP_DIR/$binary_name -c $config_file
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
StandardOutput=append:$log_file
StandardError=append:$log_file
SyslogIdentifier=$service_name

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_DIR $CONFIG_DIR

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log "INFO" "Created systemd service: $service_name"
}

# Start service
start_service() {
    local service_name="$1"
    
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log "WARN" "Service $service_name is already running"
        return 0
    fi
    
    if systemctl start "$service_name" 2>/dev/null; then
        log "INFO" "Started service: $service_name"
        return 0
    else
        log "ERROR" "Failed to start service: $service_name"
        return 1
    fi
}

# Stop service
stop_service() {
    local service_name="$1"
    
    if ! systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log "WARN" "Service $service_name is not running"
        return 0
    fi
    
    if systemctl stop "$service_name" 2>/dev/null; then
        log "INFO" "Stopped service: $service_name"
        return 0
    else
        log "ERROR" "Failed to stop service: $service_name"
        return 1
    fi
}

# Restart service
restart_service() {
    local service_name="$1"
    
    if systemctl restart "$service_name" 2>/dev/null; then
        log "INFO" "Restarted service: $service_name"
        return 0
    else
        log "ERROR" "Failed to restart service: $service_name"
        return 1
    fi
}

# Enable service
enable_service() {
    local service_name="$1"
    
    if systemctl enable "$service_name" 2>/dev/null; then
        log "INFO" "Enabled service: $service_name"
        return 0
    else
        log "ERROR" "Failed to enable service: $service_name"
        return 1
    fi
}

# Disable service
disable_service() {
    local service_name="$1"
    
    if systemctl disable "$service_name" 2>/dev/null; then
        log "INFO" "Disabled service: $service_name"
        return 0
    else
        log "ERROR" "Failed to disable service: $service_name"
        return 1
    fi
}

# Get service status
get_detailed_service_status() {
    local service_name="$1"
    
    if ! systemctl list-unit-files | grep -q "$service_name.service"; then
        echo "not_installed"
        return 0
    fi
    
    local status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
    local enabled=$(systemctl is-enabled "$service_name" 2>/dev/null || echo "disabled")
    
    echo "${status}_${enabled}"
}

# Show service status
show_service_status() {
    local service_name="$1"
    local status=$(get_detailed_service_status "$service_name")
    
    case "$status" in
        "active_enabled")
            echo -e "${GREEN}●${NC} $service_name (running, enabled)"
            ;;
        "active_disabled")
            echo -e "${YELLOW}●${NC} $service_name (running, disabled)"
            ;;
        "inactive_enabled")
            echo -e "${RED}●${NC} $service_name (stopped, enabled)"
            ;;
        "inactive_disabled")
            echo -e "${GRAY}●${NC} $service_name (stopped, disabled)"
            ;;
        "not_installed")
            echo -e "${GRAY}○${NC} $service_name (not installed)"
            ;;
        *)
            echo -e "${RED}?${NC} $service_name (unknown status)"
            ;;
    esac
}

# List all FRP services
list_frp_services() {
    echo -e "${CYAN}MoonFRP Services Status:${NC}"
    echo
    
    # Server service
    if [[ -f "/etc/systemd/system/${SERVER_SERVICE}.service" ]]; then
        show_service_status "$SERVER_SERVICE"
    fi
    
    # Client services
    local client_services=($(systemctl list-unit-files | grep "${CLIENT_SERVICE_PREFIX}-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${client_services[@]}"; do
        show_service_status "$service"
    done
    
    # Visitor services
    local visitor_services=($(systemctl list-unit-files | grep "moonfrp-visitor-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${visitor_services[@]}"; do
        show_service_status "$service"
    done
}

# Setup server service
setup_server_service() {
    local config_file="$CONFIG_DIR/frps.toml"
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Server configuration not found: $config_file"
        log "INFO" "Please run the configuration wizard first"
        return 1
    fi
    
    create_systemd_service "server" "$SERVER_SERVICE" "$config_file" "frps"
    enable_service "$SERVER_SERVICE"
    
    log "INFO" "Server service setup complete"
}

# Setup client service
setup_client_service() {
    local config_suffix="$1"
    local config_file="$CONFIG_DIR/frpc${config_suffix}.toml"
    local service_name="${CLIENT_SERVICE_PREFIX}${config_suffix}"
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Client configuration not found: $config_file"
        return 1
    fi
    
    create_systemd_service "client" "$service_name" "$config_file" "frpc" "$config_suffix}"
    enable_service "$service_name"
    
    log "INFO" "Client service setup complete: $service_name"
}

# Setup all services
setup_all_services() {
    local setup_count=0
    
    # Setup server service
    if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
        setup_server_service
        ((setup_count++))
    fi
    
    # Setup client services
    local client_configs=($(find "$CONFIG_DIR" -name "frpc*.toml" -type f | sort))
    for config in "${client_configs[@]}"; do
        local config_name=$(basename "$config" .toml)
        local suffix="${config_name#frpc}"
        setup_client_service "$suffix"
        ((setup_count++))
    done
    
    # Setup visitor services
    local visitor_configs=($(find "$CONFIG_DIR" -name "visitor*.toml" -type f | sort))
    for config in "${visitor_configs[@]}"; do
        local config_name=$(basename "$config" .toml)
        local suffix="${config_name#visitor}"
        local service_name="moonfrp-visitor$suffix"
        create_systemd_service "visitor" "$service_name" "$config" "frpc" "$suffix"
        enable_service "$service_name"
        ((setup_count++))
    done
    
    log "INFO" "Setup complete for $setup_count services"
}

# Start all services
start_all_services() {
    local started_count=0
    local failed_count=0
    
    # Start server service
    if [[ -f "/etc/systemd/system/${SERVER_SERVICE}.service" ]]; then
        if start_service "$SERVER_SERVICE"; then
            ((started_count++))
        else
            ((failed_count++))
        fi
    fi
    
    # Start client services
    local client_services=($(systemctl list-unit-files | grep "${CLIENT_SERVICE_PREFIX}-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${client_services[@]}"; do
        if start_service "$service"; then
            ((started_count++))
        else
            ((failed_count++))
        fi
    done
    
    # Start visitor services
    local visitor_services=($(systemctl list-unit-files | grep "moonfrp-visitor-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${visitor_services[@]}"; do
        if start_service "$service"; then
            ((started_count++))
        else
            ((failed_count++))
        fi
    done
    
    log "INFO" "Started $started_count services, $failed_count failed"
}

# Stop all services
stop_all_services() {
    local stopped_count=0
    local failed_count=0
    
    # Stop visitor services first
    local visitor_services=($(systemctl list-unit-files | grep "moonfrp-visitor-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${visitor_services[@]}"; do
        if stop_service "$service"; then
            ((stopped_count++))
        else
            ((failed_count++))
        fi
    done
    
    # Stop client services
    local client_services=($(systemctl list-unit-files | grep "${CLIENT_SERVICE_PREFIX}-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${client_services[@]}"; do
        if stop_service "$service"; then
            ((stopped_count++))
        else
            ((failed_count++))
        fi
    done
    
    # Stop server service last
    if [[ -f "/etc/systemd/system/${SERVER_SERVICE}.service" ]]; then
        if stop_service "$SERVER_SERVICE"; then
            ((stopped_count++))
        else
            ((failed_count++))
        fi
    fi
    
    log "INFO" "Stopped $stopped_count services, $failed_count failed"
}

# Restart all services
restart_all_services() {
    log "INFO" "Restarting all MoonFRP services..."
    stop_all_services
    sleep 2
    start_all_services
}

# Remove service
remove_service() {
    local service_name="$1"
    
    if [[ ! -f "/etc/systemd/system/${service_name}.service" ]]; then
        log "WARN" "Service not found: $service_name"
        return 0
    fi
    
    stop_service "$service_name"
    disable_service "$service_name"
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload
    
    log "INFO" "Removed service: $service_name"
}

# Remove all services
remove_all_services() {
    local removed_count=0
    
    # Remove visitor services
    local visitor_services=($(systemctl list-unit-files | grep "moonfrp-visitor-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${visitor_services[@]}"; do
        remove_service "$service"
        ((removed_count++))
    done
    
    # Remove client services
    local client_services=($(systemctl list-unit-files | grep "${CLIENT_SERVICE_PREFIX}-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${client_services[@]}"; do
        remove_service "$service"
        ((removed_count++))
    done
    
    # Remove server service
    if [[ -f "/etc/systemd/system/${SERVER_SERVICE}.service" ]]; then
        remove_service "$SERVER_SERVICE"
        ((removed_count++))
    fi
    
    log "INFO" "Removed $removed_count services"
}

# View service logs
view_service_logs() {
    local service_name="$1"
    local lines="${2:-50}"
    
    if [[ ! -f "/etc/systemd/system/${service_name}.service" ]]; then
        log "ERROR" "Service not found: $service_name"
        return 1
    fi
    
    echo -e "${CYAN}Logs for $service_name (last $lines lines):${NC}"
    echo
    journalctl -u "$service_name" -n "$lines" --no-pager
}

# Follow service logs
follow_service_logs() {
    local service_name="$1"
    
    if [[ ! -f "/etc/systemd/system/${service_name}.service" ]]; then
        log "ERROR" "Service not found: $service_name"
        return 1
    fi
    
    echo -e "${CYAN}Following logs for $service_name (Ctrl+C to stop):${NC}"
    echo
    journalctl -u "$service_name" -f
}

# Health check
health_check() {
    local all_healthy=true
    
    echo -e "${CYAN}MoonFRP Health Check:${NC}"
    echo
    
    # Check server service
    if [[ -f "/etc/systemd/system/${SERVER_SERVICE}.service" ]]; then
        local status=$(get_detailed_service_status "$SERVER_SERVICE")
        if [[ "$status" == "active_enabled" ]]; then
            echo -e "${GREEN}✓${NC} Server service is healthy"
        else
            echo -e "${RED}✗${NC} Server service is not healthy (status: $status)"
            all_healthy=false
        fi
    fi
    
    # Check client services
    local client_services=($(systemctl list-unit-files | grep "${CLIENT_SERVICE_PREFIX}-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${client_services[@]}"; do
        local status=$(get_detailed_service_status "$service")
        if [[ "$status" == "active_enabled" ]]; then
            echo -e "${GREEN}✓${NC} $service is healthy"
        else
            echo -e "${RED}✗${NC} $service is not healthy (status: $status)"
            all_healthy=false
        fi
    done
    
    # Check visitor services
    local visitor_services=($(systemctl list-unit-files | grep "moonfrp-visitor-" | awk '{print $1}' | sed 's/.service$//'))
    for service in "${visitor_services[@]}"; do
        local status=$(get_detailed_service_status "$service")
        if [[ "$status" == "active_enabled" ]]; then
            echo -e "${GREEN}✓${NC} $service is healthy"
        else
            echo -e "${RED}✗${NC} $service is not healthy (status: $status)"
            all_healthy=false
        fi
    done
    
    echo
    if $all_healthy; then
        echo -e "${GREEN}All services are healthy!${NC}"
        return 0
    else
        echo -e "${RED}Some services are not healthy!${NC}"
        return 1
    fi
}

# Service management menu
service_management_menu() {
    while true; do
        if [[ "${MENU_STATE["ctrl_c_pressed"]}" == "true" ]]; then
            MENU_STATE["ctrl_c_pressed"]="false"
            return
        fi
        
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║        MoonFRP Services              ║${NC}"
        echo -e "${PURPLE}║         Management Menu              ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        echo
        
        list_frp_services
        echo
        
        echo -e "${CYAN}Service Management Options:${NC}"
        echo "1. Start All Services"
        echo "2. Stop All Services"
        echo "3. Restart All Services"
        echo "4. Setup All Services"
        echo "5. Health Check"
        echo "6. View Service Logs"
        echo "7. Remove All Services"
        echo "0. Back to Main Menu"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1)
                start_all_services
                read -p "Press Enter to continue..."
                ;;
            2)
                stop_all_services
                read -p "Press Enter to continue..."
                ;;
            3)
                restart_all_services
                read -p "Press Enter to continue..."
                ;;
            4)
                setup_all_services
                read -p "Press Enter to continue..."
                ;;
            5)
                health_check
                read -p "Press Enter to continue..."
                ;;
            6)
                echo -e "${CYAN}Available Services:${NC}"
                systemctl list-unit-files | grep -E "(moonfrp-server|moonfrp-client|moonfrp-visitor)" | awk '{print $1}' | sed 's/.service$//'
                echo
                safe_read "Enter service name" "service_name" ""
                if [[ -n "$service_name" ]]; then
                    view_service_logs "$service_name"
                    read -p "Press Enter to continue..."
                fi
                ;;
            7)
                echo -e "${RED}This will remove ALL MoonFRP services!${NC}"
                safe_read "Are you sure? (yes/no)" "confirm" "no"
                if [[ "$confirm" == "yes" ]]; then
                    remove_all_services
                fi
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

# Export functions
export -f create_systemd_service start_service stop_service restart_service
export -f enable_service disable_service get_detailed_service_status show_service_status
export -f list_frp_services setup_server_service setup_client_service setup_all_services
export -f start_all_services stop_all_services restart_all_services
export -f remove_service remove_all_services view_service_logs follow_service_logs
export -f health_check service_management_menu