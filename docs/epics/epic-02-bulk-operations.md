# Epic 2: Bulk Operations

**Epic ID:** MOONFRP-E02  
**Priority:** P0 - Blocks Productivity  
**Estimated Effort:** 5-6 days  
**Dependencies:** Epic 1 (config index)  
**Target Release:** v2.0.0-alpha.2

---

## Epic Goal

Enable efficient management of 50+ tunnels through parallel operations, service grouping, tagging system, and configuration templating - transforming serial one-at-a-time operations into batch workflows.

## Success Criteria

- ✅ Start/stop/restart 50 services in <10 seconds (current: N/A - serial only)
- ✅ Bulk config updates via tag/filter system
- ✅ Configuration templates with variable substitution
- ✅ Dry-run mode for all bulk operations
- ✅ Continue-on-error with detailed failure reporting
- ✅ Zero service disruption from bulk operations

---

## Story 2.1: Parallel Service Management

**Story ID:** MOONFRP-E02-S01  
**Priority:** P0  
**Effort:** 2 days

### Problem Statement

Managing 50 services one-at-a-time is unusable. DevOps engineers need parallel start/stop/restart operations that complete in seconds, not minutes.

### Acceptance Criteria

1. Parallel execution of systemctl operations across all services
2. Complete 50 service restarts in <10 seconds
3. Progress indicator during bulk operations
4. Continue-on-error: report failures, don't abort
5. Final summary: X succeeded, Y failed with reasons
6. Configurable parallelism: default max 10 concurrent operations

### Technical Specification

**Location:** `moonfrp-services.sh` - New bulk operation functions

**Implementation:**
```bash
# Parallel service operation framework
bulk_service_operation() {
    local operation="$1"  # start|stop|restart|reload
    shift
    local services=("$@")
    
    local max_parallel=10
    local success_count=0
    local fail_count=0
    local total=${#services[@]}
    
    declare -a failed_services
    declare -a pids
    
    log "INFO" "Starting bulk $operation on $total services (max $max_parallel parallel)"
    
    # Create temp directory for results
    local tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT
    
    local i=0
    for service in "${services[@]}"; do
        # Wait if we hit max parallel
        while [[ ${#pids[@]} -ge $max_parallel ]]; do
            # Check for completed jobs
            for j in "${!pids[@]}"; do
                if ! kill -0 "${pids[$j]}" 2>/dev/null; then
                    wait "${pids[$j]}"
                    local exit_code=$?
                    
                    if [[ $exit_code -eq 0 ]]; then
                        ((success_count++))
                    else
                        ((fail_count++))
                        failed_services+=("${services[$j]}")
                    fi
                    
                    unset 'pids[$j]'
                fi
            done
            pids=("${pids[@]}")  # Reindex array
            sleep 0.1
        done
        
        # Start operation in background
        (
            systemctl "$operation" "$service" &>"$tmp_dir/$service.log"
            exit $?
        ) &
        pids[$i]=$!
        
        # Progress indicator
        echo -ne "\rProgress: $((i+1))/$total services..."
        
        ((i++))
    done
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    echo  # Newline after progress
    
    # Report results
    log "INFO" "Bulk $operation complete: $success_count succeeded, $fail_count failed"
    
    if [[ $fail_count -gt 0 ]]; then
        log "WARN" "Failed services:"
        for failed_svc in "${failed_services[@]}"; do
            echo "  - $failed_svc"
            if [[ -f "$tmp_dir/$failed_svc.log" ]]; then
                echo "    $(tail -1 "$tmp_dir/$failed_svc.log")"
            fi
        done
    fi
    
    return $fail_count
}

# User-facing functions
bulk_start_services() {
    local services=($(get_moonfrp_services))
    bulk_service_operation "start" "${services[@]}"
}

bulk_stop_services() {
    local services=($(get_moonfrp_services))
    bulk_service_operation "stop" "${services[@]}"
}

bulk_restart_services() {
    local services=($(get_moonfrp_services))
    bulk_service_operation "restart" "${services[@]}"
}

bulk_reload_services() {
    local services=($(get_moonfrp_services))
    bulk_service_operation "reload" "${services[@]}"
}

# Get all MoonFRP services
get_moonfrp_services() {
    systemctl list-units --type=service --all --no-pager --no-legend \
        | grep -E "moonfrp-(server|client)" \
        | awk '{print $1}' \
        | sed 's/.service$//'
}

# Filtered bulk operations (for Story 2.3 - tags)
bulk_operation_filtered() {
    local operation="$1"
    local filter_type="$2"  # tag|status|name
    local filter_value="$3"
    
    local services=()
    
    case "$filter_type" in
        tag)
            services=($(get_services_by_tag "$filter_value"))
            ;;
        status)
            services=($(get_services_by_status "$filter_value"))
            ;;
        name)
            services=($(get_moonfrp_services | grep "$filter_value"))
            ;;
        *)
            log "ERROR" "Unknown filter type: $filter_type"
            return 1
            ;;
    esac
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log "WARN" "No services match filter: $filter_type=$filter_value"
        return 0
    fi
    
    log "INFO" "Found ${#services[@]} services matching filter"
    bulk_service_operation "$operation" "${services[@]}"
}
```

