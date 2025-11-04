# Epic 1: Critical Fixes & Scale Foundation

**Epic ID:** MOONFRP-E01  
**Priority:** P0 - Must Do First  
**Estimated Effort:** 3-4 days  
**Dependencies:** None  
**Target Release:** v2.0.0-alpha.1

---

## Epic Goal

Establish the architectural and operational foundation required for managing 50+ tunnels reliably, including config indexing for performance, critical bug fixes, validation framework, and automatic backup system.

## Success Criteria

- ✅ Menu loads in <200ms with 50 configs (current: 2-3s with 10)
- ✅ FRP version displays correctly (fixes "vunknown" bug)
- ✅ Config validation prevents invalid configurations from being saved
- ✅ Automatic backup before any config modification
- ✅ Zero data loss on system crashes
- ✅ All operations measured with performance metrics

---

## Story 1.1: Fix FRP Version Detection

**Story ID:** MOONFRP-E01-S01  
**Priority:** P0  
**Effort:** 0.5 days

### Problem Statement

Current implementation shows "vunknown" for FRP version due to incorrect regex parsing of version output. This breaks compatibility checks and confuses users.

### Acceptance Criteria

1. Version detection works for FRP versions 0.52.0 through 0.65.0+
2. Displays format: "v0.65.0" (with leading 'v')
3. Falls back gracefully: "unknown" if detection fails, "not installed" if missing
4. Uses multiple detection methods (frps, frpc, version file)
5. Detection completes in <100ms

### Technical Specification

**Location:** `moonfrp-core.sh` - `get_frp_version()` function

**Implementation Approach:**
```bash
get_frp_version() {
    if ! check_frp_installation; then
        echo "not installed"
        return 1
    fi
    
    local version=""
    
    # Method 1: frps --version (primary)
    if [[ -x "$FRP_DIR/frps" ]]; then
        version=$("$FRP_DIR/frps" --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    
    # Method 2: frpc --version (fallback)
    if [[ -z "$version" && -x "$FRP_DIR/frpc" ]]; then
        version=$("$FRP_DIR/frpc" --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    
    # Method 3: Version file (if exists)
    if [[ -z "$version" && -f "$FRP_DIR/.version" ]]; then
        version=$(cat "$FRP_DIR/.version" 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+')
    fi
    
    # Ensure 'v' prefix
    if [[ -n "$version" ]]; then
        [[ "$version" =~ ^v ]] || version="v$version"
        echo "$version"
    else
        echo "unknown"
    fi
}
```

### Testing Requirements

**Unit Tests:**
```bash
test_version_detection_with_v_prefix()
test_version_detection_without_v_prefix()
test_version_detection_old_versions()
test_version_detection_missing_binary()
test_version_detection_performance()
```

**Manual Testing:**
- Install FRP 0.58.0, 0.61.0, 0.65.0
- Verify correct version display
- Remove FRP, verify "not installed"
- Corrupt binary, verify "unknown"

### Rollback Strategy

No rollback needed - pure function replacement, no state changes.

---

## Story 1.2: Implement Config Index

**Story ID:** MOONFRP-E01-S02  
**Priority:** P0  
**Effort:** 1.5 days

### Problem Statement

With 50+ config files, parsing TOML on every operation creates unacceptable performance (2-3s menu load). Need indexed metadata for fast queries.

### Acceptance Criteria

1. SQLite database indexes all config files
2. Query time for 50 configs: <50ms (vs 2000ms current)
3. Automatic rebuild on config file changes
4. Index includes: file path, server IP, port, proxy count, status, tags
5. Graceful fallback to file parsing if index corrupted
6. Index size: <1MB for 50 configs

### Technical Specification

**Location:** New file `moonfrp-index.sh`

