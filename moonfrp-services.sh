#!/bin/bash

#==============================================================================
# MoonFRP Service Management
# Version: 2.0.0
# Description: Service management and monitoring for MoonFRP
#==============================================================================

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-index.sh"

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
    
    # Ensure directories exist before checking for config
    if [[ ! -d "$CONFIG_DIR" ]] || [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR" "$LOG_DIR" 2>/dev/null || true
        chmod 755 "$CONFIG_DIR" "$LOG_DIR" 2>/dev/null || true
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Server configuration not found: $config_file"
        log "INFO" "Use 'moonfrp setup server' or run the configuration wizard to generate it"
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
    
    create_systemd_service "client" "$service_name" "$config_file" "frpc" "$config_suffix"
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

#==============================================================================
# BULK PARALLEL SERVICE OPERATIONS
#==============================================================================

# Get all MoonFRP services
get_moonfrp_services() {
    systemctl list-units --type=service --all --no-pager --no-legend \
        | grep -E "moonfrp-(server|client|visitor)" \
        | awk '{print $1}' \
        | sed 's/.service$//'
}

# Core parallel service operation framework
bulk_service_operation() {
    local operation="$1"  # start|stop|restart|reload
    local max_parallel="${2:-10}"  # Maximum concurrent operations (default 10)
    shift 2
    local services=("$@")
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log "WARN" "No services provided for bulk operation"
        echo "" >&2  # Clear any potential progress line
        return 0
    fi
    
    local total=${#services[@]}
    local success_count=0
    local fail_count=0
    local completed=0
    declare -a failed_services
    declare -a failed_reasons
    declare -a pids=()
    declare -a service_names=()
    local tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT
    
    log "INFO" "Starting bulk $operation operation on $total services (max parallel: $max_parallel)"
    
    for service in "${services[@]}"; do
        while [[ ${#pids[@]} -ge $max_parallel ]]; do
            local new_pids=()
            local new_services=()
            for i in "${!pids[@]}"; do
                local pid="${pids[$i]}"
                if ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid"
                    local exit_code=$?
                    local svc="${service_names[$i]}"
                    
                    if [[ $exit_code -eq 0 ]]; then
                        ((success_count++))
                    else
                        ((fail_count++))
                        failed_services+=("$svc")
                        if [[ -f "$tmp_dir/$svc.error" ]]; then
                            failed_reasons+=("$(cat "$tmp_dir/$svc.error")")
                        else
                            failed_reasons+=("Operation failed with exit code $exit_code")
                        fi
                    fi
                    ((completed++))
                    printf "\rProgress: $completed/$total services..." >&2
                else
                    new_pids+=("$pid")
                    new_services+=("${service_names[$i]}")
                fi
            done
            pids=("${new_pids[@]}")
            service_names=("${new_services[@]}")
            
            if [[ ${#pids[@]} -ge $max_parallel ]]; then
                sleep 0.1
            fi
        done
        
        {
            case "$operation" in
                "start")
                    start_service "$service" > "$tmp_dir/$service.log" 2> "$tmp_dir/$service.error"
                    ;;
                "stop")
                    stop_service "$service" > "$tmp_dir/$service.log" 2> "$tmp_dir/$service.error"
                    ;;
                "restart")
                    restart_service "$service" > "$tmp_dir/$service.log" 2> "$tmp_dir/$service.error"
                    ;;
                "reload")
                    if systemctl reload "$service" 2>/dev/null; then
                        log "INFO" "Reloaded service: $service" > "$tmp_dir/$service.log"
                        rm -f "$tmp_dir/$service.error"
                    else
                        log "ERROR" "Failed to reload service: $service" > "$tmp_dir/$service.error" 2>&1
                        exit 1
                    fi
                    ;;
                *)
                    echo "Unknown operation: $operation" > "$tmp_dir/$service.error"
                    exit 1
                    ;;
            esac
        } &
        
        local pid=$!
        pids+=("$pid")
        service_names+=("$service")
    done
    
    while [[ ${#pids[@]} -gt 0 ]]; do
        local new_pids=()
        local new_services=()
        for i in "${!pids[@]}"; do
            local pid="${pids[$i]}"
            if ! kill -0 "$pid" 2>/dev/null; then
                wait "$pid"
                local exit_code=$?
                local svc="${service_names[$i]}"
                
                if [[ $exit_code -eq 0 ]]; then
                    ((success_count++))
                else
                    ((fail_count++))
                    failed_services+=("$svc")
                    if [[ -f "$tmp_dir/$svc.error" ]]; then
                        failed_reasons+=("$(cat "$tmp_dir/$svc.error")")
                    else
                        failed_reasons+=("Operation failed with exit code $exit_code")
                    fi
                fi
                ((completed++))
                printf "\rProgress: $completed/$total services..." >&2
            else
                new_pids+=("$pid")
                new_services+=("${service_names[$i]}")
            fi
        done
        pids=("${new_pids[@]}")
        service_names=("${new_services[@]}")
        
        if [[ ${#pids[@]} -gt 0 ]]; then
            sleep 0.1
        fi
    done
    
    echo "" >&2
    rm -rf "$tmp_dir"
    trap - EXIT
    
    log "INFO" "Bulk $operation complete: $success_count succeeded, $fail_count failed"
    
    if [[ $fail_count -gt 0 ]]; then
        log "WARN" "Failed services:"
        for i in "${!failed_services[@]}"; do
            local svc="${failed_services[$i]}"
            local reason="${failed_reasons[$i]:-Unknown error}"
            echo "  - $svc: $reason" >&2
        done
    fi
    
    return $fail_count
}

# User-facing bulk operation functions
bulk_start_services() {
    local max_parallel="${1:-10}"
    local services=($(get_moonfrp_services))
    bulk_service_operation "start" "$max_parallel" "${services[@]}"
}

bulk_stop_services() {
    local max_parallel="${1:-10}"
    local services=($(get_moonfrp_services))
    bulk_service_operation "stop" "$max_parallel" "${services[@]}"
}

bulk_restart_services() {
    local max_parallel="${1:-10}"
    local services=($(get_moonfrp_services))
    bulk_service_operation "restart" "$max_parallel" "${services[@]}"
}

bulk_reload_services() {
    local max_parallel="${1:-10}"
    local services=($(get_moonfrp_services))
    bulk_service_operation "reload" "$max_parallel" "${services[@]}"
}

# Filtered bulk operations (for Story 2.3 - tags integration)
bulk_operation_filtered() {
    local operation="$1"
    local filter_type="$2"  # tag, status, name
    local filter_value="$3"
    local max_parallel="${4:-10}"
    
    local services=()
    
    case "$filter_type" in
        "tag")
            if command -v get_services_by_tag &>/dev/null; then
                services=($(get_services_by_tag "$filter_value"))
            else
                log "ERROR" "Tag filtering requires Story 2.3 tagging system (not yet implemented)"
                return 1
            fi
            ;;
        "status")
            local all_services=($(get_moonfrp_services))
            for svc in "${all_services[@]}"; do
                local status=$(get_detailed_service_status "$svc" | cut -d'_' -f1)
                if [[ "$status" == "$filter_value" ]]; then
                    services+=("$svc")
                fi
            done
            ;;
        "name")
            local all_services=($(get_moonfrp_services))
            for svc in "${all_services[@]}"; do
                if [[ "$svc" == *"$filter_value"* ]]; then
                    services+=("$svc")
                fi
            done
            ;;
        *)
            log "ERROR" "Invalid filter type: $filter_type. Use: tag, status, or name"
            return 1
            ;;
    esac
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log "WARN" "No services found matching filter: $filter_type=$filter_value"
        return 0
    fi
    
    bulk_service_operation "$operation" "$max_parallel" "${services[@]}"
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

#==============================================================================
# ASYNC CONNECTION TESTING (Story 3.4)
#==============================================================================

# Check and display completed test results
check_completed_tests() {
    local -n pids_ref="$1"
    local -n results_ref="$2"
    local tmp_dir="$3"
    local -n completed_ref="$4"
    
    local new_pids=()
    local updated=false
    
    for i in "${!pids_ref[@]}"; do
        local pid="${pids_ref[$i]}"
        if ! kill -0 "$pid" 2>/dev/null; then
            # Process completed
            wait "$pid" 2>/dev/null || true
            local result_file="$tmp_dir/$i.result"
            
            if [[ -f "$result_file" ]]; then
                local result=$(cat "$result_file" 2>/dev/null || echo "FAIL")
                local result_line="${results_ref[$i]}"
                
                # Extract server:port from result_line
                if [[ "$result_line" =~ ^([^:]+:[0-9]+) ]]; then
                    local server_port="${BASH_REMATCH[1]}"
                    local status_indicator=""
                    local status_text=""
                    
                    if [[ "$result" == "OK" ]]; then
                        status_indicator="${GREEN}✓${NC}"
                        status_text="${GREEN}OK${NC}"
                    else
                        status_indicator="${RED}✗${NC}"
                        status_text="${RED}FAIL${NC}"
                    fi
                    
                    # Display result immediately
                    echo -e "  $server_port $status_indicator $status_text"
                    
                    # Update result in array
                    results_ref[$i]="$server_port|$result"
                fi
            fi
            
            ((completed_ref++))
            updated=true
        else
            # Process still running
            new_pids+=("$pid")
        fi
    done
    
    # Update pids array
    pids_ref=("${new_pids[@]}")
    
    return 0
}

# Core parallel connection testing framework
async_connection_test() {
    local configs=("$@")
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        log "WARN" "No configs provided for connection testing"
        return 0
    fi
    
    local max_parallel=20
    local timeout=1
    local total=${#configs[@]}
    local started=0
    local completed=0
    local success_count=0
    local fail_count=0
    
    declare -A pids
    declare -A results
    local tmp_dir=$(mktemp -d)
    
    # Trap for cleanup on exit or SIGINT
    trap "rm -rf '$tmp_dir'; kill $(jobs -p) 2>/dev/null || true; trap - EXIT INT TERM" EXIT INT TERM
    
    log "INFO" "Testing connectivity to $total servers (max parallel: $max_parallel, timeout: ${timeout}s per test)"
    echo -e "${CYAN}Testing connectivity to $total servers...${NC}"
    echo
    
    local db_path="$INDEX_DB_PATH"
    local i=0
    local total_tests=0
    
    # Start all tests
    for config in "${configs[@]}"; do
        # Wait if max parallel reached
        while [[ ${#pids[@]} -ge $max_parallel ]]; do
            check_completed_tests pids results "$tmp_dir" completed
            if [[ $completed -lt $total_tests ]]; then
                printf "\r${CYAN}Testing %d/%d servers...${NC}" "$completed" "$total_tests" >&2
            fi
            sleep 0.05
        done
        
        # Extract server_addr and server_port from index
        local server_addr=$(sqlite3 "$db_path" \
            "SELECT server_addr FROM config_index WHERE file_path='$config'" 2>/dev/null || echo "")
        local server_port=$(sqlite3 "$db_path" \
            "SELECT server_port FROM config_index WHERE file_path='$config'" 2>/dev/null || echo "")
        
        # Skip if no server info
        if [[ -z "$server_addr" || -z "$server_port" ]]; then
            continue
        fi
        
        # Start test in background
        (
            if timeout "$timeout" bash -c "echo > /dev/tcp/$server_addr/$server_port" 2>/dev/null; then
                echo "OK" > "$tmp_dir/$i.result"
            else
                echo "FAIL" > "$tmp_dir/$i.result"
            fi
        ) &
        
        local pid=$!
        pids[$i]=$pid
        results[$i]="$server_addr:$server_port"
        ((started++))
        ((total_tests++))
        ((i++))
    done
    
    # Wait for remaining tests
    while [[ ${#pids[@]} -gt 0 ]]; do
        check_completed_tests pids results "$tmp_dir" completed
        if [[ $completed -lt $total_tests ]]; then
            printf "\r${CYAN}Testing %d/%d servers...${NC}" "$completed" "$total_tests" >&2
        fi
        sleep 0.1
    done
    
    echo "" >&2
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Generate summary
    success_count=0
    fail_count=0
    for result_key in "${!results[@]}"; do
        local result_line="${results[$result_key]}"
        if [[ "$result_line" =~ \|(OK|FAIL)$ ]]; then
            local status="${BASH_REMATCH[1]}"
            if [[ "$status" == "OK" ]]; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        fi
    done
    
    # Display summary
    echo -e "${CYAN}Summary:${NC}"
    echo -e "  ${GREEN}✓ Reachable: $success_count${NC} | ${RED}✗ Unreachable: $fail_count${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Cleanup
    rm -rf "$tmp_dir"
    trap - EXIT INT TERM
    
    return $fail_count
}

# User-facing function for testing all client configs
run_connection_tests_all() {
    if ! command -v query_configs_by_type &>/dev/null; then
        log "ERROR" "query_configs_by_type function not available. Index may not be initialized."
        return 1
    fi
    
    local configs_output=$(query_configs_by_type "client" 2>/dev/null)
    
    if [[ -z "$configs_output" ]]; then
        log "WARN" "No client configs found in index"
        echo -e "${YELLOW}No client configurations found to test.${NC}"
        return 0
    fi
    
    # Parse pipe-separated output
    local configs=()
    while IFS='|' read -r file_path server_addr proxy_count; do
        if [[ -n "$file_path" ]]; then
            configs+=("$file_path")
        fi
    done <<< "$configs_output"
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        log "WARN" "No valid client configs found"
        echo -e "${YELLOW}No valid client configurations found to test.${NC}"
        return 0
    fi
    
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Connection Test - All Servers    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo
    
    async_connection_test "${configs[@]}"
}

# Export functions
export -f create_systemd_service start_service stop_service restart_service
export -f enable_service disable_service get_detailed_service_status show_service_status
export -f list_frp_services setup_server_service setup_client_service setup_all_services
export -f start_all_services stop_all_services restart_all_services
export -f remove_service remove_all_services view_service_logs follow_service_logs
export -f health_check service_management_menu
export -f get_moonfrp_services bulk_service_operation
export -f bulk_start_services bulk_stop_services bulk_restart_services bulk_reload_services
export -f bulk_operation_filtered
export -f async_connection_test check_completed_tests run_connection_tests_all