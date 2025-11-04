#!/bin/bash

#==============================================================================
# MoonFRP Config Index Module
# Version: 3.0.0
# Description: JSON-based index for fast config file metadata queries
#==============================================================================

# Prevent multiple sourcing
if [[ "${MOONFRP_INDEX_LOADED:-}" == "true" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
export MOONFRP_INDEX_LOADED="true"

# Source core helpers
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-config.sh"

#==============================================================================
# CONFIGURATION
#==============================================================================

readonly INDEX_DATA_ROOT="${DATA_DIR}/config-index"
readonly INDEX_META_FILE="${DATA_DIR}/index-meta.json"
readonly INDEX_TMP_DIR="${DATA_DIR}/tmp"

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

check_python3() {
    if ! command -v python3 >/dev/null 2>&1; then
        log "ERROR" "python3 is required but not installed"
        return 1
    fi
    return 0
}

ensure_index_dirs() {
    mkdir -p "$DATA_DIR" "$INDEX_DATA_ROOT" "$INDEX_TMP_DIR"
    chmod 755 "$DATA_DIR" "$INDEX_DATA_ROOT" "$INDEX_TMP_DIR" 2>/dev/null || true
}

metadata_path_for_config() {
    local config_file="$1"
    local slug
    slug=$(printf '%s' "$config_file" | sha256sum | cut -c1-16)
    echo "$INDEX_DATA_ROOT/${slug}.json"
}

python_write_meta() {
    local metadata_path="$1"
    python3 - "$metadata_path" <<'PY'
import json
import os
import sys
import time

metadata_path = sys.argv[1]
existing = {}
if os.path.exists(metadata_path):
    try:
        with open(metadata_path, 'r', encoding='utf-8') as fh:
            existing = json.load(fh) or {}
    except Exception:
        existing = {}

def parse_int(value):
    if value is None:
        return None
    if isinstance(value, str) and not value.strip():
        return None
    try:
        return int(value)
    except Exception:
        return None

metadata = {
    "path": os.environ.get("CONFIG_PATH", ""),
    "hash": os.environ.get("CONFIG_HASH", ""),
    "type": os.environ.get("CONFIG_TYPE", "client"),
    "server_addr": os.environ.get("SERVER_ADDR") or None,
    "server_port": parse_int(os.environ.get("SERVER_PORT")),
    "bind_port": parse_int(os.environ.get("BIND_PORT")),
    "auth_token_hash": os.environ.get("AUTH_TOKEN_HASH") or None,
    "proxy_count": parse_int(os.environ.get("PROXY_COUNT")) or 0,
    "tags": existing.get("tags") or {},
    "last_modified": parse_int(os.environ.get("LAST_MODIFIED")) or 0,
    "last_indexed": parse_int(os.environ.get("LAST_INDEXED")) or int(time.time())
}

tmp_path = metadata_path + '.tmp'
with open(tmp_path, 'w', encoding='utf-8') as fh:
    json.dump(metadata, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
os.replace(tmp_path, metadata_path)
PY
}

python_update_meta_file() {
    python3 - "$INDEX_META_FILE" <<'PY'
import json
import os
import sys

meta_path = sys.argv[1]
key = os.environ.get('META_KEY')
value = os.environ.get('META_VALUE')
meta = {}
if os.path.exists(meta_path):
    try:
        with open(meta_path, 'r', encoding='utf-8') as fh:
            meta = json.load(fh) or {}
    except Exception:
        meta = {}

meta[key] = value

tmp_path = meta_path + '.tmp'
with open(tmp_path, 'w', encoding='utf-8') as fh:
    json.dump(meta, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
os.replace(tmp_path, meta_path)
PY
}

python_extract_field() {
    local metadata_path="$1"
    local field_name="$2"
    python3 - "$metadata_path" "$field_name" <<'PY'
import json
import sys

path = sys.argv[1]
field = sys.argv[2]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh) or {}
except Exception:
    data = {}
value = data.get(field)
if value is None:
    print("")
elif isinstance(value, (dict, list)):
    import json as _json
    print(_json.dumps(value))
else:
    print(str(value))
PY
}

remove_orphan_metadata() {
    shopt -s nullglob
    local removed=0
    for meta_file in "$INDEX_DATA_ROOT"/*.json; do
        [[ -f "$meta_file" ]] || continue
        local config_path
        config_path=$(python_extract_field "$meta_file" "path")
        if [[ -z "$config_path" || ! -f "$config_path" ]]; then
            rm -f "$meta_file"
            ((removed++))
        fi
    done
    shopt -u nullglob
    if [[ $removed -gt 0 ]]; then
        log "DEBUG" "Removed $removed orphaned index entries"
    fi
}

get_config_metadata_json() {
    local config_file="$1"
    local metadata_path
    metadata_path=$(metadata_path_for_config "$config_file")
    if [[ ! -f "$metadata_path" ]]; then
        return 1
    fi
    python3 - <<'PY' "$metadata_path"
import json
import sys

path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh) or {}
except Exception:
    data = {}

print(json.dumps(data))
PY
}

list_indexed_configs() {
    if ! check_python3; then
        return 1
    fi
    ensure_index_dirs
    python3 - <<'PY' "$INDEX_DATA_ROOT"
import json
import os
import sys

root = sys.argv[1]
paths = []
for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    cfg_path = data.get('path')
    if cfg_path:
        paths.append(cfg_path)
for cfg in sorted(paths):
    print(cfg)
PY
}

get_config_metadata_field() {
    local config_file="$1"
    local field_name="$2"
    local metadata_path
    metadata_path=$(metadata_path_for_config "$config_file")
    if [[ ! -f "$metadata_path" ]]; then
        echo ""
        return 1
    fi
    python_extract_field "$metadata_path" "$field_name"
}

#==============================================================================
# INDEX MANAGEMENT
#==============================================================================

init_config_index() {
    if ! check_python3; then
        return 1
    fi
    ensure_index_dirs
    if [[ ! -f "$INDEX_META_FILE" ]]; then
        META_KEY="created" META_VALUE="$(date +%s)" python_update_meta_file
        META_KEY="version" META_VALUE="json-1" python_update_meta_file
    fi
    return 0
}

index_config_file() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log "WARN" "Config file not found: $config_file"
            return 1
        fi
    if ! check_python3; then
        return 1
    fi

    ensure_index_dirs
    
    local file_hash
    file_hash=$(sha256sum "$config_file" 2>/dev/null | awk '{print $1}') || {
        log "WARN" "Failed to hash config: $config_file"
        return 1
    }

    local last_modified
    last_modified=$(stat -c %Y "$config_file" 2>/dev/null || echo "0")

    local config_type="client"
    if [[ "$config_file" == *"frps.toml" ]] || [[ "$config_file" == *"frps"* ]]; then
        config_type="server"
    fi
    
    local server_addr=""
    local server_port=""
    if [[ "$config_type" == "client" ]]; then
        server_addr=$(get_toml_value "$config_file" "serverAddr" 2>/dev/null | sed 's/["'\'']//g' || echo "")
        server_port=$(get_toml_value "$config_file" "serverPort" 2>/dev/null | tr -d '"' || echo "")
    fi
    
    local bind_port=""
    bind_port=$(get_toml_value "$config_file" "bindPort" 2>/dev/null | tr -d '"' || echo "")
    
    local auth_token_hash=""
    local auth_token
    auth_token=$(get_toml_value "$config_file" "auth.token" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    if [[ -n "$auth_token" ]]; then
        auth_token_hash=$(echo -n "$auth_token" | sha256sum | awk '{print $1}')
    fi
    
    local proxy_count
    proxy_count=$(grep -c '^\[\[proxies\]\]' "$config_file" 2>/dev/null || echo "0")
    
    local metadata_path
    metadata_path=$(metadata_path_for_config "$config_file")
    local now
    now=$(date +%s)

    CONFIG_PATH="$config_file" \
    CONFIG_HASH="$file_hash" \
    CONFIG_TYPE="$config_type" \
    SERVER_ADDR="$server_addr" \
    SERVER_PORT="$server_port" \
    BIND_PORT="$bind_port" \
    AUTH_TOKEN_HASH="$auth_token_hash" \
    PROXY_COUNT="$proxy_count" \
    LAST_MODIFIED="$last_modified" \
    LAST_INDEXED="$now" \
        python_write_meta "$metadata_path"
}

rebuild_config_index() {
    if ! check_python3; then
        return 1
    fi
    
    ensure_index_dirs
    
    log "INFO" "Rebuilding config index..."
    
    local indexed_count=0
    local failed_count=0
    
    while IFS= read -r -d '' config_file; do
        if index_config_file "$config_file"; then
            ((indexed_count++))
        else
            ((failed_count++))
        fi
    done < <(find "$CONFIG_DIR" -name "*.toml" -type f -print0 2>/dev/null)

    remove_orphan_metadata

    META_KEY="last_rebuild" META_VALUE="$(date +%s)" python_update_meta_file
    
    if [[ $indexed_count -gt 0 ]]; then
        log "INFO" "Index rebuild complete: $indexed_count files indexed, $failed_count failed"
        return 0
    fi

        log "WARN" "Index rebuild completed but no files were indexed"
        return 1
}

check_and_update_index() {
    if ! check_python3; then
        return 1
    fi
    
    ensure_index_dirs

    if [[ ! -f "$INDEX_META_FILE" ]]; then
        init_config_index || return 1
    fi
    
    local updated_count=0
    
    while IFS= read -r -d '' config_file; do
        local file_hash
        file_hash=$(sha256sum "$config_file" 2>/dev/null | awk '{print $1}') || continue
        local metadata_path
        metadata_path=$(metadata_path_for_config "$config_file")
        local stored_hash=""
        if [[ -f "$metadata_path" ]]; then
            stored_hash=$(python_extract_field "$metadata_path" "hash")
        fi
        if [[ -z "$stored_hash" || "$stored_hash" != "$file_hash" ]]; then
            if index_config_file "$config_file"; then
                ((updated_count++))
            fi
        fi
    done < <(find "$CONFIG_DIR" -name "*.toml" -type f -print0 2>/dev/null)

    remove_orphan_metadata
    
    if [[ $updated_count -gt 0 ]]; then
        log "DEBUG" "Index updated: $updated_count files changed"
    fi
    
    return 0
}

verify_index_integrity() {
    ensure_index_dirs
    shopt -s nullglob
    for meta_file in "$INDEX_DATA_ROOT"/*.json; do
        [[ -f "$meta_file" ]] || continue
        python3 - "$meta_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as fh:
        json.load(fh)
except Exception:
    raise SystemExit(1)
PY
        if [[ $? -ne 0 ]]; then
            log "WARN" "Corrupted metadata detected: $meta_file"
            shopt -u nullglob
        return 1
    fi
    done
    shopt -u nullglob
    return 0
}

#==============================================================================
# QUERY FUNCTIONS
#==============================================================================

query_configs_by_type() {
    local config_type="${1:-}"
    
    if [[ -z "$config_type" ]]; then
        log "ERROR" "config_type parameter required"
        return 1
    fi
    
    if ! check_python3; then
        return 1
    fi
    
    check_and_update_index >/dev/null 2>&1 || true

    python3 - <<'PY' "$INDEX_DATA_ROOT" "$config_type"
import json
import os
import sys

root = sys.argv[1]
filter_type = sys.argv[2]

for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    if data.get('type') != filter_type:
        continue
    file_path = data.get('path', '')
    server_addr = data.get('server_addr') or ''
    proxy_count = data.get('proxy_count') or 0
    print(f"{file_path}|{server_addr}|{proxy_count}")
PY
}

query_total_proxy_count() {
    if ! check_python3; then
        echo "0"
        return 1
    fi
    
    check_and_update_index >/dev/null 2>&1 || true

    python3 - <<'PY' "$INDEX_DATA_ROOT"
import json
import os
import sys

root = sys.argv[1]
proxies = 0
for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    proxies += int(data.get('proxy_count') or 0)
print(proxies)
PY
    return 0
}

query_configs_by_server_addr() {
    local server_addr="${1:-}"
    
    if [[ -z "$server_addr" ]]; then
        log "ERROR" "server_addr parameter required"
        return 1
    fi
    
    if ! check_python3; then
        return 1
    fi
    
    check_and_update_index >/dev/null 2>&1 || true

    python3 - <<'PY' "$INDEX_DATA_ROOT" "$server_addr"
import json
import os
import sys

root = sys.argv[1]
target = sys.argv[2]
for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    if data.get('server_addr') != target:
        continue
    file_path = data.get('path', '')
    proxy_count = data.get('proxy_count') or 0
    print(f"{file_path}|{proxy_count}")
PY
}

get_index_stats() {
    if ! check_python3; then
        echo "Index not available"
        return 1
    fi
    
    check_and_update_index >/dev/null 2>&1 || true

    python3 - <<'PY' "$INDEX_DATA_ROOT"
import json
import os
import sys

root = sys.argv[1]
summary = {
    "total": 0,
    "servers": 0,
    "clients": 0,
    "proxies": 0,
    "size_bytes": 0,
}

for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    summary["total"] += 1
    cfg_type = data.get('type')
    if cfg_type == 'server':
        summary["servers"] += 1
    elif cfg_type == 'client':
        summary["clients"] += 1
    summary["proxies"] += int(data.get('proxy_count') or 0)
    try:
        summary["size_bytes"] += os.path.getsize(path)
    except OSError:
        pass

size_mb = summary["size_bytes"] / (1024 * 1024) if summary["size_bytes"] else 0
print(f"Total configs: {summary['total']} (server: {summary['servers']}, client: {summary['clients']})")
print(f"Total proxies: {summary['proxies']}")
print(f"Metadata size: {size_mb:.2f}MB")
PY
    return 0
}

#==============================================================================
# TAG MANAGEMENT FUNCTIONS
#==============================================================================

query_configs_by_tag() {
    local tag="${1:-}"

    if [[ -z "$tag" ]]; then
        log "ERROR" "tag parameter required"
        return 1
    fi

    if ! check_python3; then
        return 1
    fi

    check_and_update_index >/dev/null 2>&1 || true

    python3 - <<'PY' "$INDEX_DATA_ROOT" "$tag"
import json
import os
import sys

root = sys.argv[1]
tag_query = sys.argv[2]
key = tag_query
value = None
if ':' in tag_query:
    key, value = tag_query.split(':', 1)

results = []
for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    tags = data.get('tags')
    if not isinstance(tags, dict):
        continue
    if key not in tags:
        continue
    if value is not None and str(tags.get(key)) != value:
        continue
    results.append(data.get('path', ''))

for item in results:
    if item:
        print(item)
PY
}

add_config_tag() {
    local config_file="$1"
    local tag_key="$2"
    local tag_value="$3"
    
    if [[ -z "$tag_key" || -z "$tag_value" ]]; then
        log "ERROR" "Both tag key and value are required"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Config file not found: $config_file"
        return 1
    fi
    
    if ! check_python3; then
        return 1
    fi
    
    check_and_update_index >/dev/null 2>&1 || true

    local metadata_path
    metadata_path=$(metadata_path_for_config "$config_file")

    if [[ ! -f "$metadata_path" ]]; then
        log "ERROR" "Config file not indexed: $config_file"
        return 1
    fi
    
    TAG_KEY="$tag_key" TAG_VALUE="$tag_value" python3 - <<'PY' "$metadata_path"
import json
import os
import sys

metadata_path = sys.argv[1]
tag_key = os.environ.get('TAG_KEY')
tag_value = os.environ.get('TAG_VALUE')

try:
    with open(metadata_path, 'r', encoding='utf-8') as fh:
        data = json.load(fh) or {}
except Exception:
    data = {}

tags = data.get('tags')
if not isinstance(tags, dict):
    tags = {}

tags[tag_key] = tag_value

data['tags'] = tags

tmp_path = metadata_path + '.tmp'
with open(tmp_path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
os.replace(tmp_path, metadata_path)
PY

        log "INFO" "Added tag $tag_key:$tag_value to config: $config_file"
        return 0
}

remove_config_tag() {
    local config_file="$1"
    local tag_key="$2"
    
    if [[ -z "$tag_key" ]]; then
        log "ERROR" "Tag key is required"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Config file not found: $config_file"
        return 1
    fi
    
    if ! check_python3; then
        return 1
    fi
    
    local metadata_path
    metadata_path=$(metadata_path_for_config "$config_file")

    if [[ ! -f "$metadata_path" ]]; then
        log "ERROR" "Config file not indexed: $config_file"
        return 1
    fi
    
    TAG_KEY="$tag_key" python3 - <<'PY' "$metadata_path"
import json
import os
import sys

metadata_path = sys.argv[1]
tag_key = os.environ.get('TAG_KEY')

try:
    with open(metadata_path, 'r', encoding='utf-8') as fh:
        data = json.load(fh) or {}
except Exception:
    data = {}

tags = data.get('tags')
if isinstance(tags, dict) and tag_key in tags:
    del tags[tag_key]
    data['tags'] = tags
    tmp_path = metadata_path + '.tmp'
    with open(tmp_path, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write('\n')
    os.replace(tmp_path, metadata_path)
PY

        log "INFO" "Removed tag $tag_key from config: $config_file"
        return 0
}

list_config_tags() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Config file not found: $config_file"
        return 1
    fi
    
    if ! check_python3; then
        return 1
    fi
    
    local metadata_path
    metadata_path=$(metadata_path_for_config "$config_file")
    
    if [[ ! -f "$metadata_path" ]]; then
        log "WARN" "Config file not indexed: $config_file"
        return 1
    fi
    
    python3 - <<'PY' "$metadata_path"
import json
import sys

path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh) or {}
except Exception:
    data = {}

tags = data.get('tags')
if isinstance(tags, dict):
    for key in sorted(tags):
        print(f"{key}:{tags[key]}")
PY
    return 0
}

list_all_tags() {
    if ! check_python3; then
        return 1
    fi
    
    python3 - <<'PY' "$INDEX_DATA_ROOT"
import json
import os
import sys

root = sys.argv[1]
counts = {}
for name in os.listdir(root):
    if not name.endswith('.json'):
        continue
    path = os.path.join(root, name)
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh) or {}
    except Exception:
        continue
    tags = data.get('tags')
    if not isinstance(tags, dict):
        continue
    for key, value in tags.items():
        counts.setdefault((key, str(value)), 0)
        counts[(key, str(value))] += 1

for (key, value), count in sorted(counts.items()):
    print(f"{key}:{value}:{count}")
PY
    return 0
}

bulk_tag_configs() {
    local tag_key="$1"
    local tag_value="$2"
    local filter="$3"
    
    if [[ -z "$tag_key" || -z "$tag_value" ]]; then
        log "ERROR" "Tag key and value are required"
        return 1
    fi
    
    local configs=($(get_configs_by_filter "$filter"))

    log "INFO" "Bulk tagging ${#configs[@]} configuration(s) with $tag_key:$tag_value"

    local updated=0
    for config in "${configs[@]}"; do
        if [[ -n "$config" ]]; then
            if add_config_tag "$config" "$tag_key" "$tag_value" >/dev/null 2>&1; then
                ((updated++))
            fi
        fi
    done
    
    log "INFO" "Bulk tagging complete: $updated updated"
    return 0
}

tag_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}           Tag Management Console            ${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "1. Add tag to config"
        echo "2. Remove tag from config"
        echo "3. List tags for config"
        echo "4. Bulk tag configs"
        echo "5. List all tags"
        echo "6. Show services for tag"
        echo "0. Back"
        echo
        safe_read "Choice" "choice" "0"
        
        case "$choice" in
            1)
                safe_read "Config file path" "cfg" ""
                safe_read "Tag key" "tag_key" ""
                safe_read "Tag value" "tag_value" ""
                if [[ -n "$cfg" && -n "$tag_key" && -n "$tag_value" ]]; then
                    add_config_tag "$cfg" "$tag_key" "$tag_value"
                else
                    log "ERROR" "All fields are required"
                fi
                read -p "Press Enter to continue..."
                ;;
            2)
                safe_read "Config file path" "cfg" ""
                safe_read "Tag key" "tag_key" ""
                if [[ -n "$cfg" && -n "$tag_key" ]]; then
                    remove_config_tag "$cfg" "$tag_key"
                else
                    log "ERROR" "All fields are required"
                fi
                read -p "Press Enter to continue..."
                ;;
            3)
                safe_read "Config file path" "cfg" ""
                if [[ -n "$cfg" ]]; then
                    list_config_tags "$cfg" || true
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                safe_read "Tag key" "tag_key" ""
                safe_read "Tag value" "tag_value" ""
                safe_read "Filter (all | type:client | type:server | tag:key:value | name:pattern)" "filter" "all"
                bulk_tag_configs "$tag_key" "$tag_value" "$filter"
                read -p "Press Enter to continue..."
                ;;
            5)
                list_all_tags || true
                read -p "Press Enter to continue..."
                ;;
            6)
                safe_read "Tag query (key or key:value)" "tag_query" ""
                if [[ -n "$tag_query" ]]; then
                    echo
                    echo "Matching services:"
                    if command -v get_services_by_tag >/dev/null 2>&1; then
                        local services
                        services=($(get_services_by_tag "$tag_query" 2>/dev/null))
                        if [[ ${#services[@]} -eq 0 ]]; then
                            echo "  (none)"
                        else
                            for svc in "${services[@]}"; do
                                echo "  - $svc"
                            done
                        fi
                    else
                        echo "  Tag-based service lookup unavailable"
                    fi
                fi
                read -p "Press Enter to continue..."
                ;;
            0)
                return 0
                ;;
            *)
                log "ERROR" "Invalid choice"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

#==============================================================================
# EXPORTS
#==============================================================================

export -f check_python3 ensure_index_dirs init_config_index index_config_file rebuild_config_index
export -f check_and_update_index verify_index_integrity list_indexed_configs get_config_metadata_json get_config_metadata_field
export -f query_configs_by_type query_total_proxy_count query_configs_by_server_addr get_index_stats
export -f query_configs_by_tag add_config_tag remove_config_tag list_config_tags list_all_tags bulk_tag_configs tag_management_menu

