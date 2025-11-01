# FRP CLI Features Analysis - Unused Capabilities in moonfrp Scripts

## Executive Summary

This document analyzes FRP (Fast Reverse Proxy) CLI commands and features that are **not currently utilized** in the moonfrp*.sh scripts but could significantly enhance their functionality. The focus is on CLI command outputs and direct command execution, not TOML configuration files.

**Current Usage in moonfrp Scripts:**
- `frps -c config_file` - Start server with config file
- `frpc -c config_file` - Start client with config file  
- `frps --version` - Check version

**Missing CLI Capabilities Identified:** Multiple CLI subcommands and options that enable direct proxy creation without config files.

---

## 1. FRP CLI Subcommands (CRITICAL - Not Used)

### 1.1 TCP Proxy CLI Subcommand

**Feature:** Create TCP proxies directly from command line without TOML files.

**Example from frp documentation:**
```bash
# Equivalent to creating a proxy in config, but done via CLI
frpc tcp --proxy_name "test-tcp" \
         --local_ip 127.0.0.1 \
         --local_port 8080 \
         --remote_port 9090 \
         --server_addr x.x.x.x \
         --server_port 7000 \
         --auth_token your_token
```

**Benefits for moonfrp:**
- Quick temporary proxy creation
- Testing without editing config files
- Dynamic proxy management
- Script-friendly operations

**Implementation suggestion:**
```bash
# Add to moonfrp.sh
proxy_tcp_create() {
    local proxy_name="$1"
    local local_ip="$2"
    local local_port="$3"
    local remote_port="$4"
    local server_addr="$5"
    local server_port="${6:-7000}"
    local auth_token="$7"
    
    "$FRP_DIR/frpc" tcp \
        --proxy_name "$proxy_name" \
        --local_ip "$local_ip" \
        --local_port "$local_port" \
        --remote_port "$remote_port" \
        --server_addr "$server_addr" \
        --server_port "$server_port" \
        --auth_token "$auth_token"
}
```

---

### 1.2 UDP Proxy CLI Subcommand

**Feature:** Create UDP proxies via CLI.

**Example:**
```bash
frpc udp --proxy_name "test-udp" \
         --local_ip 127.0.0.1 \
         --local_port 53 \
         --remote_port 5353 \
         --server_addr x.x.x.x \
         --server_port 7000 \
         --auth_token your_token
```

**Benefits:**
- DNS tunneling support
- UDP service forwarding
- Quick UDP proxy setup

---

### 1.3 HTTP/HTTPS Proxy CLI Subcommands

**Feature:** Create HTTP/HTTPS proxies via CLI.

**Example:**
```bash
frpc http --proxy_name "web01" \
          --local_port 80 \
          --custom_domains web.example.com \
          --server_addr x.x.x.x \
          --server_port 7000 \
          --auth_token your_token
```

**Benefits:**
- Quick web service exposure
- Domain-based routing
- No config file editing needed

---

### 1.4 STCP/XTCP CLI Subcommands (P2P Tunnels)

**Feature:** Create secure TCP proxies with visitor mode support.

**Example:**
```bash
# Create STCP server-side proxy
frpc stcp --proxy_name "secret-tcp" \
          --server_name "my-service" \
          --secret_key "your-secret-key" \
          --local_ip 127.0.0.1 \
          --local_port 22 \
          --server_addr x.x.x.x \
          --server_port 7000 \
          --auth_token your_token

# Create visitor (client-side)
frpc visitor --role visitor \
             --server_name "my-service" \
             --secret_key "your-secret-key" \
             --bind_addr 127.0.0.1 \
             --bind_port 9000 \
             --server_addr x.x.x.x \
             --server_port 7000 \
             --auth_token your_token
```

**Benefits:**
- Secure P2P tunneling
- Visitor mode support
- No need for separate visitor config files

---

## 2. SSH Tunnel Gateway Feature (Not Used)

**Feature:** Use SSH protocol for tunneling instead of frpc binary.

