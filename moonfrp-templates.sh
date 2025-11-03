#!/bin/bash

#==============================================================================
# MoonFRP Configuration Templates Module
# Version: 1.0.0
# Description: Template system for rapid deployment of similar tunnel configurations
#==============================================================================

# Prevent multiple sourcing
if [[ "${MOONFRP_TEMPLATES_LOADED:-}" == "true" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
export MOONFRP_TEMPLATES_LOADED="true"

# Source core functions
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-index.sh"

#==============================================================================
# CONFIGURATION
#==============================================================================

readonly TEMPLATE_DIR="$HOME/.moonfrp/templates"
readonly TEMPLATE_EXT=".toml.tmpl"

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Ensure template directory exists
ensure_template_dir() {
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        mkdir -p "$TEMPLATE_DIR"
        log "DEBUG" "Created template directory: $TEMPLATE_DIR"
    fi
}

# Get template file path
get_template_path() {
    local template_name="$1"
    echo "$TEMPLATE_DIR/${template_name}${TEMPLATE_EXT}"
}

# Check if template exists
template_exists() {
    local template_name="$1"
    local template_path=$(get_template_path "$template_name")
    [[ -f "$template_path" ]]
}

# Extract metadata from template content
extract_template_metadata() {
    local template_content="$1"
    local metadata_type="$2"  # "variables", "tags", "version", "description"
    
    case "$metadata_type" in
        variables)
            echo "$template_content" | grep -E "^#\s*Variables?:" | sed 's/^#\s*Variables\?:\s*//' | tr ',' ' '
            ;;
        tags)
            echo "$template_content" | grep -E "^#\s*Tags?:" | sed 's/^#\s*Tags\?:\s*//' | tr -d ' '
            ;;
        version)
            echo "$template_content" | grep -E "^#\s*Version:" | sed 's/^#\s*Version:\s*//'
            ;;
        description)
            echo "$template_content" | grep -E "^#\s*Template:" | sed 's/^#\s*Template:\s*//'
            ;;
    esac
}

# Parse tags from metadata string
parse_tags() {
    local tags_string="$1"
    if [[ -z "$tags_string" ]]; then
        return 0
    fi
    
    # Tags format: "env:prod, type:client, region:eu"
    # Return array of tag_key:tag_value pairs
    local IFS=','
    local tags_array=()
    
    for tag in $tags_string; do
        tag=$(echo "$tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ "$tag" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$ ]]; then
            tags_array+=("$tag")
        else
            log "WARN" "Invalid tag format: $tag (expected key:value)"
        fi
    done
    
    printf '%s\n' "${tags_array[@]}"
}

# Extract variables from template content
extract_template_variables() {
    local template_content="$1"
    # Find all ${VAR_NAME} patterns
    echo "$template_content" | grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' | sed 's/\${\([^}]*\)}/\1/' | sort -u
}

#==============================================================================
# TEMPLATE CREATION FUNCTIONS
#==============================================================================

# Create a new template from content
create_template() {
    local template_name="$1"
    local template_content="$2"
    
    if [[ -z "$template_name" ]]; then
        log "ERROR" "Template name is required"
        return 1
    fi
    
    if [[ -z "$template_content" ]]; then
        log "ERROR" "Template content is required"
        return 1
    fi
    
    ensure_template_dir
    
    local template_path=$(get_template_path "$template_name")
    
    if [[ -f "$template_path" ]]; then
        log "WARN" "Template already exists: $template_name"
        return 1
    fi
    
    echo "$template_content" > "$template_path"
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "Template created: $template_name"
        return 0
    else
        log "ERROR" "Failed to create template: $template_name"
        return 1
    fi
}

# Create template from file
create_template_from_file() {
    local template_name="$1"
    local source_file="$2"
    
    if [[ ! -f "$source_file" ]]; then
        log "ERROR" "Source file not found: $source_file"
        return 1
    fi
    
    local template_content
    template_content=$(cat "$source_file")
    
    create_template "$template_name" "$template_content"
}

#==============================================================================
# TEMPLATE LISTING FUNCTIONS
#==============================================================================

# List all available templates
list_templates() {
    ensure_template_dir
    
    local templates=()
    
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        return 0
    fi
    
    while IFS= read -r -d '' template_file; do
        local basename=$(basename "$template_file")
        local template_name="${basename%$TEMPLATE_EXT}"
        templates+=("$template_name")
    done < <(find "$TEMPLATE_DIR" -name "*${TEMPLATE_EXT}" -type f -print0 2>/dev/null)
    
    printf '%s\n' "${templates[@]}" | sort
}

# Get template version
get_template_version() {
    local template_name="$1"
    
    if ! template_exists "$template_name"; then
        log "ERROR" "Template not found: $template_name"
        return 1
    fi
    
    local template_path=$(get_template_path "$template_name")
    local template_content
    template_content=$(cat "$template_path")
    
    local version=$(extract_template_metadata "$template_content" "version")
    
    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    else
        echo "1.0"  # Default version
        return 0
    fi
}