**Database Schema:**
```sql
CREATE TABLE IF NOT EXISTS config_index (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    file_hash TEXT NOT NULL,
    config_type TEXT NOT NULL, -- 'server' or 'client'
    server_addr TEXT,
    server_port INTEGER,
    bind_port INTEGER,
    auth_token_hash TEXT,
    proxy_count INTEGER DEFAULT 0,
    tags TEXT, -- JSON array
    last_modified INTEGER,
    last_indexed INTEGER,
    UNIQUE(file_path)
);

CREATE INDEX IF NOT EXISTS idx_config_type ON config_index(config_type);
CREATE INDEX IF NOT EXISTS idx_server_addr ON config_index(server_addr);
CREATE INDEX IF NOT EXISTS idx_tags ON config_index(tags);

CREATE TABLE IF NOT EXISTS index_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);
```

**Core Functions:**
```bash
# Initialize index
init_config_index() {
    local db_path="$HOME/.moonfrp/index.db"
    mkdir -p "$(dirname "$db_path")"
    
    sqlite3 "$db_path" < "$SCRIPT_DIR/schema.sql"
    echo "$(date +%s)" | sqlite3 "$db_path" \
        "INSERT OR REPLACE INTO index_meta VALUES('created', $(cat))"
}

# Rebuild entire index
rebuild_config_index() {
    local db_path="$HOME/.moonfrp/index.db"
    
    sqlite3 "$db_path" "DELETE FROM config_index"
    
    find "$CONFIG_DIR" -name "*.toml" -type f | while read -r config_file; do
        index_config_file "$config_file"
    done
}

# Index single config file
index_config_file() {
    local config_file="$1"
    local db_path="$HOME/.moonfrp/index.db"
    
    local file_hash=$(sha256sum "$config_file" | awk '{print $1}')
    local config_type="client"
    [[ "$config_file" == *"frps.toml" ]] && config_type="server"
    
    local server_addr=$(get_toml_value "$config_file" "serverAddr" 2>/dev/null | tr -d '"')
    local server_port=$(get_toml_value "$config_file" "serverPort" 2>/dev/null | tr -d '"')
    local bind_port=$(get_toml_value "$config_file" "bindPort" 2>/dev/null | tr -d '"')
    local proxy_count=$(grep -c '^\[\[proxies\]\]' "$config_file" 2>/dev/null || echo "0")
    local last_modified=$(stat -c %Y "$config_file" 2>/dev/null || echo "0")
    
    sqlite3 "$db_path" <<SQL
INSERT OR REPLACE INTO config_index 
    (file_path, file_hash, config_type, server_addr, server_port, 
     bind_port, proxy_count, last_modified, last_indexed)
VALUES 
    ('$config_file', '$file_hash', '$config_type', '$server_addr', '$server_port',
     '$bind_port', $proxy_count, $last_modified, $(date +%s));
SQL
}

# Fast query functions
query_configs_by_type() {
    local config_type="$1"
    local db_path="$HOME/.moonfrp/index.db"
    
    sqlite3 -separator '|' "$db_path" \
        "SELECT file_path, server_addr, proxy_count FROM config_index 
         WHERE config_type='$config_type' ORDER BY file_path"
}

query_total_proxy_count() {
    local db_path="$HOME/.moonfrp/index.db"
    sqlite3 "$db_path" "SELECT SUM(proxy_count) FROM config_index"
}
```

**Auto-rebuild trigger:**
```bash
# Watch for config changes (called before operations)
check_and_update_index() {
    local db_path="$HOME/.moonfrp/index.db"
    
    [[ ! -f "$db_path" ]] && init_config_index
    
    find "$CONFIG_DIR" -name "*.toml" -type f -newer "$db_path" | while read -r changed_file; do
        index_config_file "$changed_file"
    done
}
```

### Testing Requirements

**Performance Tests:**
```bash
test_index_query_50_configs_under_50ms()
test_index_rebuild_50_configs_under_2s()
test_index_incremental_update_under_100ms()
```

**Functional Tests:**
```bash
test_index_survives_corrupted_config()
test_index_auto_rebuild_on_changes()
test_index_fallback_to_file_parsing()
test_query_by_type()
test_query_by_server_addr()
test_total_proxy_count()
```

**Load Tests:**
- Generate 100 config files
- Measure index rebuild time
- Measure query performance