**From frp documentation:**
```bash
# SSH Tunnel Gateway - No frpc needed!
ssh -R :80:127.0.0.1:8080 v0@{frp_address} -p 2200 tcp \
    --proxy_name "test-tcp" \
    --remote_port 9090
```

**Benefits:**
- No frpc binary required on client
- Uses standard SSH client
- Lightweight solution
- Works where SSH is available but frp binaries aren't

**Implementation suggestion:**
```bash
# Add SSH tunnel gateway support to moonfrp
setup_ssh_tunnel() {
    local local_port="$1"
    local local_host="${2:-127.0.0.1}"
    local proxy_name="$3"
    local remote_port="$4"
    local frp_server="$5"
    local ssh_port="${6:-2200}"
    
    ssh -R ":${local_port}:${local_host}:${local_port}" \
        "v0@${frp_server}" \
        -p "${ssh_port}" \
        "tcp" \
        --proxy_name "$proxy_name" \
        --remote_port "$remote_port"
}
```

---

## 3. CLI Configuration Validation (Not Used)

**Feature:** Validate config files without starting service.

**Example:**
```bash
# Check if config syntax is valid
frpc verify -c /etc/frp/frpc.toml

# Or dry-run mode
frps --config /etc/frp/frps.toml --dry-run
```

**Benefits:**
- Validate configs before service start
- Prevent service failures
- Better error messages

---

## 4. CLI Reload Command (Not Used)

**Feature:** Reload configuration without restarting service.

**From frp documentation, frpc has HTTP API for reload:**
```bash
# Reload frpc configuration
curl -X POST http://127.0.0.1:7400/api/config/reload
```

**Benefits:**
- Zero-downtime config updates
- No service interruption
- Better service management

**Implementation suggestion:**
```bash
reload_frpc_config() {
    local service_name="$1"
    local admin_port="${2:-7400}"
    
    # Get admin port from service
    local admin_addr="127.0.0.1"
    
    curl -X POST "http://${admin_addr}:${admin_port}/api/config/reload" || {
        log "ERROR" "Failed to reload config for $service_name"
        return 1
    }
    
    log "INFO" "Configuration reloaded for $service_name"
}
```

---

## 5. CLI Status/Info Commands (Not Used)

**Feature:** Get proxy status and information via CLI.

**Examples:**
```bash
# Get proxy status from frpc admin API
curl http://127.0.0.1:7400/api/proxy/tcp/test-tcp/status

# List all proxies
curl http://127.0.0.1:7400/api/proxy

# Get server info from frps
curl http://127.0.0.1:7500/api/serverinfo
```

**Benefits:**
- Real-time proxy status
- Monitoring integration
- Health check improvements

**Implementation suggestion:**
```bash
get_proxy_status() {
    local proxy_name="$1"
    local admin_port="${2:-7400}"
    local admin_addr="127.0.0.1"
    
    curl -s "http://${admin_addr}:${admin_port}/api/proxy/tcp/${proxy_name}/status" \
        | jq -r '.status' || echo "unknown"
}

list_all_proxies() {
    local admin_port="${1:-7400}"
    local admin_addr="127.0.0.1"
    
    curl -s "http://${admin_addr}:${admin_port}/api/proxy" \
        | jq -r '.proxies[] | "\(.name) - \(.type) - \(.status)"' || {
        log "ERROR" "Failed to list proxies"
    }
}
```

---

## 6. CLI Proxy Management (Not Used)

**Feature:** Start/stop individual proxies dynamically.

**Examples:**
```bash
# Start a specific proxy
curl -X POST http://127.0.0.1:7400/api/proxy/tcp/test-tcp/start

# Stop a specific proxy
curl -X POST http://127.0.0.1:7400/api/proxy/tcp/test-tcp/stop

# Get proxy statistics
curl http://127.0.0.1:7400/api/proxy/tcp/test-tcp/stats
```

**Benefits:**
- Fine-grained control
- Individual proxy management
- Better resource utilization

---

## 7. CLI Health Check Integration (Not Used)