#==============================================================================
# VARIABLE SUBSTITUTION FUNCTIONS
#==============================================================================

# Substitute variables in template content
substitute_variables() {
    local template_content="$1"
    shift
    local variables=("$@")  # Array of "KEY=VALUE" pairs
    
    local result="$template_content"
    
    # Build associative array for variable lookup
    declare -A var_map
    for var_pair in "${variables[@]}"; do
        if [[ "$var_pair" =~ ^([^=]+)=(.*)$ ]]; then
            local var_key="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            var_map["$var_key"]="$var_value"
        else
            log "WARN" "Invalid variable format: $var_pair (expected KEY=VALUE)"
        fi
    done
    
    # Substitute all ${VAR_NAME} occurrences
    for var_key in "${!var_map[@]}"; do
        local var_value="${var_map[$var_key]}"
        # Escape special characters for sed (fix: properly escape [ and close character class)
        local escaped_value=$(printf '%s\n' "$var_value" | sed 's/[\[\]\.\*\+\?\|\{\}\(\)\^\$]/\\&/g')
        # Replace ${VAR_KEY} with value
        result=$(echo "$result" | sed "s|\${${var_key}}|${escaped_value}|g")
    done
    
    echo "$result"
}

# Check for unsubstituted variables
check_unsubstituted_variables() {
    local content="$1"
    
    local unsubstituted
    unsubstituted=$(echo "$content" | grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' | sort -u)
    
    if [[ -n "$unsubstituted" ]]; then
        log "WARN" "Unsubstituted variables found:"
        echo "$unsubstituted" | while read -r var; do
            log "WARN" "  $var"
        done
        return 1
    fi
    
    return 0
}

#==============================================================================
# TEMPLATE INSTANTIATION FUNCTIONS
#==============================================================================

# Instantiate a template with variables
instantiate_template() {
    local template_name="$1"
    local output_file="$2"
    shift 2
    local variables=("$@")  # Array of "KEY=VALUE" pairs
    
    if ! template_exists "$template_name"; then
        log "ERROR" "Template not found: $template_name"
        return 1
    fi
    
    local template_path=$(get_template_path "$template_name")
    local template_content
    template_content=$(cat "$template_path")
    
    # Substitute variables
    local instantiated_content
    instantiated_content=$(substitute_variables "$template_content" "${variables[@]}")
    
    # Check for unsubstituted variables (warn but continue)
    check_unsubstituted_variables "$instantiated_content"
    
    # Write to output file
    echo "$instantiated_content" > "$output_file"
    
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to write output file: $output_file"
        return 1
    fi
    
    # Validate generated config
    local config_type="auto"
    if [[ "$output_file" == *"frps"* ]]; then
        config_type="server"
    elif [[ "$output_file" == *"frpc"* ]]; then
        config_type="client"
    fi
    
    if ! validate_config_file "$output_file" "$config_type"; then
        log "ERROR" "Generated config validation failed: $output_file"
        rm -f "$output_file"
        return 1
    fi
    
    # Index the generated config
    if ! index_config_file "$output_file"; then
        log "WARN" "Failed to index generated config: $output_file"
    fi
    
    # Apply tags from template metadata (if add_config_tag exists)
    if command -v add_config_tag &>/dev/null || declare -f add_config_tag &>/dev/null 2>&1; then
        local tags_string=$(extract_template_metadata "$template_content" "tags")
        if [[ -n "$tags_string" ]]; then
            local tags_array
            readarray -t tags_array < <(parse_tags "$tags_string")
            
            for tag_pair in "${tags_array[@]}"; do
                if [[ "$tag_pair" =~ ^([^:]+):(.+)$ ]]; then
                    local tag_key="${BASH_REMATCH[1]}"
                    local tag_value="${BASH_REMATCH[2]}"
                    if add_config_tag "$output_file" "$tag_key" "$tag_value"; then
                        log "DEBUG" "Applied tag: $tag_key:$tag_value to $output_file"
                    else
                        log "WARN" "Failed to apply tag: $tag_key:$tag_value"
                    fi
                fi
            done
        fi
    else
        log "DEBUG" "add_config_tag() not available (Story 2.3 not implemented yet), skipping tag application"
    fi
    
    log "INFO" "Template instantiated: $template_name -> $output_file"
    return 0
}

#==============================================================================
# BULK INSTANTIATION FUNCTIONS
#==============================================================================

# Bulk instantiate template from CSV file
bulk_instantiate_template() {
    local template_name="$1"
    local csv_file="$2"
    
    if ! template_exists "$template_name"; then
        log "ERROR" "Template not found: $template_name"
        return 1
    fi
    
    if [[ ! -f "$csv_file" ]]; then
        log "ERROR" "CSV file not found: $csv_file"
        return 1
    fi
    
    local line_num=0
    local success_count=0
    local error_count=0
    local header_read=false
    local header_vars=()
    local output_file_col=0
    
    while IFS=',' read -r line; do
        ((line_num++))
        
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Read header row
        if [[ "$header_read" == false ]]; then
            IFS=',' read -ra header_fields <<< "$line"
            
            # Find output_file column index
            for i in "${!header_fields[@]}"; do
                local field=$(echo "${header_fields[$i]}" | tr -d ' ')
                if [[ "$field" == "output_file" ]]; then
                    output_file_col=$i
                else
                    header_vars+=("$field")
                fi
            done
            
            header_read=true
            continue
        fi
        
        # Parse data row
        IFS=',' read -ra data_fields <<< "$line"
        
        if [[ ${#data_fields[@]} -lt $((output_file_col + 1)) ]]; then
            log "WARN" "Row $line_num: Insufficient columns, skipping"
            ((error_count++))
            continue
        fi
        
        local output_file=$(echo "${data_fields[$output_file_col]}" | tr -d ' ')
        
        # Build variable array
        local variables=()
        local var_index=0
        for i in "${!data_fields[@]}"; do
            if [[ $i -ne $output_file_col ]]; then
                local var_key="${header_vars[$var_index]}"
                local var_value=$(echo "${data_fields[$i]}" | tr -d ' ')
                if [[ -n "$var_key" ]]; then
                    variables+=("${var_key}=${var_value}")
                fi
                ((var_index++))
            fi
        done
        
        # Instantiate template
        if instantiate_template "$template_name" "$output_file" "${variables[@]}"; then
            ((success_count++))
        else
            log "ERROR" "Row $line_num: Failed to instantiate $output_file"
            ((error_count++))
        fi
    done < "$csv_file"
    
    log "INFO" "Bulk instantiation complete: $success_count succeeded, $error_count failed"
    
    if [[ $error_count -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

#==============================================================================
# TEMPLATE MANAGEMENT FUNCTIONS
#==============================================================================

# View template content
view_template() {
    local template_name="$1"
    
    if ! template_exists "$template_name"; then
        log "ERROR" "Template not found: $template_name"
        return 1
    fi
    
    local template_path=$(get_template_path "$template_name")
    cat "$template_path"
}

# Delete template
delete_template() {
    local template_name="$1"
    
    if ! template_exists "$template_name"; then
        log "ERROR" "Template not found: $template_name"
        return 1
    fi
    
    local template_path=$(get_template_path "$template_name")
    
    if rm -f "$template_path"; then
        log "INFO" "Template deleted: $template_name"
        return 0
    else
        log "ERROR" "Failed to delete template: $template_name"
        return 1
    fi
}

#==============================================================================
# INTERACTIVE MENU
#==============================================================================

# Interactive template management menu
template_management_menu() {
    while true; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Template Management"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "1) List templates"
        echo "2) Create template"
        echo "3) Instantiate template"
        echo "4) Bulk instantiate from CSV"
        echo "5) View template"
        echo "6) Delete template"
        echo "7) Show template version"
        echo "8) Back to main menu"
        echo ""
        read -p "Select option: " choice
        
        case "$choice" in
            1)
                echo ""
                echo "Available templates:"
                list_templates | while read -r template; do
                    echo "  - $template"
                done
                ;;
            2)
                read -p "Template name: " template_name
                read -p "Template file path (or press Enter to create from editor): " template_file
                
                if [[ -n "$template_file" && -f "$template_file" ]]; then
                    create_template_from_file "$template_name" "$template_file"
                else
                    echo "Please provide template content (end with EOF on a new line):"
                    local temp_file=$(mktemp)
                    cat > "$temp_file"
                    create_template_from_file "$template_name" "$temp_file"
                    rm -f "$temp_file"
                fi
                ;;
            3)
                read -p "Template name: " template_name
                read -p "Output file path: " output_file
                
                echo "Enter variables (format: KEY=VALUE, one per line, empty line to finish):"
                local variables=()
                while IFS= read -r var_line; do
                    [[ -z "$var_line" ]] && break
                    variables+=("$var_line")
                done
                
                instantiate_template "$template_name" "$output_file" "${variables[@]}"
                ;;
            4)
                read -p "Template name: " template_name
                read -p "CSV file path: " csv_file
                
                bulk_instantiate_template "$template_name" "$csv_file"
                ;;
            5)
                read -p "Template name: " template_name
                echo ""
                view_template "$template_name"
                ;;
            6)
                read -p "Template name: " template_name
                read -p "Are you sure? (yes/no): " confirm
                if [[ "$confirm" == "yes" ]]; then
                    delete_template "$template_name"
                fi
                ;;
            7)
                read -p "Template name: " template_name
                local version=$(get_template_version "$template_name")
                echo "Template version: $version"
                ;;
            8)
                return 0
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

# Export functions
export -f ensure_template_dir get_template_path template_exists
export -f extract_template_metadata parse_tags extract_template_variables
export -f create_template create_template_from_file
export -f list_templates get_template_version
export -f substitute_variables check_unsubstituted_variables
export -f instantiate_template
export -f bulk_instantiate_template
export -f view_template delete_template template_management_menu

