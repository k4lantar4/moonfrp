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
    
    if systemctl daemon-reload 2>/dev/null; then
        log "INFO" "Created systemd service: $service_name"
    else
        log "ERROR" "Failed to reload systemd daemon after creating service: $service_name"
        return 1
    fi
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
    
    if ! systemctl list-unit-files "$service_name.service" &>/dev/null; then
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

# List all FRP services (simplified - always fresh on each call)
list_frp_services() {
    echo -e "${CYAN}MoonFRP Services Status:${NC}"
    echo
    
    # Get all MoonFRP services from systemd in one query (faster, always fresh)
    local all_services=($(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
        awk '/moonfrp-/{print $1}' | \
        sed 's/.service$//' | \
        sort))
    
    if [[ ${#all_services[@]} -eq 0 ]]; then
        echo -e "${GRAY}No MoonFRP services found${NC}"
        return 0
    fi
    
    # Display status for each service
    for service in "${all_services[@]}"; do
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
    local failed_count=0
    local failed_configs=()
    
    echo -e "${CYAN}Setting up MoonFRP services...${NC}"
    echo
    
    # Setup server service
    if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
        if setup_server_service; then
            ((setup_count++))
            echo -e "  ${GREEN}✓${NC} Server service (frps.toml)"
        else
            ((failed_count++))
            failed_configs+=("frps.toml")
            echo -e "  ${RED}✗${NC} Server service (frps.toml) - failed"
        fi
    fi
    
    # Setup client services
    local client_configs=($(find "$CONFIG_DIR" -maxdepth 1 -name "frpc*.toml" -type f 2>/dev/null | sort))
    for config in "${client_configs[@]}"; do
        local config_name=$(basename "$config" .toml)
        local suffix="${config_name#frpc}"
        if setup_client_service "$suffix"; then
            ((setup_count++))
            echo -e "  ${GREEN}✓${NC} Client service ($config_name)"
        else
            ((failed_count++))
            failed_configs+=("$config_name")
            echo -e "  ${RED}✗${NC} Client service ($config_name) - failed"
        fi
    done
    
    # Setup visitor services
    local visitor_configs=($(find "$CONFIG_DIR" -maxdepth 1 -name "visitor*.toml" -type f 2>/dev/null | sort))
    for config in "${visitor_configs[@]}"; do
        local config_name=$(basename "$config" .toml)
        local suffix="${config_name#visitor}"
        local service_name="moonfrp-visitor$suffix"
        if create_systemd_service "visitor" "$service_name" "$config" "frpc" "$suffix" && enable_service "$service_name"; then
            ((setup_count++))
            echo -e "  ${GREEN}✓${NC} Visitor service ($config_name)"
        else
            ((failed_count++))
            failed_configs+=("$config_name")
            echo -e "  ${RED}✗${NC} Visitor service ($config_name) - failed"
        fi
    done
    
    echo
    if [[ $failed_count -eq 0 ]]; then
        log "INFO" "Successfully setup $setup_count service(s)"
    else
        log "WARN" "Setup $setup_count service(s), $failed_count failed"
        if [[ ${#failed_configs[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Failed configs:${NC} ${failed_configs[*]}"
        fi
    fi
    
    # Reload systemd after setup
    if [[ $setup_count -gt 0 ]]; then
        systemctl daemon-reload 2>/dev/null || true
    fi
}

# Start all services (simplified - uses same logic as list_frp_services)
start_all_services() {
    local started_count=0
    local failed_count=0
    local failed_services=()
    
    # Get all MoonFRP services in one query
    local all_services=($(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
        awk '/moonfrp-/{print $1}' | \
        sed 's/.service$//' | \
        sort))
    
    if [[ ${#all_services[@]} -eq 0 ]]; then
        log "WARN" "No MoonFRP services found to start"
        return 0
    fi
    
    echo -e "${CYAN}Starting ${#all_services[@]} service(s)...${NC}"
    
    for service in "${all_services[@]}"; do
        if start_service "$service"; then
            ((started_count++))
            echo -e "  ${GREEN}✓${NC} $service"
        else
            ((failed_count++))
            failed_services+=("$service")
            echo -e "  ${RED}✗${NC} $service"
        fi
    done
    
    echo
    if [[ $failed_count -eq 0 ]]; then
        log "INFO" "Successfully started $started_count service(s)"
    else
        log "WARN" "Started $started_count service(s), $failed_count failed"
        if [[ ${#failed_services[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Failed services:${NC} ${failed_services[*]}"
        fi
    fi
}

# Stop all services (simplified - uses same logic as list_frp_services)
stop_all_services() {
    local stopped_count=0
    local failed_count=0
    local failed_services=()
    
    # Get all MoonFRP services in one query
    local all_services=($(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
        awk '/moonfrp-/{print $1}' | \
        sed 's/.service$//' | \
        sort -r))  # Reverse sort to stop visitors/clients before server
    
    if [[ ${#all_services[@]} -eq 0 ]]; then
        log "WARN" "No MoonFRP services found to stop"
        return 0
    fi
    
    echo -e "${CYAN}Stopping ${#all_services[@]} service(s)...${NC}"
    
    for service in "${all_services[@]}"; do
        if stop_service "$service"; then
            ((stopped_count++))
            echo -e "  ${GREEN}✓${NC} $service"
        else
            ((failed_count++))
            failed_services+=("$service")
            echo -e "  ${RED}✗${NC} $service"
        fi
    done
    
    echo
    if [[ $failed_count -eq 0 ]]; then
        log "INFO" "Successfully stopped $stopped_count service(s)"
    else
        log "WARN" "Stopped $stopped_count service(s), $failed_count failed"
        if [[ ${#failed_services[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Failed services:${NC} ${failed_services[*]}"
        fi
    fi
}

# Restart all services
restart_all_services() {
    echo -e "${CYAN}Restarting all MoonFRP services...${NC}"
    echo
    
    stop_all_services
    echo
    
    if [[ $? -eq 0 ]] || [[ $? -eq 1 ]]; then  # stop_all_services may return 0 even with some failures
        sleep 2
        start_all_services
    else
        log "ERROR" "Failed to stop services. Cannot restart."
        return 1
    fi
}

#==============================================================================
# BULK PARALLEL SERVICE OPERATIONS
#==============================================================================

# Get all MoonFRP services
get_moonfrp_services() {
    systemctl list-units --type=service --all --no-pager --no-legend \
        | awk '/moonfrp-/{print $1}' \
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
    
    if systemctl daemon-reload 2>/dev/null; then
        log "INFO" "Removed service: $service_name"
    else
        log "ERROR" "Failed to reload systemd daemon after removing service: $service_name"
        return 1
    fi
}

# Remove all services (using *frp* pattern to catch all frp-related services)
remove_all_services() {
    local removed_count=0
    
    # Find all services matching *frp* pattern
    local all_frp_services=($(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
        awk '/frp/{print $1}' | \
        sed 's/.service$//' | \
        sort))
    
    if [[ ${#all_frp_services[@]} -eq 0 ]]; then
        log "WARN" "No FRP services found to remove"
        return 0
    fi
    
    echo -e "${CYAN}Removing ${#all_frp_services[@]} FRP service(s)...${NC}"
    
    for service in "${all_frp_services[@]}"; do
        if remove_service "$service"; then
            ((removed_count++))
            echo -e "  ${GREEN}✓${NC} $service"
        else
            echo -e "  ${RED}✗${NC} $service"
        fi
    done
    
    echo
    log "INFO" "Removed $removed_count service(s)"
}

# Remove all config files from /etc/frp matching frp* pattern
remove_all_config_files() {
    local removed_count=0
    local failed_count=0
    
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log "WARN" "Config directory not found: $CONFIG_DIR"
        return 0
    fi
    
    # Find all config files matching frp* pattern
    local config_files=($(find "$CONFIG_DIR" -maxdepth 1 -name "frp*" -type f 2>/dev/null | sort))
    
    if [[ ${#config_files[@]} -eq 0 ]]; then
        log "WARN" "No FRP config files found in $CONFIG_DIR"
        return 0
    fi
    
    echo -e "${CYAN}Removing ${#config_files[@]} config file(s) from $CONFIG_DIR...${NC}"
    
    for config_file in "${config_files[@]}"; do
        if rm -f "$config_file" 2>/dev/null; then
            ((removed_count++))
            echo -e "  ${GREEN}✓${NC} $(basename "$config_file")"
        else
            ((failed_count++))
            echo -e "  ${RED}✗${NC} $(basename "$config_file")"
        fi
    done
    
    echo
    if [[ $failed_count -eq 0 ]]; then
        log "INFO" "Removed $removed_count config file(s)"
    else
        log "WARN" "Removed $removed_count config file(s), $failed_count failed"
    fi
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
    if ! journalctl -u "$service_name" -n "$lines" --no-pager; then
        log "ERROR" "Failed to read logs for $service_name. Try running with elevated privileges."
        return 1
    fi
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
    if ! journalctl -u "$service_name" -f; then
        log "ERROR" "Failed to follow logs for $service_name. Try running with elevated privileges."
        return 1
    fi
}

# Health check helpers
get_service_config_path() {
    local service_name="$1"

    if [[ -z "$service_name" ]]; then
        return 1
    fi

    if [[ "$service_name" == "$SERVER_SERVICE" ]]; then
        echo "$CONFIG_DIR/frps.toml"
        return 0
    fi

    if [[ "$service_name" == ${CLIENT_SERVICE_PREFIX}* ]]; then
        local suffix="${service_name#${CLIENT_SERVICE_PREFIX}}"
        echo "$CONFIG_DIR/frpc${suffix}.toml"
        return 0
    fi

    if [[ "$service_name" == moonfrp-visitor* ]]; then
        local suffix="${service_name#moonfrp-visitor}"
        echo "$CONFIG_DIR/visitor${suffix}.toml"
        return 0
    fi

    return 1
}

describe_admin_health() {
    local service_name="$1"
    local config_path
    config_path=$(get_service_config_path "$service_name" 2>/dev/null || true)

    if [[ -z "$config_path" ]]; then
        echo "Unknown service type"
        return 2
    fi

    if [[ ! -f "$config_path" ]]; then
        echo "Config missing at $config_path"
        return 2
    fi

    local admin_addr
    admin_addr=$(get_toml_value "$config_path" "webServer.addr" 2>/dev/null | tr -d '"' | tr -d "'" || echo "")
    local admin_port
    admin_port=$(get_toml_value "$config_path" "webServer.port" 2>/dev/null | tr -d '"' | tr -d "'" || echo "")

    if [[ -z "$admin_addr" ]]; then
        admin_addr="127.0.0.1"
    fi

    if [[ -z "$admin_port" ]]; then
        if [[ "$service_name" == "$SERVER_SERVICE" ]]; then
            admin_port="$DEFAULT_SERVER_DASHBOARD_PORT"
        else
            admin_port="7400"
        fi
    fi

    local health_url="http://${admin_addr}:${admin_port}/healthz"
    if curl -sf --max-time 3 "$health_url" >/dev/null; then
        echo "Reachable at $health_url"
        return 0
    fi

    echo "Failed to reach $health_url"
    return 1
}

# Health check leveraging FRP admin endpoints when available
health_check() {
    local all_healthy=true
    local checked_count=0

    echo -e "${CYAN}MoonFRP Health Check:${NC}"
    echo

    local all_services=($(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
        awk '/moonfrp-/{print $1}' | \
        sed 's/.service$//' | \
        sort))

    if [[ ${#all_services[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No services found to check.${NC}"
        return 1
    fi

    for service in "${all_services[@]}"; do
        ((checked_count++))
        local status
        status=$(get_detailed_service_status "$service")

        local status_icon="${GRAY}○${NC}"
        local status_note="unknown"
        case "$status" in
            active_enabled)
                status_icon="${GREEN}●${NC}"
                status_note="running, enabled"
                ;;
            active_disabled)
                status_icon="${YELLOW}●${NC}"
                status_note="running, disabled"
                ;;
            inactive_enabled)
                status_icon="${RED}●${NC}"
                status_note="stopped, enabled"
                all_healthy=false
                ;;
            inactive_disabled)
                status_icon="${GRAY}●${NC}"
                status_note="stopped, disabled"
                all_healthy=false
                ;;
            not_installed)
                status_icon="${GRAY}○${NC}"
                status_note="not installed"
                all_healthy=false
                ;;
            *)
                status_icon="${RED}?${NC}"
                status_note="unknown status"
                all_healthy=false
                ;;
        esac

        echo -e "  $status_icon $service (${status_note})"

        if [[ "$status" == active_* ]]; then
            local admin_msg
            admin_msg=$(describe_admin_health "$service")
            local admin_rc=$?
            case $admin_rc in
                0)
                    echo -e "     Admin endpoint: ${GREEN}${admin_msg}${NC}"
                    ;;
                1)
                    echo -e "     Admin endpoint: ${RED}${admin_msg}${NC}"
                    all_healthy=false
                    ;;
                2)
                    echo -e "     Admin endpoint: ${YELLOW}${admin_msg}${NC}"
                    all_healthy=false
                    ;;
            esac
        else
            echo -e "     Admin endpoint: ${GRAY}Skipped (service inactive)${NC}"
        fi

        echo
    done

    if $all_healthy; then
        echo -e "${GREEN}All ${checked_count} service(s) passed health checks.${NC}"
        return 0
    fi

    echo -e "${RED}Health check detected issues. Review the details above.${NC}"
    return 1
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
        
        echo -e "${CYAN}Service Management Options:${NC}"
        echo "1. Start All Services"
        echo "2. Stop All Services"
        echo "3. Restart All Services"
        echo "4. Setup All Services"
        echo "5. Health Check"
        echo "6. View Service Logs"
        echo "7. Remove All Services"
        echo "8. Show Service Status"
        echo "9. Remove Config Files"
        echo "0. Back to Main Menu"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1)
                local services_count=$(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
                    awk '/moonfrp-/{print}' | wc -l)
                if [[ $services_count -eq 0 ]]; then
                    log "WARN" "No services found. Use option 4 (Setup All Services) first."
                else
                    if ! start_all_services; then
                        log "WARN" "Start operation reported failures. Review service logs for details."
                    fi
                fi
                echo
                read -p "Press Enter to continue..."
                ;;
            2)
                local services_count=$(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
                    awk '/moonfrp-/{print}' | wc -l)
                if [[ $services_count -eq 0 ]]; then
                    log "WARN" "No services found to stop."
                else
                    if ! stop_all_services; then
                        log "WARN" "Stop operation reported failures. Check service status for details."
                    fi
                fi
                echo
                read -p "Press Enter to continue..."
                ;;
            3)
                local services_count=$(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
                    awk '/moonfrp-/{print}' | wc -l)
                if [[ $services_count -eq 0 ]]; then
                    log "WARN" "No services found to restart."
                else
                    if ! restart_all_services; then
                        log "WARN" "Restart operation reported failures. Review service logs for more information."
                    fi
                fi
                echo
                read -p "Press Enter to continue..."
                ;;
            4)
                if [[ ! -f "$CONFIG_DIR/frps.toml" ]] && [[ $(find "$CONFIG_DIR" -name "frpc*.toml" -o -name "visitor*.toml" 2>/dev/null | wc -l) -eq 0 ]]; then
                    log "WARN" "No configuration files found. Please create configs first (Main Menu -> 3)."
                else
                    if ! setup_all_services; then
                        log "WARN" "Service setup encountered issues. Some units may require manual review or root privileges."
                    fi
                fi
                echo
                read -p "Press Enter to continue..."
                ;;
            5)
                if ! health_check; then
                    log "WARN" "Health check reported issues. See details above."
                else
                    log "INFO" "All services passed health checks."
                fi
                echo
                read -p "Press Enter to continue..."
                ;;
            6)
                # Get available services
                local available_services=($(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
                    awk '/moonfrp-/{print $1}' | \
                    sed 's/.service$//' | \
                    sort))
                
                if [[ ${#available_services[@]} -eq 0 ]]; then
                    log "WARN" "No services found."
                    read -p "Press Enter to continue..."
                else
                    echo -e "${CYAN}Available Services:${NC}"
                    local idx=1
                    for svc in "${available_services[@]}"; do
                        echo "$idx. $svc"
                        ((idx++))
                    done
                    echo "0. Cancel"
                    echo
                    safe_read "Select service (number or name)" "service_input" "0"
                    
                    if [[ "$service_input" == "0" ]]; then
                        continue
                    elif [[ "$service_input" =~ ^[0-9]+$ ]] && [[ "$service_input" -ge 1 ]] && [[ "$service_input" -le ${#available_services[@]} ]]; then
                        local service_name="${available_services[$((service_input - 1))]}"
                        if ! view_service_logs "$service_name"; then
                            log "WARN" "Unable to display logs for $service_name."
                        fi
                    elif [[ -n "$service_input" ]]; then
                        if [[ " ${available_services[*]} " =~ " ${service_input} " ]]; then
                            if ! view_service_logs "$service_input"; then
                                log "WARN" "Unable to display logs for $service_input."
                            fi
                        else
                            log "ERROR" "Service not found: $service_input"
                        fi
                    fi
                    echo
                    read -p "Press Enter to continue..."
                fi
                ;;
            7)
                # Validate: Check if any services exist
                local services_count=$(systemctl list-unit-files --type=service --all --no-pager --no-legend 2>/dev/null | \
                    awk '/frp/{print}' | wc -l)
                if [[ $services_count -eq 0 ]]; then
                    log "WARN" "No FRP services found to remove."
                else
                    echo -e "${RED}⚠ WARNING: This will remove ALL FRP services!${NC}"
                    echo -e "${YELLOW}This action cannot be undone.${NC}"
                    echo
                    echo -e "${CYAN}Do you also want to remove config files from $CONFIG_DIR?${NC}"
                    echo -e "${YELLOW}Config files matching 'frp*' pattern will be removed.${NC}"
                    echo
                    safe_read "Remove config files? (yes/no)" "remove_configs" "no"
                    
                    safe_read "Type 'yes' to confirm service removal" "confirm" "no"
                    if [[ "$confirm" == "yes" ]]; then
                        if ! remove_all_services; then
                            log "WARN" "Failed to remove one or more services. Check permissions."
                        fi
                        
                        if [[ "$remove_configs" == "yes" ]]; then
                            echo
                            if ! remove_all_config_files; then
                                log "WARN" "Failed to remove one or more config files. Check permissions."
                            fi
                        fi
                    else
                        log "INFO" "Removal cancelled."
                    fi
                fi
                echo
                read -p "Press Enter to continue..."
                ;;
            8)
                list_frp_services
                echo
                read -p "Press Enter to continue..."
                ;;
            9)
                # Check if any config files exist
                local config_count=$(find "$CONFIG_DIR" -maxdepth 1 -name "frp*" -type f 2>/dev/null | wc -l)
                if [[ $config_count -eq 0 ]]; then
                    log "WARN" "No FRP config files found in $CONFIG_DIR"
                else
                    echo -e "${RED}⚠ WARNING: This will remove ALL config files from $CONFIG_DIR!${NC}"
                    echo -e "${YELLOW}Files matching 'frp*' pattern will be removed.${NC}"
                    echo -e "${YELLOW}This action cannot be undone.${NC}"
                    echo
                    
                    # Show what will be removed
                    echo -e "${CYAN}Config files to be removed:${NC}"
                    find "$CONFIG_DIR" -maxdepth 1 -name "frp*" -type f 2>/dev/null | sort | while read -r config_file; do
                        echo -e "  - $(basename "$config_file")"
                    done
                    echo
                    
                    safe_read "Type 'yes' to confirm removal" "confirm" "no"
                    if [[ "$confirm" == "yes" ]]; then
                        if ! remove_all_config_files; then
                            log "WARN" "Failed to remove one or more config files. Check permissions."
                        fi
                    else
                        log "INFO" "Removal cancelled."
                    fi
                fi
                echo
                read -p "Press Enter to continue..."
                ;;
            0)
                return
                ;;
            *)
                log "ERROR" "Invalid choice: $choice"
                read -p "Press Enter to continue..."
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
        
        # Extract server_addr and server_port from metadata
        local server_addr
        server_addr=$(get_config_metadata_field "$config" "server_addr")
        local server_port
        server_port=$(get_config_metadata_field "$config" "server_port")
        
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
export -f remove_service remove_all_services remove_all_config_files view_service_logs follow_service_logs
export -f health_check service_management_menu
export -f get_moonfrp_services bulk_service_operation
export -f bulk_start_services bulk_stop_services bulk_restart_services bulk_reload_services
export -f bulk_operation_filtered
export -f async_connection_test check_completed_tests run_connection_tests_all

get_services_by_tag() {
    local tag_query="$1"
    if [[ -z "$tag_query" ]]; then
        return 0
    fi
    local configs
    configs=($(query_configs_by_tag "$tag_query" 2>/dev/null || echo ""))
    local services=()
    for cfg in "${configs[@]}"; do
        [[ -n "$cfg" ]] || continue
        local name="moonfrp-$(basename "$cfg" .toml)"
        services+=("$name")
    done
    printf '%s\n' "${services[@]}"
}