**Feature:** Use frpc/frps health check endpoints.

**Examples:**
```bash
# Check frpc health
curl http://127.0.0.1:7400/healthz

# Check frps health  
curl http://127.0.0.1:7500/healthz

# Get detailed health info
curl http://127.0.0.1:7400/api/health
```

**Benefits:**
- Better health checks
- Monitoring integration
- Automated testing

**Implementation suggestion:**
```bash
enhanced_health_check() {
    # Check frpc services
    local frpc_services=($(systemctl list-unit-files | grep "moonfrp-client" | awk '{print $1}' | sed 's/.service$//'))
    
    for service in "${frpc_services[@]}"; do
        local admin_port=$(get_admin_port_for_service "$service")
        if curl -sf "http://127.0.0.1:${admin_port}/healthz" > /dev/null; then
            echo -e "${GREEN}✓${NC} $service is healthy"
        else
            echo -e "${RED}✗${NC} $service health check failed"
        fi
    done
    
    # Check frps service
    if systemctl is-active --quiet "$SERVER_SERVICE"; then
        local dash_port=$(get_dashboard_port)
        if curl -sf "http://127.0.0.1:${dash_port}/healthz" > /dev/null; then
            echo -e "${GREEN}✓${NC} $SERVER_SERVICE is healthy"
        else
            echo -e "${RED}✗${NC} $SERVER_SERVICE health check failed"
        fi
    fi
}
```

---

## 8. CLI Log Level Control (Not Used)

**Feature:** Change log levels dynamically without restart.

**Example:**
```bash
# Set log level via API
curl -X PUT http://127.0.0.1:7400/api/config/log/level \
     -H "Content-Type: application/json" \
     -d '{"level": "debug"}'
```

**Benefits:**
- Dynamic debugging
- No service restart needed
- Better troubleshooting

---

## 9. Port Range Mapping via CLI (Partially Used)

**Feature:** Create multiple proxies from port ranges using Go template syntax.

**From frp documentation:**
```bash
# This can be done via config with template, but CLI could support it
frpc tcp-range --local_range "6000-6007" \
                --remote_range "6000-6007" \
                --server_addr x.x.x.x \
                --server_port 7000 \
                --auth_token your_token
```

**Note:** While the documentation shows this as config-based template feature, CLI implementation would be valuable.

---

## 10. Feature Gates CLI Control (Not Used)

**Feature:** Enable/disable experimental features via CLI.

**From frp documentation:**
```bash
# Enable VirtualNet feature (v0.62.0+)
frps --feature-gates VirtualNet=true -c config.toml

frpc --feature-gates VirtualNet=true -c config.toml
```

**Benefits:**
- Test experimental features
- Enable features per-instance
- No config file modification

---

## 11. CLI Verbosity and Debug Options (Not Used)

**Feature:** Enhanced logging and debug output.

**Examples:**
```bash
# Verbose output
frpc -c config.toml --verbose

# Debug mode
frpc -c config.toml --debug

# Log to specific file
frpc -c config.toml --log-file /var/log/frp/debug.log

# Log level override
frpc -c config.toml --log-level debug
```

**Benefits:**
- Better troubleshooting
- Temporary debug sessions
- Script debugging

---

## 12. CLI Proxy Protocol Support (Not Used)

**Feature:** Enable proxy protocol via CLI flags.

**Example:**
```bash
frpc http --proxy_name "web01" \
          --local_port 80 \
          --proxy_protocol_version v2 \
          --server_addr x.x.x.x \
          --auth_token your_token
```

**Benefits:**
- Preserve client IP
- Better proxy chain support
- Network transparency

---

## Implementation Priority Recommendations

### HIGH PRIORITY (Immediate Value)

1. **CLI Subcommands for TCP/UDP/HTTP proxies** - Enable quick proxy creation
2. **Config Validation Commands** - Prevent service failures
3. **Reload Command via API** - Zero-downtime updates
4. **Status/Info Commands** - Better monitoring