**CLI Integration:**
```bash
# moonfrp service bulk --operation=restart
# moonfrp service bulk --operation=start --filter=tag:prod
# moonfrp service bulk --operation=stop --dry-run
```

### Testing Requirements

**Performance Tests:**
```bash
test_bulk_restart_50_services_under_10s()
test_bulk_start_parallel_execution()
test_max_parallelism_respected()
```

**Functional Tests:**
```bash
test_bulk_operation_continue_on_error()
test_bulk_operation_failure_reporting()
test_bulk_operation_progress_indicator()
test_bulk_operation_empty_service_list()
```

**Load Tests:**
- 50 services: restart, measure time
- 10 failed services: verify error handling
- Concurrent bulk operations: verify no race conditions

### Rollback Strategy

Bulk operations are stateless. If operation fails:
1. Services remain in current state
2. Retry failed subset with: `--retry-failed`
3. Manual intervention for specific failures

---

## Story 2.2: Bulk Configuration Operations

**Story ID:** MOONFRP-E02-S02  
**Priority:** P0  
**Effort:** 1.5 days

### Problem Statement

Updating auth tokens, server IPs, or ports across 50 configs manually is error-prone and time-consuming. Need bulk update capabilities with validation and dry-run.

### Acceptance Criteria

1. Update single field across multiple configs: `bulk-update --field=auth.token --value=NEW_TOKEN --filter=all`
2. Update multiple fields with JSON/YAML input
3. Dry-run mode shows changes without applying
4. Validates each config before saving
5. Atomic operation: all succeed or all rollback
6. Backup before bulk changes
7. Performance: <5s for 50 configs

### Technical Specification

**Location:** `moonfrp-config.sh` - Bulk configuration functions

