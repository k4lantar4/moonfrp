# Epic 4: System Optimization

**Epic ID:** MOONFRP-E04  
**Priority:** P2 - Power Users  
**Estimated Effort:** 3-4 days  
**Dependencies:** None  
**Target Release:** v2.0.0-beta.2

---

## Epic Goal

Provide system-level performance tuning specifically optimized for high-throughput tunnel operations, with safety mechanisms, monitoring capabilities, and easy rollback to ensure DevOps engineers can maximize tunnel performance without risking system stability.

## Success Criteria

- ✅ Three optimization presets: conservative, balanced, aggressive
- ✅ Dry-run mode shows all changes before applying
- ✅ Automatic rollback on failure or validation error
- ✅ Performance monitoring with metrics export
- ✅ Prometheus-compatible metrics endpoint
- ✅ Zero system damage from optimization failures
- ✅ Ubuntu 20.04+ validated, warnings for others

---

## Story 4.1: System Optimization Module with Safety

**Story ID:** MOONFRP-E04-S01  
**Priority:** P2  
**Effort:** 2 days

### Problem Statement

50 concurrent tunnels can saturate default Linux network settings. DevOps engineers need system tuning but current aggressive approach risks stability. Need preset-based optimization with safety checks.

### Acceptance Criteria

1. Three presets: conservative (safe), balanced (recommended), aggressive (max performance)
2. Dry-run shows all sysctl/ulimit changes before applying
3. Automatic backup of original settings
4. Validation of changes after applying
5. One-command rollback to original settings
6. OS detection with warnings for non-Ubuntu systems
7. Optimization completes in <10s

### Technical Specification

**Location:** New file `moonfrp-optimize.sh`