### Rollback Strategy

If index causes issues:
1. Delete `~/.moonfrp/index.db`
2. System falls back to file parsing
3. Performance degrades but functionality preserved

---

## Story 1.3: Config Validation Framework

**Story ID:** MOONFRP-E01-S03  
**Priority:** P0  
**Effort:** 1 day

### Problem Statement

Invalid configs crash services and are hard to debug. Need pre-save validation with clear error messages to prevent configuration errors.

### Acceptance Criteria

1. Validates TOML syntax before saving
2. Validates required fields (serverAddr, bindPort, auth.token, etc.)
3. Validates value ranges (ports 1-65535, valid IPs)
4. Clear error messages with line numbers
5. Validation completes in <100ms
6. Prevents save if validation fails
7. Optional: Use `frps --verify-config` if available

### Technical Specification

**Location:** `moonfrp-config.sh` - New validation functions

**Implementation:**
```bash
validate_config_file() {
    local config_file="$1"
    local config_type="${2:-auto}"  # server|client|auto
    
    # Detect type if auto
    if [[ "$config_type" == "auto" ]]; then
        [[ "$config_file" == *"frps"* ]] && config_type="server" || config_type="client"
    fi
    
    local errors=()
    
    # 1. TOML syntax validation
    if ! validate_toml_syntax "$config_file"; then
        errors+=("Invalid TOML syntax")
    fi
    
    # 2. Required fields validation
    case "$config_type" in
        server)
            validate_server_config "$config_file" || errors+=("Server config validation failed")
            ;;
        client)
            validate_client_config "$config_file" || errors+=("Client config validation failed")
            ;;
    esac
    
    # 3. Report results
    if [[ ${#errors[@]} -gt 0 ]]; then
        log "ERROR" "Config validation failed: $config_file"
        printf '%s\n' "${errors[@]}"
        return 1
    fi
    
    log "INFO" "Config validation passed: $config_file"
    return 0
}

validate_toml_syntax() {
    local config_file="$1"
    
    # Method 1: Use toml validator if available
    if command -v toml-validator &>/dev/null; then
        toml-validator "$config_file" 2>&1
        return $?
    fi
    
    # Method 2: Try parsing with get_toml_value
    if ! get_toml_value "$config_file" "auth.token" &>/dev/null; then
        if ! get_toml_value "$config_file" "bindPort" &>/dev/null; then
            # Both failed - likely syntax error
            return 1
        fi
    fi
    
    return 0
}

validate_server_config() {
    local config_file="$1"
    local errors=()
    
    # Required: bindPort
    local bind_port=$(get_toml_value "$config_file" "bindPort" 2>/dev/null | tr -d '"')
    if [[ -z "$bind_port" ]]; then
        errors+=("Missing required field: bindPort")
    elif [[ ! "$bind_port" =~ ^[0-9]+$ ]] || [[ $bind_port -lt 1 ]] || [[ $bind_port -gt 65535 ]]; then
        errors+=("Invalid bindPort: must be 1-65535")
    fi
    
    # Required: auth.token
    local auth_token=$(get_toml_value "$config_file" "auth.token" 2>/dev/null | sed 's/["'\'']//g')
    if [[ -z "$auth_token" ]]; then
        errors+=("Missing required field: auth.token")
    elif [[ ${#auth_token} -lt 8 ]]; then
        errors+=("auth.token too short: minimum 8 characters")
    fi
    
    # Report
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}" >&2
        return 1
    fi
    return 0
}

validate_client_config() {
    local config_file="$1"
    local errors=()
    
    # Required: serverAddr
    local server_addr=$(get_toml_value "$config_file" "serverAddr" 2>/dev/null | sed 's/["'\'']//g')
    if [[ -z "$server_addr" ]]; then
        errors+=("Missing required field: serverAddr")
    fi
    
    # Required: serverPort
    local server_port=$(get_toml_value "$config_file" "serverPort" 2>/dev/null | tr -d '"')
    if [[ -z "$server_port" ]]; then
        errors+=("Missing required field: serverPort")
    elif [[ ! "$server_port" =~ ^[0-9]+$ ]] || [[ $server_port -lt 1 ]] || [[ $server_port -gt 65535 ]]; then
        errors+=("Invalid serverPort: must be 1-65535")
    fi
    
    # Required: auth.token
    local auth_token=$(get_toml_value "$config_file" "auth.token" 2>/dev/null | sed 's/["'\'']//g')
    if [[ -z "$auth_token" ]]; then
        errors+=("Missing required field: auth.token")
    fi
    
    # Check for at least one proxy
    local proxy_count=$(grep -c '^\[\[proxies\]\]' "$config_file" 2>/dev/null || echo "0")
    if [[ $proxy_count -eq 0 ]]; then
        errors+=("Warning: No proxies defined")
    fi
    
    # Report
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf '%s\n' "${errors[@]}" >&2
        return 1
    fi
    return 0
}
```