**Implementation:**
```bash
bulk_update_config_field() {
    local field="$1"
    local value="$2"
    local filter="${3:-all}"  # all|tag:X|type:client|server
    local dry_run="${4:-false}"
    
    # Get matching configs
    local configs=($(get_configs_by_filter "$filter"))
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        log "WARN" "No configs match filter: $filter"
        return 0
    fi
    
    log "INFO" "Bulk update: $field = $value"
    log "INFO" "Matching configs: ${#configs[@]}"
    
    # Dry-run: show changes
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY-RUN MODE - No changes will be applied${NC}"
        echo
        for config in "${configs[@]}"; do
            local old_value=$(get_toml_value "$config" "$field" 2>/dev/null || echo "(not set)")
            echo "  $(basename "$config"): $old_value → $value"
        done
        return 0
    fi
    
    # Real update with transaction-like behavior
    local temp_files=()
    local success=true
    
    # Phase 1: Update all to temp files & validate
    for config in "${configs[@]}"; do
        local temp_file="${config}.bulk-update.tmp"
        
        # Read, update, write to temp
        if ! update_toml_field "$config" "$field" "$value" "$temp_file"; then
            log "ERROR" "Failed to update: $config"
            success=false
            break
        fi
        
        # Validate temp file
        if ! validate_config_file "$temp_file"; then
            log "ERROR" "Validation failed: $config"
            success=false
            break
        fi
        
        temp_files+=("$temp_file")
    done
    
    # Phase 2: If all succeeded, commit; else rollback
    if [[ "$success" == "true" ]]; then
        log "INFO" "All validations passed. Committing changes..."
        
        for i in "${!configs[@]}"; do
            local config="${configs[$i]}"
            local temp_file="${temp_files[$i]}"
            
            # Backup original
            backup_config_file "$config"
            
            # Atomic move
            mv "$temp_file" "$config"
            
            # Update index
            index_config_file "$config"
        done
        
        log "INFO" "Bulk update complete: ${#configs[@]} configs updated"
        return 0
    else
        log "ERROR" "Bulk update failed. Rolling back..."
        
        # Remove temp files
        for temp_file in "${temp_files[@]}"; do
            rm -f "$temp_file"
        done
        
        return 1
    fi
}

# Update TOML field (helper function)
update_toml_field() {
    local input_file="$1"
    local field="$2"
    local value="$3"
    local output_file="$4"
    
    # Parse field path (e.g., "auth.token" → auth section, token key)
    local section=""
    local key="$field"
    
    if [[ "$field" == *.* ]]; then
        section="${field%.*}"
        key="${field##*.}"
    fi
    
    # Use awk/sed to update field
    if [[ -n "$section" ]]; then
        # Nested field (e.g., auth.token)
        awk -v section="$section" -v key="$key" -v value="$value" '
        BEGIN { in_section=0 }
        /^\[/ { in_section=0 }
        $0 ~ "^\\[" section "\\]" { in_section=1; print; next }
        in_section && $1 == key {
            print key " = \"" value "\""
            next
        }
        { print }
        ' "$input_file" > "$output_file"
    else
        # Top-level field
        awk -v key="$key" -v value="$value" '
        $1 == key {
            print key " = \"" value "\""
            next
        }
        { print }
        ' "$input_file" > "$output_file"
    fi
    
    return 0
}

# Filter configs by various criteria
get_configs_by_filter() {
    local filter="$1"
    
    case "$filter" in
        all)
            find "$CONFIG_DIR" -name "*.toml" -type f
            ;;
        type:server)
            echo "$CONFIG_DIR/frps.toml"
            ;;
        type:client)
            find "$CONFIG_DIR" -name "frpc*.toml" -type f
            ;;
        tag:*)
            local tag="${filter#tag:}"
            query_configs_by_tag "$tag"
            ;;
        name:*)
            local pattern="${filter#name:}"
            find "$CONFIG_DIR" -name "*${pattern}*.toml" -type f
            ;;
        *)
            log "ERROR" "Unknown filter: $filter"
            return 1
            ;;
    esac
}

# Bulk update from JSON/YAML file
bulk_update_from_file() {
    local update_file="$1"
    local dry_run="${2:-false}"
    
    # Parse update file (assume JSON format)
    # Example: {"field": "auth.token", "value": "NEW_TOKEN", "filter": "all"}
    
    if command -v jq &>/dev/null; then
        local field=$(jq -r '.field' "$update_file")
        local value=$(jq -r '.value' "$update_file")
        local filter=$(jq -r '.filter // "all"' "$update_file")
        
        bulk_update_config_field "$field" "$value" "$filter" "$dry_run"
    else
        log "ERROR" "jq not found. Cannot parse update file."
        return 1
    fi
}
```

**CLI Integration:**
```bash
# Update single field
moonfrp config bulk-update --field=auth.token --value=NEW_TOKEN --filter=all --dry-run

# Update from file
moonfrp config bulk-update --file=updates.json --dry-run
moonfrp config bulk-update --file=updates.json  # apply
```

### Testing Requirements

```bash
test_bulk_update_single_field_dry_run()
test_bulk_update_single_field_apply()
test_bulk_update_validation_failure_rollback()
test_bulk_update_atomic_transaction()
test_bulk_update_50_configs_under_5s()
test_bulk_update_backup_before_change()
test_bulk_update_filter_by_type()
test_bulk_update_filter_by_tag()
```

### Rollback Strategy

1. All changes in single transaction
2. Validation failure: automatic rollback (temp files deleted)
3. After commit: restore from automatic backups
4. CLI: `moonfrp config restore-all --from-backup=TIMESTAMP`

---

## Story 2.3: Service Grouping & Tagging

**Story ID:** MOONFRP-E02-S03  
**Priority:** P0  
**Effort:** 1.5 days

### Problem Statement

50 tunnels need logical organization: by environment (prod/staging), region (eu/us), customer, or service type. Tagging enables filtered operations.

### Acceptance Criteria

1. Tag services with key-value pairs: `env:prod`, `region:eu`, `customer:acme`
2. Multiple tags per service
3. Tags stored in config index (fast queries)
4. Operations by tag: `restart --tag=env:prod`
5. List/filter services by tags
6. Tag inheritance from config templates
7. Tag management: add, remove, list

### Technical Specification

**Location:** `moonfrp-index.sh` and `moonfrp-services.sh`

