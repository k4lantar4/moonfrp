#!/bin/bash

#==============================================================================
# MoonFRP Configuration Management
# Version: 2.0.0
# Description: Configuration generation and management for MoonFRP
#==============================================================================

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"

#==============================================================================
# CONFIGURATION FUNCTIONS
#==============================================================================
# Read a TOML key's value (supports dotted keys) from file
get_toml_value() {
    local file="$1"
    local key="$2"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    # Exact key match at line start (allow spaces)
    local pattern="^$(printf '%s' "$key" | sed 's/[].[^$*\\]/\\&/g')\\s*=\\s*"
    local line
    line=$(grep -E "$pattern" "$file" | head -1 || true)
    if [[ -z "$line" ]]; then
        return 1
    fi
    # Extract value after '=' and trim spaces
    echo "$line" | sed -E 's/^[^=]+=\\s*//'
}

# Set or add a TOML key=value (preserves file, replaces first occurrence, adds if missing)
set_toml_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmp_file
    tmp_file="${file}.tmp.$$"
    local escaped_key
    escaped_key=$(printf '%s' "$key" | sed 's/[].[^$*\\]/\\&/g')
    if grep -Eq "^${escaped_key}\\s*=" "$file"; then
        # Replace existing line
        sed -E "s|^(${escaped_key}\\s*=).*|\\1 ${value}|" "$file" > "$tmp_file"
    else
        # Append at end
        cp "$file" "$tmp_file"
        echo "${key} = ${value}" >> "$tmp_file"
    fi
    mv "$tmp_file" "$file"
}


# Generate server configuration
generate_server_config() {
    local config_file="$CONFIG_DIR/frps.toml"
    local auth_token="${1:-$DEFAULT_SERVER_AUTH_TOKEN}"
    
    # Generate token if not provided
    if [[ -z "$auth_token" ]]; then
        auth_token=$(generate_token)
        log "INFO" "Generated server auth token: $auth_token"
    fi
    
    # Generate dashboard password if not provided
    local dashboard_password="${2:-$DEFAULT_SERVER_DASHBOARD_PASSWORD}"
    if [[ -z "$dashboard_password" ]]; then
        dashboard_password=$(generate_token 16)
        log "INFO" "Generated dashboard password: $dashboard_password"
    fi
    
    cat > "$config_file" << EOF
# MoonFRP Server Configuration
# Generated on $(date)

bindAddr = "$DEFAULT_SERVER_BIND_ADDR"
bindPort = $DEFAULT_SERVER_BIND_PORT
quicBindPort = $DEFAULT_SERVER_BIND_PORT

# Authentication
auth.method = "$DEFAULT_AUTH_METHOD"
auth.token = "$auth_token"

# Dashboard
webServer.addr = "$DEFAULT_SERVER_BIND_ADDR"
webServer.port = $DEFAULT_SERVER_DASHBOARD_PORT
webServer.user = "$DEFAULT_SERVER_DASHBOARD_USER"
webServer.password = "$dashboard_password"
webServer.pprofEnable = false

# Logging
log.to = "$LOG_DIR/frps.log"
log.level = "$DEFAULT_LOG_LEVEL"
log.maxDays = $DEFAULT_LOG_MAX_DAYS
log.disablePrintColor = $DEFAULT_LOG_DISABLE_COLOR

# Transport
# transport.tls.enable = $DEFAULT_TLS_ENABLE
# transport.tls.force = $DEFAULT_TLS_FORCE
# sample override: maximize connection pool per client
transport.maxPoolCount = 65535
transport.tcpMux = false
transport.tcpMuxKeepaliveInterval = 10
transport.tcpKeepalive = 120
# transport.heartbeatInterval = $DEFAULT_HEARTBEAT_INTERVAL
transport.heartbeatTimeout = 90
transport.quic.keepalivePeriod = 10
transport.quic.maxIdleTimeout = 30
transport.quic.maxIncomingStreams = 100000

# Performance
userConnTimeout = 10
maxPortsPerClient = 100

# Security
# detailedErrorsToClient = true

# HTTP/HTTPS
vhostHTTPPort = 80
vhostHTTPSPort = 443

# UDP
udpPacketSize = 1500

# NAT hole punching
natholeAnalysisDataReserveHours = 168
EOF
    
    log "INFO" "Generated server configuration: $config_file"
    echo "$auth_token"
}

