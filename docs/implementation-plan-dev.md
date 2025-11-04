# MoonFRP Implementation Plan - Developer Guide

## Overview

This document provides comprehensive implementation guidance for enhancing MoonFRP with FRP CLI capabilities, performance optimizations, UI improvements, and system management features.

## Priority Implementation Order

### Phase 1: Critical Fixes & Foundation (Must Do First)

#### 1.1 Fix FRP Version Detection
**Location**: `moonfrp-core.sh` - `get_frp_version()` function

**Problem**: Currently shows "vunknown" due to incorrect regex parsing

**Solution**:
```bash
get_frp_version() {
    if check_frp_installation; then
        # Try multiple methods for version detection
        local version=""
        
        # Method 1: frps --version
        version=$("$FRP_DIR/frps" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        
        # Method 2: frpc --version (fallback)
        if [[ -z "$version" ]]; then
            version=$("$FRP_DIR/frpc" --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi
        
        # Method 3: Extract from version string without 'v'
        if [[ -z "$version" ]]; then
            version=$("$FRP_DIR/frps" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            [[ -n "$version" ]] && version="v$version"
        fi
        
        if [[ -n "$version" ]]; then
            echo "$version"
        else
            echo "unknown"
        fi
    else
        echo "not installed"
    fi
}
```

#### 1.2 Enhanced Config File Creation Validation
**Location**: `moonfrp-config.sh`

**Requirements**:
- Validate frps config before saving
- Validate frpc config (single & multi-IP) before saving
- Extract and validate all required fields
- Better error messages

**Implementation**:
```bash
validate_frps_config() {
    local config_file="$1"
    # Check required fields: bindAddr, bindPort, auth.token
    # Validate TOML syntax
    # Test with frps --check if available
}

validate_frpc_config() {
    local config_file="$1"
    # Check required fields: serverAddr, serverPort, auth.token, user
    # Validate all proxies sections
    # Check for conflicts in multi-IP configs
}
```

#### 1.3 Performance Optimization: Lazy Loading
**Location**: `moonfrp-ui.sh` - `main_menu()`

**Problem**: Current implementation loads all status on every menu render

**Solution**: 
- Cache status information
- Load only on demand
- Use background processes for slow operations

```bash
# Cache for menu performance
declare -A MENU_CACHE
MENU_CACHE["status_timestamp"]=""
MENU_CACHE["status_data"]=""
MENU_CACHE_TTL=5  # seconds

get_cached_status() {
    local now=$(date +%s)
    local cache_time="${MENU_CACHE["status_timestamp"]:-0}"
    
    if [[ $((now - cache_time)) -lt $MENU_CACHE_TTL ]] && [[ -n "${MENU_CACHE["status_data"]:-}" ]]; then
        echo "${MENU_CACHE["status_data"]}"
        return
    fi
    
    # Generate fresh status
    local status_data=$(generate_quick_status)
    MENU_CACHE["status_timestamp"]="$now"
    MENU_CACHE["status_data"]="$status_data"
    echo "$status_data"
}
```

### Phase 2: New Module: `moonfrp-optimize.sh`

**Purpose**: System optimization for FRP performance

**Implementation**:

```bash
#!/bin/bash
# moonfrp-optimize.sh - System optimization module

source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"

readonly SYS_PATH="/etc/sysctl.conf"
readonly PROF_PATH="/etc/profile"

# Sysctl optimizations
sysctl_optimizations() {
    # Backup original
    if [[ ! -f "${SYS_PATH}.bak" ]]; then
        cp "$SYS_PATH" "${SYS_PATH}.bak"
        log "INFO" "Backup saved: ${SYS_PATH}.bak"
    fi
    
    log "INFO" "Optimizing network settings..."
    
    # Remove old entries
    sed -i \
        -e '/fs.file-max/d' \
        -e '/net.core.default_qdisc/d' \
        # ... (all sed patterns from m.txt)
        "$SYS_PATH"
    
    # Add optimized parameters
    cat >> "$SYS_PATH" << 'EOFSYSCTL'

################################################################
# MoonFRP Network Optimizations
# Generated on $(date)
################################################################

# File system settings
fs.file-max = 67108864

# Network core settings
net.core.default_qdisc = fq_codel
net.core.netdev_max_backlog = 32768
# ... (all parameters from m.txt)

EOFSYSCTL

    sysctl -p > /dev/null 2>&1
    log "INFO" "Network optimization completed"
}

# System limits optimization
limits_optimizations() {
    log "INFO" "Optimizing system limits..."
    
    # Remove old ulimits
    sed -i '/ulimit -[cdfilmqstuvx]/d' "$PROF_PATH"
    
    # Add new ulimits
    cat >> "$PROF_PATH" << 'EOFLIMITS'

################################################################
# MoonFRP System Limits
################################################################
ulimit -c unlimited
ulimit -d unlimited
# ... (all ulimits from m.txt)

EOFLIMITS
    
    log "INFO" "System limits optimization completed"
}

# Main optimization function
optimize_system() {
    clear
    show_header "System Optimization" "Network & Limits Tuning"
    
    # Check OS
    if ! command -v lsb_release &> /dev/null; then
        log "ERROR" "lsb_release not found. Cannot verify Ubuntu."
        return 1
    fi
    
    local os_name=$(lsb_release -is 2>/dev/null || echo "")
    if [[ "$os_name" != "Ubuntu" ]]; then
        log "WARN" "Optimization tested on Ubuntu. Proceed? (y/N)"
        safe_read "Continue" "confirm" "n"
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    fi
    
    sysctl_optimizations
    limits_optimizations
    
    log "INFO" "System optimization complete!"
    echo
    echo -e "${YELLOW}Note:${NC} Changes to /etc/profile require new shell or: source /etc/profile"
    echo -e "${YELLOW}Note:${NC} Reboot recommended for full effect"
    echo
    
    safe_read "Reboot now? (y/N)" "reboot_confirm" "n"
    if [[ "$reboot_confirm" == "y" || "$reboot_confirm" == "Y" ]]; then
        log "INFO" "Rebooting system..."
        reboot
    fi
}

export -f sysctl_optimizations limits_optimizations optimize_system
```

### Phase 3: Enhanced Configuration Details View

**Location**: `moonfrp-ui.sh` - New function `show_config_details()`

**Replaces**: Current `show_system_status()`

**Implementation**:

```bash
show_config_details() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC} $(printf "%-34s" "MoonFRP Config Details") ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo
    
    # Detect server vs client context
    local is_server=false
    local is_client=false
    
    [[ -f "$CONFIG_DIR/frps.toml" ]] && is_server=true
    [[ -f "$CONFIG_DIR/frpc.toml" ]] && is_client=true
    [[ -n "$(find "$CONFIG_DIR" -name "frpc*.toml" -type f 2>/dev/null)" ]] && is_client=true
    
    # Server Configuration Section
    echo -e "${CYAN}🏠 Server Configurations (Iran):${NC}"
    if [[ "$is_server" == true ]]; then
        local server_port=$(get_toml_value "$CONFIG_DIR/frps.toml" "bindPort" 2>/dev/null | tr -d '"' || echo "7000")
        local auth_token=$(get_toml_value "$CONFIG_DIR/frps.toml" "auth.token" 2>/dev/null | sed 's/["'\'']//g' || echo "")
        local dash_port=$(get_toml_value "$CONFIG_DIR/frps.toml" "webServer.port" 2>/dev/null | tr -d '"' || echo "7500")
        local server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "SERVER-IP")
        
        echo "  Server Port: $server_port"
        if [[ -n "$auth_token" ]]; then
            echo "  Auth Token: ${auth_token:0:12}..."
        fi
        echo "  Dashboard: http://$server_ip:$dash_port"
        echo
        echo "  📋 Share with clients:"
        echo "     • Server IPs: $(get_server_ips_for_sharing)"
        echo "     • Server Port: $server_port"
        echo "     • Token: ${auth_token}"
        
        local server_status=$(get_service_status "$SERVER_SERVICE")
        if [[ "$server_status" == "active" ]]; then
            echo "  Status: ${GREEN}✅ Active${NC} ($(count_active_services) service(s))"
        else
            echo "  Status: ${RED}❌ Inactive${NC}"
        fi
    else
        echo "  No server configuration found"
    fi
    echo
    
    # Client Configuration Section
    echo -e "${CYAN}🌍 Client Configurations (Foreign):${NC}"
    if [[ "$is_client" == true ]]; then
        local client_configs=($(find "$CONFIG_DIR" -name "frpc*.toml" -type f 2>/dev/null | sort))
        local total_configs=${#client_configs[@]}
        local total_proxies=0
        local server_ips=()
        local server_ports=()
        local auth_tokens=()
        
        for config in "${client_configs[@]}"; do
            local ip=$(get_toml_value "$config" "serverAddr" 2>/dev/null | sed 's/["'\'']//g')
            local port=$(get_toml_value "$config" "serverPort" 2>/dev/null | tr -d '"')
            local token=$(get_toml_value "$config" "auth.token" 2>/dev/null | sed 's/["'\'']//g')
            
            [[ -n "$ip" ]] && server_ips+=("$ip")
            [[ -n "$port" ]] && server_ports+=("$port")
            [[ -n "$token" ]] && auth_tokens+=("$token")
            
            # Count proxies
            local proxies=$(grep -c '^\[\[proxies\]\]' "$config" 2>/dev/null || echo "0")
            total_proxies=$((total_proxies + proxies))
        done
        
        echo "  Total Configs: $total_configs"
        if [[ ${#server_ips[@]} -gt 0 ]]; then
            echo "  Server IPs: $(IFS=','; echo "${server_ips[*]}")"
        fi
        if [[ ${#server_ports[@]} -gt 0 ]]; then
            local unique_ports=($(printf '%s\n' "${server_ports[@]}" | sort -u))
            echo "  Server Ports: $(IFS=','; echo "${unique_ports[*]}")"
        fi
        if [[ ${#auth_tokens[@]} -gt 0 ]]; then
            echo "  Auth Token: ${auth_tokens[0]"
        fi
        echo "  Total Proxies: $total_proxies"
        echo
        echo -e "  ${CYAN}🔗 Quick Connection Test:${NC}"
        
        # Test connections (non-blocking, fast)
        for ip in "${server_ips[@]}"; do
            local port="${server_ports[0]:-7000}"
            if timeout 1 bash -c "echo > /dev/tcp/$ip/$port" 2>/dev/null; then
                echo "    $ip:$port   ${GREEN}✅ OK${NC}"
            else
                echo "    $ip:$port   ${RED}❌ FAIL${NC}"
            fi
        done
    else
        echo "  No client configurations found"
    fi
    echo
    
    # System Information
    echo -e "${CYAN}🖥️  System Information:${NC}"
    local frp_ver=$(get_frp_version)
    echo "  FRP Version: $frp_ver"
    echo "  MoonFRP Version: v$MOONFRP_VERSION"
    echo "  Config Directory: $CONFIG_DIR"
    echo "  Log Directory: $LOG_DIR"
    local active_services=$(count_active_services)
    local total_services=$(count_total_services)
    echo "  Services: $active_services active / $total_services total"
    echo
    
    read -p "Press Enter to continue..."
}

# Helper functions
get_server_ips_for_sharing() {
    # Get all server IPs from network interfaces
    hostname -I 2>/dev/null | tr ' ' ',' || echo "SERVER-IP"
}

count_active_services() {
    local count=0
    for service in $(systemctl list-unit-files | grep -E "moonfrp-(server|client)" | awk '{print $1}' | sed 's/.service$//'); do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            ((count++))
        fi
    done
    echo $count
}

count_total_services() {
    systemctl list-unit-files | grep -E "moonfrp-(server|client)" | wc -l
}
```

### Phase 4: Enhanced Service Management

**Location**: `moonfrp-services.sh` - Complete rewrite of `service_management_menu()`

**New Features**:
- Individual proxy management via API
- Service reload without restart
- Real-time status updates
- Better error handling

**Implementation Structure**:

```bash
service_management_menu() {
    while true; do
        clear
        show_header "Service Management" "FRP Services Control"
        
        # Fast status display (cached)
        list_services_fast
        
        echo
        echo -e "${CYAN}Service Management Options:${NC}"
        echo "1. Start All Services"
        echo "2. Stop All Services"
        echo "3. Restart All Services"
        echo "4. Reload Configuration (Zero Downtime)"
        echo "5. View Service Logs"
        echo "6. Proxy Management"
        echo "7. Health Check"
        echo "0. Back to Main Menu"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1) start_all_services_wrapper ;;
            2) stop_all_services_wrapper ;;
            3) restart_all_services_wrapper ;;
            4) reload_configurations_menu ;;
            5) view_logs_interactive ;;
            6) proxy_management_menu ;;
            7) enhanced_health_check ;;
            0) return ;;
            *) log "ERROR" "Invalid choice" ;;
        esac
    done
}

# Fast service listing (minimal overhead)
list_services_fast() {
    echo -e "${CYAN}Service Status:${NC}"
    
    # Use systemctl in batch mode for speed
    systemctl list-units --type=service --no-pager --no-legend \
        | grep -E "moonfrp-(server|client)" \
        | while read -r unit state rest; do
            local status_symbol
            case "$state" in
                "active"|"running") status_symbol="${GREEN}●${NC}" ;;
                "failed") status_symbol="${RED}●${NC}" ;;
                *) status_symbol="${YELLOW}○${NC}" ;;
            esac
            echo "  $status_symbol ${unit%.service}"
        done
}
```

### Phase 5: File Viewing & Editing Utilities

**Location**: New functions in `moonfrp-core.sh` or `moonfrp-config.sh`

**Implementation**:

```bash
# View and optionally edit a file
view_and_edit_file() {
    local file_path="$1"
    local file_type="${2:-config}"  # config, service, log
    
    if [[ ! -f "$file_path" ]]; then
        log "ERROR" "File not found: $file_path"
        return 1
    fi
    
    clear
    echo -e "${CYAN}File: $file_path${NC}"
    echo -e "${CYAN}Type: $file_type${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    # Display file content with syntax highlighting if possible
    if command -v bat &> /dev/null; then
        bat --style=plain --color=always "$file_path" || cat "$file_path"
    elif command -v highlight &> /dev/null; then
        highlight -O xterm256 "$file_path" || cat "$file_path"
    else
        cat "$file_path"
    fi
    
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    safe_read "Edit this file? (y/N)" "edit_confirm" "n"
    
    if [[ "$edit_confirm" == "y" || "$edit_confirm" == "Y" ]]; then
        # Determine editor (prefer nano, fallback to vi)
        local editor="${EDITOR:-nano}"
        
        if ! command -v "$editor" &> /dev/null; then
            editor="vi"
        fi
        
        # Edit file
        $editor "$file_path"
        
        # If config file, validate after edit
        if [[ "$file_type" == "config" ]] && [[ "$file_path" == *.toml ]]; then
            echo
            log "INFO" "Validating configuration..."
            validate_config_file "$file_path" || {
                log "WARN" "Configuration may have errors. Review and fix."
            }
        fi
    fi
}

# Quick file viewer menu
quick_file_viewer() {
    clear
    show_header "File Viewer" "View Configuration & Service Files"
    
    echo -e "${CYAN}Available Files:${NC}"
    echo "1. Server Config (frps.toml)"
    echo "2. Client Configs (frpc*.toml)"
    echo "3. Systemd Service Files"
    echo "4. Custom File Path"
    echo "0. Back"
    echo
    
    safe_read "Select option" "choice" "0"
    
    case "$choice" in
        1)
            if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
                view_and_edit_file "$CONFIG_DIR/frps.toml" "config"
            else
                log "ERROR" "Server config not found"
            fi
            ;;
        2)
            local configs=($(find "$CONFIG_DIR" -name "frpc*.toml" -type f | sort))
            if [[ ${#configs[@]} -eq 0 ]]; then
                log "WARN" "No client configs found"
            else
                select_file_from_list "${configs[@]}" | while read -r selected; do
                    [[ -n "$selected" ]] && view_and_edit_file "$selected" "config"
                done
            fi
            ;;
        3)
            local services=($(find /etc/systemd/system -name "moonfrp*.service" -type f))
            if [[ ${#services[@]} -eq 0 ]]; then
                log "WARN" "No service files found"
            else
                select_file_from_list "${services[@]}" | while read -r selected; do
                    [[ -n "$selected" ]] && view_and_edit_file "$selected" "service"
                done
            fi
            ;;
        4)
            safe_read "Enter file path" "custom_path" ""
            [[ -n "$custom_path" ]] && view_and_edit_file "$custom_path"
            ;;
    esac
}
```

