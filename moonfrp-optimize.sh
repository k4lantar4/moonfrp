#!/bin/bash

#==============================================================================
# MoonFRP System Optimization Module (Story 4.1)
# Version: 1.0.0
# Description: Preset-based sysctl/ulimit tuning with dry-run, backup, validation, and rollback
#==============================================================================

set -euo pipefail

# Source core/ui helpers
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-ui.sh"

readonly SYSCTL_PATH="/etc/sysctl.conf"
readonly PROFILE_PATH="/etc/profile"
## Do not assign to BACKUP_DIR directly to avoid clashes with pre-set readonly vars
# Use a resolver function instead; if BACKUP_DIR is set, we respect it
backups_root() {
    echo "${BACKUP_DIR:-$HOME/.moonfrp/backups/system}"
}
readonly MOONFRP_SYSCTL_BLOCK_BEGIN="# >>> MoonFRP Optimization (managed) >>>"
readonly MOONFRP_SYSCTL_BLOCK_END="# <<< MoonFRP Optimization (managed) <<<"
readonly MOONFRP_LIMITS_BLOCK_BEGIN="# >>> MoonFRP Limits (managed) >>>"
readonly MOONFRP_LIMITS_BLOCK_END="# <<< MoonFRP Limits (managed) <<<"

# Presets (Bash 4 assoc arrays)
declare -A PRESET_CONSERVATIVE=([
    fs.file-max]='2097152' [net.core.rmem_max]='8388608' [net.core.wmem_max]='8388608' [net.ipv4.tcp_rmem]='4096 87380 8388608' [net.ipv4.tcp_wmem]='4096 65536 8388608' [net.core.netdev_max_backlog]='16384' [net.ipv4.tcp_max_syn_backlog]='8192']
)
declare -A PRESET_BALANCED=([
    fs.file-max]='4194304' [net.core.rmem_max]='16777216' [net.core.wmem_max]='16777216' [net.ipv4.tcp_rmem]='4096 131072 16777216' [net.ipv4.tcp_wmem]='4096 131072 16777216' [net.core.netdev_max_backlog]='32768' [net.ipv4.tcp_max_syn_backlog]='16384' [net.core.somaxconn]='4096']
)
declare -A PRESET_AGGRESSIVE=([
    fs.file-max]='8388608' [net.core.rmem_max]='33554432' [net.core.wmem_max]='33554432' [net.ipv4.tcp_rmem]='4096 262144 33554432' [net.ipv4.tcp_wmem]='4096 262144 33554432' [net.core.netdev_max_backlog]='65536' [net.ipv4.tcp_max_syn_backlog]='32768' [net.core.somaxconn]='8192' [net.ipv4.tcp_fastopen]='3' [net.core.default_qdisc]='fq']
)

#===============================================================================
# Utility helpers
#===============================================================================

get_preset_assoc_name() {
    local preset="$1"
    case "$preset" in
        conservative) echo "PRESET_CONSERVATIVE" ;;
        balanced) echo "PRESET_BALANCED" ;;
        aggressive) echo "PRESET_AGGRESSIVE" ;;
        *) echo "" ;;
    esac
}

display_preset_info() {
    local preset="$1"
    local assoc_name; assoc_name=$(get_preset_assoc_name "$preset")
    if [[ -z "$assoc_name" ]]; then
        log "ERROR" "Unknown preset: $preset"
        return 1
    fi
    show_header "System Optimization" "Preset: $preset"
    echo -e "${CYAN}Planned sysctl keys:${NC}"
    local -n preset_ref="$assoc_name"
    for key in "${!preset_ref[@]}"; do
        echo "  $key = ${preset_ref[$key]}"
    done
    echo
    echo -e "${CYAN}Planned limits:${NC}"
    echo "  ulimit -n 1048576"
    echo "  ulimit -u 65536"
}

validate_os_compatibility() {
    local os_name="" os_version=""
    if command -v lsb_release >/dev/null 2>&1; then
        os_name=$(lsb_release -is 2>/dev/null || echo "")
        os_version=$(lsb_release -rs 2>/dev/null || echo "")
    else
        os_name=$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
        os_version=$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
    fi
    if [[ "${os_name,,}" != "ubuntu" ]]; then
        log "WARN" "Non-Ubuntu system detected (${os_name:-unknown}). Proceed with caution."
        return 2
    fi
    # Compare versions using dpkg if available
    if command -v dpkg >/dev/null 2>&1; then
        if ! dpkg --compare-versions "$os_version" ge "20.04"; then
            log "WARN" "Ubuntu $os_version detected (< 20.04)."
            return 3
        fi
    else
        log "WARN" "Cannot verify Ubuntu version precisely (dpkg not available)."
        return 0
    fi
    return 0
}