**Integration into save flow:**
```bash
save_config_file() {
    local config_file="$1"
    local config_content="$2"
    
    # Write to temp file first
    local temp_file="${config_file}.tmp"
    echo "$config_content" > "$temp_file"
    
    # Validate
    if ! validate_config_file "$temp_file"; then
        log "ERROR" "Validation failed. Config NOT saved."
        rm -f "$temp_file"
        return 1
    fi
    
    # Backup existing (Story 1.4)
    [[ -f "$config_file" ]] && backup_config_file "$config_file"
    
    # Atomic move
    mv "$temp_file" "$config_file"
    log "INFO" "Config saved: $config_file"
    
    # Update index
    index_config_file "$config_file"
    
    return 0
}
```

### Testing Requirements

```bash
test_validate_valid_server_config()
test_validate_valid_client_config()
test_validate_missing_required_field()
test_validate_invalid_port_range()
test_validate_invalid_toml_syntax()
test_validate_performance_under_100ms()
test_save_rejected_on_validation_failure()
```

### Rollback Strategy

Pure validation - no rollback needed. Failed validation simply prevents save.

---

## Story 1.4: Automatic Backup System

**Story ID:** MOONFRP-E01-S04  
**Priority:** P0  
**Effort:** 0.5 days

### Problem Statement

Config changes risk data loss and service disruption. Need automatic backups before modifications with easy rollback capability.

### Acceptance Criteria

1. Automatic backup before ANY config modification
2. Timestamped backups: `config-name.YYYYMMDD-HHMMSS.bak`
3. Keeps last 10 backups per file
4. Easy restore: `moonfrp restore <config> --backup=<timestamp>`
5. Backup operation <50ms
6. Backup directory: `~/.moonfrp/backups/`

### Technical Specification

**Location:** `moonfrp-core.sh` or `moonfrp-config.sh`

