# Epic 3: Performance & UX at Scale

**Epic ID:** MOONFRP-E03  
**Priority:** P1 - Major Quality of Life  
**Estimated Effort:** 4-5 days  
**Dependencies:** Epic 1 (config index)  
**Target Release:** v2.0.0-beta.1

---

## Epic Goal

Transform the user experience for 50-tunnel management through aggressive caching, instant search/filter capabilities, enhanced configuration views optimized for DevOps workflows, and non-blocking async operations.

## Success Criteria

- ✅ Menu loads in <200ms with 50 configs (current: 2-3s)
- ✅ Search/filter returns results in <50ms
- ✅ Config details view copy-paste ready for team sharing
- ✅ Connection tests complete in <5s for 50 IPs (parallel execution)
- ✅ Zero blocking operations in UI
- ✅ Smooth, responsive experience at scale

---

## Story 3.1: Cached Status Display

**Story ID:** MOONFRP-E03-S01  
**Priority:** P1  
**Effort:** 1.5 days

### Problem Statement

Current menu loads all service statuses synchronously on every render, causing 2-3s delays with 50 tunnels. DevOps engineers need instant menu access.

### Acceptance Criteria

1. Menu renders in <200ms with 50 configs
2. Status cached with 5s TTL (configurable)
3. Background refresh: updates cache without blocking UI
4. Visual indicator when cache is stale/refreshing
5. Manual refresh option
6. Cache survives across menu navigation

### Technical Specification

**Location:** `moonfrp-ui.sh` - Enhanced menu system