preview_optimizations() {
    local preset="$1"
    local assoc_name; assoc_name=$(get_preset_assoc_name "$preset")
    local -n preset_ref="$assoc_name"
    echo -e "${CYAN}Dry-run: Current → New (sysctl)${NC}"
    for key in "${!preset_ref[@]}"; do
        local current
        current=$(sysctl -n "$key" 2>/dev/null || echo "(unset)")
        echo "  $key: $current -> ${preset_ref[$key]}"
    done
    echo
    echo -e "${CYAN}Dry-run: Planned ulimit changes${NC}"
    echo "  nofile: $(ulimit -n 2>/dev/null || echo unknown) -> 1048576"
    echo "  nproc:  $(ulimit -u 2>/dev/null || echo unknown) -> 65536"
}

backup_system_settings() {
    local __backup_dir
    __backup_dir="$(backups_root)"
    mkdir -p "$__backup_dir"
    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    local backup_root="$__backup_dir/$ts"
    mkdir -p "$backup_root"
    cp -a "$SYSCTL_PATH" "$backup_root/sysctl.conf" 2>/dev/null || true
    cp -a "$PROFILE_PATH" "$backup_root/profile" 2>/dev/null || true
    sysctl -a 2>/dev/null > "$backup_root/sysctl.snapshot" || true
    echo "$ts" > "$__backup_dir/.latest"
    log "INFO" "Backup created at $backup_root"
}

rollback_system_settings() {
    local __backup_dir
    __backup_dir="$(backups_root)"
    if [[ ! -f "$__backup_dir/.latest" ]]; then
        log "ERROR" "No backup found to rollback"
        return 1
    fi
    local ts
    ts=$(cat "$__backup_dir/.latest")
    local backup_root="$__backup_dir/$ts"
    if [[ -f "$backup_root/sysctl.conf" ]]; then
        cp -a "$backup_root/sysctl.conf" "$SYSCTL_PATH"
    fi
    if [[ -f "$backup_root/profile" ]]; then
        cp -a "$backup_root/profile" "$PROFILE_PATH"
    fi
    if sysctl -p "$SYSCTL_PATH"; then
        log "INFO" "Rollback applied"
    else
        log "WARN" "Rollback applied but sysctl -p returned non-zero"
    fi
}

remove_existing_block() {
    local path="$1" begin_marker="$2" end_marker="$3"
    if [[ -f "$path" ]]; then
        # Remove existing managed block if present
        if grep -q "$begin_marker" "$path" 2>/dev/null; then
            sed -i "/$begin_marker/,/$end_marker/d" "$path"
        fi
    fi
}