### MEDIUM PRIORITY (Useful Enhancements)

5. **SSH Tunnel Gateway Support** - Alternative lightweight solution
6. **Health Check Integration** - Better health monitoring
7. **Dynamic Log Level Control** - Better debugging

### LOW PRIORITY (Nice to Have)

8. **Individual Proxy Start/Stop** - Fine-grained control
9. **Feature Gates CLI** - Experimental features
10. **Proxy Protocol CLI** - Advanced networking

---

## Example Integration Code

### Complete CLI Proxy Creation Function

```bash
# Add to moonfrp-core.sh or new moonfrp-cli.sh

create_proxy_cli() {
    local proxy_type="$1"  # tcp, udp, http, https, stcp, xtcp
    local proxy_name="$2"
    local local_ip="${3:-127.0.0.1}"
    local local_port="$4"
    local remote_port="$5"
    local server_addr="$6"
    local server_port="${7:-7000}"
    local auth_token="$8"
    local additional_args="${9:-}"
    
    case "$proxy_type" in
        tcp|udp)
            "$FRP_DIR/frpc" "$proxy_type" \
                --proxy_name "$proxy_name" \
                --local_ip "$local_ip" \
                --local_port "$local_port" \
                --remote_port "$remote_port" \
                --server_addr "$server_addr" \
                --server_port "$server_port" \
                --auth_token "$auth_token" \
                $additional_args
            ;;
        http|https)
            local custom_domains="${additional_args}"
            "$FRP_DIR/frpc" "$proxy_type" \
                --proxy_name "$proxy_name" \
                --local_port "$local_port" \
                --custom_domains "$custom_domains" \
                --server_addr "$server_addr" \
                --server_port "$server_port" \
                --auth_token "$auth_token"
            ;;
        *)
            log "ERROR" "Unsupported proxy type: $proxy_type"
            return 1
            ;;
    esac
}

# Validate config without starting
validate_frp_config() {
    local config_file="$1"
    local binary_type="${2:-frpc}"  # frpc or frps
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Config file not found: $config_file"
        return 1
    fi
    
    # Try to validate (if frp supports --validate or --check flag)
    if "$FRP_DIR/$binary_type" --check -c "$config_file" 2>&1; then
        log "INFO" "Configuration is valid: $config_file"
        return 0
    else
        log "ERROR" "Configuration validation failed: $config_file"
        return 1
    fi
}

# Reload config via API
reload_frpc_config_api() {
    local admin_port="${1:-7400}"
    local admin_addr="${2:-127.0.0.1}"
    
    local response=$(curl -s -X POST "http://${admin_addr}:${admin_port}/api/config/reload")
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "Configuration reloaded successfully"
        return 0
    else
        log "ERROR" "Failed to reload configuration"
        return 1
    fi
}

# Get proxy status via API
get_proxy_status_api() {
    local proxy_name="$1"
    local proxy_type="${2:-tcp}"
    local admin_port="${3:-7400}"
    local admin_addr="${4:-127.0.0.1}"
    
    curl -s "http://${admin_addr}:${admin_port}/api/proxy/${proxy_type}/${proxy_name}/status" \
        | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown"
}
```

---

## Conclusion

The moonfrp scripts currently use only basic FRP CLI functionality (`-c` for config file and `--version`). By implementing the CLI subcommands and API integration features identified above, the scripts can:

1. **Enable quick proxy creation** without config file editing
2. **Provide better monitoring** through status APIs
3. **Support zero-downtime updates** via reload commands
4. **Improve troubleshooting** with validation and health checks
5. **Offer alternative deployment methods** (SSH Tunnel Gateway)

These enhancements would make moonfrp significantly more powerful and user-friendly while leveraging the full capabilities of the FRP project.

---

## References

- FRP GitHub: https://github.com/fatedier/frp
- FRP Documentation: https://github.com/fatedier/frp/blob/dev/README.md
- FRP Release v0.65.0 (Latest): https://github.com/fatedier/frp/releases/tag/v0.65.0