**Implementation:**
```bash
# Cache management
declare -A STATUS_CACHE
STATUS_CACHE["timestamp"]=0
STATUS_CACHE["data"]=""
STATUS_CACHE["ttl"]=5
STATUS_CACHE["refreshing"]=false

# Fast cached status
get_cached_status() {
    local now=$(date +%s)
    local cache_age=$((now - ${STATUS_CACHE["timestamp"]:-0}))
    
    # Return cache if fresh
    if [[ $cache_age -lt ${STATUS_CACHE["ttl"]} ]] && [[ -n "${STATUS_CACHE["data"]}" ]]; then
        echo "${STATUS_CACHE["data"]}"
        return 0
    fi
    
    # Cache stale - refresh in background if not already refreshing
    if [[ "${STATUS_CACHE["refreshing"]}" == "false" ]]; then
        refresh_status_cache_background
    fi
    
    # Return stale cache while refreshing (better than blocking)
    if [[ -n "${STATUS_CACHE["data"]}" ]]; then
        echo "${STATUS_CACHE["data"]}"
        return 0
    fi
    
    # First run - must load synchronously
    refresh_status_cache_sync
    echo "${STATUS_CACHE["data"]}"
}

# Synchronous refresh (blocking - only for first load)
refresh_status_cache_sync() {
    local status_data=$(generate_quick_status)
    
    STATUS_CACHE["data"]="$status_data"
    STATUS_CACHE["timestamp"]=$(date +%s)
    STATUS_CACHE["refreshing"]=false
}

# Background refresh (non-blocking)
refresh_status_cache_background() {
    STATUS_CACHE["refreshing"]=true
    
    (
        # Generate status in background
        local status_data=$(generate_quick_status)
        
        # Update cache file (shared between processes)
        local cache_file="$HOME/.moonfrp/status.cache"
        echo "$status_data" > "$cache_file"
        echo "$(date +%s)" > "$cache_file.timestamp"
    ) &
    
    # Check for completion asynchronously
    {
        sleep 0.5
        local cache_file="$HOME/.moonfrp/status.cache"
        if [[ -f "$cache_file" ]]; then
            STATUS_CACHE["data"]=$(cat "$cache_file")
            STATUS_CACHE["timestamp"]=$(cat "$cache_file.timestamp" 2>/dev/null || echo "0")
        fi
        STATUS_CACHE["refreshing"]=false
    } &
}

# Generate quick status (optimized)
generate_quick_status() {
    local db_path="$HOME/.moonfrp/index.db"
    
    # Query index for counts
    local total_configs=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index" 2>/dev/null || echo "0")
    local total_proxies=$(sqlite3 "$db_path" "SELECT SUM(proxy_count) FROM config_index" 2>/dev/null || echo "0")
    
    # Quick service status (batch mode)
    local active_count=0
    local failed_count=0
    local inactive_count=0
    
    # Use systemctl batch query
    while read -r unit state; do
        case "$state" in
            active|running) ((active_count++)) ;;
            failed) ((failed_count++)) ;;
            *) ((inactive_count++)) ;;
        esac
    done < <(systemctl list-units --type=service --all --no-pager --no-legend \
             | grep -E "moonfrp-(server|client)" | awk '{print $1, $3}')
    
    # FRP version (cached separately - changes rarely)
    local frp_version=$(get_frp_version_cached)
    
    # Format output
    cat <<EOF
{
  "total_configs": $total_configs,
  "total_proxies": $total_proxies,
  "services": {
    "active": $active_count,
    "failed": $failed_count,
    "inactive": $inactive_count
  },
  "frp_version": "$frp_version"
}
EOF
}

# FRP version with caching
get_frp_version_cached() {
    local cache_file="$HOME/.moonfrp/frp_version.cache"
    
    # Cache for 1 hour (version doesn't change often)
    if [[ -f "$cache_file" ]] && [[ $(($(date +%s) - $(stat -c %Y "$cache_file"))) -lt 3600 ]]; then
        cat "$cache_file"
        return
    fi
    
    local version=$(get_frp_version)
    echo "$version" > "$cache_file"
    echo "$version"
}

# Enhanced main menu
main_menu() {
    while true; do
        if [[ "${MENU_STATE["ctrl_c_pressed"]}" == "true" ]]; then
            MENU_STATE["ctrl_c_pressed"]="false"
            return
        fi
        
        clear
        
        # Minimal header
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${PURPLE}  MoonFRP v$MOONFRP_VERSION${NC} - ${GRAY}Enterprise Tunnel Management${NC}"
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        # Fast status display
        display_cached_status
        
        echo
        echo -e "${CYAN}Main Menu:${NC}"
        echo "1. Quick Setup"
        echo "2. Service Management"
        echo "3. Configuration Management"
        echo "4. Config Details (Copy-Paste Ready)"
        echo "5. Search & Filter"
        echo "6. Advanced Tools"
        echo "7. System Optimization"
        echo "r. Refresh Status"
        echo "0. Exit"
        echo
        
        safe_read "Choice" "choice" "0"
        
        case "$choice" in
            1) quick_setup_wizard ;;
            2) service_management_menu ;;
            3) config_wizard ;;
            4) show_config_details ;;
            5) search_filter_menu ;;
            6) advanced_tools_menu ;;
            7) optimize_system ;;
            r|R) refresh_status_cache_sync; continue ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) log "ERROR" "Invalid choice" ;;
        esac
    done
}

# Display cached status
display_cached_status() {
    local status_json=$(get_cached_status)
    
    if [[ -z "$status_json" ]]; then
        echo -e "  ${GRAY}Loading status...${NC}"
        return
    fi
    
    # Parse JSON (using jq if available, fallback to grep)
    if command -v jq &>/dev/null; then
        local total_configs=$(echo "$status_json" | jq -r '.total_configs')
        local total_proxies=$(echo "$status_json" | jq -r '.total_proxies')
        local active=$(echo "$status_json" | jq -r '.services.active')
        local failed=$(echo "$status_json" | jq -r '.services.failed')
        local frp_version=$(echo "$status_json" | jq -r '.frp_version')
        
        echo -e "  ${GREEN}●${NC} FRP: $frp_version | Configs: $total_configs | Proxies: $total_proxies"
        
        if [[ $failed -gt 0 ]]; then
            echo -e "  Services: ${GREEN}$active active${NC} | ${RED}$failed failed${NC}"
        else
            echo -e "  Services: ${GREEN}$active active${NC}"
        fi
    else
        # Fallback: simple display
        echo -e "  ${GREEN}●${NC} Status: OK (detailed view requires jq)"
    fi
    
    # Staleness indicator
    local cache_age=$(($(date +%s) - ${STATUS_CACHE["timestamp"]:-0}))
    if [[ $cache_age -gt ${STATUS_CACHE["ttl"]} ]] && [[ "${STATUS_CACHE["refreshing"]}" == "true" ]]; then
        echo -e "  ${YELLOW}⟳ Refreshing...${NC}"
    fi
}
```

### Testing Requirements

**Performance Tests:**
```bash
test_menu_load_under_200ms_with_50_configs()
test_cached_status_query_under_50ms()
test_background_refresh_non_blocking()
```

**Functional Tests:**
```bash
test_cache_ttl_expiration()
test_manual_refresh_works()
test_cache_survives_menu_navigation()
test_stale_cache_display_while_refreshing()
```

### Rollback Strategy

