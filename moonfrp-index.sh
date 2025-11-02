#!/bin/bash

#==============================================================================
# MoonFRP Config Index Module
# Version: 2.0.0
# Description: SQLite-based index for fast config file metadata queries
#==============================================================================

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-config.sh"

# Prevent multiple sourcing
if [[ "${MOONFRP_INDEX_LOADED:-}" == "true" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
export MOONFRP_INDEX_LOADED="true"

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

# Export functions
export -f check_sqlite3 init_config_index index_config_file rebuild_config_index
export -f check_and_update_index verify_index_integrity
export -f query_configs_by_type query_total_proxy_count query_configs_by_server_addr get_index_stats
export -f query_configs_by_type_fallback query_total_proxy_count_fallback