### Phase 6: Enhanced Logging with FRP CLI

**Location**: New functions in `moonfrp-services.sh`

**Implementation**:

```bash
# Get useful logs from FRP service
get_frp_useful_logs() {
    local service_name="$1"
    local lines="${2:-50}"
    local log_file="$LOG_DIR/${service_name#moonfrp-}.log"
    
    # Use FRP's built-in log viewing capabilities
    # Also check systemd journal for service logs
    
    echo -e "${CYAN}Service Logs: $service_name${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    # Check if log file exists
    if [[ -f "$log_file" ]]; then
        echo -e "${YELLOW}File: $log_file${NC}"
        tail -n "$lines" "$log_file"
        echo
    fi
    
    # Also show systemd journal (most recent, useful entries)
    echo -e "${YELLOW}Systemd Journal (filtered):${NC}"
    journalctl -u "$service_name" -n "$lines" --no-pager \
        | grep -E "(error|warn|fail|connect|disconnect|proxy)" \
        | tail -n "$lines" || journalctl -u "$service_name" -n "$lines" --no-pager
}

# Real-time log following
follow_frp_logs() {
    local service_name="$1"
    local log_file="$LOG_DIR/${service_name#moonfrp-}.log"
    
    echo -e "${CYAN}Following logs for $service_name (Ctrl+C to stop)${NC}"
    echo
    
    # Follow both file and journal
    if [[ -f "$log_file" ]]; then
        tail -f "$log_file" &
        local tail_pid=$!
    fi
    
    journalctl -u "$service_name" -f &
    local journal_pid=$!
    
    # Wait for interrupt
    trap "kill $tail_pid $journal_pid 2>/dev/null; exit" INT TERM
    wait
}
```

### Phase 7: Menu Optimization & UI Improvements

**Location**: `moonfrp-ui.sh` - `main_menu()`

**Changes**:
1. Minimal header (one line)
2. Fast menu rendering
3. Removed slow operations from menu loop

**Implementation**:

```bash
main_menu() {
    while true; do
        if [[ "${MENU_STATE["ctrl_c_pressed"]}" == "true" ]]; then
            MENU_STATE["ctrl_c_pressed"]="false"
            return
        fi
        
        # Minimal fast header
        clear
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${PURPLE}  MoonFRP${NC} - ${GRAY}Advanced FRP Tunnel Management${NC}"
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        # Quick status (cached, non-blocking)
        show_quick_status_line
        
        echo
        echo -e "${CYAN}Main Menu:${NC}"
        echo "1. Quick Setup"
        echo "2. Service Management"
        echo "3. Configuration Management"
        echo "4. Config Details (Copy-Paste Ready)"
        echo "5. Advanced Tools"
        echo "6. System Optimization"
        echo "0. Exit"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1) quick_setup_wizard ;;
            2) service_management_menu ;;
            3) config_wizard ;;
            4) show_config_details ;;
            5) advanced_tools_menu ;;
            6) optimize_system ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) log "ERROR" "Invalid choice" ;;
        esac
    done
}

# Fast one-line status
show_quick_status_line() {
    local frp_status
    if check_frp_installation; then
        local ver=$(get_frp_version)
        frp_status="${GREEN}FRP: $ver${NC}"
    else
        frp_status="${RED}FRP: Not Installed${NC}"
    fi
    
    local server_status
    if systemctl is-active --quiet "$SERVER_SERVICE" 2>/dev/null; then
        server_status="${GREEN}Server: Active${NC}"
    else
        server_status="${GRAY}Server: Inactive${NC}"
    fi
    
    echo -e "  Status: $frp_status | $server_status"
}
```

### Phase 8: Enhanced Advanced Tools Menu

**Location**: `moonfrp-ui.sh` - `advanced_tools_menu()`

**Changes**:
- Move FRP install here
- Add version selection
- Add file viewer
- Better organization