**Implementation:**
```bash
#!/bin/bash
# moonfrp-optimize.sh - System optimization module

source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"

readonly SYSCTL_PATH="/etc/sysctl.conf"
readonly PROFILE_PATH="/etc/profile"
readonly BACKUP_DIR="$HOME/.moonfrp/backups/system"

# Optimization presets
declare -A PRESET_CONSERVATIVE=(
    ["fs.file-max"]="262144"
    ["net.core.rmem_max"]="16777216"
    ["net.core.wmem_max"]="16777216"
    ["net.ipv4.tcp_rmem"]="4096 87380 16777216"
    ["net.ipv4.tcp_wmem"]="4096 65536 16777216"
    ["net.core.netdev_max_backlog"]="5000"
    ["net.ipv4.tcp_max_syn_backlog"]="2048"
)

declare -A PRESET_BALANCED=(
    ["fs.file-max"]="1048576"
    ["net.core.rmem_max"]="33554432"
    ["net.core.wmem_max"]="33554432"
    ["net.ipv4.tcp_rmem"]="4096 87380 33554432"
    ["net.ipv4.tcp_wmem"]="4096 65536 33554432"
    ["net.core.netdev_max_backlog"]="16384"
    ["net.ipv4.tcp_max_syn_backlog"]="8192"
    ["net.core.somaxconn"]="4096"
    ["net.ipv4.tcp_tw_reuse"]="1"
    ["net.ipv4.tcp_fin_timeout"]="15"
)

declare -A PRESET_AGGRESSIVE=(
    ["fs.file-max"]="67108864"
    ["net.core.rmem_max"]="134217728"
    ["net.core.wmem_max"]="134217728"
    ["net.ipv4.tcp_rmem"]="4096 87380 134217728"
    ["net.ipv4.tcp_wmem"]="4096 65536 134217728"
    ["net.core.netdev_max_backlog"]="32768"
    ["net.ipv4.tcp_max_syn_backlog"]="16384"
    ["net.core.somaxconn"]="8192"
    ["net.ipv4.tcp_tw_reuse"]="1"
    ["net.ipv4.tcp_fin_timeout"]="10"
    ["net.ipv4.tcp_fastopen"]="3"
    ["net.core.default_qdisc"]="fq_codel"
)

# Main optimization function
optimize_system() {
    local preset="${1:-balanced}"
    local dry_run="${2:-false}"
    
    clear
    show_header "System Optimization" "Network & Performance Tuning"
    
    # OS validation
    if ! validate_os_compatibility; then
        return 1
    fi
    
    # Display preset info
    display_preset_info "$preset"
    
    # Dry-run mode
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY-RUN MODE - No changes will be applied${NC}"
        echo
        preview_optimizations "$preset"
        return 0
    fi
    
    # Confirmation
    safe_read "Apply $preset optimizations? (y/N)" "confirm" "n"
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    
    # Backup current settings
    backup_system_settings || {
        log "ERROR" "Failed to backup settings. Aborting."
        return 1
    }
    
    # Apply optimizations
    apply_sysctl_optimizations "$preset" || {
        log "ERROR" "Failed to apply sysctl optimizations"
        rollback_system_settings
        return 1
    }
    
    apply_ulimit_optimizations "$preset" || {
        log "ERROR" "Failed to apply ulimit optimizations"
        rollback_system_settings
        return 1
    }
    
    # Validate
    if ! validate_optimizations "$preset"; then
        log "ERROR" "Validation failed. Rolling back..."
        rollback_system_settings
        return 1
    fi
    
    log "INFO" "Optimization complete!"
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

# Validate OS compatibility
validate_os_compatibility() {
    if ! command -v lsb_release &> /dev/null; then
        log "WARN" "Cannot detect OS. Proceed with caution."
        safe_read "Continue anyway? (y/N)" "confirm" "n"
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 1
        return 0
    fi
    
    local os_name=$(lsb_release -is 2>/dev/null || echo "Unknown")
    local os_version=$(lsb_release -rs 2>/dev/null || echo "0")
    
    if [[ "$os_name" != "Ubuntu" ]]; then
        echo -e "${YELLOW}Warning:${NC} Optimizations tested on Ubuntu 20.04+."
        echo "Your OS: $os_name $os_version"
        echo
        safe_read "Proceed anyway? (y/N)" "confirm" "n"
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 1
    elif [[ $(echo "$os_version < 20.04" | bc) -eq 1 ]]; then
        echo -e "${YELLOW}Warning:${NC} Ubuntu version older than 20.04."
        echo "Some optimizations may not be available."
        echo
        safe_read "Proceed anyway? (y/N)" "confirm" "n"
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 1
    fi
    
    return 0
}

# Display preset information
display_preset_info() {
    local preset="$1"
    
    echo -e "${CYAN}Preset: $preset${NC}"
    echo
    
    case "$preset" in
        conservative)
            echo "  Profile: Safe, minimal changes"
            echo "  Target: 10-20 tunnels"
            echo "  Risk: Very low"
            ;;
        balanced)
            echo "  Profile: Recommended for most users"
            echo "  Target: 20-50 tunnels"
            echo "  Risk: Low"
            ;;
        aggressive)
            echo "  Profile: Maximum performance"
            echo "  Target: 50+ tunnels"
            echo "  Risk: Medium (may affect other services)"
            ;;
    esac
    echo
}

# Preview optimizations (dry-run)
preview_optimizations() {
    local preset="$1"
    local -n preset_ref=PRESET_${preset^^}
    
    echo -e "${CYAN}Sysctl Parameters (${#preset_ref[@]} changes):${NC}"
    for key in "${!preset_ref[@]}"; do
        local current=$(sysctl -n "$key" 2>/dev/null || echo "(not set)")
        local new="${preset_ref[$key]}"
        echo "  $key: $current → $new"
    done
    echo
    
    echo -e "${CYAN}Ulimit Changes:${NC}"
    echo "  ulimit -n (open files): $(ulimit -n) → unlimited"
    echo "  ulimit -u (processes): $(ulimit -u) → unlimited"
    echo
}

# Apply sysctl optimizations
apply_sysctl_optimizations() {
    local preset="$1"
    local -n preset_ref=PRESET_${preset^^}
    
    log "INFO" "Applying sysctl optimizations..."
    
    # Remove old MoonFRP entries
    sed -i '/^# MoonFRP Network Optimizations/,/^$/d' "$SYSCTL_PATH"
    
    # Add new entries
    cat >> "$SYSCTL_PATH" <<EOF

# MoonFRP Network Optimizations
# Generated: $(date)
# Preset: $preset

EOF
    
    for key in "${!preset_ref[@]}"; do
        echo "$key = ${preset_ref[$key]}" >> "$SYSCTL_PATH"
    done
    
    # Apply immediately
    sysctl -p > /dev/null 2>&1 || {
        log "ERROR" "Failed to apply sysctl settings"
        return 1
    }
    
    log "INFO" "Sysctl optimizations applied"
    return 0
}

# Apply ulimit optimizations
apply_ulimit_optimizations() {
    local preset="$1"
    
    log "INFO" "Applying ulimit optimizations..."
    
    # Remove old entries
    sed -i '/^# MoonFRP System Limits/,/^$/d' "$PROFILE_PATH"
    
    # Add new entries
    cat >> "$PROFILE_PATH" <<'EOF'

# MoonFRP System Limits
# Generated: $(date)

ulimit -n 1048576  # Open files
ulimit -u 65536    # Max user processes

EOF
    
    log "INFO" "Ulimit optimizations applied"
    return 0
}

# Backup system settings
backup_system_settings() {
    mkdir -p "$BACKUP_DIR"
    
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    
    cp "$SYSCTL_PATH" "$BACKUP_DIR/sysctl.conf.$timestamp" || return 1
    cp "$PROFILE_PATH" "$BACKUP_DIR/profile.$timestamp" || return 1
    
    # Save current sysctl values
    sysctl -a > "$BACKUP_DIR/sysctl-values.$timestamp" 2>/dev/null
    
    # Save latest backup reference
    echo "$timestamp" > "$BACKUP_DIR/.latest"
    
    log "INFO" "System settings backed up: $timestamp"
    return 0
}

# Rollback system settings
rollback_system_settings() {
    local timestamp=$(cat "$BACKUP_DIR/.latest" 2>/dev/null)
    
    if [[ -z "$timestamp" ]]; then
        log "ERROR" "No backup found to rollback"
        return 1
    fi
    
    log "INFO" "Rolling back to: $timestamp"
    
    cp "$BACKUP_DIR/sysctl.conf.$timestamp" "$SYSCTL_PATH" || return 1
    cp "$BACKUP_DIR/profile.$timestamp" "$PROFILE_PATH" || return 1
    
    sysctl -p > /dev/null 2>&1
    
    log "INFO" "Rollback complete"
    return 0
}

# Validate optimizations
validate_optimizations() {
    local preset="$1"
    local -n preset_ref=PRESET_${preset^^}
    
    log "INFO" "Validating optimizations..."
    
    local validation_failed=false
    
    for key in "${!preset_ref[@]}"; do
        local expected="${preset_ref[$key]}"
        local actual=$(sysctl -n "$key" 2>/dev/null)
        
        if [[ "$actual" != "$expected" ]]; then
            log "WARN" "Validation failed: $key (expected: $expected, actual: $actual)"
            validation_failed=true
        fi
    done
    
    if [[ "$validation_failed" == "true" ]]; then
        return 1
    fi
    
    log "INFO" "Validation passed"
    return 0
}

# Interactive optimization menu
optimization_menu() {
    while true; do
        clear
        show_header "System Optimization" "Performance Tuning"
        
        echo -e "${CYAN}Presets:${NC}"
        echo "1. Conservative (10-20 tunnels, very safe)"
        echo "2. Balanced (20-50 tunnels, recommended)"
        echo "3. Aggressive (50+ tunnels, max performance)"
        echo "4. Dry-run (preview changes without applying)"
        echo "5. Rollback to previous settings"
        echo "0. Back"
        echo
        
        safe_read "Choice" "choice" "0"
        
        case "$choice" in
            1) optimize_system "conservative" "false" ;;
            2) optimize_system "balanced" "false" ;;
            3) optimize_system "aggressive" "false" ;;
            4) 
                safe_read "Preset to preview (conservative/balanced/aggressive)" "preset" "balanced"
                optimize_system "$preset" "true"
                read -p "Press Enter to continue..."
                ;;
            5) rollback_system_settings; read -p "Press Enter..." ;;
            0) return ;;
        esac
    done
}

export -f optimize_system validation_os_compatibility apply_sysctl_optimizations
export -f apply_ulimit_optimizations backup_system_settings rollback_system_settings
```