Cache is transparent - if it fails, falls back to synchronous status generation. Performance degrades but functionality preserved.

---

## Story 3.2: Search & Filter Interface

**Story ID:** MOONFRP-E03-S02  
**Priority:** P1  
**Effort:** 1.5 days

### Problem Statement

Finding specific tunnels in a list of 50 is time-consuming. DevOps engineers need instant search by name, IP, port, tag, or status.

### Acceptance Criteria

1. Search configs by: name, server IP, port, tag, status
2. Results in <50ms from index
3. Interactive filter builder
4. Save common filters as presets
5. Operations on search results (bulk restart filtered services)
6. Fuzzy matching for name search

### Technical Specification

**Location:** New `moonfrp-search.sh`

**Implementation:**
```bash
# Search configs
search_configs() {
    local query="$1"
    local search_type="${2:-auto}"  # auto|name|ip|port|tag|status
    local db_path="$HOME/.moonfrp/index.db"
    
    case "$search_type" in
        auto)
            # Smart search - try all fields
            search_configs_auto "$query"
            ;;
        name)
            # Fuzzy name search
            sqlite3 -separator '|' "$db_path" \
                "SELECT file_path, config_type, server_addr, proxy_count 
                 FROM config_index 
                 WHERE file_path LIKE '%$query%'"
            ;;
        ip)
            sqlite3 -separator '|' "$db_path" \
                "SELECT file_path, config_type, server_addr, proxy_count 
                 FROM config_index 
                 WHERE server_addr='$query' OR bind_port='$query'"
            ;;
        port)
            sqlite3 -separator '|' "$db_path" \
                "SELECT file_path, config_type, server_addr, proxy_count 
                 FROM config_index 
                 WHERE server_port=$query OR bind_port=$query"
            ;;
        tag)
            # Already have this from Epic 2
            query_configs_by_tag "$query"
            ;;
    esac
}

# Auto-detect search intent
search_configs_auto() {
    local query="$1"
    local db_path="$HOME/.moonfrp/index.db"
    
    # Try IP pattern
    if [[ "$query" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        search_configs "$query" "ip"
        return
    fi
    
    # Try port pattern
    if [[ "$query" =~ ^[0-9]+$ ]] && [[ $query -ge 1 ]] && [[ $query -le 65535 ]]; then
        search_configs "$query" "port"
        return
    fi
    
    # Try tag pattern (key:value)
    if [[ "$query" == *:* ]]; then
        search_configs "$query" "tag"
        return
    fi
    
    # Default: name search
    search_configs "$query" "name"
}

# Interactive search menu
search_filter_menu() {
    while true; do
        clear
        show_header "Search & Filter" "Find Configs Quickly"
        
        echo -e "${CYAN}Search Options:${NC}"
        echo "1. Quick Search (auto-detect)"
        echo "2. Search by Name"
        echo "3. Search by IP Address"
        echo "4. Search by Port"
        echo "5. Search by Tag"
        echo "6. Filter by Status"
        echo "7. Advanced Filter Builder"
        echo "8. Saved Filters"
        echo "0. Back"
        echo
        
        safe_read "Choice" "choice" "0"
        
        case "$choice" in
            1) quick_search_interactive ;;
            2) search_by_name_interactive ;;
            3) search_by_ip_interactive ;;
            4) search_by_port_interactive ;;
            5) search_by_tag_interactive ;;
            6) filter_by_status_interactive ;;
            7) advanced_filter_builder ;;
            8) saved_filters_menu ;;
            0) return ;;
        esac
    done
}

# Quick search
quick_search_interactive() {
    clear
    show_header "Quick Search" "Auto-detect search type"
    
    safe_read "Search query (name, IP, port, or tag:value)" "query" ""
    
    if [[ -z "$query" ]]; then
        return
    fi
    
    echo
    echo -e "${CYAN}Searching...${NC}"
    
    local results=($(search_configs "$query" "auto"))
    
    if [[ ${#results[@]} -eq 0 ]]; then
        log "WARN" "No results found for: $query"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${GREEN}Found ${#results[@]} result(s):${NC}"
    echo
    
    local i=1
    for result in "${results[@]}"; do
        IFS='|' read -ra fields <<< "$result"
        echo "$i) $(basename "${fields[0]}")"
        echo "   Type: ${fields[1]}, Server: ${fields[2]}, Proxies: ${fields[3]}"
        ((i++))
    done
    echo
    
    echo -e "${CYAN}Operations on results:${NC}"
    echo "1. View config"
    echo "2. Edit config"
    echo "3. Restart service(s)"
    echo "4. View service status"
    echo "0. Back"
    echo
    
    safe_read "Choice" "op_choice" "0"
    
    case "$op_choice" in
        1|2|3|4)
            # Perform operation on all results
            for result in "${results[@]}"; do
                IFS='|' read -ra fields <<< "$result"
                local config_file="${fields[0]}"
                
                case "$op_choice" in
                    1) view_and_edit_file "$config_file" "config" ;;
                    2) edit_config_file "$config_file" ;;
                    3) 
                        local service_name="moonfrp-$(basename "$config_file" .toml)"
                        systemctl restart "$service_name"
                        log "INFO" "Restarted: $service_name"
                        ;;
                    4)
                        local service_name="moonfrp-$(basename "$config_file" .toml)"
                        systemctl status "$service_name" --no-pager
                        ;;
                esac
            done
            read -p "Press Enter to continue..."
            ;;
    esac
}

# Advanced filter builder
advanced_filter_builder() {
    declare -A filters
    
    while true; do
        clear
        show_header "Advanced Filter Builder" "Combine multiple criteria"
        
        echo -e "${CYAN}Current Filters:${NC}"
        if [[ ${#filters[@]} -eq 0 ]]; then
            echo "  (none)"
        else
            for key in "${!filters[@]}"; do
                echo "  $key = ${filters[$key]}"
            done
        fi
        echo
        
        echo -e "${CYAN}Options:${NC}"
        echo "1. Add filter"
        echo "2. Remove filter"
        echo "3. Apply filters (show results)"
        echo "4. Save filter preset"
        echo "0. Back"
        echo
        
        safe_read "Choice" "choice" "0"
        
        case "$choice" in
            1) add_filter_interactive filters ;;
            2) remove_filter_interactive filters ;;
            3) apply_filters "${filters[@]}" ;;
            4) save_filter_preset "${filters[@]}" ;;
            0) return ;;
        esac
    done
}

# Filter presets
save_filter_preset() {
    local preset_name="$1"
    shift
    local -n filters_ref=$1
    
    local preset_file="$HOME/.moonfrp/filter_presets.json"
    
    # Convert filters to JSON (requires jq)
    if command -v jq &>/dev/null; then
        # Append to presets file
        jq -n --arg name "$preset_name" --argjson filters "$(declare -p filters_ref | sed 's/declare -A //')" \
            '{name: $name, filters: $filters}' >> "$preset_file"
        
        log "INFO" "Filter preset saved: $preset_name"
    else
        log "WARN" "jq not available. Cannot save presets."
    fi
}

load_filter_preset() {
    local preset_name="$1"
    local preset_file="$HOME/.moonfrp/filter_presets.json"
    
    if [[ ! -f "$preset_file" ]]; then
        log "WARN" "No saved presets found"
        return 1
    fi
    
    # Load preset (requires jq)
    if command -v jq &>/dev/null; then
        jq -r ".[] | select(.name==\"$preset_name\") | .filters" "$preset_file"
    else
        log "WARN" "jq not available. Cannot load presets."
        return 1
    fi
}
```