# Generate client configuration
generate_client_config() {
    local server_addr="$1"
    local server_port="$2"
    local auth_token="$3"
    local client_user="$4"
    local config_suffix="${5:-}"
    local local_ports="${6:-}"
    
    local config_file="$CONFIG_DIR/frpc${config_suffix}.toml"
    
    # Generate client user if not provided
    if [[ -z "$client_user" ]]; then
        client_user="moonfrp${config_suffix}"
    fi
    
    # Calculate webServer port from suffix (extract numeric part)
    local web_port_offset=0
    if [[ -n "$config_suffix" ]]; then
        local numeric_part=$(echo "$config_suffix" | sed 's/[^0-9]//g')
        web_port_offset=${numeric_part:-0}
        # Limit offset to prevent port conflicts (max 999)
        if [[ $web_port_offset -gt 999 ]]; then
            web_port_offset=$((web_port_offset % 1000))
        fi
    fi
    local web_port=$((7400 + web_port_offset))
    
    cat > "$config_file" << EOF
# MoonFRP Client Configuration
# Generated on $(date)

user = "$client_user"
serverAddr = "$server_addr"
serverPort = $server_port

# Authentication
auth.method = "$DEFAULT_AUTH_METHOD"
auth.token = "$auth_token"

# Logging
log.to = "$LOG_DIR/frpc${config_suffix}.log"
log.level = "$DEFAULT_LOG_LEVEL"
log.maxDays = $DEFAULT_LOG_MAX_DAYS
log.disablePrintColor = $DEFAULT_LOG_DISABLE_COLOR

# Transport
transport.protocol = "tcp"
transport.tcpMux = false
transport.tcpMuxKeepaliveInterval = 10
transport.dialServerTimeout = 10
transport.dialServerKeepalive = 120
transport.poolCount = 20
transport.heartbeatInterval = 30
transport.heartbeatTimeout = 90
transport.tls.enable = false
transport.quic.keepalivePeriod = 10
transport.quic.maxIdleTimeout = 30
transport.quic.maxIncomingStreams = 100000

# Performance
loginFailExit = false
udpPacketSize = 1500

# Web server for control
webServer.addr = "127.0.0.1"
webServer.port = $web_port
webServer.user = "admin"
webServer.password = "$(generate_token 16)"
webServer.pprofEnable = false
EOF
    
    # Add proxy configurations if local ports are provided
    if [[ -n "$local_ports" ]]; then
        IFS=',' read -ra PORTS <<< "$local_ports"
        for port in "${PORTS[@]}"; do
            if validate_port "$port"; then
                cat >> "$config_file" << EOF

[[proxies]]
name = "tcp_${port}${config_suffix}"
type = "tcp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port
EOF
            fi
        done
    fi
    
    log "INFO" "Generated client configuration: $config_file"
}

