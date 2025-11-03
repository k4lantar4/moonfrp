#!/bin/bash

#==============================================================================
# MoonFRP Search & Filter Module
# Version: 2.0.0
# Description: Search and filter configurations by name, IP, port, tag, or status
# Story: 3-2-search-filter-interface
#==============================================================================

# Prevent multiple sourcing
if [[ "${MOONFRP_SEARCH_LOADED:-}" == "true" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
export MOONFRP_SEARCH_LOADED="true"

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-index.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-services.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-ui.sh"

#==============================================================================
# CONFIGURATION
#==============================================================================

readonly FILTER_PRESETS_FILE="$HOME/.moonfrp/filter_presets.json"

#==============================================================================
# CORE SEARCH FUNCTIONS
#==============================================================================

# Auto-detect search type from query pattern
search_configs_auto() {
    local query="$1"
    
    if [[ -z "$query" ]]; then
        log "ERROR" "Query string required"
        return 1
    fi
    
    # Check IP pattern: ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$
    if [[ "$query" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        search_configs "$query" "ip"
        return $?
    fi
    
    # Check port pattern: ^[0-9]+$ and in range 1-65535
    if [[ "$query" =~ ^[0-9]+$ ]] && [[ "$query" -ge 1 ]] && [[ "$query" -le 65535 ]]; then
        search_configs "$query" "port"
        return $?
    fi
    
    # Check tag pattern: contains ':'
    if [[ "$query" == *":"* ]]; then
        search_configs "$query" "tag"
        return $?
    fi
    
    # Default to name search
    search_configs "$query" "name"
    return $?
}

# Core search function with type support
search_configs() {
    local query="$1"
    local search_type="${2:-auto}"  # auto|name|ip|port|tag|status
    
    if [[ -z "$query" ]]; then
        log "ERROR" "Query string required"
        return 1
    fi
    
    # Handle auto mode by delegating to the detector
    if [[ "$search_type" == "auto" ]]; then
        search_configs_auto "$query"
        return $?
    fi

    if ! check_python3; then
        log "ERROR" "python3 is required for search functionality"
        return 1
    fi
    
    # Ensure metadata is up-to-date
    check_and_update_index >/dev/null 2>&1 || true

    case "$search_type" in
        name|ip|port|tag)
            python3 - <<'PY' "$INDEX_DATA_ROOT" "$search_type" "$query"
import json
import os
import sys

root = sys.argv[1]
search_type = sys.argv[2]
query = sys.argv[3]

if search_type == 'port':
    try:
        query_port = int(query)
    except ValueError:
        query_port = None
else:
    query_port = None

if search_type == 'tag':
    tag_key = query
    tag_value = None
    if ':' in query:
        tag_key, tag_value = query.split(':', 1)

for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue

    cfg_path = data.get('path', '')
    cfg_type = data.get('type', '')
    server_addr = data.get('server_addr') or ''
    proxy_count = int(data.get('proxy_count') or 0)
    bind_port = data.get('bind_port')
    server_port = data.get('server_port')

    if search_type == 'name':
        if query.lower() not in cfg_path.lower():
            continue
    elif search_type == 'ip':
        match = False
        if server_addr == query:
            match = True
        elif bind_port is not None and str(bind_port) == query:
            match = True
        if not match:
            continue
    elif search_type == 'port':
        if query_port is None:
            continue
        match = False
        if isinstance(server_port, int) and server_port == query_port:
            match = True
        if isinstance(bind_port, int) and bind_port == query_port:
            match = True
        if not match:
            continue
    elif search_type == 'tag':
        tags = data.get('tags')
        if not isinstance(tags, dict):
            continue
        if tag_key not in tags:
            continue
        if tag_value is not None and str(tags.get(tag_key)) != tag_value:
            continue

    print(f"{cfg_path}|{cfg_type}|{server_addr}|{proxy_count}")
PY
                    return 0
            ;;
        status)
            local target_status="$query"
            local services=($(get_moonfrp_services))
            for svc in "${services[@]}"; do
                local svc_status
                svc_status=$(get_detailed_service_status "$svc" | cut -d'_' -f1)
                if [[ "$svc_status" != "$target_status" ]]; then
                    continue
                fi
                local config_name="${svc#moonfrp-}"
                local config_path="$CONFIG_DIR/${config_name}.toml"
                if [[ -f "$config_path" ]]; then
                    local summary
                    summary=$(python3 - <<'PY' "$INDEX_DATA_ROOT" "$config_path"
import json
import os
import sys

root = sys.argv[1]
config_path = sys.argv[2]
slug = None
for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    if data.get('path') == config_path:
        print(f"{data.get('path','')}|{data.get('type','')}|{data.get('server_addr') or ''}|{int(data.get('proxy_count') or 0)}")
        break
PY
)
                    if [[ -n "$summary" ]]; then
                        echo "$summary"
                    fi
                fi
            done
            return 0
            ;;
        *)
            log "ERROR" "Unknown search type: $search_type"
            return 1
            ;;
    esac
}

#==============================================================================
# INTERACTIVE SEARCH FUNCTIONS
#==============================================================================

# Quick search interactive with auto-detect
quick_search_interactive() {
    show_header "Quick Search" "Auto-detect search type"
    
    safe_read "Enter search query" "query" ""
    
    if [[ -z "$query" ]]; then
        log "WARN" "Empty query"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    local start_time
    start_time=$(date +%s%N)
    
    local results
    results=$(search_configs "$query" "auto")
    local search_exit=$?
    
    local end_time
    end_time=$(date +%s%N)
    local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    
    clear
    show_header "Search Results" "Query: $query (${elapsed_ms}ms)"
    
    if [[ $search_exit -ne 0 ]] || [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results found${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    display_search_results "$results"
    show_operations_menu "$results"
    
    return 0
}

# Search by name interactive
search_by_name_interactive() {
    show_header "Search by Name" "Fuzzy name matching"
    
    safe_read "Enter name query" "query" ""
    
    if [[ -z "$query" ]]; then
        log "WARN" "Empty query"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    local start_time
    start_time=$(date +%s%N)
    
    local results
    results=$(search_configs "$query" "name")
    local search_exit=$?
    
    local end_time
    end_time=$(date +%s%N)
    local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    
    clear
    show_header "Name Search Results" "Query: $query (${elapsed_ms}ms)"
    
    if [[ $search_exit -ne 0 ]] || [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results found${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    display_search_results "$results"
    show_operations_menu "$results"
    
    return 0
}

# Search by IP interactive
search_by_ip_interactive() {
    show_header "Search by IP" "Server or bind port IP address"
    
    safe_read "Enter IP address" "query" ""
    
    if [[ -z "$query" ]]; then
        log "WARN" "Empty query"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    if ! validate_ip "$query"; then
        log "ERROR" "Invalid IP address format"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    local start_time
    start_time=$(date +%s%N)
    
    local results
    results=$(search_configs "$query" "ip")
    local search_exit=$?
    
    local end_time
    end_time=$(date +%s%N)
    local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    
    clear
    show_header "IP Search Results" "Query: $query (${elapsed_ms}ms)"
    
    if [[ $search_exit -ne 0 ]] || [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results found${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    display_search_results "$results"
    show_operations_menu "$results"
    
    return 0
}

# Search by port interactive
search_by_port_interactive() {
    show_header "Search by Port" "Server or bind port number"
    
    safe_read "Enter port number" "query" ""
    
    if [[ -z "$query" ]]; then
        log "WARN" "Empty query"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    if ! validate_port "$query"; then
        log "ERROR" "Invalid port number (must be 1-65535)"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    local start_time
    start_time=$(date +%s%N)
    
    local results
    results=$(search_configs "$query" "port")
    local search_exit=$?
    
    local end_time
    end_time=$(date +%s%N)
    local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    
    clear
    show_header "Port Search Results" "Query: $query (${elapsed_ms}ms)"
    
    if [[ $search_exit -ne 0 ]] || [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results found${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    display_search_results "$results"
    show_operations_menu "$results"
    
    return 0
}

# Search by tag interactive
search_by_tag_interactive() {
    show_header "Search by Tag" "Tag key:value or key-only"
    
    safe_read "Enter tag (key:value or key)" "query" ""
    
    if [[ -z "$query" ]]; then
        log "WARN" "Empty query"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    local start_time
    start_time=$(date +%s%N)
    
    local results
    results=$(search_configs "$query" "tag")
    local search_exit=$?
    
    local end_time
    end_time=$(date +%s%N)
    local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    
    clear
    show_header "Tag Search Results" "Query: $query (${elapsed_ms}ms)"
    
    if [[ $search_exit -ne 0 ]] || [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results found${NC}"
        log "INFO" "Tag search requires Story 2.3 tagging system"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    display_search_results "$results"
    show_operations_menu "$results"
    
    return 0
}

# Filter by status interactive
filter_by_status_interactive() {
    show_header "Filter by Status" "Service status filter"
    
    echo -e "${CYAN}Status Options:${NC}"
    echo "1. active"
    echo "2. failed"
    echo "3. inactive"
    echo
    safe_read "Select status (1-3)" "status_choice" ""
    
    local query=""
    case "$status_choice" in
        1) query="active" ;;
        2) query="failed" ;;
        3) query="inactive" ;;
        *)
            log "ERROR" "Invalid choice"
            read -p "Press Enter to continue..."
            return 1
            ;;
    esac
    
    local start_time
    start_time=$(date +%s%N)
    
    local results
    results=$(search_configs "$query" "status")
    local search_exit=$?
    
    local end_time
    end_time=$(date +%s%N)
    local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    
    clear
    show_header "Status Filter Results" "Status: $query (${elapsed_ms}ms)"
    
    if [[ $search_exit -ne 0 ]] || [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results found${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    display_search_results "$results"
    show_operations_menu "$results"
    
    return 0
}

#==============================================================================
# SEARCH RESULT DISPLAY AND OPERATIONS
#==============================================================================

# Display search results in formatted table
display_search_results() {
    local results="$1"
    
    if [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Results:${NC}"
    echo
    printf "%-40s %-10s %-20s %s\n" "Config File" "Type" "Server IP" "Proxies"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    local count=0
    while IFS='|' read -r file_path config_type server_addr proxy_count; do
        if [[ -n "$file_path" ]]; then
            local config_name=$(basename "$file_path" .toml)
            printf "%-40s %-10s %-20s %s\n" "$config_name" "$config_type" "${server_addr:-N/A}" "$proxy_count"
            ((count++))
        fi
    done <<< "$results"
    
    echo
    echo -e "${GREEN}Found $count matching configuration(s)${NC}"
    
    return 0
}

# Show operations menu for search results
show_operations_menu() {
    local results="$1"
    
    if [[ -z "$results" ]]; then
        return 1
    fi
    
    echo
    echo -e "${CYAN}Operations:${NC}"
    echo "1. View config"
    echo "2. Edit config"
    echo "3. Restart service(s)"
    echo "4. View service status"
    echo "0. Back"
    echo
    
    safe_read "Select operation" "op_choice" "0"
    
    case "$op_choice" in
        1)
            show_results_view_config "$results"
            ;;
        2)
            show_results_edit_config "$results"
            ;;
        3)
            show_results_restart_services "$results"
            ;;
        4)
            show_results_view_status "$results"
            ;;
        0)
            return 0
            ;;
        *)
            log "ERROR" "Invalid choice"
            ;;
    esac
    
    return 0
}

# View config from search results
show_results_view_config() {
    local results="$1"
    
    local config_files=()
    while IFS='|' read -r file_path config_type server_addr proxy_count; do
        if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
            config_files+=("$file_path")
        fi
    done <<< "$results"
    
    if [[ ${#config_files[@]} -eq 0 ]]; then
        log "WARN" "No valid config files found in results"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    if [[ ${#config_files[@]} -eq 1 ]]; then
        # Single file - show directly
        show_header "View Config" "${config_files[0]}"
        cat "${config_files[0]}"
        echo
        read -p "Press Enter to continue..."
    else
        # Multiple files - let user choose
        show_header "Select Config to View" ""
        local i=1
        for config_file in "${config_files[@]}"; do
            echo "$i. $(basename "$config_file")"
            ((i++))
        done
        echo "0. Cancel"
        echo
        
        safe_read "Select config" "file_choice" "0"
        
        if [[ "$file_choice" -ge 1 ]] && [[ "$file_choice" -le ${#config_files[@]} ]]; then
            local selected_file="${config_files[$((file_choice - 1))]}"
            show_header "View Config" "$selected_file"
            cat "$selected_file"
            echo
            read -p "Press Enter to continue..."
        fi
    fi
    
    return 0
}

# Edit config from search results
show_results_edit_config() {
    local results="$1"
    
    local config_files=()
    while IFS='|' read -r file_path config_type server_addr proxy_count; do
        if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
            config_files+=("$file_path")
        fi
    done <<< "$results"
    
    if [[ ${#config_files[@]} -eq 0 ]]; then
        log "WARN" "No valid config files found in results"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # For multiple files, let user choose or edit all
    if [[ ${#config_files[@]} -gt 1 ]]; then
        show_header "Select Config to Edit" ""
        local i=1
        for config_file in "${config_files[@]}"; do
            echo "$i. $(basename "$config_file")"
            ((i++))
        done
        echo "$((${#config_files[@]} + 1)). Edit all"
        echo "0. Cancel"
        echo
        
        safe_read "Select option" "file_choice" "0"
        
        if [[ "$file_choice" -ge 1 ]] && [[ "$file_choice" -le ${#config_files[@]} ]]; then
            local selected_file="${config_files[$((file_choice - 1))]}"
            ${EDITOR:-nano} "$selected_file"
        elif [[ "$file_choice" -eq $((${#config_files[@]} + 1)) ]]; then
            # Edit all
            for config_file in "${config_files[@]}"; do
                ${EDITOR:-nano} "$config_file"
            done
        fi
    else
        # Single file - edit directly
        ${EDITOR:-nano} "${config_files[0]}"
    fi
    
    return 0
}

# Restart services from search results
show_results_restart_services() {
    local results="$1"
    
    local service_names=()
    while IFS='|' read -r file_path config_type server_addr proxy_count; do
        if [[ -n "$file_path" ]]; then
            local config_name=$(basename "$file_path" .toml)
            local service_name="moonfrp-${config_name}"
            
            # Check if service exists
            if systemctl list-unit-files | grep -q "${service_name}\.service"; then
                service_names+=("$service_name")
            fi
        fi
    done <<< "$results"
    
    if [[ ${#service_names[@]} -eq 0 ]]; then
        log "WARN" "No services found for restart"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    show_header "Restart Services" "Services: ${#service_names[@]}"
    echo -e "${CYAN}Services to restart:${NC}"
    for service in "${service_names[@]}"; do
        echo "  - $service"
    done
    echo
    
    safe_read "Confirm restart? (y/N)" "confirm" "n"
    
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # Use bulk_restart_services from Story 2.1 if available
        if command -v bulk_restart_services &> /dev/null || [[ "$(type -t bulk_restart_services)" == "function" ]]; then
            # For filtered services, we need to pass specific service list
            # Since bulk_restart_services() restarts all services, we'll call restart_service for each
            local restarted=0
            for service in "${service_names[@]}"; do
                if restart_service "$service" 2>/dev/null; then
                    ((restarted++))
                fi
            done
            log "INFO" "Restarted $restarted of ${#service_names[@]} services"
        else
            # Fallback: restart individually
            local restarted=0
            for service in "${service_names[@]}"; do
                if systemctl restart "$service" 2>/dev/null; then
                    log "INFO" "Restarted: $service"
                    ((restarted++))
                else
                    log "ERROR" "Failed to restart: $service"
                fi
            done
            log "INFO" "Restarted $restarted of ${#service_names[@]} services"
        fi
    else
        log "INFO" "Restart cancelled"
    fi
    
    read -p "Press Enter to continue..."
    return 0
}

# View service status from search results
show_results_view_status() {
    local results="$1"
    
    show_header "Service Status" ""
    echo -e "${CYAN}Service Status:${NC}"
    echo
    printf "%-40s %-20s %s\n" "Service" "Status" "Config"
    echo "────────────────────────────────────────────────────────────────────"
    
    local count=0
    while IFS='|' read -r file_path config_type server_addr proxy_count; do
        if [[ -n "$file_path" ]]; then
            local config_name=$(basename "$file_path" .toml)
            local service_name="moonfrp-${config_name}"
            
            local status="N/A"
            local status_color="${GRAY}"
            
            if systemctl list-unit-files | grep -q "${service_name}\.service"; then
                if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                    status="active"
                    status_color="${GREEN}"
                elif systemctl is-failed --quiet "$service_name" 2>/dev/null; then
                    status="failed"
                    status_color="${RED}"
                else
                    status="inactive"
                    status_color="${YELLOW}"
                fi
            else
                status="not installed"
            fi
            
            printf "%-40s ${status_color}%-20s${NC} %s\n" "$service_name" "$status" "$(basename "$file_path")"
            ((count++))
        fi
    done <<< "$results"
    
    echo
    echo -e "${GREEN}Displayed status for $count service(s)${NC}"
    read -p "Press Enter to continue..."
    
    return 0
}

#==============================================================================
# ADVANCED FILTER BUILDER
#==============================================================================

# Advanced filter builder with multiple criteria
advanced_filter_builder() {
    show_header "Advanced Filter Builder" "Multi-criteria filter"
    
    # Associative array for filters
    declare -A filters
    
    while true; do
        clear
        show_header "Advanced Filter Builder" "Current filters: ${#filters[@]}"
        
        if [[ ${#filters[@]} -gt 0 ]]; then
            echo -e "${CYAN}Active Filters:${NC}"
            local i=1
            for filter_key in "${!filters[@]}"; do
                echo "$i. $filter_key: ${filters[$filter_key]}"
                ((i++))
            done
            echo
        fi
        
        echo -e "${CYAN}Options:${NC}"
        echo "1. Add name filter"
        echo "2. Add IP filter"
        echo "3. Add port filter"
        echo "4. Add tag filter"
        echo "5. Add status filter"
        echo "6. Remove filter"
        echo "7. Apply filters"
        echo "8. Save as preset"
        echo "0. Back"
        echo
        
        safe_read "Select option" "builder_choice" "0"
        
        case "$builder_choice" in
            1)
                safe_read "Enter name pattern" "name_pattern" ""
                if [[ -n "$name_pattern" ]]; then
                    filters["name"]="$name_pattern"
                fi
                ;;
            2)
                safe_read "Enter IP address" "ip_addr" ""
                if [[ -n "$ip_addr" ]] && validate_ip "$ip_addr"; then
                    filters["ip"]="$ip_addr"
                elif [[ -n "$ip_addr" ]]; then
                    log "ERROR" "Invalid IP address"
                    read -p "Press Enter to continue..."
                fi
                ;;
            3)
                safe_read "Enter port number" "port_num" ""
                if [[ -n "$port_num" ]] && validate_port "$port_num"; then
                    filters["port"]="$port_num"
                elif [[ -n "$port_num" ]]; then
                    log "ERROR" "Invalid port number"
                    read -p "Press Enter to continue..."
                fi
                ;;
            4)
                safe_read "Enter tag (key:value or key)" "tag_query" ""
                if [[ -n "$tag_query" ]]; then
                    filters["tag"]="$tag_query"
                fi
                ;;
            5)
                echo "1. active"
                echo "2. failed"
                echo "3. inactive"
                safe_read "Select status" "status_choice" ""
                case "$status_choice" in
                    1) filters["status"]="active" ;;
                    2) filters["status"]="failed" ;;
                    3) filters["status"]="inactive" ;;
                esac
                ;;
            6)
                if [[ ${#filters[@]} -eq 0 ]]; then
                    log "WARN" "No filters to remove"
                    read -p "Press Enter to continue..."
                else
                    echo -e "${CYAN}Select filter to remove:${NC}"
                    local i=1
                    local filter_keys=()
                    for filter_key in "${!filters[@]}"; do
                        echo "$i. $filter_key: ${filters[$filter_key]}"
                        filter_keys+=("$filter_key")
                        ((i++))
                    done
                    safe_read "Select filter" "remove_choice" ""
                    if [[ "$remove_choice" -ge 1 ]] && [[ "$remove_choice" -le ${#filter_keys[@]} ]]; then
                        unset filters["${filter_keys[$((remove_choice - 1))]}"]
                    fi
                fi
                ;;
            7)
                apply_filters filters
                read -p "Press Enter to continue..."
                ;;
            8)
                safe_read "Enter preset name" "preset_name" ""
                if [[ -n "$preset_name" ]]; then
                    save_filter_preset "$preset_name" filters
                fi
                ;;
            0)
                return 0
                ;;
            *)
                log "ERROR" "Invalid choice"
                ;;
        esac
    done
}

# Apply multiple filters (AND logic)
apply_filters() {
    local -n filter_ref="$1"
    
    if [[ ${#filter_ref[@]} -eq 0 ]]; then
        log "WARN" "No filters to apply"
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    if [[ ! -f "$db_path" ]]; then
        log "ERROR" "Index database not found"
        return 1
    fi
    
    # Start with all configs, then filter progressively
    local all_results
    all_results=$(sqlite3 "$db_path" \
        "SELECT file_path FROM config_index ORDER BY file_path;" 2>/dev/null)
    
    # Apply each filter in sequence (AND logic)
    local filtered_results="$all_results"
    
    # Name filter
    if [[ -n "${filter_ref[name]:-}" ]]; then
        local name_pattern=$(printf '%s\n' "${filter_ref[name]}" | sed "s/'/''/g")
        filtered_results=$(echo "$filtered_results" | while IFS= read -r file_path; do
            if [[ "$file_path" == *"$name_pattern"* ]]; then
                echo "$file_path"
            fi
        done)
    fi
    
    # IP filter
    if [[ -n "${filter_ref[ip]:-}" ]]; then
        local ip_addr=$(printf '%s\n' "${filter_ref[ip]}" | sed "s/'/''/g")
        local ip_results
        ip_results=$(sqlite3 "$db_path" \
            "SELECT file_path FROM config_index 
             WHERE server_addr='$ip_addr' OR bind_port='$ip_addr';" 2>/dev/null)
        filtered_results=$(comm -12 <(echo "$filtered_results" | sort) <(echo "$ip_results" | sort))
    fi
    
    # Port filter
    if [[ -n "${filter_ref[port]:-}" ]]; then
        local port_num="${filter_ref[port]}"
        local port_results
        port_results=$(sqlite3 "$db_path" \
            "SELECT file_path FROM config_index 
             WHERE server_port=$port_num OR bind_port=$port_num;" 2>/dev/null)
        filtered_results=$(comm -12 <(echo "$filtered_results" | sort) <(echo "$port_results" | sort))
    fi
    
    # Tag filter
    if [[ -n "${filter_ref[tag]:-}" ]]; then
        local tag_results
        tag_results=$(search_configs "${filter_ref[tag]}" "tag" 2>/dev/null | cut -d'|' -f1)
        if [[ -n "$tag_results" ]]; then
            filtered_results=$(comm -12 <(echo "$filtered_results" | sort) <(echo "$tag_results" | sort))
        else
            filtered_results=""
        fi
    fi
    
    # Status filter (requires checking systemctl for each)
    if [[ -n "${filter_ref[status]:-}" ]]; then
        local status_query="${filter_ref[status]}"
        local status_filtered=""
        while IFS= read -r file_path; do
            if [[ -z "$file_path" ]]; then
                continue
            fi
            local config_name=$(basename "$file_path" .toml)
            local service_name="moonfrp-${config_name}"
            local service_status="inactive"
            
            if systemctl list-unit-files | grep -q "${service_name}\.service"; then
                if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                    service_status="active"
                elif systemctl is-failed --quiet "$service_name" 2>/dev/null; then
                    service_status="failed"
                fi
            fi
            
            if [[ "$service_status" == "$status_query" ]]; then
                status_filtered="${status_filtered}${file_path}\n"
            fi
        done <<< "$filtered_results"
        filtered_results=$(echo -e "$status_filtered")
    fi
    
    # Convert filtered file paths to full config info
    local final_results=""
    while IFS= read -r file_path; do
        if [[ -z "$file_path" ]]; then
            continue
        fi
        local escaped_path=$(printf '%s\n' "$file_path" | sed "s/'/''/g")
        local config_info
        config_info=$(sqlite3 -separator '|' "$db_path" \
            "SELECT file_path, config_type, server_addr, COALESCE(proxy_count, 0)
             FROM config_index 
             WHERE file_path='$escaped_path'
             LIMIT 1;" 2>/dev/null)
        if [[ -n "$config_info" ]]; then
            final_results="${final_results}${config_info}\n"
        fi
    done <<< "$filtered_results"
    
    clear
    show_header "Filter Results" "Applied ${#filter_ref[@]} filter(s)"
    
    if [[ -z "$final_results" ]] || [[ -z "$(echo -e "$final_results")" ]]; then
        echo -e "${YELLOW}No results found${NC}"
    else
        display_search_results "$(echo -e "$final_results")"
        show_operations_menu "$(echo -e "$final_results")"
    fi
    
    return 0
}

#==============================================================================
# FILTER PRESET MANAGEMENT
#==============================================================================

# Save filter preset to JSON file
save_filter_preset() {
    local preset_name="$1"
    local -n filter_ref="$2"
    
    if [[ -z "$preset_name" ]]; then
        log "ERROR" "Preset name required"
        return 1
    fi
    
    if [[ ${#filter_ref[@]} -eq 0 ]]; then
        log "WARN" "No filters to save"
        return 1
    fi
    
    mkdir -p "$(dirname "$FILTER_PRESETS_FILE")"
    
    # Create preset object
    local preset_json="{"
    preset_json="${preset_json}\"name\":\"$(printf '%s' "$preset_name" | sed 's/"/\\"/g')\","
    preset_json="${preset_json}\"filters\":{"
    
    local first=1
    for filter_key in "${!filter_ref[@]}"; do
        if [[ $first -eq 0 ]]; then
            preset_json="${preset_json},"
        fi
        preset_json="${preset_json}\"$(printf '%s' "$filter_key" | sed 's/"/\\"/g')\":\"$(printf '%s' "${filter_ref[$filter_key]}" | sed 's/"/\\"/g')\""
        first=0
    done
    
    preset_json="${preset_json}}"
    preset_json="${preset_json}}"
    
    # Load existing presets or create new array
    local existing_presets="[]"
    if [[ -f "$FILTER_PRESETS_FILE" ]]; then
        existing_presets=$(cat "$FILTER_PRESETS_FILE" 2>/dev/null || echo "[]")
    fi
    
    # Use jq if available, otherwise use basic text manipulation
    if command -v jq &> /dev/null; then
        # Remove preset if it exists with same name
        existing_presets=$(echo "$existing_presets" | jq "map(select(.name != \"$preset_name\"))" 2>/dev/null || echo "$existing_presets")
        # Add new preset
        existing_presets=$(echo "$existing_presets" | jq ". + [$(echo "$preset_json" | jq -c .)]" 2>/dev/null || echo "$existing_presets")
        echo "$existing_presets" > "$FILTER_PRESETS_FILE"
    else
        # Fallback: simple text-based storage
        # Remove existing preset with same name
        local temp_file="${FILTER_PRESETS_FILE}.tmp"
        grep -v "\"name\":\"$(printf '%s' "$preset_name" | sed 's/"/\\"/g')\"" "$FILTER_PRESETS_FILE" > "$temp_file" 2>/dev/null || echo "[]" > "$temp_file"
        # Append new preset (basic format)
        echo "$preset_json" >> "$temp_file"
        mv "$temp_file" "$FILTER_PRESETS_FILE" 2>/dev/null
    fi
    
    log "INFO" "Filter preset saved: $preset_name"
    return 0
}

# Load filter preset from JSON file
load_filter_preset() {
    local preset_name="$1"
    
    if [[ -z "$preset_name" ]]; then
        log "ERROR" "Preset name required"
        return 1
    fi
    
    if [[ ! -f "$FILTER_PRESETS_FILE" ]]; then
        log "WARN" "No presets file found"
        return 1
    fi
    
    # Use jq if available
    if command -v jq &> /dev/null; then
        local preset_json
        preset_json=$(jq -r ".[] | select(.name == \"$preset_name\") | .filters" "$FILTER_PRESETS_FILE" 2>/dev/null)
        if [[ -n "$preset_json" ]] && [[ "$preset_json" != "null" ]]; then
            echo "$preset_json"
            return 0
        fi
    else
        # Fallback: simple grep-based parsing
        local preset_line
        preset_line=$(grep "\"name\":\"$(printf '%s' "$preset_name" | sed 's/"/\\"/g')\"" "$FILTER_PRESETS_FILE" 2>/dev/null)
        if [[ -n "$preset_line" ]]; then
            # Extract filters portion (basic parsing)
            echo "$preset_line" | grep -o '"filters":{[^}]*}' 2>/dev/null || echo "{}"
            return 0
        fi
    fi
    
    log "WARN" "Preset not found: $preset_name"
    return 1
}

# Saved filters menu
saved_filters_menu() {
    show_header "Saved Filter Presets" ""
    
    if [[ ! -f "$FILTER_PRESETS_FILE" ]]; then
        echo -e "${YELLOW}No saved presets${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    # Load presets
    local presets=()
    local preset_names=()
    
    if command -v jq &> /dev/null; then
        while IFS= read -r preset_name; do
            if [[ -n "$preset_name" ]] && [[ "$preset_name" != "null" ]]; then
                preset_names+=("$preset_name")
            fi
        done < <(jq -r '.[].name' "$FILTER_PRESETS_FILE" 2>/dev/null)
    else
        # Fallback: basic grep extraction
        while IFS= read -r preset_line; do
            local preset_name
            preset_name=$(echo "$preset_line" | grep -o '"name":"[^"]*"' | sed 's/"name":"\(.*\)"/\1/' 2>/dev/null)
            if [[ -n "$preset_name" ]]; then
                preset_names+=("$preset_name")
            fi
        done < "$FILTER_PRESETS_FILE"
    fi
    
    if [[ ${#preset_names[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No saved presets${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    echo -e "${CYAN}Available Presets:${NC}"
    local i=1
    for preset_name in "${preset_names[@]}"; do
        echo "$i. $preset_name"
        ((i++))
    done
    echo "0. Back"
    echo
    
    safe_read "Select preset" "preset_choice" "0"
    
    if [[ "$preset_choice" == "0" ]]; then
        return 0
    fi
    
    if [[ "$preset_choice" -ge 1 ]] && [[ "$preset_choice" -le ${#preset_names[@]} ]]; then
        local selected_preset="${preset_names[$((preset_choice - 1))]}"
        local filters_json
        filters_json=$(load_filter_preset "$selected_preset")
        
        if [[ $? -eq 0 ]] && [[ -n "$filters_json" ]]; then
            # Convert JSON filters to associative array
            declare -A loaded_filters
            
            if command -v jq &> /dev/null; then
                while IFS='=' read -r key value; do
                    if [[ -n "$key" ]] && [[ -n "$value" ]]; then
                        loaded_filters["$key"]="$value"
                    fi
                done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' <<< "$filters_json" 2>/dev/null)
            fi
            
            if [[ ${#loaded_filters[@]} -gt 0 ]]; then
                apply_filters loaded_filters
            else
                log "WARN" "Failed to load filters from preset"
            fi
        else
            log "ERROR" "Failed to load preset: $selected_preset"
        fi
    else
        log "ERROR" "Invalid choice"
    fi
    
    read -p "Press Enter to continue..."
    return 0
}

#==============================================================================
# INTERACTIVE SEARCH MENU
#==============================================================================

# Main search and filter menu
search_filter_menu() {
    while true; do
        show_header "Search & Filter" "Find configurations quickly"
        
        echo -e "${CYAN}Search Options:${NC}"
        echo "1. Quick Search (auto-detect)"
        echo "2. Search by Name"
        echo "3. Search by IP"
        echo "4. Search by Port"
        echo "5. Search by Tag"
        echo "6. Filter by Status"
        echo "7. Advanced Filter Builder"
        echo "8. Saved Filters"
        echo "0. Back"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1)
                quick_search_interactive
                ;;
            2)
                search_by_name_interactive
                ;;
            3)
                search_by_ip_interactive
                ;;
            4)
                search_by_port_interactive
                ;;
            5)
                search_by_tag_interactive
                ;;
            6)
                filter_by_status_interactive
                ;;
            7)
                advanced_filter_builder
                ;;
            8)
                saved_filters_menu
                ;;
            0)
                return 0
                ;;
            *)
                log "ERROR" "Invalid choice"
                ;;
        esac
    done
}

# Export functions for use in other modules
export -f search_configs search_configs_auto
export -f quick_search_interactive search_by_name_interactive search_by_ip_interactive
export -f search_by_port_interactive search_by_tag_interactive filter_by_status_interactive
export -f display_search_results show_operations_menu
export -f advanced_filter_builder apply_filters
export -f save_filter_preset load_filter_preset saved_filters_menu
export -f search_filter_menu