**Database Schema Update:**
```sql
-- Already in Epic 1, but utilized here
CREATE TABLE IF NOT EXISTS service_tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    config_id INTEGER NOT NULL,
    tag_key TEXT NOT NULL,
    tag_value TEXT NOT NULL,
    FOREIGN KEY (config_id) REFERENCES config_index(id) ON DELETE CASCADE,
    UNIQUE(config_id, tag_key)
);

CREATE INDEX IF NOT EXISTS idx_tag_key ON service_tags(tag_key);
CREATE INDEX IF NOT EXISTS idx_tag_value ON service_tags(tag_value);
CREATE INDEX IF NOT EXISTS idx_tag_key_value ON service_tags(tag_key, tag_value);
```

**Implementation:**
```bash
# Add tag to config
add_config_tag() {
    local config_file="$1"
    local tag_key="$2"
    local tag_value="$3"
    local db_path="$HOME/.moonfrp/index.db"
    
    # Get config_id
    local config_id=$(sqlite3 "$db_path" "SELECT id FROM config_index WHERE file_path='$config_file'")
    
    if [[ -z "$config_id" ]]; then
        log "ERROR" "Config not found in index: $config_file"
        return 1
    fi
    
    # Insert or update tag
    sqlite3 "$db_path" <<SQL
INSERT OR REPLACE INTO service_tags (config_id, tag_key, tag_value)
VALUES ($config_id, '$tag_key', '$tag_value');
SQL
    
    log "INFO" "Tag added: $config_file → $tag_key:$tag_value"
}

# Remove tag from config
remove_config_tag() {
    local config_file="$1"
    local tag_key="$2"
    local db_path="$HOME/.moonfrp/index.db"
    
    local config_id=$(sqlite3 "$db_path" "SELECT id FROM config_index WHERE file_path='$config_file'")
    
    sqlite3 "$db_path" "DELETE FROM service_tags WHERE config_id=$config_id AND tag_key='$tag_key'"
    
    log "INFO" "Tag removed: $config_file → $tag_key"
}

# List tags for config
list_config_tags() {
    local config_file="$1"
    local db_path="$HOME/.moonfrp/index.db"
    
    local config_id=$(sqlite3 "$db_path" "SELECT id FROM config_index WHERE file_path='$config_file'")
    
    sqlite3 -separator ':' "$db_path" \
        "SELECT tag_key, tag_value FROM service_tags WHERE config_id=$config_id"
}

# Query configs by tag
query_configs_by_tag() {
    local tag="$1"  # Format: "key:value" or just "key"
    local db_path="$HOME/.moonfrp/index.db"
    
    if [[ "$tag" == *:* ]]; then
        local tag_key="${tag%:*}"
        local tag_value="${tag#*:}"
        
        sqlite3 "$db_path" <<SQL
SELECT ci.file_path FROM config_index ci
JOIN service_tags st ON ci.id = st.config_id
WHERE st.tag_key='$tag_key' AND st.tag_value='$tag_value';
SQL
    else
        # Just key, any value
        sqlite3 "$db_path" <<SQL
SELECT ci.file_path FROM config_index ci
JOIN service_tags st ON ci.id = st.config_id
WHERE st.tag_key='$tag';
SQL
    fi
}

# Get services by tag (for filtered operations)
get_services_by_tag() {
    local tag="$1"
    
    local configs=($(query_configs_by_tag "$tag"))
    
    for config in "${configs[@]}"; do
        # Convert config path to service name
        local basename=$(basename "$config" .toml)
        echo "moonfrp-${basename}"
    done
}

# Bulk tag assignment
bulk_tag_configs() {
    local tag_key="$1"
    local tag_value="$2"
    local filter="$3"
    
    local configs=($(get_configs_by_filter "$filter"))
    
    log "INFO" "Bulk tagging: $tag_key:$tag_value on ${#configs[@]} configs"
    
    for config in "${configs[@]}"; do
        add_config_tag "$config" "$tag_key" "$tag_value"
    done
}

# Interactive tag management menu
tag_management_menu() {
    while true; do
        clear
        show_header "Tag Management" "Organize Services with Tags"
        
        echo -e "${CYAN}Options:${NC}"
        echo "1. Add tag to config"
        echo "2. Remove tag from config"
        echo "3. List tags for config"
        echo "4. Bulk tag configs"
        echo "5. List all tags"
        echo "6. Operations by tag"
        echo "0. Back"
        echo
        
        safe_read "Choice" "choice" "0"
        
        case "$choice" in
            1) add_tag_interactive ;;
            2) remove_tag_interactive ;;
            3) list_tags_interactive ;;
            4) bulk_tag_interactive ;;
            5) list_all_tags ;;
            6) operations_by_tag_menu ;;
            0) return ;;
        esac
    done
}
```