### Testing Requirements

```bash
test_optimize_conservative_preset()
test_optimize_balanced_preset()
test_optimize_aggressive_preset()
test_optimize_dry_run()
test_optimize_rollback()
test_optimize_validation_failure()
test_optimize_backup_created()
test_os_compatibility_check()
```

### Rollback Strategy

1. Automatic backup before any changes
2. Validation failure triggers automatic rollback
3. Manual rollback command available
4. Rollback restores exact previous state in <30s

---

## Story 4.2: Performance Monitoring & Metrics

**Story ID:** MOONFRP-E04-S02  
**Priority:** P2  
**Effort:** 1.5 days

### Problem Statement

After optimization, DevOps teams need to monitor actual performance impact. Need metrics collection and export for integration with monitoring stacks (Prometheus, Grafana).

### Acceptance Criteria

1. Track per-tunnel metrics: bandwidth, connections, errors
2. System metrics: CPU, memory, network I/O
3. Export metrics in Prometheus format
4. Simple text dashboard for quick viewing
5. Metrics history: last 24h, configurable retention
6. Alerting on tunnel failures
7. Performance: metrics collection <1% CPU overhead

### Technical Specification

**Location:** New file `moonfrp-metrics.sh`

**Implementation:**
```bash
#!/bin/bash
# moonfrp-metrics.sh - Performance monitoring and metrics

source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"

readonly METRICS_DIR="$HOME/.moonfrp/metrics"
readonly METRICS_FILE="$METRICS_DIR/moonfrp_metrics.prom"
readonly RETENTION_HOURS=24

# Initialize metrics collection
init_metrics() {
    mkdir -p "$METRICS_DIR"
    
    # Start metrics collector in background
    collect_metrics_background &
}

# Collect metrics (called periodically)
collect_metrics() {
    local timestamp=$(date +%s)
    
    # Service metrics
    collect_service_metrics "$timestamp"
    
    # System metrics
    collect_system_metrics "$timestamp"
    
    # Tunnel-specific metrics (if FRP provides API)
    collect_tunnel_metrics "$timestamp"
}

# Collect service metrics
collect_service_metrics() {
    local timestamp="$1"
    local db_path="$HOME/.moonfrp/index.db"
    
    local total_services=$(systemctl list-units --type=service --all --no-pager --no-legend \
        | grep -c "moonfrp-")
    local active_services=$(systemctl list-units --type=service --no-pager --no-legend \
        | grep "moonfrp-" | grep -c "active")
    local failed_services=$(systemctl list-units --type=service --all --no-pager --no-legend \
        | grep "moonfrp-" | grep -c "failed")
    
    # Write Prometheus metrics
    cat > "$METRICS_FILE" <<EOF
# HELP moonfrp_services_total Total number of MoonFRP services
# TYPE moonfrp_services_total gauge
moonfrp_services_total $total_services $timestamp

# HELP moonfrp_services_active Number of active MoonFRP services
# TYPE moonfrp_services_active gauge
moonfrp_services_active $active_services $timestamp

# HELP moonfrp_services_failed Number of failed MoonFRP services
# TYPE moonfrp_services_failed gauge
moonfrp_services_failed $failed_services $timestamp

EOF
}

# Collect system metrics
collect_system_metrics() {
    local timestamp="$1"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    
    # Memory usage
    local mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/^Mem:/ {print $3}')
    
    # Network I/O
    local rx_bytes=$(cat /proc/net/dev | grep -E "eth0|ens" | head -1 | awk '{print $2}')
    local tx_bytes=$(cat /proc/net/dev | grep -E "eth0|ens" | head -1 | awk '{print $10}')
    
    cat >> "$METRICS_FILE" <<EOF
# HELP moonfrp_system_cpu_usage System CPU usage percentage
# TYPE moonfrp_system_cpu_usage gauge
moonfrp_system_cpu_usage $cpu_usage $timestamp

# HELP moonfrp_system_memory_used Memory used in MB
# TYPE moonfrp_system_memory_used gauge
moonfrp_system_memory_used $mem_used $timestamp

# HELP moonfrp_system_network_rx_bytes Network RX bytes
# TYPE moonfrp_system_network_rx_bytes counter
moonfrp_system_network_rx_bytes $rx_bytes $timestamp

# HELP moonfrp_system_network_tx_bytes Network TX bytes
# TYPE moonfrp_system_network_tx_bytes counter
moonfrp_system_network_tx_bytes $tx_bytes $timestamp

EOF
}

# Background metrics collector
collect_metrics_background() {
    while true; do
        collect_metrics
        sleep 60  # Collect every minute
    done
}

# Display metrics dashboard
show_metrics_dashboard() {
    clear
    show_header "Performance Metrics" "Real-time Monitoring"
    
    if [[ ! -f "$METRICS_FILE" ]]; then
        log "WARN" "No metrics available yet"
        return
    fi
    
    echo -e "${CYAN}Service Metrics:${NC}"
    grep "moonfrp_services" "$METRICS_FILE" | grep -v "^#" | while read -r metric value timestamp; do
        echo "  $metric: $value"
    done
    echo
    
    echo -e "${CYAN}System Metrics:${NC}"
    grep "moonfrp_system" "$METRICS_FILE" | grep -v "^#" | while read -r metric value timestamp; do
        echo "  $metric: $value"
    done
    echo
    
    read -p "Press Enter to continue..."
}

# Export metrics for Prometheus
export_metrics_prometheus() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        log "ERROR" "No metrics available"
        return 1
    fi
    
    echo -e "${CYAN}Metrics endpoint:${NC} file://$METRICS_FILE"
    echo
    echo "Add to Prometheus config:"
    echo
    cat <<EOF
- job_name: 'moonfrp'
  static_configs:
    - targets: ['localhost:9090']
  file_sd_configs:
    - files:
      - '$METRICS_FILE'
EOF
    echo
    read -p "Press Enter to continue..."
}
```

### Testing Requirements

```bash
test_metrics_collection()
test_prometheus_format_valid()
test_metrics_dashboard_display()
test_metrics_retention()
test_metrics_low_overhead()
```

### Rollback Strategy

Metrics collection is passive - can be disabled without affecting tunnel operation.

---

## Epic-Level Acceptance

**This epic is COMPLETE when:**

1. ✅ All 2 stories implemented and tested
2. ✅ Three optimization presets working with dry-run
3. ✅ Automatic rollback on failure verified
4. ✅ Metrics exported in Prometheus format
5. ✅ Zero system damage in chaos testing
6. ✅ Performance benchmarks pass
7. ✅ Documentation updated

---

**Status:** Ready for Implementation  
**Created:** 2025-11-02  
**Approved By:** BMad Master, Team Consensus