**Implementation:**
```bash
BACKUP_DIR="$HOME/.moonfrp/backups"
MAX_BACKUPS_PER_FILE=10

backup_config_file() {
    local config_file="$1"
    
    [[ ! -f "$config_file" ]] && return 1
    
    mkdir -p "$BACKUP_DIR"
    
    local filename=$(basename "$config_file")
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_file="$BACKUP_DIR/${filename%.toml}.$timestamp.bak"
    
    cp "$config_file" "$backup_file"
    log "INFO" "Backup created: $backup_file"
    
    # Cleanup old backups (keep last 10)
    cleanup_old_backups "$filename"
    
    return 0
}

cleanup_old_backups() {
    local filename="$1"
    local base_name="${filename%.toml}"
    
    # Find all backups for this config, sorted by age
    local backups=($(find "$BACKUP_DIR" -name "${base_name}.*.bak" -type f -printf '%T@ %p\n' \
                     | sort -rn | awk '{print $2}'))
    
    # Remove older backups beyond MAX_BACKUPS_PER_FILE
    if [[ ${#backups[@]} -gt $MAX_BACKUPS_PER_FILE ]]; then
        for ((i=$MAX_BACKUPS_PER_FILE; i<${#backups[@]}; i++)); do
            rm -f "${backups[$i]}"
            log "INFO" "Removed old backup: ${backups[$i]}"
        done
    fi
}

list_backups() {
    local config_name="${1:-}"
    
    if [[ -n "$config_name" ]]; then
        local base_name="${config_name%.toml}"
        find "$BACKUP_DIR" -name "${base_name}.*.bak" -type f -printf '%T@ %p\n' \
            | sort -rn | awk '{print $2}'
    else
        find "$BACKUP_DIR" -name "*.bak" -type f -printf '%T@ %p\n' \
            | sort -rn | awk '{print $2}'
    fi
}

restore_config_from_backup() {
    local config_file="$1"
    local backup_file="$2"
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "Backup not found: $backup_file"
        return 1
    fi
    
    # Backup current before restore (inception!)
    [[ -f "$config_file" ]] && backup_config_file "$config_file"
    
    # Restore
    cp "$backup_file" "$config_file"
    log "INFO" "Restored from backup: $backup_file -> $config_file"
    
    # Revalidate
    if ! validate_config_file "$config_file"; then
        log "WARN" "Restored config failed validation. Review manually."
    fi
    
    # Update index
    index_config_file "$config_file"
    
    return 0
}

# Interactive restore menu
restore_config_interactive() {
    local config_file="$1"
    local filename=$(basename "$config_file")
    
    clear
    echo -e "${CYAN}Available backups for: $filename${NC}"
    echo
    
    local backups=($(list_backups "$filename"))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log "WARN" "No backups found for $filename"
        return 1
    fi
    
    local i=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_date=$(echo "$backup_name" | grep -oE '[0-9]{8}-[0-9]{6}')
        local formatted_date=$(date -d "${backup_date:0:8} ${backup_date:9:2}:${backup_date:11:2}:${backup_date:13:2}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$backup_date")
        echo "$i) $formatted_date"
        ((i++))
    done
    echo "0) Cancel"
    echo
    
    safe_read "Select backup to restore" "choice" "0"
    
    if [[ "$choice" -eq 0 ]]; then
        return 0
    fi
    
    if [[ "$choice" -ge 1 && "$choice" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((choice-1))]}"
        
        safe_read "Restore from this backup? Current config will be backed up first. (y/N)" "confirm" "n"
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            restore_config_from_backup "$config_file" "$selected_backup"
        fi
    else
        log "ERROR" "Invalid selection"
    fi
}
```

### Testing Requirements

```bash
test_backup_creates_timestamped_file()
test_backup_cleanup_keeps_last_10()
test_restore_from_backup()
test_restore_validates_config()
test_backup_performance_under_50ms()
test_list_backups_sorted()
```

### Rollback Strategy

Backups themselves are the rollback mechanism. If backup system fails, configs remain unchanged.

---

## Epic-Level Acceptance

**This epic is COMPLETE when:**

1. ✅ All 4 stories implemented and tested
2. ✅ Menu loads in <200ms with 50 configs (measured)
3. ✅ FRP version displays correctly across versions
4. ✅ Invalid configs rejected with clear errors
5. ✅ All config changes automatically backed up
6. ✅ Zero data loss in chaos testing
7. ✅ Performance benchmarks pass
8. ✅ Documentation updated

---

## Dependencies & Blockers

**Dependencies:**
- None - This is the foundation epic

**Potential Blockers:**
- SQLite not available on system (fallback to flat file index)
- Very old FRP versions (<0.50) with different output format
- Filesystem permissions for backup directory

---

## Handoff to Development

**Development Team (@dev Amelia):**
- All stories have complete technical specs
- Test scenarios defined
- Performance targets clear
- Rollback strategies documented

**Questions for Dev:**
1. Prefer SQLite or flat-file JSON index?
2. Any concerns about concurrent access to index?
3. Need spike task for SQLite integration?

---

**Status:** Ready for Implementation  
**Created:** 2025-11-02  
**Approved By:** BMad Master, Team Consensus