**CLI Integration:**
```bash
# Tag management
moonfrp tag add frpc-eu-1.toml env prod
moonfrp tag add frpc-eu-1.toml region eu
moonfrp tag remove frpc-eu-1.toml region
moonfrp tag list frpc-eu-1.toml

# Bulk tagging
moonfrp tag bulk --key=env --value=prod --filter=name:frpc-eu

# Operations by tag
moonfrp service restart --tag=env:prod
moonfrp service stop --tag=region:us
moonfrp service status --tag=customer:acme
```

### Testing Requirements

```bash
test_add_tag_to_config()
test_remove_tag_from_config()
test_query_configs_by_tag()
test_bulk_tag_assignment()
test_filtered_operations_by_tag()
test_multiple_tags_per_config()
test_tag_persistence_in_index()
```

### Rollback Strategy

Tags stored in database - can be easily removed or modified. No service impact from tagging operations.

---

## Story 2.4: Configuration Templates

**Story ID:** MOONFRP-E02-S04  
**Priority:** P1  
**Effort:** 1.5 days

### Problem Statement

Creating 50 similar configs manually is tedious and error-prone. Templates with variables enable rapid, consistent deployment of tunnel configs.

### Acceptance Criteria

1. Create template with variables: `${SERVER_IP}`, `${REGION}`, `${PORT}`
2. Instantiate template with variable values
3. Bulk instantiation: CSV with variable values
4. Templates stored in `~/.moonfrp/templates/`
5. Validate template before instantiation
6. Auto-tag from template metadata
7. Template versioning

### Technical Specification

**Location:** New file `moonfrp-templates.sh`

**Template Format:**
```toml
# Template: client-base.toml.tmpl
# Variables: SERVER_IP, SERVER_PORT, REGION, PROXY_NAME, LOCAL_PORT
# Tags: env:prod, type:client

serverAddr = "${SERVER_IP}"
serverPort = ${SERVER_PORT}
auth.token = "${AUTH_TOKEN}"

user = "moonfrp-${REGION}"

[[proxies]]
name = "${PROXY_NAME}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${LOCAL_PORT}
remotePort = ${REMOTE_PORT}
```

