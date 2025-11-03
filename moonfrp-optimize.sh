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

    {
        echo "$MOONFRP_SYSCTL_BLOCK_BEGIN"
        echo "# Preset: $preset"
        for key in "${!preset_ref[@]}"; do
            echo "$key = ${preset_ref[$key]}"
        done
        echo "$MOONFRP_SYSCTL_BLOCK_END"
    } | tee -a "$SYSCTL_PATH" >/dev/null

    if sysctl -p "$SYSCTL_PATH"; then
        log "INFO" "Sysctl optimizations applied"
    else
        log "ERROR" "Failed to apply sysctl settings"
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
    for key in "${!preset_ref[@]}"; do
        local current
        current=$(sysctl -n "$key" 2>/dev/null || echo "")
        if [[ "$current" != "${preset_ref[$key]}" ]]; then
            log "WARN" "Validation mismatch: $key expected '${preset_ref[$key]}' got '$current'"
            failed=1
        fi
    done
    if [[ $failed -eq 0 ]]; then
        log "INFO" "Validation successful"
        return 0
    else
        return 1
    fi
}

optimize_system() {
    local preset="${1:-balanced}"
    local dry_run="${2:-false}"

    check_root

    local assoc_name; assoc_name=$(get_preset_assoc_name "$preset")
    if [[ -z "$assoc_name" ]]; then
        log "ERROR" "Invalid preset: $preset (use conservative|balanced|aggressive)"
        return 1
    fi

    display_preset_info "$preset"

    local os_status=0
    if ! validate_os_compatibility; then
        os_status=$?
    fi
    if [[ $os_status -ne 0 ]]; then
        echo -e "${YELLOW}OS compatibility warnings detected.${NC}"
        safe_read "Type 'yes' to proceed anyway" "os_confirm" "no"
        if [[ "${os_confirm}" != "yes" ]]; then
            log "INFO" "Aborted by user due to OS warning"
            return 1
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        preview_optimizations "$preset"
        log "INFO" "Dry-run only; no changes applied"
        return 0
    fi

    safe_read "Apply optimization now? (yes/no)" "confirm" "no"
    if [[ "$confirm" != "yes" ]]; then
        log "INFO" "Cancelled by user"
        return 0
    fi

    local start_ts
    start_ts=$(date +%s)

    backup_system_settings
    apply_sysctl_optimizations "$preset"
    apply_ulimit_optimizations

    if ! validate_optimizations "$preset"; then
        log "ERROR" "Validation failed; initiating automatic rollback"
        rollback_system_settings || true
        return 1
    fi

    local end_ts
    end_ts=$(date +%s)
    local elapsed=$((end_ts - start_ts))
    log "INFO" "Optimization completed in ${elapsed}s"
    if [[ $elapsed -ge 10 ]]; then
        log "WARN" "Performance target exceeded (>=10s)"
    fi
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
export -f optimization_menu

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