### Testing Requirements

```bash
test_search_by_name_under_50ms()
test_search_by_ip()
test_search_by_port()
test_search_by_tag()
test_fuzzy_name_matching()
test_operations_on_search_results()
test_save_load_filter_presets()
```

### Rollback Strategy

Search is read-only - no rollback needed. Falls back to manual config browsing if search fails.

---

## Story 3.3: Enhanced Config Details View

**Story ID:** MOONFRP-E03-S03  
**Priority:** P1  
**Effort:** 1 day

### Problem Statement

DevOps teams need to quickly share config information (server IPs, ports, tokens) with team members. Current display requires manual extraction from files.

### Acceptance Criteria

1. One-screen summary of all configs
2. Copy-paste ready format for sharing
3. Grouped by server IP for clarity
4. Shows: server IPs, ports, token (masked), proxy count
5. Quick connection test indicator
6. Export to text/JSON/YAML

### Technical Specification

**Location:** `moonfrp-ui.sh` - Enhanced `show_config_details()`

**Implementation:**
```bash
show_config_details() {
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║$(printf "%63s" "MoonFRP Configuration Summary")║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Query index for all configs
    local db_path="$HOME/.moonfrp/index.db"
    local configs=($(sqlite3 "$db_path" "SELECT file_path FROM config_index ORDER BY config_type, server_addr"))
    
    # Group by server IP
    declare -A server_groups
    
    for config in "${configs[@]}"; do
        local server_addr=$(sqlite3 "$db_path" \
            "SELECT server_addr FROM config_index WHERE file_path='$config'" 2>/dev/null)
        
        if [[ -z "$server_addr" ]]; then
            server_addr="server"
        fi
        
        server_groups["$server_addr"]+="$config "
    done
    
    # Display grouped configs
    for server_ip in "${!server_groups[@]}"; do
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}🖥️  Server: $server_ip${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local configs_for_server=(${server_groups[$server_ip]})
        
        for config in "${configs_for_server[@]}"; do
            display_config_summary "$config"
        done
        
        echo
    done
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📊 Overall Statistics${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local total_configs=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index")
    local total_proxies=$(sqlite3 "$db_path" "SELECT SUM(proxy_count) FROM config_index")
    local unique_servers=$(sqlite3 "$db_path" "SELECT COUNT(DISTINCT server_addr) FROM config_index")
    
    echo "  Total Configs: $total_configs"
    echo "  Total Proxies: $total_proxies"
    echo "  Unique Servers: $unique_servers"
    echo
    
    echo -e "${CYAN}Options:${NC}"
    echo "1. Export to text file"
    echo "2. Export to JSON"
    echo "3. Run connection tests"
    echo "0. Back"
    echo
    
    safe_read "Choice" "choice" "0"
    
    case "$choice" in
        1) export_config_summary "text" ;;
        2) export_config_summary "json" ;;
        3) run_connection_tests_all ;;
        0) return ;;
    esac
}

display_config_summary() {
    local config="$1"
    local db_path="$HOME/.moonfrp/index.db"
    
    local config_type=$(sqlite3 "$db_path" "SELECT config_type FROM config_index WHERE file_path='$config'")
    local server_addr=$(sqlite3 "$db_path" "SELECT server_addr FROM config_index WHERE file_path='$config'")
    local server_port=$(sqlite3 "$db_path" "SELECT server_port FROM config_index WHERE file_path='$config'")
    local bind_port=$(sqlite3 "$db_path" "SELECT bind_port FROM config_index WHERE file_path='$config'")
    local proxy_count=$(sqlite3 "$db_path" "SELECT proxy_count FROM config_index WHERE file_path='$config'")
    local auth_token=$(get_toml_value "$config" "auth.token" 2>/dev/null | sed 's/["'\'']//g')
    
    local config_name=$(basename "$config" .toml)
    local service_status=$(systemctl is-active "moonfrp-$config_name" 2>/dev/null || echo "inactive")
    
    local status_icon
    case "$service_status" in
        active) status_icon="${GREEN}●${NC}" ;;
        failed) status_icon="${RED}●${NC}" ;;
        *) status_icon="${GRAY}○${NC}" ;;
    esac
    
    echo "  $status_icon $config_name"
    echo "     Type: $config_type"
    
    if [[ "$config_type" == "client" ]]; then
        echo "     Server: $server_addr:$server_port"
        echo "     Proxies: $proxy_count"
    else
        echo "     Bind Port: $bind_port"
    fi
    
    if [[ -n "$auth_token" ]]; then
        echo "     Token: ${auth_token:0:8}...${auth_token: -4}"
    fi
    
    # Tags
    local tags=$(list_config_tags "$config" 2>/dev/null)
    if [[ -n "$tags" ]]; then
        echo "     Tags: $tags"
    fi
}

export_config_summary() {
    local format="$1"
    local output_file="$HOME/.moonfrp/config-summary.${format}"
    
    case "$format" in
        text)
            show_config_details > "$output_file"
            ;;
        json)
            # Generate JSON summary
            local db_path="$HOME/.moonfrp/index.db"
            sqlite3 "$db_path" -json \
                "SELECT * FROM config_index" > "$output_file"
            ;;
    esac
    
    log "INFO" "Config summary exported: $output_file"
    read -p "Press Enter to continue..."
}
```