**Implementation:**
```bash
TEMPLATE_DIR="$HOME/.moonfrp/templates"

# Create template
create_template() {
    local template_name="$1"
    local template_content="$2"
    
    mkdir -p "$TEMPLATE_DIR"
    
    local template_file="$TEMPLATE_DIR/${template_name}.toml.tmpl"
    
    echo "$template_content" > "$template_file"
    
    log "INFO" "Template created: $template_file"
}

# List templates
list_templates() {
    find "$TEMPLATE_DIR" -name "*.toml.tmpl" -type f -printf '%f\n' | sed 's/.toml.tmpl$//'
}

# Instantiate template
instantiate_template() {
    local template_name="$1"
    local output_file="$2"
    shift 2
    local variables=("$@")  # key=value pairs
    
    local template_file="$TEMPLATE_DIR/${template_name}.toml.tmpl"
    
    if [[ ! -f "$template_file" ]]; then
        log "ERROR" "Template not found: $template_name"
        return 1
    fi
    
    # Read template
    local content=$(cat "$template_file")
    
    # Extract template metadata (tags, description)
    local tags=$(grep "^# Tags:" "$template_file" | sed 's/^# Tags: //')
    
    # Substitute variables
    for var_pair in "${variables[@]}"; do
        local key="${var_pair%=*}"
        local value="${var_pair#*=}"
        
        content="${content//\$\{${key}\}/$value}"
    done
    
    # Check for unsubstituted variables
    if echo "$content" | grep -q '\${'; then
        log "WARN" "Template has unsubstituted variables:"
        echo "$content" | grep -o '\${[^}]*}' | sort -u
        
        safe_read "Continue anyway? (y/N)" "confirm" "n"
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 1
    fi
    
    # Write to output file
    echo "$content" > "$output_file"
    
    # Validate
    if ! validate_config_file "$output_file"; then
        log "ERROR" "Generated config failed validation"
        rm -f "$output_file"
        return 1
    fi
    
    # Index
    index_config_file "$output_file"
    
    # Apply tags if specified
    if [[ -n "$tags" ]]; then
        IFS=',' read -ra tag_array <<< "$tags"
        for tag in "${tag_array[@]}"; do
            tag=$(echo "$tag" | xargs)  # trim whitespace
            if [[ "$tag" == *:* ]]; then
                local tag_key="${tag%:*}"
                local tag_value="${tag#*:}"
                add_config_tag "$output_file" "$tag_key" "$tag_value"
            fi
        done
    fi
    
    log "INFO" "Config created from template: $output_file"
}

# Bulk instantiation from CSV
bulk_instantiate_template() {
    local template_name="$1"
    local csv_file="$2"
    
    # CSV format: output_file,SERVER_IP,SERVER_PORT,REGION,...
    # First row is header with variable names
    
    local line_num=0
    local headers=()
    
    while IFS=',' read -ra fields; do
        if [[ $line_num -eq 0 ]]; then
            # Parse headers
            headers=("${fields[@]}")
        else
            # Process data row
            local output_file="${fields[0]}"
            local variables=()
            
            for i in $(seq 1 $((${#fields[@]}-1))); do
                local key="${headers[$i]}"
                local value="${fields[$i]}"
                variables+=("${key}=${value}")
            done
            
            instantiate_template "$template_name" "$output_file" "${variables[@]}"
        fi
        
        ((line_num++))
    done < "$csv_file"
    
    log "INFO" "Bulk instantiation complete: $((line_num-1)) configs created"
}

# Interactive template menu
template_management_menu() {
    while true; do
        clear
        show_header "Template Management" "Config Templates"
        
        echo -e "${CYAN}Templates:${NC}"
        local templates=($(list_templates))
        if [[ ${#templates[@]} -gt 0 ]]; then
            for tmpl in "${templates[@]}"; do
                echo "  - $tmpl"
            done
        else
            echo "  (no templates)"
        fi
        echo
        
        echo -e "${CYAN}Options:${NC}"
        echo "1. Create template"
        echo "2. Instantiate template"
        echo "3. Bulk instantiate from CSV"
        echo "4. View template"
        echo "5. Delete template"
        echo "0. Back"
        echo
        
        safe_read "Choice" "choice" "0"
        
        case "$choice" in
            1) create_template_interactive ;;
            2) instantiate_template_interactive ;;
            3) bulk_instantiate_interactive ;;
            4) view_template_interactive ;;
            5) delete_template_interactive ;;
            0) return ;;
        esac
    done
}
```

**Example CSV for Bulk Instantiation:**
```csv
output_file,SERVER_IP,SERVER_PORT,REGION,PROXY_NAME,LOCAL_PORT,REMOTE_PORT
frpc-eu-1.toml,192.168.1.100,7000,eu,web-eu-1,8080,30001
frpc-eu-2.toml,192.168.1.100,7000,eu,web-eu-2,8080,30002
frpc-us-1.toml,10.0.1.50,7000,us,web-us-1,8080,30003
```

### Testing Requirements

```bash
test_create_template()
test_instantiate_template_with_variables()
test_instantiate_template_missing_variable_warning()
test_bulk_instantiate_from_csv()
test_template_validation()
test_template_auto_tagging()
test_template_list()
```

### Rollback Strategy

Templates are non-destructive. Generated configs follow normal backup/validation flow from Epic 1.

---

## Epic-Level Acceptance

**This epic is COMPLETE when:**

1. ✅ All 4 stories implemented and tested
2. ✅ 50 services restart in <10 seconds (measured)
3. ✅ Bulk config updates with dry-run working
4. ✅ Tag-based filtering operational
5. ✅ Template instantiation tested with 10+ configs
6. ✅ Zero service disruption from bulk operations
7. ✅ Performance benchmarks pass
8. ✅ Documentation updated

---

## Dependencies & Blockers

**Dependencies:**
- Epic 1: Config index (critical for performance)
- Epic 1: Validation framework (for bulk updates)
- Epic 1: Backup system (for bulk operations safety)

**Potential Blockers:**
- Systemctl rate limiting with many parallel operations
- File locking conflicts during bulk config updates
- Database transaction limits in SQLite

---

## Handoff to Development

**Ready for implementation. All technical specifications complete.**

---

**Status:** Ready for Implementation  
**Created:** 2025-11-02  
**Approved By:** BMad Master, Team Consensus

