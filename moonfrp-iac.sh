#!/bin/bash

#==============================================================================
# MoonFRP Infrastructure as Code (IaC) Module
# Version: 1.0.0
# Description: Export and import MoonFRP configurations as YAML for version control
#==============================================================================

# Prevent multiple sourcing
if [[ "${MOONFRP_IAC_LOADED:-}" == "true" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
export MOONFRP_IAC_LOADED="true"

# Source core helpers
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-index.sh"

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

# Check if yq is available
check_yq() {
    if command -v yq >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Validate YAML file using yq with fallback to basic syntax check
validate_yaml_file() {
    local yaml_file="$1"
    
    if [[ ! -f "$yaml_file" ]]; then
        log "ERROR" "YAML file not found: $yaml_file"
        return 1
    fi
    
    if check_yq; then
        if yq eval '.' "$yaml_file" >/dev/null 2>&1; then
            log "DEBUG" "YAML validation passed (yq)"
            return 0
        else
            log "ERROR" "YAML validation failed (yq): Invalid YAML syntax"
            return 1
        fi
    else
        log "WARN" "yq not available, using basic YAML syntax check"
        # Basic YAML validation: check for balanced brackets and basic structure
        local line_count
        line_count=$(wc -l < "$yaml_file" 2>/dev/null || echo "0")
        if [[ $line_count -eq 0 ]]; then
            log "ERROR" "YAML file is empty"
            return 1
        fi
        # Check for basic YAML structure (at least one key-value pair or list)
        if grep -qE '^[a-zA-Z_][a-zA-Z0-9_]*:' "$yaml_file" 2>/dev/null; then
            log "DEBUG" "YAML validation passed (basic check)"
            return 0
        else
            log "ERROR" "YAML validation failed: No valid YAML structure found"
            return 1
        fi
    fi
}

# Convert TOML to YAML representation (basic conversion)
toml_to_yaml_value() {
    local toml_value="$1"
    # Remove quotes if present
    toml_value=$(echo "$toml_value" | sed -E "s/^[\"']|[\"']$//g")
    # Handle boolean values
    if [[ "$toml_value" == "true" ]] || [[ "$toml_value" == "false" ]]; then
        echo "$toml_value"
    # Handle numeric values
    elif [[ "$toml_value" =~ ^[0-9]+$ ]]; then
        echo "$toml_value"
    # Handle strings (quote if contains special chars)
    else
        if echo "$toml_value" | grep -q '[:"'\''\[\]\{\} ]'; then
            echo "\"$toml_value\""
        else
            echo "$toml_value"
        fi
    fi
}

# Export server configuration to YAML structure
export_server_yaml() {
    local config_file="$1"
    local indent="${2:-0}"
    local indent_str=""
    local i
    for ((i=0; i<indent; i++)); do
        indent_str="${indent_str}  "
    done
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    local basename_file
    basename_file=$(basename "$config_file")
    
    echo "${indent_str}type: server"
    echo "${indent_str}file: $basename_file"
    echo "${indent_str}content: |"
    
    # Read TOML file and indent each line
    while IFS= read -r line; do
        echo "${indent_str}  $line"
    done < "$config_file"
    
    # Export metadata if available
    local metadata
    if metadata=$(get_config_metadata_json "$config_file" 2>/dev/null); then
        local tags
        tags=$(echo "$metadata" | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('tags', {})))" 2>/dev/null || echo "{}")
        if [[ "$tags" != "{}" ]] && [[ -n "$tags" ]]; then
            echo "${indent_str}tags:"
            local indent_py="$indent_str"
            echo "$tags" | python3 - "$indent_py" <<'PYEOF'
import sys, json
indent = sys.argv[1]
data = json.load(sys.stdin)
for k, v in sorted(data.items()):
    print(indent + "  " + str(k) + ": " + str(v))
PYEOF
        fi
    fi
}

# Export client configuration to YAML structure
export_client_yaml() {
    local config_file="$1"
    local indent="${2:-0}"
    local indent_str=""
    local i
    for ((i=0; i<indent; i++)); do
        indent_str="${indent_str}  "
    done
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    local basename_file
    basename_file=$(basename "$config_file")
    
    echo "${indent_str}type: client"
    echo "${indent_str}file: $basename_file"
    echo "${indent_str}content: |"
    
    # Read TOML file and indent each line
    while IFS= read -r line; do
        echo "${indent_str}  $line"
    done < "$config_file"
    
    # Export metadata if available
    local metadata
    if metadata=$(get_config_metadata_json "$config_file" 2>/dev/null); then
        local tags
        tags=$(echo "$metadata" | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('tags', {})))" 2>/dev/null || echo "{}")
        if [[ "$tags" != "{}" ]] && [[ -n "$tags" ]]; then
            echo "${indent_str}tags:"
            local indent_py="$indent_str"
            echo "$tags" | python3 - "$indent_py" <<'PYEOF'
import sys, json
indent = sys.argv[1]
data = json.load(sys.stdin)
for k, v in sorted(data.items()):
    print(indent + "  " + str(k) + ": " + str(v))
PYEOF
        fi
    fi
}

