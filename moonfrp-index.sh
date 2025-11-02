#!/bin/bash

#==============================================================================
# MoonFRP Config Index Module
# Version: 2.0.0
# Description: SQLite-based index for fast config file metadata queries
#==============================================================================

# Prevent multiple sourcing
if [[ "${MOONFRP_INDEX_LOADED:-}" == "true" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
export MOONFRP_INDEX_LOADED="true"

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-config.sh"

#==============================================================================
# CONFIGURATION
#==============================================================================

readonly INDEX_DB_DIR="$HOME/.moonfrp"
readonly INDEX_DB_PATH="$INDEX_DB_DIR/index.db"

#==============================================================================
# DATABASE FUNCTIONS
#==============================================================================

# Check if SQLite3 is available
check_sqlite3() {
    if ! command -v sqlite3 &> /dev/null; then
        log "ERROR" "sqlite3 is required but not installed"
        return 1
    fi
    return 0
}

# Initialize database schema
init_config_index() {
    if ! check_sqlite3; then
        return 1
    fi
    
    mkdir -p "$INDEX_DB_DIR"
    
    local db_path="$INDEX_DB_PATH"
    
    sqlite3 "$db_path" << 'SQL'
CREATE TABLE IF NOT EXISTS config_index (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    file_hash TEXT NOT NULL,
    config_type TEXT NOT NULL,
    server_addr TEXT,
    server_port INTEGER,
    bind_port INTEGER,
    auth_token_hash TEXT,
    proxy_count INTEGER DEFAULT 0,
    tags TEXT,
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
SQL
    
    if [[ $? -eq 0 ]]; then
        local created_time=$(date +%s)
        sqlite3 "$db_path" "INSERT OR REPLACE INTO index_meta (key, value) VALUES ('created', '$created_time');"
        sqlite3 "$db_path" "INSERT OR REPLACE INTO index_meta (key, value) VALUES ('version', '1.0');"
        log "DEBUG" "Config index database initialized: $db_path"
        return 0
    else
        log "ERROR" "Failed to initialize config index database"
        return 1
    fi
}

# Index a single config file
index_config_file() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log "WARN" "Config file not found: $config_file"
        return 1
    fi
    
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        if ! init_config_index; then
            return 1
        fi
    fi
    
    local file_hash
    local config_type="client"
    local server_addr=""
    local server_port=""
    local bind_port=""
    local auth_token=""
    local auth_token_hash=""
    local proxy_count=0
    local tags="[]"
    local last_modified=0
    local last_indexed=$(date +%s)
    
    if [[ "$config_file" == *"frps.toml" ]] || [[ "$config_file" == *"frps"* ]]; then
        config_type="server"
    fi
    
    if ! file_hash=$(sha256sum "$config_file" 2>/dev/null | awk '{print $1}'); then
        log "WARN" "Failed to calculate hash for: $config_file"
        return 1
    fi
    
    if last_modified=$(stat -c %Y "$config_file" 2>/dev/null || echo "0"); then
        : 
    fi
    
    if [[ "$config_type" == "client" ]]; then
        server_addr=$(get_toml_value "$config_file" "serverAddr" 2>/dev/null | sed 's/["'\'']//g' || echo "")
        server_port=$(get_toml_value "$config_file" "serverPort" 2>/dev/null | tr -d '"' || echo "")
    fi
    
    bind_port=$(get_toml_value "$config_file" "bindPort" 2>/dev/null | tr -d '"' || echo "")
    auth_token=$(get_toml_value "$config_file" "auth.token" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    
    if [[ -n "$auth_token" ]]; then
        auth_token_hash=$(echo -n "$auth_token" | sha256sum | awk '{print $1}')
    fi
    
    proxy_count=$(grep -c '^\[\[proxies\]\]' "$config_file" 2>/dev/null || echo "0")
    
    local escaped_path=$(printf '%s\n' "$config_file" | sed "s/'/''/g")
    local escaped_hash=$(printf '%s\n' "$file_hash" | sed "s/'/''/g")
    local escaped_type=$(printf '%s\n' "$config_type" | sed "s/'/''/g")
    local escaped_addr=$(printf '%s\n' "$server_addr" | sed "s/'/''/g")
    local escaped_tags=$(printf '%s\n' "$tags" | sed "s/'/''/g")
    local escaped_token_hash=$(printf '%s\n' "$auth_token_hash" | sed "s/'/''/g")
    
    sqlite3 "$db_path" << SQL
INSERT OR REPLACE INTO config_index 
    (file_path, file_hash, config_type, server_addr, server_port, 
     bind_port, auth_token_hash, proxy_count, tags, last_modified, last_indexed)
VALUES 
    ('$escaped_path', '$escaped_hash', '$escaped_type', '$escaped_addr', 
     ${server_port:-NULL}, ${bind_port:-NULL}, '$escaped_token_hash', 
     $proxy_count, '$escaped_tags', $last_modified, $last_indexed);
SQL
    
    if [[ $? -eq 0 ]]; then
        log "DEBUG" "Indexed config file: $config_file"
        return 0
    else
        log "WARN" "Failed to index config file: $config_file"
        return 1
    fi
}

# Rebuild entire index
rebuild_config_index() {
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        if ! init_config_index; then
            return 1
        fi
    fi
    
    log "INFO" "Rebuilding config index..."
    
    sqlite3 "$db_path" "DELETE FROM config_index;"
    
    local indexed_count=0
    local failed_count=0
    
    while IFS= read -r -d '' config_file; do
        if index_config_file "$config_file"; then
            ((indexed_count++))
        else
            ((failed_count++))
        fi
    done < <(find "$CONFIG_DIR" -name "*.toml" -type f -print0 2>/dev/null)
    
    if [[ $indexed_count -gt 0 ]]; then
        local rebuild_time=$(date +%s)
        sqlite3 "$db_path" "INSERT OR REPLACE INTO index_meta (key, value) VALUES ('last_rebuild', '$rebuild_time');"
        log "INFO" "Index rebuild complete: $indexed_count files indexed, $failed_count failed"
        return 0
    else
        log "WARN" "Index rebuild completed but no files were indexed"
        return 1
    fi
}

# Check and update index for changed files
check_and_update_index() {
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        if ! init_config_index; then
            log "WARN" "Index unavailable, falling back to file parsing"
            return 1
        fi
        rebuild_config_index
        return $?
    fi
    
    local updated_count=0
    
    while IFS= read -r -d '' config_file; do
        local file_hash=$(sha256sum "$config_file" 2>/dev/null | awk '{print $1}')
        local indexed_hash=$(sqlite3 "$db_path" "SELECT file_hash FROM config_index WHERE file_path='$(printf '%s' "$config_file" | sed "s/'/''/g")';" 2>/dev/null || echo "")
        
        if [[ "$file_hash" != "$indexed_hash" ]]; then
            if index_config_file "$config_file"; then
                ((updated_count++))
            fi
        fi
    done < <(find "$CONFIG_DIR" -name "*.toml" -type f -print0 2>/dev/null)
    
    if [[ $updated_count -gt 0 ]]; then
        log "DEBUG" "Index updated: $updated_count files changed"
    fi
    
    return 0
}

# Verify index integrity
verify_index_integrity() {
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        return 1
    fi
    
    if ! sqlite3 "$db_path" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
        log "WARN" "Index database corruption detected"
        return 1
    fi
    
    return 0
}

#==============================================================================
# QUERY FUNCTIONS
#==============================================================================

# Query configs by type
query_configs_by_type() {
    local config_type="${1:-}"
    
    if [[ -z "$config_type" ]]; then
        log "ERROR" "config_type parameter required"
        return 1
    fi
    
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "DEBUG" "Index not available, falling back to file parsing"
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted, falling back to file parsing"
        return 1
    fi
    
    local escaped_type=$(printf '%s\n' "$config_type" | sed "s/'/''/g")
    
    sqlite3 -separator '|' "$db_path" \
        "SELECT file_path, server_addr, COALESCE(proxy_count, 0) FROM config_index 
         WHERE config_type='$escaped_type' ORDER BY file_path;" 2>/dev/null
    
    return $?
}

# Query total proxy count
query_total_proxy_count() {
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "DEBUG" "Index not available, falling back to file parsing"
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted, falling back to file parsing"
        return 1
    fi
    
    local total=$(sqlite3 "$db_path" "SELECT COALESCE(SUM(proxy_count), 0) FROM config_index;" 2>/dev/null || echo "0")
    echo "$total"
    return 0
}

# Query configs by server address
query_configs_by_server_addr() {
    local server_addr="${1:-}"
    
    if [[ -z "$server_addr" ]]; then
        log "ERROR" "server_addr parameter required"
        return 1
    fi
    
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "DEBUG" "Index not available, falling back to file parsing"
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted, falling back to file parsing"
        return 1
    fi
    
    local escaped_addr=$(printf '%s\n' "$server_addr" | sed "s/'/''/g")
    
    sqlite3 -separator '|' "$db_path" \
        "SELECT file_path, server_port, COALESCE(proxy_count, 0) FROM config_index 
         WHERE server_addr='$escaped_addr' ORDER BY file_path;" 2>/dev/null
    
    return $?
}

# Get index statistics
get_index_stats() {
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        echo "Index not available"
        return 1
    fi
    
    if ! verify_index_integrity; then
        echo "Index corrupted"
        return 1
    fi
    
    local total_configs=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index;" 2>/dev/null || echo "0")
    local server_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index WHERE config_type='server';" 2>/dev/null || echo "0")
    local client_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM config_index WHERE config_type='client';" 2>/dev/null || echo "0")
    local total_proxies=$(query_total_proxy_count)
    local db_size=$(stat -c %s "$db_path" 2>/dev/null || echo "0")
    local db_size_mb=$(awk "BEGIN {printf \"%.2f\", $db_size/1024/1024}")
    
    echo "Total configs: $total_configs (server: $server_count, client: $client_count)"
    echo "Total proxies: $total_proxies"
    echo "Database size: ${db_size_mb}MB"
    
    return 0
}

#==============================================================================
# FALLBACK FUNCTIONS
#==============================================================================

# Fallback to file parsing (when index unavailable)
query_configs_by_type_fallback() {
    local config_type="${1:-}"
    local config_files=()
    
    if [[ "$config_type" == "server" ]]; then
        if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
            config_files+=("$CONFIG_DIR/frps.toml")
        fi
    elif [[ "$config_type" == "client" ]]; then
        while IFS= read -r -d '' file; do
            config_files+=("$file")
        done < <(find "$CONFIG_DIR" -name "frpc*.toml" -type f -print0 2>/dev/null)
    fi
    
    for file in "${config_files[@]}"; do
        local server_addr=$(get_toml_value "$file" "serverAddr" 2>/dev/null | sed 's/["'\'']//g' || echo "")
        local proxy_count=$(grep -c '^\[\[proxies\]\]' "$file" 2>/dev/null || echo "0")
        echo "${file}|${server_addr}|${proxy_count}"
    done
}

# Fallback total proxy count
query_total_proxy_count_fallback() {
    local total=0
    
    while IFS= read -r -d '' file; do
        local count=$(grep -c '^\[\[proxies\]\]' "$file" 2>/dev/null || echo "0")
        total=$((total + count))
    done < <(find "$CONFIG_DIR" -name "*.toml" -type f -print0 2>/dev/null)
    
    echo "$total"
}

#==============================================================================
# TAG MANAGEMENT FUNCTIONS
#==============================================================================

# Add tag to config
add_config_tag() {
    local config_file="$1"
    local tag_key="$2"
    local tag_value="$3"
    
    if [[ -z "$config_file" ]] || [[ -z "$tag_key" ]] || [[ -z "$tag_value" ]]; then
        log "ERROR" "Usage: add_config_tag <config_file> <tag_key> <tag_value>"
        return 1
    fi
    
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "ERROR" "Index database not found. Please initialize index first."
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted"
        return 1
    fi
    
    local escaped_path=$(printf '%s\n' "$config_file" | sed "s/'/''/g")
    local escaped_key=$(printf '%s\n' "$tag_key" | sed "s/'/''/g")
    local escaped_value=$(printf '%s\n' "$tag_value" | sed "s/'/''/g")
    
    local config_id=$(sqlite3 "$db_path" "SELECT id FROM config_index WHERE file_path='$escaped_path';" 2>/dev/null || echo "")
    
    if [[ -z "$config_id" ]]; then
        log "ERROR" "Config file not found in index: $config_file"
        log "INFO" "Please index the config file first using index_config_file()"
        return 1
    fi
    
    sqlite3 "$db_path" << SQL
INSERT OR REPLACE INTO service_tags (config_id, tag_key, tag_value)
VALUES ($config_id, '$escaped_key', '$escaped_value');
SQL
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "Added tag $tag_key:$tag_value to config: $config_file"
        return 0
    else
        log "ERROR" "Failed to add tag to config: $config_file"
        return 1
    fi
}

# Remove tag from config
remove_config_tag() {
    local config_file="$1"
    local tag_key="$2"
    
    if [[ -z "$config_file" ]] || [[ -z "$tag_key" ]]; then
        log "ERROR" "Usage: remove_config_tag <config_file> <tag_key>"
        return 1
    fi
    
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "ERROR" "Index database not found. Please initialize index first."
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted"
        return 1
    fi
    
    local escaped_path=$(printf '%s\n' "$config_file" | sed "s/'/''/g")
    local escaped_key=$(printf '%s\n' "$tag_key" | sed "s/'/''/g")
    
    local config_id=$(sqlite3 "$db_path" "SELECT id FROM config_index WHERE file_path='$escaped_path';" 2>/dev/null || echo "")
    
    if [[ -z "$config_id" ]]; then
        log "ERROR" "Config file not found in index: $config_file"
        return 1
    fi
    
    sqlite3 "$db_path" "DELETE FROM service_tags WHERE config_id=$config_id AND tag_key='$escaped_key';" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "Removed tag $tag_key from config: $config_file"
        return 0
    else
        log "ERROR" "Failed to remove tag from config: $config_file"
        return 1
    fi
}

# List tags for config
list_config_tags() {
    local config_file="$1"
    
    if [[ -z "$config_file" ]]; then
        log "ERROR" "Usage: list_config_tags <config_file>"
        return 1
    fi
    
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "ERROR" "Index database not found. Please initialize index first."
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted"
        return 1
    fi
    
    local escaped_path=$(printf '%s\n' "$config_file" | sed "s/'/''/g")
    
    local config_id=$(sqlite3 "$db_path" "SELECT id FROM config_index WHERE file_path='$escaped_path';" 2>/dev/null || echo "")
    
    if [[ -z "$config_id" ]]; then
        log "WARN" "Config file not found in index: $config_file"
        return 1
    fi
    
    sqlite3 -separator ':' "$db_path" \
        "SELECT tag_key, tag_value FROM service_tags WHERE config_id=$config_id ORDER BY tag_key;" 2>/dev/null
    
    return $?
}

# Bulk tag configs
bulk_tag_configs() {
    local tag_key="$1"
    local tag_value="$2"
    local filter="${3:-all}"
    
    if [[ -z "$tag_key" ]] || [[ -z "$tag_value" ]]; then
        log "ERROR" "Usage: bulk_tag_configs <tag_key> <tag_value> [filter]"
        log "INFO" "Filter types: all, type:server, type:client, tag:X, name:pattern"
        return 1
    fi
    
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "ERROR" "Index database not found. Please initialize index first."
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted"
        return 1
    fi
    
    local config_files=()
    local configs_output
    
    if type get_configs_by_filter &>/dev/null; then
        source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-config.sh" 2>/dev/null || true
        configs_output=$(get_configs_by_filter "$filter" 2>/dev/null || true)
    else
        log "ERROR" "get_configs_by_filter() not available (requires Story 2.2)"
        return 1
    fi
    
    if [[ -z "$configs_output" ]]; then
        log "WARN" "No config files found matching filter: $filter"
        return 1
    fi
    
    while IFS= read -r config_file; do
        [[ -n "$config_file" ]] && [[ -f "$config_file" ]] && config_files+=("$config_file")
    done <<< "$configs_output"
    
    if [[ ${#config_files[@]} -eq 0 ]]; then
        log "WARN" "No valid config files found matching filter: $filter"
        return 1
    fi
    
    log "INFO" "Bulk tagging ${#config_files[@]} config file(s) with tag $tag_key:$tag_value (filter: $filter)"
    
    local success_count=0
    local fail_count=0
    
    for config_file in "${config_files[@]}"; do
        if add_config_tag "$config_file" "$tag_key" "$tag_value"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    log "INFO" "Bulk tagging complete: $success_count succeeded, $fail_count failed"
    
    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# Query configs by tag
query_configs_by_tag() {
    local tag_query="$1"
    
    if [[ -z "$tag_query" ]]; then
        log "ERROR" "Usage: query_configs_by_tag <tag_query>"
        log "INFO" "Tag query format: 'key:value' for exact match, or 'key' for key-only match"
        return 1
    fi
    
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "DEBUG" "Index not available, falling back to file parsing"
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted, falling back to file parsing"
        return 1
    fi
    
    local tag_key=""
    local tag_value=""
    
    if [[ "$tag_query" == *":"* ]]; then
        tag_key="${tag_query%%:*}"
        tag_value="${tag_query#*:}"
    else
        tag_key="$tag_query"
    fi
    
    local escaped_key=$(printf '%s\n' "$tag_key" | sed "s/'/''/g")
    local escaped_value=""
    
    if [[ -n "$tag_value" ]]; then
        escaped_value=$(printf '%s\n' "$tag_value" | sed "s/'/''/g")
        sqlite3 "$db_path" \
            "SELECT DISTINCT ci.file_path FROM config_index ci
             JOIN service_tags st ON ci.id = st.config_id
             WHERE st.tag_key='$escaped_key' AND st.tag_value='$escaped_value'
             ORDER BY ci.file_path;" 2>/dev/null
    else
        sqlite3 "$db_path" \
            "SELECT DISTINCT ci.file_path FROM config_index ci
             JOIN service_tags st ON ci.id = st.config_id
             WHERE st.tag_key='$escaped_key'
             ORDER BY ci.file_path;" 2>/dev/null
    fi
    
    return $?
}

# List all tags in use
list_all_tags() {
    if ! check_sqlite3; then
        return 1
    fi
    
    local db_path="$INDEX_DB_PATH"
    
    if [[ ! -f "$db_path" ]]; then
        log "ERROR" "Index database not found. Please initialize index first."
        return 1
    fi
    
    if ! verify_index_integrity; then
        log "WARN" "Index corrupted"
        return 1
    fi
    
    sqlite3 -separator ':' "$db_path" \
        "SELECT DISTINCT st.tag_key, st.tag_value, COUNT(*) as count
         FROM service_tags st
         GROUP BY st.tag_key, st.tag_value
         ORDER BY st.tag_key, st.tag_value;" 2>/dev/null
    
    return $?
}

# Tag management menu
tag_management_menu() {
    while true; do
        if [[ "${MENU_STATE["ctrl_c_pressed"]:-false}" == "true" ]]; then
            MENU_STATE["ctrl_c_pressed"]="false"
            return
        fi
        
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║        MoonFRP Tag Management        ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
        echo
        
        echo -e "${CYAN}Tag Management Options:${NC}"
        echo "1. Add tag to config"
        echo "2. Remove tag from config"
        echo "3. List tags for config"
        echo "4. Bulk tag configs"
        echo "5. List all tags"
        echo "6. Operations by tag"
        echo "0. Back to Main Menu"
        echo
        
        safe_read "Enter your choice" "choice" "0"
        
        case "$choice" in
            1)
                echo -e "${CYAN}Add Tag to Config${NC}"
                echo
                safe_read "Config file path" "config_file" ""
                if [[ -n "$config_file" ]]; then
                    safe_read "Tag key (e.g., env)" "tag_key" ""
                    if [[ -n "$tag_key" ]]; then
                        safe_read "Tag value (e.g., prod)" "tag_value" ""
                        if [[ -n "$tag_value" ]]; then
                            add_config_tag "$config_file" "$tag_key" "$tag_value"
                        fi
                    fi
                fi
                read -p "Press Enter to continue..."
                ;;
            2)
                echo -e "${CYAN}Remove Tag from Config${NC}"
                echo
                safe_read "Config file path" "config_file" ""
                if [[ -n "$config_file" ]]; then
                    safe_read "Tag key to remove" "tag_key" ""
                    if [[ -n "$tag_key" ]]; then
                        remove_config_tag "$config_file" "$tag_key"
                    fi
                fi
                read -p "Press Enter to continue..."
                ;;
            3)
                echo -e "${CYAN}List Tags for Config${NC}"
                echo
                safe_read "Config file path" "config_file" ""
                if [[ -n "$config_file" ]]; then
                    echo
                    echo "Tags for $config_file:"
                    local tags_output
                    if tags_output=$(list_config_tags "$config_file"); then
                        while IFS=':' read -r key value; do
                            [[ -n "$key" ]] && echo "  $key: $value"
                        done <<< "$tags_output"
                    else
                        echo "  (no tags)"
                    fi
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo -e "${CYAN}Bulk Tag Configs${NC}"
                echo
                safe_read "Tag key (e.g., env)" "tag_key" ""
                if [[ -n "$tag_key" ]]; then
                    safe_read "Tag value (e.g., prod)" "tag_value" ""
                    if [[ -n "$tag_value" ]]; then
                        safe_read "Filter (all, type:server, type:client, tag:X, name:pattern)" "filter" "all"
                        bulk_tag_configs "$tag_key" "$tag_value" "${filter:-all}"
                    fi
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                echo -e "${CYAN}All Tags in Use${NC}"
                echo
                local all_tags_output
                if all_tags_output=$(list_all_tags); then
                    echo "Tag Key:Tag Value (Count)"
                    echo "─────────────────────────"
                    while IFS=':' read -r key value count; do
                        [[ -n "$key" ]] && echo "$key:$value ($count config(s))"
                    done <<< "$all_tags_output"
                else
                    echo "  (no tags in use)"
                fi
                read -p "Press Enter to continue..."
                ;;
            6)
                echo -e "${CYAN}Operations by Tag${NC}"
                echo
                safe_read "Tag query (key:value or key)" "tag_query" ""
                if [[ -n "$tag_query" ]]; then
                    echo
                    echo "Services matching tag '$tag_query':"
                    source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-services.sh" 2>/dev/null || true
                    local services_output
                    if services_output=$(get_services_by_tag "$tag_query" 2>/dev/null); then
                        while IFS= read -r service; do
                            [[ -n "$service" ]] && echo "  - $service"
                        done <<< "$services_output"
                        echo
                        echo "Available operations:"
                        echo "  - Start: moonfrp service start --tag=$tag_query"
                        echo "  - Stop: moonfrp service stop --tag=$tag_query"
                        echo "  - Restart: moonfrp service restart --tag=$tag_query"
                    else
                        echo "  (no services found)"
                    fi
                fi
                read -p "Press Enter to continue..."
                ;;
            0)
                return
                ;;
            *)
                log "ERROR" "Invalid choice"
                ;;
        esac
    done
}

# Export functions
export -f check_sqlite3 init_config_index index_config_file rebuild_config_index
export -f check_and_update_index verify_index_integrity
export -f query_configs_by_type query_total_proxy_count query_configs_by_server_addr get_index_stats
export -f query_configs_by_type_fallback query_total_proxy_count_fallback
export -f add_config_tag remove_config_tag list_config_tags query_configs_by_tag bulk_tag_configs
export -f list_all_tags tag_management_menu