### Testing Requirements

```bash
test_config_details_grouped_by_server()
test_config_details_display_all_fields()
test_export_to_text()
test_export_to_json()
test_copy_paste_format()
```

### Rollback Strategy

Pure display function - no state changes, no rollback needed.

---

## Story 3.4: Async Connection Testing

**Story ID:** MOONFRP-E03-S04  
**Priority:** P1  
**Effort:** 1 day

### Problem Statement

Testing connectivity to 50 tunnel servers sequentially takes 100+ seconds (2s × 50). Parallel async testing needed for usability.

### Acceptance Criteria

1. Test 50 IPs in <5 seconds total
2. Results display as they complete (live updates)
3. Timeout per test: 1s
4. Non-blocking: can cancel anytime
5. Visual progress indicator
6. Summary: X reachable, Y unreachable

### Technical Specification

**Location:** `moonfrp-services.sh` - Async connection testing

**Implementation:**
```bash
# Parallel connection test
async_connection_test() {
    local configs=("$@")
    local max_parallel=20
    local timeout=1
    
    declare -A pids
    declare -A results
    
    local tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT
    
    echo -e "${CYAN}Testing connectivity to ${#configs[@]} servers...${NC}"
    echo
    
    # Start all tests in parallel
    local i=0
    for config in "${configs[@]}"; do
        # Wait if max parallel reached
        while [[ ${#pids[@]} -ge $max_parallel ]]; do
            check_completed_tests pids results "$tmp_dir"
            sleep 0.05
        done
        
        local server_addr=$(sqlite3 "$db_path" \
            "SELECT server_addr FROM config_index WHERE file_path='$config'")
        local server_port=$(sqlite3 "$db_path" \
            "SELECT server_port FROM config_index WHERE file_path='$config'")
        
        # Skip if no server info
        [[ -z "$server_addr" || -z "$server_port" ]] && continue
        
        # Start test in background
        (
            if timeout $timeout bash -c "echo > /dev/tcp/$server_addr/$server_port" 2>/dev/null; then
                echo "OK" > "$tmp_dir/$i.result"
            else
                echo "FAIL" > "$tmp_dir/$i.result"
            fi
        ) &
        
        pids[$i]=$!
        results[$i]="$server_addr:$server_port PENDING"
        
        ((i++))
    done
    
    # Wait for remaining tests
    while [[ ${#pids[@]} -gt 0 ]]; do
        check_completed_tests pids results "$tmp_dir"
        sleep 0.1
    done
    
    # Summary
    local success_count=0
    local fail_count=0
    
    for key in "${!results[@]}"; do
        if [[ "${results[$key]}" == *"OK"* ]]; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Reachable: $success_count${NC} | ${RED}✗ Unreachable: $fail_count${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

check_completed_tests() {
    local -n pids_ref=$1
    local -n results_ref=$2
    local tmp_dir="$3"
    
    for i in "${!pids_ref[@]}"; do
        local pid="${pids_ref[$i]}"
        
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null
            
            # Read result
            local result_file="$tmp_dir/$i.result"
            if [[ -f "$result_file" ]]; then
                local result=$(cat "$result_file")
                local server_info=$(echo "${results_ref[$i]}" | awk '{print $1}')
                
                if [[ "$result" == "OK" ]]; then
                    results_ref[$i]="$server_info ${GREEN}✓ OK${NC}"
                    echo -e "  $server_info ${GREEN}✓ OK${NC}"
                else
                    results_ref[$i]="$server_info ${RED}✗ FAIL${NC}"
                    echo -e "  $server_info ${RED}✗ FAIL${NC}"
                fi
            fi
            
            unset 'pids_ref[$i]'
        fi
    done
}

# User-facing function
run_connection_tests_all() {
    local db_path="$HOME/.moonfrp/index.db"
    local configs=($(sqlite3 "$db_path" \
        "SELECT file_path FROM config_index WHERE config_type='client'"))
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        log "WARN" "No client configs found"
        return
    fi
    
    clear
    show_header "Connection Tests" "Testing tunnel connectivity"
    
    async_connection_test "${configs[@]}"
    
    echo
    read -p "Press Enter to continue..."
}
```

### Testing Requirements

```bash
test_async_connection_test_50_servers_under_5s()
test_async_connection_test_live_results()
test_async_connection_test_timeout()
test_async_connection_test_cancellation()
test_async_connection_test_summary()
```

### Rollback Strategy

Read-only testing - no rollback needed. Can be cancelled anytime without side effects.

---

## Epic-Level Acceptance

**This epic is COMPLETE when:**

1. ✅ All 4 stories implemented and tested
2. ✅ Menu loads in <200ms with 50 configs (measured)
3. ✅ Search returns results in <50ms
4. ✅ Config details copy-paste ready
5. ✅ Connection tests complete in <5s for 50 IPs
6. ✅ Zero blocking UI operations
7. ✅ Performance benchmarks pass
8. ✅ Documentation updated

---

**Status:** Ready for Implementation  
**Created:** 2025-11-02  
**Approved By:** BMad Master, Team Consensus