# Export all configurations to a single YAML file
export_config_yaml() {
    local output_file="${1:-moonfrp-configs.yaml}"
    local start_time
    start_time=$(date +%s)
    
    log "INFO" "Exporting all configurations to $output_file"
    
    # Ensure index is up to date
    check_and_update_index >/dev/null 2>&1 || true
    
    # Create backup directory structure
    local backup_dir
    backup_dir=$(dirname "$output_file")
    if [[ -n "$backup_dir" ]] && [[ "$backup_dir" != "." ]]; then
        mkdir -p "$backup_dir"
    fi
    
    # Write YAML header
    cat > "$output_file" <<EOF
# MoonFRP Configuration Export
# Generated: $(date -Iseconds)
# Version: 1.0

configs:
EOF
    
    local exported_count=0
    local server_count=0
    local client_count=0
    
    # Export server configs
    while IFS= read -r config_file; do
        if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
            echo "  -" >> "$output_file"
            export_server_yaml "$config_file" 2 >> "$output_file"
            ((exported_count++))
            ((server_count++))
        fi
    done < <(query_configs_by_type "server" 2>/dev/null || find "$CONFIG_DIR" -name "frps*.toml" -type f 2>/dev/null | sort)
    
    # Export client configs
    while IFS= read -r config_file; do
        if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
            echo "  -" >> "$output_file"
            export_client_yaml "$config_file" 2 >> "$output_file"
            ((exported_count++))
            ((client_count++))
        fi
    done < <(query_configs_by_type "client" 2>/dev/null || find "$CONFIG_DIR" -name "frpc*.toml" -type f 2>/dev/null | sort)
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "INFO" "Export complete: $exported_count configs ($server_count servers, $client_count clients) in ${duration}s"
    
    # Performance validation: fail if exceeds 2s for 50+ configs
    if [[ $exported_count -ge 50 ]] && [[ $duration -gt 2 ]]; then
        log "ERROR" "Export performance requirement not met: ${duration}s (target: <2s for 50 configs)"
        return 1
    elif [[ $duration -gt 2 ]]; then
        log "WARN" "Export took ${duration}s (target: <2s for 50 configs)"
    fi
    
    return 0
}