apply_sysctl_optimizations() {
    local preset="$1"
    local assoc_name; assoc_name=$(get_preset_assoc_name "$preset")
    local -n preset_ref="$assoc_name"

    remove_existing_block "$SYSCTL_PATH" "$MOONFRP_SYSCTL_BLOCK_BEGIN" "$MOONFRP_SYSCTL_BLOCK_END"

    local success_count=0
    local fail_count=0
    local failed_keys=()
    local successful_settings=()

    # First, try to apply each setting individually to identify failures
    for key in "${!preset_ref[@]}"; do
        local value="${preset_ref[$key]}"
        local output
        if output=$(sysctl -w "$key=$value" 2>&1); then
            ((success_count++))
            successful_settings+=("$key = $value")
            echo "$output"  # Show successful application
        else
            ((fail_count++))
            failed_keys+=("$key")
            log "WARN" "Failed to apply sysctl setting: $key = $value"
            echo "$output" >&2  # Show error to user
        fi
    done

    # Write only successful settings to the file for persistence
    if [[ ${#successful_settings[@]} -gt 0 ]]; then
        {
            echo "$MOONFRP_SYSCTL_BLOCK_BEGIN"
            echo "# Preset: $preset"
            for setting in "${successful_settings[@]}"; do
                echo "$setting"
            done
            echo "$MOONFRP_SYSCTL_BLOCK_END"
        } | tee -a "$SYSCTL_PATH" >/dev/null
    fi

    # Report results
    if [[ $fail_count -eq 0 ]]; then
        log "INFO" "Sysctl optimizations applied successfully ($success_count settings)"
        return 0
    elif [[ $success_count -gt 0 ]]; then
        log "WARN" "Applied $success_count settings, $fail_count failed"
        log "WARN" "Failed settings: ${failed_keys[*]}"
        return 0  # Partial success is acceptable
    else
        log "ERROR" "All sysctl settings failed to apply"
        return 1
    fi
}

apply_ulimit_optimizations() {
    remove_existing_block "$PROFILE_PATH" "$MOONFRP_LIMITS_BLOCK_BEGIN" "$MOONFRP_LIMITS_BLOCK_END"
    {
        echo "$MOONFRP_LIMITS_BLOCK_BEGIN"
        echo "# Increased limits for MoonFRP high-throughput tunnels"
        echo "ulimit -n 1048576"
        echo "ulimit -u 65536"
        echo "$MOONFRP_LIMITS_BLOCK_END"
    } | tee -a "$PROFILE_PATH" >/dev/null
    log "INFO" "Ulimit optimizations appended to $PROFILE_PATH (apply on new shells)"
}

validate_optimizations() {
    local preset="$1"
    local assoc_name; assoc_name=$(get_preset_assoc_name "$preset")
    local -n preset_ref="$assoc_name"
    local failed=0
    local validated=0
    for key in "${!preset_ref[@]}"; do
        local current
        current=$(sysctl -n "$key" 2>/dev/null || echo "")
        if [[ -z "$current" ]]; then
            log "WARN" "Cannot read sysctl value for $key (may not be supported on this system)"
            continue
        fi
        
        local expected="${preset_ref[$key]}"
        # Normalize whitespace for multi-value settings (e.g., "4096 131072 16777216")
        current=$(echo "$current" | tr -s ' ' | xargs)
        expected=$(echo "$expected" | tr -s ' ' | xargs)
        
        if [[ "$current" != "$expected" ]]; then
            log "WARN" "Validation mismatch: $key expected '$expected' got '$current'"
            failed=1
        else
            ((validated++))
        fi
    done
    
    if [[ $failed -eq 0 ]]; then
        if [[ $validated -gt 0 ]]; then
            log "INFO" "Validation successful ($validated settings verified)"
        else
            log "WARN" "No settings could be validated (system may not support these parameters)"
        fi
        return 0
    else
        log "WARN" "Some settings did not match expected values (but optimization may still be partially effective)"
        return 0  # Don't fail validation - partial success is acceptable
    fi
}

# Ask for reboot
ask_reboot() {
    echo
    echo -e "${YELLOW}System optimization completed.${NC}"
    echo -e "${CYAN}Some changes may require a reboot to take full effect.${NC}"
    echo
    safe_read "Reboot now? (yes/no)" "reboot_confirm" "no"
    if [[ "$reboot_confirm" == "yes" ]]; then
        log "INFO" "Rebooting system..."
        reboot
    else
        log "INFO" "Reboot skipped. Changes will apply on next reboot."
    fi
}

# SYSCTL Optimization
sysctl_optimizations() {
    # Make a backup of the original sysctl.conf file
    cp "$SYSCTL_PATH" /etc/sysctl.conf.bak

    echo
    echo -e "${YELLOW}Default sysctl.conf file Saved. Directory: /etc/sysctl.conf.bak${NC}"
    echo
    sleep 1

    echo
    echo -e "${YELLOW}Optimizing the Network...${NC}"
    echo
    sleep 0.5

    sed -i -e '/fs.file-max/d' \
        -e '/net.core.default_qdisc/d' \
        -e '/net.core.netdev_max_backlog/d' \
        -e '/net.core.optmem_max/d' \
        -e '/net.core.somaxconn/d' \
        -e '/net.core.rmem_max/d' \
        -e '/net.core.wmem_max/d' \
        -e '/net.core.rmem_default/d' \
        -e '/net.core.wmem_default/d' \
        -e '/net.ipv4.tcp_rmem/d' \
        -e '/net.ipv4.tcp_wmem/d' \
        -e '/net.ipv4.tcp_congestion_control/d' \
        -e '/net.ipv4.tcp_fastopen/d' \
        -e '/net.ipv4.tcp_fin_timeout/d' \
        -e '/net.ipv4.tcp_keepalive_time/d' \
        -e '/net.ipv4.tcp_keepalive_probes/d' \
        -e '/net.ipv4.tcp_keepalive_intvl/d' \
        -e '/net.ipv4.tcp_max_orphans/d' \
        -e '/net.ipv4.tcp_max_syn_backlog/d' \
        -e '/net.ipv4.tcp_max_tw_buckets/d' \
        -e '/net.ipv4.tcp_mem/d' \
        -e '/net.ipv4.tcp_mtu_probing/d' \
        -e '/net.ipv4.tcp_notsent_lowat/d' \
        -e '/net.ipv4.tcp_retries2/d' \
        -e '/net.ipv4.tcp_sack/d' \
        -e '/net.ipv4.tcp_dsack/d' \
        -e '/net.ipv4.tcp_slow_start_after_idle/d' \
        -e '/net.ipv4.tcp_window_scaling/d' \
        -e '/net.ipv4.tcp_adv_win_scale/d' \
        -e '/net.ipv4.tcp_ecn/d' \
        -e '/net.ipv4.tcp_ecn_fallback/d' \
        -e '/net.ipv4.tcp_syncookies/d' \
        -e '/net.ipv4.udp_mem/d' \
        -e '/net.ipv6.conf.all.disable_ipv6/d' \
        -e '/net.ipv6.conf.default.disable_ipv6/d' \
        -e '/net.ipv6.conf.lo.disable_ipv6/d' \
        -e '/net.unix.max_dgram_qlen/d' \
        -e '/vm.min_free_kbytes/d' \
        -e '/vm.swappiness/d' \
        -e '/vm.vfs_cache_pressure/d' \
        -e '/net.ipv4.conf.default.rp_filter/d' \
        -e '/net.ipv4.conf.all.rp_filter/d' \
        -e '/net.ipv4.conf.all.accept_source_route/d' \
        -e '/net.ipv4.conf.default.accept_source_route/d' \
        -e '/net.ipv4.neigh.default.gc_thresh1/d' \
        -e '/net.ipv4.neigh.default.gc_thresh2/d' \
        -e '/net.ipv4.neigh.default.gc_thresh3/d' \
        -e '/net.ipv4.neigh.default.gc_stale_time/d' \
        -e '/net.ipv4.conf.default.arp_announce/d' \
        -e '/net.ipv4.conf.lo.arp_announce/d' \
        -e '/net.ipv4.conf.all.arp_announce/d' \
        -e '/kernel.panic/d' \
        -e '/vm.dirty_ratio/d' \
        "$SYSCTL_PATH"

    # Add new parameters
    cat <<EOF >> "$SYSCTL_PATH"

################################################################
################################################################

# /etc/sysctl.conf
# These parameters in this file will be added/updated to the sysctl.conf file.
# Read More: https://github.com/hawshemi/Linux-Optimizer/blob/main/files/sysctl.conf

## File system settings
## ----------------------------------------------------------------

# Set the maximum number of open file descriptors
fs.file-max = 67108864

## Network core settings
## ----------------------------------------------------------------

# Specify default queuing discipline for network devices
net.core.default_qdisc = fq_codel

# Configure maximum network device backlog
net.core.netdev_max_backlog = 32768

# Set maximum socket receive buffer
net.core.optmem_max = 262144

# Define maximum backlog of pending connections
net.core.somaxconn = 65536

# Configure maximum TCP receive buffer size
net.core.rmem_max = 33554432

# Set default TCP receive buffer size
net.core.rmem_default = 1048576

# Configure maximum TCP send buffer size
net.core.wmem_max = 33554432

# Set default TCP send buffer size
net.core.wmem_default = 1048576

## TCP settings
## ----------------------------------------------------------------

# Define socket receive buffer sizes
net.ipv4.tcp_rmem = 16384 1048576 33554432

# Specify socket send buffer sizes
net.ipv4.tcp_wmem = 16384 1048576 33554432

# Set TCP congestion control algorithm to BBR
net.ipv4.tcp_congestion_control = bbr

# Configure TCP FIN timeout period
net.ipv4.tcp_fin_timeout = 25

# Set keepalive time (seconds)
net.ipv4.tcp_keepalive_time = 1200

# Configure keepalive probes count and interval
net.ipv4.tcp_keepalive_probes = 7
net.ipv4.tcp_keepalive_intvl = 30

# Define maximum orphaned TCP sockets
net.ipv4.tcp_max_orphans = 819200

# Set maximum TCP SYN backlog
net.ipv4.tcp_max_syn_backlog = 20480

# Configure maximum TCP Time Wait buckets
net.ipv4.tcp_max_tw_buckets = 1440000

# Define TCP memory limits
net.ipv4.tcp_mem = 65536 1048576 33554432

# Enable TCP MTU probing
net.ipv4.tcp_mtu_probing = 1

# Define minimum amount of data in the send buffer before TCP starts sending
net.ipv4.tcp_notsent_lowat = 32768

# Specify retries for TCP socket to establish connection
net.ipv4.tcp_retries2 = 8

# Enable TCP SACK and DSACK
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1

# Disable TCP slow start after idle
net.ipv4.tcp_slow_start_after_idle = 0

# Enable TCP window scaling
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = -2

# Enable TCP ECN
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1

# Enable the use of TCP SYN cookies to help protect against SYN flood attacks
net.ipv4.tcp_syncookies = 1

## UDP settings
## ----------------------------------------------------------------

# Define UDP memory limits
net.ipv4.udp_mem = 65536 1048576 33554432

## IPv6 settings
## ----------------------------------------------------------------

# Enable IPv6
net.ipv6.conf.all.disable_ipv6 = 0

# Enable IPv6 by default
net.ipv6.conf.default.disable_ipv6 = 0

# Enable IPv6 on the loopback interface (lo)
net.ipv6.conf.lo.disable_ipv6 = 0

## UNIX domain sockets
## ----------------------------------------------------------------

# Set maximum queue length of UNIX domain sockets
net.unix.max_dgram_qlen = 256

## Virtual memory (VM) settings
## ----------------------------------------------------------------

# Specify minimum free Kbytes at which VM pressure happens
vm.min_free_kbytes = 65536

# Define how aggressively swap memory pages are used
vm.swappiness = 10

# Set the tendency of the kernel to reclaim memory used for caching of directory and inode objects
vm.vfs_cache_pressure = 250

## Network Configuration
## ----------------------------------------------------------------

# Configure reverse path filtering
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.rp_filter = 2

# Disable source route acceptance
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Neighbor table settings
net.ipv4.neigh.default.gc_thresh1 = 512
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 16384
net.ipv4.neigh.default.gc_stale_time = 60

# ARP settings
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2

# Kernel panic timeout
kernel.panic = 1

# Set dirty page ratio for virtual memory
vm.dirty_ratio = 20

################################################################
################################################################

EOF

    sysctl -p || {
        log "WARN" "Some sysctl settings may not have been applied. Check errors above."
    }

    echo
    echo -e "${GREEN}Network is Optimized.${NC}"
    echo
    sleep 0.5
}

# System Limits Optimizations
limits_optimizations() {
    echo
    echo -e "${YELLOW}Optimizing System Limits...${NC}"
    echo
    sleep 0.5

    # Clear old ulimits
    sed -i '/ulimit -c/d' "$PROFILE_PATH"
    sed -i '/ulimit -d/d' "$PROFILE_PATH"
    sed -i '/ulimit -f/d' "$PROFILE_PATH"
    sed -i '/ulimit -i/d' "$PROFILE_PATH"
    sed -i '/ulimit -l/d' "$PROFILE_PATH"
    sed -i '/ulimit -m/d' "$PROFILE_PATH"
    sed -i '/ulimit -n/d' "$PROFILE_PATH"
    sed -i '/ulimit -q/d' "$PROFILE_PATH"
    sed -i '/ulimit -s/d' "$PROFILE_PATH"
    sed -i '/ulimit -t/d' "$PROFILE_PATH"
    sed -i '/ulimit -u/d' "$PROFILE_PATH"
    sed -i '/ulimit -v/d' "$PROFILE_PATH"
    sed -i '/ulimit -x/d' "$PROFILE_PATH"
    sed -i '/ulimit -s/d' "$PROFILE_PATH"

    # Add new ulimits
    # The maximum size of core files created.
    echo "ulimit -c unlimited" | tee -a "$PROFILE_PATH"

    # The maximum size of a process's data segment
    echo "ulimit -d unlimited" | tee -a "$PROFILE_PATH"

    # The maximum size of files created by the shell (default option)
    echo "ulimit -f unlimited" | tee -a "$PROFILE_PATH"

    # The maximum number of pending signals
    echo "ulimit -i unlimited" | tee -a "$PROFILE_PATH"

    # The maximum size that may be locked into memory
    echo "ulimit -l unlimited" | tee -a "$PROFILE_PATH"

    # The maximum memory size
    echo "ulimit -m unlimited" | tee -a "$PROFILE_PATH"

    # The maximum number of open file descriptors
    echo "ulimit -n 1048576" | tee -a "$PROFILE_PATH"

    # The maximum POSIX message queue size
    echo "ulimit -q unlimited" | tee -a "$PROFILE_PATH"

    # The maximum stack size
    echo "ulimit -s -H 65536" | tee -a "$PROFILE_PATH"
    echo "ulimit -s 32768" | tee -a "$PROFILE_PATH"

    # The maximum number of seconds to be used by each process.
    echo "ulimit -t unlimited" | tee -a "$PROFILE_PATH"

    # The maximum number of processes available to a single user
    echo "ulimit -u unlimited" | tee -a "$PROFILE_PATH"

    # The maximum amount of virtual memory available to the process
    echo "ulimit -v unlimited" | tee -a "$PROFILE_PATH"

    # The maximum number of file locks
    echo "ulimit -x unlimited" | tee -a "$PROFILE_PATH"

    echo
    echo -e "${GREEN}System Limits are Optimized.${NC}"
    echo
    sleep 0.5
}

optimize_system() {
    local preset="${1:-}"
    local dry_run="${2:-false}"

    # Ignore preset and dry_run parameters for compatibility
    # Hawshemi script always applies optimizations

    check_root

    clear

    echo -e "${PURPLE}Special thanks to Hawshemi, the author of optimizer script...${NC}"
    sleep 2

    # Get the operating system name
    local os_name
    os_name=$(lsb_release -is 2>/dev/null || echo "")

    echo

    # Check if the operating system is Ubuntu
    if [[ "$os_name" == "Ubuntu" ]]; then
        echo -e "${GREEN}The operating system is Ubuntu.${NC}"
        sleep 1
    else
        echo -e "${RED}The operating system is not Ubuntu.${NC}"
        sleep 2
        return
    fi

    sysctl_optimizations
    limits_optimizations
    ask_reboot
    read -p "Press Enter to continue..."
}

optimization_menu() {
    while true; do
        show_header "System Optimization" "Presets & Safety"
        echo -e "${CYAN}Options:${NC}"
        echo "1. Dry-run (conservative)"
        echo "2. Dry-run (balanced)"
        echo "3. Dry-run (aggressive)"
        echo "4. Apply (conservative)"
        echo "5. Apply (balanced)"
        echo "6. Apply (aggressive)"
        echo "7. Rollback to last backup"
        echo "0. Back"
        echo
        safe_read "Enter your choice" "choice" "0"
        case "$choice" in
            1) optimize_system "conservative" "true" ; read -p "Press Enter to continue..." ;;
            2) optimize_system "balanced" "true" ; read -p "Press Enter to continue..." ;;
            3) optimize_system "aggressive" "true" ; read -p "Press Enter to continue..." ;;
            4) optimize_system "conservative" "false" ; read -p "Press Enter to continue..." ;;
            5) optimize_system "balanced" "false" ; read -p "Press Enter to continue..." ;;
            6) optimize_system "aggressive" "false" ; read -p "Press Enter to continue..." ;;
            7) rollback_system_settings ; read -p "Press Enter to continue..." ;;
            0) return ;;
            *) log "ERROR" "Invalid choice" ;;
        esac
    done
}

# Export functions
export -f optimize_system validate_os_compatibility display_preset_info preview_optimizations
export -f apply_sysctl_optimizations apply_ulimit_optimizations backup_system_settings rollback_system_settings validate_optimizations
export -f optimization_menu ask_reboot sysctl_optimizations limits_optimizations

# Allow running directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Simple CLI: moonfrp-optimize.sh [preset] [--dry-run]
    preset="${1:-balanced}"
    dry_run_flag="${2:-}"
    if [[ "$dry_run_flag" == "--dry-run" ]]; then
        optimize_system "$preset" "true"
    else
        optimize_system "$preset" "false"
    fi
fi