**Implementation**:

```bash
advanced_tools_menu() {
    while true; do
        clear
        show_header "Advanced Tools" "System Utilities"
        
        echo -e "${CYAN}Advanced Tools:${NC}"
        echo "1. Download & Install FRP (Version Selectable)"
        echo "2. Health Check"
        echo "3. View Logs"
        echo "4. File Viewer & Editor"
        echo "5. Backup Configurations"
        echo "6. Restore Configurations"
        echo "7. Update MoonFRP"
        echo "8. Uninstall MoonFRP"
        echo "0. Back to Main Menu"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1) install_frp_with_version ;;
            2) enhanced_health_check ;;
            3) view_logs_interactive ;;
            4) quick_file_viewer ;;
            5) backup_configurations ;;
            6) restore_configurations ;;
            7) update_moonfrp ;;
            8) uninstall_moonfrp ;;
            0) return ;;
            *) log "ERROR" "Invalid choice" ;;
        esac
    done
}

install_frp_with_version() {
    clear
    show_header "Install FRP" "Download & Install FRP Binaries"
    
    safe_read "FRP Version (default: 0.65.0)" "frp_version" "0.65.0"
    
    # Validate version format
    if [[ ! "$frp_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "ERROR" "Invalid version format. Use X.Y.Z (e.g., 0.65.0)"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Temporarily set FRP_VERSION
    local old_version="$FRP_VERSION"
    export FRP_VERSION="$frp_version"
    
    install_frp
    
    # Restore original version if install failed
    if [[ $? -ne 0 ]]; then
        export FRP_VERSION="$old_version"
    fi
    
    read -p "Press Enter to continue..."
}
```

## Error Handling Improvements

### Safe File Operations

```bash
# Safe file deletion with pattern matching
safe_delete_configs() {
    local pattern="$1"  # e.g., "frpc*" or "*frp*"
    local config_dir="${2:-$CONFIG_DIR}"
    
    # Find files matching pattern
    local files=($(find "$config_dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null))
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log "WARN" "No files found matching: $pattern"
        return 0
    fi
    
    echo -e "${YELLOW}Files to delete:${NC}"
    for file in "${files[@]}"; do
        echo "  - $file"
    done
    
    safe_read "Delete these files? (y/N)" "confirm" "n"
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for file in "${files[@]}"; do
            if rm -f "$file" 2>/dev/null; then
                log "INFO" "Deleted: $file"
            else
                log "ERROR" "Failed to delete: $file"
            fi
        done
    fi
}
```

## Module Integration

### Updated `moonfrp.sh` Entry Point

```bash
# Source all modules
source "$SCRIPT_DIR/moonfrp-core.sh"
source "$SCRIPT_DIR/moonfrp-config.sh"
source "$SCRIPT_DIR/moonfrp-services.sh"
source "$SCRIPT_DIR/moonfrp-ui.sh"
source "$SCRIPT_DIR/moonfrp-api.sh"      # NEW
source "$SCRIPT_DIR/moonfrp-cli.sh"      # NEW
source "$SCRIPT_DIR/moonfrp-optimize.sh" # NEW
```

## Testing Checklist

- [ ] FRP version detection works correctly
- [ ] Config files created correctly (frps, frpc single, frpc multi-IP)
- [ ] Menu loads quickly (< 0.5s)
- [ ] Config details show correct information
- [ ] Connection tests work and are fast
- [ ] File viewer/editor works correctly
- [ ] Service management doesn't break existing functionality
- [ ] System optimization works on Ubuntu
- [ ] Error handling prevents crashes
- [ ] Log viewing shows useful information

## Performance Targets

- Menu render: < 500ms
- Status check: < 200ms (cached)
- Config details: < 1s
- Connection test: < 2s per IP (parallel)
- File operations: Immediate

## Notes for Developer

1. **Always validate inputs** before file operations
2. **Use caching** for expensive operations (status, config parsing)
3. **Background processes** for slow operations (connection tests)
4. **Graceful fallbacks** when optional tools missing (bat, highlight, jq)
5. **Test on clean Ubuntu** installation
6. **Preserve backward compatibility** with existing configs