# Import configurations from YAML file
import_config_yaml() {
    local yaml_file="$1"
    local import_type="${2:-all}"  # all, server, client
    local dry_run="${3:-false}"
    
    if [[ ! -f "$yaml_file" ]]; then
        log "ERROR" "YAML file not found: $yaml_file"
        return 1
    fi
    
    # Validate YAML
    if ! validate_yaml_file "$yaml_file"; then
        log "ERROR" "YAML validation failed, aborting import"
        return 1
    fi
    
    log "INFO" "Importing configurations from $yaml_file (type: $import_type, dry-run: $dry_run)"
    
    # Create backup before import
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$CONFIG_DIR/backups/pre-import-$backup_timestamp"
    
    if [[ "$dry_run" != "true" ]]; then
        mkdir -p "$backup_dir"
        log "INFO" "Creating backup in $backup_dir"
        
        # Backup all existing configs
        while IFS= read -r config_file; do
            if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
                local backup_file="$backup_dir/$(basename "$config_file")"
                cp "$config_file" "$backup_file" 2>/dev/null || true
            fi
        done < <(find "$CONFIG_DIR" -name "*.toml" -type f 2>/dev/null)
        
        log "INFO" "Backup created successfully"
    else
        log "INFO" "DRY-RUN mode: No changes will be made"
    fi
    
    local imported_count=0
    local skipped_count=0
    local error_count=0
    local failed_files=()
    
    # Parse YAML and import configs
    if check_yq; then
        # Use yq for parsing
        local config_count
        config_count=$(yq eval '.configs | length' "$yaml_file" 2>/dev/null || echo "0")
        
        for ((i=0; i<config_count; i++)); do
            local config_type
            config_type=$(yq eval ".configs[$i].type" "$yaml_file" 2>/dev/null || echo "")
            local config_file_name
            config_file_name=$(yq eval ".configs[$i].file" "$yaml_file" 2>/dev/null || echo "")
            local config_content
            config_content=$(yq eval ".configs[$i].content" "$yaml_file" 2>/dev/null || echo "")
            local config_tags
            config_tags=$(yq eval ".configs[$i].tags // {}" "$yaml_file" 2>/dev/null || echo "{}")
            
            # Filter by type if specified
            if [[ "$import_type" != "all" ]] && [[ "$config_type" != "$import_type" ]]; then
                ((skipped_count++))
                continue
            fi
            
            local target_file="$CONFIG_DIR/$config_file_name"
            
            if [[ "$dry_run" == "true" ]]; then
                log "INFO" "[DRY-RUN] Would import $config_type config: $config_file_name"
                ((imported_count++))
            else
                # Write config content
                if ! echo "$config_content" > "$target_file" 2>/dev/null; then
                    log "ERROR" "Failed to write config file: $config_file_name"
                    ((error_count++))
                    failed_files+=("$target_file")
                    continue
                fi
                
                # Index the config
                if ! index_config_file "$target_file" >/dev/null 2>&1; then
                    log "WARN" "Failed to index config: $config_file_name (non-critical)"
                fi
                
                # Apply tags if present
                if [[ "$config_tags" != "{}" ]] && [[ -n "$config_tags" ]]; then
                    local tag_errors=0
                    local tag_output
                    tag_output=$(echo "$config_tags" | python3 -c "
import sys, json
tags = json.load(sys.stdin)
for key, value in tags.items():
    print(f'{key}:{value}')
" 2>/dev/null)
                    
                    while IFS=: read -r tag_key tag_value; do
                        if [[ -n "$tag_key" ]] && [[ -n "$tag_value" ]]; then
                            if ! add_config_tag "$target_file" "$tag_key" "$tag_value" >/dev/null 2>&1; then
                                log "WARN" "Failed to apply tag $tag_key:$tag_value to $config_file_name"
                                ((tag_errors++))
                            fi
                        fi
                    done <<< "$tag_output"
                    
                    if [[ $tag_errors -gt 0 ]]; then
                        log "WARN" "$tag_errors tag(s) failed to apply for $config_file_name (non-critical)"
                    fi
                fi
                
                log "DEBUG" "Imported $config_type config: $config_file_name"
                ((imported_count++))
            fi
        done
    else
        # Fallback: Try Python with PyYAML, or provide clear error
        if ! python3 -c "import yaml" 2>/dev/null; then
            log "ERROR" "Neither yq nor PyYAML is available. Please install one of them:"
            log "ERROR" "  - yq: https://github.com/mikefarah/yq"
            log "ERROR" "  - PyYAML: pip3 install pyyaml"
            return 1
        fi
        
        # Use Python with PyYAML for parsing
        local result
        result=$(python3 - "$yaml_file" "$import_type" "$dry_run" "$CONFIG_DIR" <<'PY'
import sys
import yaml
import os

yaml_file = sys.argv[1]
import_type = sys.argv[2]
dry_run = sys.argv[3] == "true"
config_dir = sys.argv[4]

try:
    with open(yaml_file, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
except Exception as e:
    print(f"ERROR: Failed to parse YAML: {e}", file=sys.stderr)
    sys.exit(1)

configs = data.get('configs', [])
imported = 0
skipped = 0

for cfg in configs:
    cfg_type = cfg.get('type', '')
    cfg_file = cfg.get('file', '')
    cfg_content = cfg.get('content', '')
    cfg_tags = cfg.get('tags', {})
    
    if import_type != 'all' and cfg_type != import_type:
        skipped += 1
        continue
    
    target_file = os.path.join(config_dir, cfg_file)
    
    if dry_run:
        print(f"INFO: [DRY-RUN] Would import {cfg_type} config: {cfg_file}")
        imported += 1
    else:
        try:
            with open(target_file, 'w', encoding='utf-8') as f:
                f.write(cfg_content)
            imported += 1
            print(f"DEBUG: Imported {cfg_type} config: {cfg_file}")
        except Exception as e:
            print(f"ERROR: Failed to import {cfg_file}: {e}", file=sys.stderr)

print(f"IMPORTED:{imported}")
print(f"SKIPPED:{skipped}")
PY
)
        if [[ $? -ne 0 ]]; then
            log "ERROR" "Failed to parse YAML file"
            return 1
        fi
        
        imported_count=$(echo "$result" | grep "^IMPORTED:" | cut -d: -f2 || echo "0")
        skipped_count=$(echo "$result" | grep "^SKIPPED:" | cut -d: -f2 || echo "0")
        # Count errors from Python output
        local python_errors
        python_errors=$(echo "$result" | grep -c "^ERROR:" || echo "0")
        error_count=$((error_count + python_errors))
    fi
    
    # Rollback on failure if backup exists and errors occurred
    if [[ "$dry_run" != "true" ]] && [[ $error_count -gt 0 ]] && [[ -d "$backup_dir" ]]; then
        log "ERROR" "Import failed with $error_count error(s). Rolling back to previous state..."
        
        # Restore all files from backup
        local rollback_success=true
        while IFS= read -r backup_file; do
            if [[ -n "$backup_file" ]] && [[ -f "$backup_file" ]]; then
                local original_file="$CONFIG_DIR/$(basename "$backup_file")"
                if ! cp "$backup_file" "$original_file" 2>/dev/null; then
                    log "ERROR" "Failed to restore: $(basename "$backup_file")"
                    rollback_success=false
                else
                    log "DEBUG" "Restored: $(basename "$backup_file")"
                fi
            fi
        done < <(find "$backup_dir" -name "*.toml" -type f 2>/dev/null)
        
        if [[ "$rollback_success" == "true" ]]; then
            log "INFO" "Rollback completed successfully. All configs restored from backup."
        else
            log "ERROR" "Rollback partially failed. Manual intervention may be required."
            log "INFO" "Backup location: $backup_dir"
        fi
        
        # Rebuild index after rollback
        rebuild_config_index >/dev/null 2>&1 || true
        
        return 1
    fi
    
    if [[ "$dry_run" != "true" ]]; then
        # Rebuild index after import
        log "INFO" "Rebuilding config index..."
        rebuild_config_index >/dev/null 2>&1 || true
        log "INFO" "Index rebuild complete"
    fi
    
    log "INFO" "Import complete: $imported_count imported, $skipped_count skipped"
    
    if [[ $error_count -gt 0 ]]; then
        log "WARN" "$error_count errors occurred during import"
        return 1
    fi
    
    return 0
}

#==============================================================================
# CLI FUNCTIONS
#==============================================================================

# Export command handler
moonfrp_export() {
    local output_file="${1:-moonfrp-configs.yaml}"
    
    if ! export_config_yaml "$output_file"; then
        log "ERROR" "Export failed"
        return 1
    fi
    
    log "INFO" "Configuration exported to: $output_file"
    return 0
}

# Import command handler
moonfrp_import() {
    local yaml_file="${1:-}"
    local import_type="${2:-all}"
    local dry_run="${3:-false}"
    
    if [[ -z "$yaml_file" ]]; then
        log "ERROR" "YAML file path required"
        echo "Usage: moonfrp import <yaml-file> [server|client|all] [--dry-run]"
        return 1
    fi
    
    # Check for --dry-run flag
    if [[ "$import_type" == "--dry-run" ]] || [[ "$dry_run" == "--dry-run" ]]; then
        dry_run="true"
        if [[ "$import_type" == "--dry-run" ]]; then
            import_type="all"
        fi
    fi
    
    if ! import_config_yaml "$yaml_file" "$import_type" "$dry_run"; then
        log "ERROR" "Import failed"
        return 1
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log "INFO" "Dry-run completed. Use without --dry-run to apply changes."
    else
        log "INFO" "Configuration imported from: $yaml_file"
    fi
    
    return 0
}

#==============================================================================
# EXPORTS
#==============================================================================

export -f validate_yaml_file export_config_yaml export_server_yaml export_client_yaml
export -f import_config_yaml moonfrp_export moonfrp_import check_yq