# Generate multi-IP client configurations
generate_multi_ip_configs() {
    local server_ips="$1"
    local server_ports="$2"
    local client_ports="$3"
    local auth_token="$4"
    
    if [[ -z "$server_ips" || -z "$server_ports" ]]; then
        log "ERROR" "Server IPs and ports are required for multi-IP configuration"
        return 1
    fi
    
    IFS=',' read -ra IPS <<< "$server_ips"
    IFS=',' read -ra SRV_PORTS_ARRAY <<< "$server_ports"
    
    # Validate array lengths
    if [[ ${#IPS[@]} -ne ${#SRV_PORTS_ARRAY[@]} ]]; then
        log "WARN" "Server IPs count (${#IPS[@]}) doesn't match server ports count (${#SRV_PORTS_ARRAY[@]})"
    fi
    
    # Use server ports as client ports if not specified
    if [[ -z "$client_ports" ]]; then
        client_ports="$server_ports"
    fi
    
    IFS=',' read -ra CLI_PORTS_ARRAY <<< "$client_ports"
    
    # Validate client ports array length
    if [[ ${#IPS[@]} -ne ${#CLI_PORTS_ARRAY[@]} ]]; then
        log "WARN" "Server IPs count (${#IPS[@]}) doesn't match client ports count (${#CLI_PORTS_ARRAY[@]})"
    fi
    
    local config_count=0
    for i in "${!IPS[@]}"; do
        local ip="${IPS[i]}"
        local server_port="${SRV_PORTS_ARRAY[i]:-7000}"
        local client_port="${CLI_PORTS_ARRAY[i]:-8080}"
        
        if validate_ip "$ip" && validate_port "$server_port"; then
            # Extract last octet from IP for filename (e.g., 185.177.177.177 -> 177)
            local ip_last_octet=$(echo "$ip" | awk -F'.' '{print $4}')
            local config_suffix="-${ip_last_octet}"
            local client_user="moonfrp-${ip_last_octet}"
            
            ((config_count++))
            generate_client_config "$ip" "$server_port" "$auth_token" "$client_user" "$config_suffix" "$client_port"
        else
            log "WARN" "Skipping invalid IP/port: $ip:$server_port"
        fi
    done
    
    log "INFO" "Generated $config_count multi-IP client configurations"
}

# Generate visitor configuration
generate_visitor_config() {
    local server_name="$1"
    local secret_key="$2"
    local bind_port="$3"
    local config_suffix="${4:-}"
    
    local config_file="$CONFIG_DIR/visitor${config_suffix}.toml"
    
    # Generate secret key if not provided
    if [[ -z "$secret_key" ]]; then
        secret_key=$(generate_token)
        log "INFO" "Generated secret key: $secret_key"
    fi
    
    cat > "$config_file" << EOF
# MoonFRP Visitor Configuration
# Generated on $(date)

user = "visitor${config_suffix}"
serverAddr = "$DEFAULT_CLIENT_SERVER_ADDR"
serverPort = $DEFAULT_CLIENT_SERVER_PORT

# Authentication
auth.method = "$DEFAULT_AUTH_METHOD"
auth.token = "$DEFAULT_CLIENT_AUTH_TOKEN"

# Logging
log.to = "$LOG_DIR/visitor${config_suffix}.log"
log.level = "$DEFAULT_LOG_LEVEL"
log.maxDays = $DEFAULT_LOG_MAX_DAYS
log.disablePrintColor = $DEFAULT_LOG_DISABLE_COLOR

# Transport
transport.tls.enable = $DEFAULT_TLS_ENABLE
transport.poolCount = $DEFAULT_POOL_COUNT
transport.tcpMux = $DEFAULT_TCP_MUX

# Visitors
[[visitors]]
name = "visitor_${server_name}${config_suffix}"
type = "stcp"
serverName = "$server_name"
secretKey = "$secret_key"
bindAddr = "127.0.0.1"
bindPort = $bind_port
EOF
    
    log "INFO" "Generated visitor configuration: $config_file"
    echo "$secret_key"
}

# Validate configuration syntax
validate_config_syntax() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check if it's a TOML file
    if [[ "$config_file" == *.toml ]]; then
        # Basic TOML syntax check
        if grep -q "=" "$config_file" && ! grep -q "^\[\[.*\]\]" "$config_file" || grep -q "^\[.*\]" "$config_file"; then
            log "DEBUG" "TOML syntax appears valid: $config_file"
            return 0
        else
            log "ERROR" "Invalid TOML syntax in: $config_file"
            return 1
        fi
    else
        log "WARN" "Unknown configuration file format: $config_file"
        return 1
    fi
}

# Backup configuration
backup_config() {
    local config_file="$1"
    local backup_dir="$CONFIG_DIR/backups"
    
    if [[ ! -f "$config_file" ]]; then
        log "WARN" "Configuration file not found: $config_file"
        return 1
    fi
    
    mkdir -p "$backup_dir"
    
    local filename=$(basename "$config_file")
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$backup_dir/${filename}.backup.$timestamp"
    
    cp "$config_file" "$backup_file"
    log "INFO" "Backed up configuration: $backup_file"
    
    # Clean up old backups (keep last 10)
    find "$backup_dir" -name "${filename}.backup.*" -type f | sort -r | tail -n +11 | xargs rm -f
}

# Restore configuration from backup
restore_config() {
    local config_file="$1"
    local backup_file="$2"
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    backup_config "$config_file"
    cp "$backup_file" "$config_file"
    log "INFO" "Restored configuration from: $backup_file"
}

# List available configurations
list_configurations() {
    check_and_update_index 2>/dev/null || true
    
    echo -e "${CYAN}Available FRP Configurations:${NC}"
    echo
    
    # Server configurations - try indexed query first, fallback to file parsing
    local server_configs
    if server_configs=$(query_configs_by_type "server" 2>/dev/null); then
        if [[ -n "$server_configs" ]]; then
            echo -e "${GREEN}Server Configuration:${NC}"
            while IFS='|' read -r file_path server_addr proxy_count; do
                echo "  File: $file_path"
                [[ -n "$server_addr" ]] && echo "  Server: $server_addr"
                echo "  Proxies: $proxy_count"
                echo "  Status: $(get_service_status "$SERVER_SERVICE")"
                echo
            done <<< "$server_configs"
        fi
    else
        if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
            echo -e "${GREEN}Server Configuration:${NC}"
            echo "  File: $CONFIG_DIR/frps.toml"
            echo "  Status: $(get_service_status "$SERVER_SERVICE")"
            echo
        fi
    fi
    
    # Client configurations - try indexed query first, fallback to file parsing
    local client_configs_data
    if client_configs_data=$(query_configs_by_type "client" 2>/dev/null); then
        if [[ -n "$client_configs_data" ]]; then
            echo -e "${GREEN}Client Configurations:${NC}"
            while IFS='|' read -r file_path server_addr proxy_count; do
                local config_name=$(basename "$file_path" .toml)
                local service_name="${CLIENT_SERVICE_PREFIX}-${config_name#frpc}"
                echo "  File: $file_path"
                [[ -n "$server_addr" ]] && echo "  Server: $server_addr"
                echo "  Proxies: $proxy_count"
                echo "  Service: $service_name"
                echo "  Status: $(get_service_status "$service_name")"
                echo
            done <<< "$client_configs_data"
        fi
    else
        local client_configs=($(find "$CONFIG_DIR" -name "frpc*.toml" -type f | sort))
        if [[ ${#client_configs[@]} -gt 0 ]]; then
            echo -e "${GREEN}Client Configurations:${NC}"
            for config in "${client_configs[@]}"; do
                local config_name=$(basename "$config" .toml)
                local service_name="${CLIENT_SERVICE_PREFIX}-${config_name#frpc}"
                echo "  File: $config"
                echo "  Service: $service_name"
                echo "  Status: $(get_service_status "$service_name")"
                echo
            done
        fi
    fi
    
    # Visitor configurations (not indexed, use file parsing)
    local visitor_configs=($(find "$CONFIG_DIR" -name "visitor*.toml" -type f | sort))
    if [[ ${#visitor_configs[@]} -gt 0 ]]; then
        echo -e "${GREEN}Visitor Configurations:${NC}"
        for config in "${visitor_configs[@]}"; do
            local config_name=$(basename "$config" .toml)
            echo "  File: $config"
            echo
        done
    fi
}

# Interactive configuration wizard
config_wizard() {
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        MoonFRP Configuration         ║${NC}"
    echo -e "${PURPLE}║            Setup Wizard              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo
    
    echo -e "${CYAN}This wizard will help you configure MoonFRP.${NC}"
    echo -e "${CYAN}You can press Ctrl+C at any time to cancel.${NC}"
    echo
    
    # Configuration type selection
    echo -e "${YELLOW}Select configuration type:${NC}"
    echo "1. Server (frps)"
    echo "2. Client (frpc)"
    echo "3. Multi-IP Client"
    echo "4. Visitor (stcp/xtcp)"
    echo "0. Cancel"
    echo
    
    safe_read "Enter your choice" "config_type" "1"
    
    case "$config_type" in
        1)
            config_server_wizard
            ;;
        2)
            config_client_wizard
            ;;
        3)
            config_multi_ip_wizard
            ;;
        4)
            config_visitor_wizard
            ;;
        0)
            log "INFO" "Configuration cancelled"
            return 0
            ;;
        *)
            log "ERROR" "Invalid choice"
            return 1
            ;;
    esac
}

# Server configuration wizard
config_server_wizard() {
    echo -e "${CYAN}Server Configuration Wizard${NC}"
    echo
    
    local bind_addr bind_port auth_token dashboard_port dashboard_user dashboard_password
    local existing_file="$CONFIG_DIR/frps.toml"
    
    # If existing config, read current values as defaults
    local def_bind_addr="$DEFAULT_SERVER_BIND_ADDR"
    local def_bind_port="$DEFAULT_SERVER_BIND_PORT"
    local def_auth_token="$DEFAULT_SERVER_AUTH_TOKEN"
    local def_dash_port="$DEFAULT_SERVER_DASHBOARD_PORT"
    local def_dash_user="$DEFAULT_SERVER_DASHBOARD_USER"
    if [[ -f "$existing_file" ]]; then
        def_bind_addr=$(get_toml_value "$existing_file" "bindAddr" | sed 's/["\'']//g' || echo "$def_bind_addr")
        def_bind_port=$(get_toml_value "$existing_file" "bindPort" | tr -d '"' || echo "$def_bind_port")
        def_auth_token=$(get_toml_value "$existing_file" "auth.token" | sed 's/["\'']//g' || echo "$def_auth_token")
        def_dash_port=$(get_toml_value "$existing_file" "webServer.port" | tr -d '"' || echo "$def_dash_port")
        def_dash_user=$(get_toml_value "$existing_file" "webServer.user" | sed 's/["\'']//g' || echo "$def_dash_user")
    fi
    
    safe_read "Server bind address" "bind_addr" "$def_bind_addr"
    while ! validate_ip "$bind_addr" && [[ "$bind_addr" != "0.0.0.0" ]]; do
        log "ERROR" "Invalid IP address"
        safe_read "Server bind address" "bind_addr" "$DEFAULT_SERVER_BIND_ADDR"
    done
    
    safe_read "Server bind port" "bind_port" "$def_bind_port"
    while ! validate_port "$bind_port"; do
        log "ERROR" "Invalid port number"
        safe_read "Server bind port" "bind_port" "$DEFAULT_SERVER_BIND_PORT"
    done
    
    safe_read "Auth token (leave empty to keep/generate)" "auth_token" "$def_auth_token"
    
    safe_read "Dashboard port" "dashboard_port" "$def_dash_port"
    while ! validate_port "$dashboard_port"; do
        log "ERROR" "Invalid port number"
        safe_read "Dashboard port" "dashboard_port" "$DEFAULT_SERVER_DASHBOARD_PORT"
    done
    
    safe_read "Dashboard username" "dashboard_user" "$def_dash_user"
    safe_read "Dashboard password (leave empty to keep/generate)" "dashboard_password" ""
    
    # If no existing config, generate new; else update keys in place
    if [[ ! -f "$existing_file" ]]; then
        local generated_token=$(generate_server_config "$auth_token" "$dashboard_password")
        echo
        log "INFO" "Server configuration generated successfully!"
        echo -e "${GREEN}Configuration file:${NC} $CONFIG_DIR/frps.toml"
        echo -e "${GREEN}Auth token:${NC} $generated_token"
        echo -e "${GREEN}Dashboard:${NC} http://$bind_addr:$dashboard_port"
        echo -e "${GREEN}Username:${NC} $dashboard_user"
        echo -e "${GREEN}Password:${NC} ${dashboard_password:-$(grep 'webServer.password' "$CONFIG_DIR/frps.toml" | cut -d'"' -f2)}"
    else
        backup_config "$existing_file"
        set_toml_value "$existing_file" "bindAddr" "\"$bind_addr\""
        set_toml_value "$existing_file" "bindPort" "$bind_port"
        if [[ -n "$auth_token" ]]; then
            set_toml_value "$existing_file" "auth.token" "\"$auth_token\""
        fi
        set_toml_value "$existing_file" "webServer.port" "$dashboard_port"
        set_toml_value "$existing_file" "webServer.user" "\"$dashboard_user\""
        if [[ -n "$dashboard_password" ]]; then
            set_toml_value "$existing_file" "webServer.password" "\"$dashboard_password\""
        fi
        echo
        log "INFO" "Server configuration updated in-place: $existing_file"
        echo -e "${GREEN}Dashboard:${NC} http://$bind_addr:$dashboard_port"
    fi
}

# Client configuration wizard
config_client_wizard() {
    echo -e "${CYAN}Client Configuration Wizard${NC}"
    echo
    
    local server_addr server_port auth_token client_user local_ports
    local existing_file="$CONFIG_DIR/frpc.toml"
    
    # Read defaults from existing config if present
    local def_server_addr="$DEFAULT_CLIENT_SERVER_ADDR"
    local def_server_port="$DEFAULT_CLIENT_SERVER_PORT"
    local def_auth_token="$DEFAULT_CLIENT_AUTH_TOKEN"
    local def_client_user="$DEFAULT_CLIENT_USER"
    if [[ -f "$existing_file" ]]; then
        def_server_addr=$(get_toml_value "$existing_file" "serverAddr" | sed 's/["\'']//g' || echo "$def_server_addr")
        def_server_port=$(get_toml_value "$existing_file" "serverPort" | tr -d '"' || echo "$def_server_port")
        def_auth_token=$(get_toml_value "$existing_file" "auth.token" | sed 's/["\'']//g' || echo "$def_auth_token")
        def_client_user=$(get_toml_value "$existing_file" "user" | sed 's/["\'']//g' || echo "$def_client_user")
    fi
    
    safe_read "Server address" "server_addr" "$def_server_addr"
    while ! validate_ip "$server_addr"; do
        log "ERROR" "Invalid IP address"
        safe_read "Server address" "server_addr" "$DEFAULT_CLIENT_SERVER_ADDR"
    done
    
    safe_read "Server port" "server_port" "$def_server_port"
    while ! validate_port "$server_port"; do
        log "ERROR" "Invalid port number"
        safe_read "Server port" "server_port" "$DEFAULT_CLIENT_SERVER_PORT"
    done
    
    safe_read "Auth token" "auth_token" "$def_auth_token"
    safe_read "Client username" "client_user" "$def_client_user"
    safe_read "Local ports to proxy (comma-separated)" "local_ports" ""
    
    if [[ ! -f "$existing_file" ]]; then
        # Generate configuration
        generate_client_config "$server_addr" "$server_port" "$auth_token" "$client_user" "" "$local_ports"
        echo
        log "INFO" "Client configuration generated successfully!"
        echo -e "${GREEN}Configuration file:${NC} $CONFIG_DIR/frpc.toml"
    else
        backup_config "$existing_file"
        set_toml_value "$existing_file" "serverAddr" "\"$server_addr\""
        set_toml_value "$existing_file" "serverPort" "$server_port"
        set_toml_value "$existing_file" "auth.token" "\"$auth_token\""
        set_toml_value "$existing_file" "user" "\"$client_user\""
        echo
        log "INFO" "Client configuration updated in-place: $existing_file"
        if [[ -n "$local_ports" ]]; then
            echo -e "${YELLOW}Note:${NC} Local ports input provided; add/update proxies manually if needed."
        fi
    fi
}

# Multi-IP configuration wizard
config_multi_ip_wizard() {
    echo -e "${CYAN}Multi-IP Client Configuration Wizard${NC}"
    echo
    
    local server_ips server_ports client_ports auth_token
    
    safe_read "Server IPs (comma-separated)" "server_ips" "$SERVER_IPS"
    safe_read "Server ports (comma-separated)" "server_ports" "$SERVER_PORTS"
    safe_read "Client ports (comma-separated)" "client_ports" "$CLIENT_PORTS"
    safe_read "Auth token" "auth_token" "$DEFAULT_CLIENT_AUTH_TOKEN"
    
    # Generate configurations
    generate_multi_ip_configs "$server_ips" "$server_ports" "$client_ports" "$auth_token"
    
    echo
    log "INFO" "Multi-IP client configurations generated successfully!"
}

# Visitor configuration wizard
config_visitor_wizard() {
    echo -e "${CYAN}Visitor Configuration Wizard${NC}"
    echo
    
    local server_name secret_key bind_port
    
    safe_read "Server name" "server_name" ""
    safe_read "Secret key (leave empty to generate)" "secret_key" ""
    safe_read "Bind port" "bind_port" "9000"
    while ! validate_port "$bind_port"; do
        log "ERROR" "Invalid port number"
        safe_read "Bind port" "bind_port" "9000"
    done
    
    # Generate configuration
    local generated_secret=$(generate_visitor_config "$server_name" "$secret_key" "$bind_port")
    
    echo
    log "INFO" "Visitor configuration generated successfully!"
    echo -e "${GREEN}Configuration file:${NC} $CONFIG_DIR/visitor.toml"
    echo -e "${GREEN}Secret key:${NC} $generated_secret"
}

# Export functions
export -f generate_server_config generate_client_config generate_multi_ip_configs
export -f generate_visitor_config validate_config_syntax backup_config restore_config
export -f list_configurations config_wizard config_server_wizard config_client_wizard
export -f config_multi_ip_wizard config_visitor_wizard