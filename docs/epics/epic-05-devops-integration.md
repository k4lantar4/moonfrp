# Epic 5: DevOps Integration

**Epic ID:** MOONFRP-E05  
**Priority:** P2 - Automation Enablers  
**Estimated Effort:** 3-4 days  
**Dependencies:** Epic 1 (config index), Epic 2 (bulk ops)  
**Target Release:** v2.0.0-rc.1

---

## Epic Goal

Enable full automation and infrastructure-as-code workflows by providing non-interactive CLI modes, configuration export/import capabilities, structured logging for machine parsing, and idempotent operations suitable for CI/CD pipelines.

## Success Criteria

- ✅ All operations work non-interactively with `--yes` flag
- ✅ Configuration export/import in YAML format
- ✅ Idempotent operations (safe to run multiple times)
- ✅ Structured JSON logging option
- ✅ Exit codes suitable for scripting (0=success, non-zero=failure)
- ✅ CI/CD pipeline compatibility
- ✅ Zero manual intervention required

---

## Story 5.1: Configuration as Code (Export/Import)

**Story ID:** MOONFRP-E05-S01  
**Priority:** P2  
**Effort:** 1.5 days

### Problem Statement

DevOps teams need to version control MoonFRP configurations and deploy them consistently across environments. Manual config management doesn't scale and isn't auditable.

### Acceptance Criteria

1. Export all configs to single YAML file
2. Import YAML file recreates exact configuration
3. Idempotent: running import twice produces same result
4. Supports partial imports (specific configs only)
5. Validates YAML before import
6. Git-friendly format (readable diffs)
7. Export/import completes in <2s for 50 configs

### Technical Specification

**Location:** New file `moonfrp-iac.sh` (Infrastructure as Code)

**YAML Format:**
```yaml
# moonfrp-config.yaml
version: "2.0"
generated: "2025-11-02T14:30:00Z"

server:
  bind_port: 7000
  auth_token: "your-secret-token-here"
  dashboard_port: 7500
  tags:
    env: "prod"
    region: "iran"

clients:
  - name: "eu-1"
    server_addr: "192.168.1.100"
    server_port: 7000
    auth_token: "your-secret-token-here"
    proxies:
      - name: "web-eu-1"
        type: "tcp"
        local_ip: "127.0.0.1"
        local_port: 8080
        remote_port: 30001
    tags:
      env: "prod"
      region: "eu"
  
  - name: "us-1"
    server_addr: "10.0.1.50"
    server_port: 7000
    auth_token: "your-secret-token-here"
    proxies:
      - name: "web-us-1"
        type: "tcp"
        local_ip: "127.0.0.1"
        local_port: 8080
        remote_port: 30002
    tags:
      env: "prod"
      region: "us"
```

**Implementation:**
```bash
#!/bin/bash
# moonfrp-iac.sh - Infrastructure as Code module

source "$(dirname "${BASH_SOURCE[0]}")/moonfrp-core.sh"

# Export configuration to YAML
export_config_yaml() {
    local output_file="${1:-moonfrp-config.yaml}"
    local db_path="$HOME/.moonfrp/index.db"
    
    log "INFO" "Exporting configuration to: $output_file"
    
    # Start YAML file
    cat > "$output_file" <<EOF
# MoonFRP Configuration Export
# Generated: $(date -Iseconds)
# Version: $MOONFRP_VERSION

version: "2.0"
generated: "$(date -Iseconds)"

EOF
    
    # Export server config
    if [[ -f "$CONFIG_DIR/frps.toml" ]]; then
        export_server_yaml "$CONFIG_DIR/frps.toml" >> "$output_file"
    fi
    
    # Export client configs
    echo "clients:" >> "$output_file"
    
    local client_configs=($(find "$CONFIG_DIR" -name "frpc*.toml" -type f | sort))
    for config in "${client_configs[@]}"; do
        export_client_yaml "$config" >> "$output_file"
    done
    
    log "INFO" "Export complete: $output_file"
    return 0
}

# Export server config to YAML
export_server_yaml() {
    local config_file="$1"
    
    local bind_port=$(get_toml_value "$config_file" "bindPort" | tr -d '"')
    local auth_token=$(get_toml_value "$config_file" "auth.token" | sed 's/["'\'']//g')
    local dashboard_port=$(get_toml_value "$config_file" "webServer.port" | tr -d '"')
    
    # Get tags
    local tags=$(list_config_tags "$config_file" 2>/dev/null)
    
    cat <<EOF
server:
  bind_port: $bind_port
  auth_token: "$auth_token"
  dashboard_port: ${dashboard_port:-7500}
EOF
    
    if [[ -n "$tags" ]]; then
        echo "  tags:"
        while IFS=':' read -r key value; do
            echo "    $key: \"$value\""
        done <<< "$tags"
    fi
    echo
}

# Export client config to YAML
export_client_yaml() {
    local config_file="$1"
    local config_name=$(basename "$config_file" .toml | sed 's/^frpc-//')
    
    local server_addr=$(get_toml_value "$config_file" "serverAddr" | sed 's/["'\'']//g')
    local server_port=$(get_toml_value "$config_file" "serverPort" | tr -d '"')
    local auth_token=$(get_toml_value "$config_file" "auth.token" | sed 's/["'\'']//g')
    
    cat <<EOF
  - name: "$config_name"
    server_addr: "$server_addr"
    server_port: $server_port
    auth_token: "$auth_token"
    proxies:
EOF
    
    # Export proxies
    local proxy_count=$(grep -c '^\[\[proxies\]\]' "$config_file")
    
    # Parse proxies (simplified - actual implementation would be more robust)
    awk '
    /^\[\[proxies\]\]/ { in_proxy=1; next }
    in_proxy && /^name/ { gsub(/["'\'']/, "", $3); print "      - name: \"" $3 "\"" }
    in_proxy && /^type/ { gsub(/["'\'']/, "", $3); print "        type: \"" $3 "\"" }
    in_proxy && /^localIP/ { gsub(/["'\'']/, "", $3); print "        local_ip: \"" $3 "\"" }
    in_proxy && /^localPort/ { print "        local_port: " $3 }
    in_proxy && /^remotePort/ { print "        remote_port: " $3; in_proxy=0 }
    ' "$config_file"
    
    # Tags
    local tags=$(list_config_tags "$config_file" 2>/dev/null)
    if [[ -n "$tags" ]]; then
        echo "    tags:"
        while IFS=':' read -r key value; do
            echo "      $key: \"$value\""
        done <<< "$tags"
    fi
    echo
}

# Import configuration from YAML
import_config_yaml() {
    local input_file="$1"
    local dry_run="${2:-false}"
    
    if [[ ! -f "$input_file" ]]; then
        log "ERROR" "Config file not found: $input_file"
        return 1
    fi
    
    log "INFO" "Importing configuration from: $input_file"
    
    # Validate YAML
    if ! validate_yaml_file "$input_file"; then
        log "ERROR" "Invalid YAML format"
        return 1
    fi
    
    # Dry-run mode
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY-RUN MODE - Preview changes${NC}"
        preview_yaml_import "$input_file"
        return 0
    fi
    
    # Backup existing configs
    backup_all_configs
    
    # Import server config
    import_server_from_yaml "$input_file" || {
        log "ERROR" "Failed to import server config"
        return 1
    }
    
    # Import client configs
    import_clients_from_yaml "$input_file" || {
        log "ERROR" "Failed to import client configs"
        return 1
    }
    
    # Rebuild index
    rebuild_config_index
    
    log "INFO" "Import complete"
    return 0
}

# Validate YAML file
validate_yaml_file() {
    local yaml_file="$1"
    
    # Check if yq is available
    if command -v yq &>/dev/null; then
        yq eval '.' "$yaml_file" > /dev/null 2>&1
        return $?
    fi
    
    # Fallback: basic syntax check
    if ! grep -q "^version:" "$yaml_file"; then
        log "ERROR" "Missing 'version' field"
        return 1
    fi
    
    return 0
}

# Import server config from YAML
import_server_from_yaml() {
    local yaml_file="$1"
    
    if ! command -v yq &>/dev/null; then
        log "ERROR" "yq required for YAML import. Install: sudo apt install yq"
        return 1
    fi
    
    # Extract server config
    local bind_port=$(yq eval '.server.bind_port' "$yaml_file")
    local auth_token=$(yq eval '.server.auth_token' "$yaml_file")
    local dashboard_port=$(yq eval '.server.dashboard_port' "$yaml_file")
    
    if [[ "$bind_port" == "null" ]]; then
        log "WARN" "No server config in YAML. Skipping."
        return 0
    fi
    
    # Generate TOML config
    local config_file="$CONFIG_DIR/frps.toml"
    
    cat > "$config_file" <<EOF
bindPort = $bind_port

[auth]
token = "$auth_token"

[webServer]
addr = "0.0.0.0"
port = ${dashboard_port:-7500}
user = "admin"
password = "admin"
EOF
    
    # Validate and index
    validate_config_file "$config_file" || return 1
    index_config_file "$config_file"
    
    # Apply tags
    local tag_count=$(yq eval '.server.tags | length' "$yaml_file")
    if [[ "$tag_count" != "0" && "$tag_count" != "null" ]]; then
        yq eval '.server.tags | to_entries | .[] | .key + ":" + .value' "$yaml_file" | while read -r tag; do
            local key="${tag%:*}"
            local value="${tag#*:}"
            add_config_tag "$config_file" "$key" "$value"
        done
    fi
    
    log "INFO" "Server config imported"
    return 0
}

# Import client configs from YAML
import_clients_from_yaml() {
    local yaml_file="$1"
    
    local client_count=$(yq eval '.clients | length' "$yaml_file")
    
    if [[ "$client_count" == "0" || "$client_count" == "null" ]]; then
        log "WARN" "No client configs in YAML"
        return 0
    fi
    
    log "INFO" "Importing $client_count client configs..."
    
    for i in $(seq 0 $((client_count - 1))); do
        import_single_client "$yaml_file" "$i" || {
            log "ERROR" "Failed to import client $i"
            return 1
        }
    done
    
    return 0
}

# Import single client config
import_single_client() {
    local yaml_file="$1"
    local index="$2"
    
    local name=$(yq eval ".clients[$index].name" "$yaml_file")
    local server_addr=$(yq eval ".clients[$index].server_addr" "$yaml_file")
    local server_port=$(yq eval ".clients[$index].server_port" "$yaml_file")
    local auth_token=$(yq eval ".clients[$index].auth_token" "$yaml_file")
    
    local config_file="$CONFIG_DIR/frpc-${name}.toml"
    
    # Generate TOML
    cat > "$config_file" <<EOF
serverAddr = "$server_addr"
serverPort = $server_port

[auth]
token = "$auth_token"

user = "moonfrp-$name"

EOF
    
    # Import proxies
    local proxy_count=$(yq eval ".clients[$index].proxies | length" "$yaml_file")
    
    for j in $(seq 0 $((proxy_count - 1))); do
        local proxy_name=$(yq eval ".clients[$index].proxies[$j].name" "$yaml_file")
        local proxy_type=$(yq eval ".clients[$index].proxies[$j].type" "$yaml_file")
        local local_ip=$(yq eval ".clients[$index].proxies[$j].local_ip" "$yaml_file")
        local local_port=$(yq eval ".clients[$index].proxies[$j].local_port" "$yaml_file")
        local remote_port=$(yq eval ".clients[$index].proxies[$j].remote_port" "$yaml_file")
        
        cat >> "$config_file" <<EOF
[[proxies]]
name = "$proxy_name"
type = "$proxy_type"
localIP = "$local_ip"
localPort = $local_port
remotePort = $remote_port

EOF
    done
    
    # Validate and index
    validate_config_file "$config_file" || return 1
    index_config_file "$config_file"
    
    # Apply tags
    local tag_count=$(yq eval ".clients[$index].tags | length" "$yaml_file")
    if [[ "$tag_count" != "0" && "$tag_count" != "null" ]]; then
        yq eval ".clients[$index].tags | to_entries | .[] | .key + \":\" + .value" "$yaml_file" | while read -r tag; do
            local key="${tag%:*}"
            local value="${tag#*:}"
            add_config_tag "$config_file" "$key" "$value"
        done
    fi
    
    log "INFO" "Client config imported: $name"
    return 0
}

# CLI integration
moonfrp_export() {
    export_config_yaml "${1:-moonfrp-config.yaml}"
}

moonfrp_import() {
    local file="$1"
    local dry_run="${2:-false}"
    
    import_config_yaml "$file" "$dry_run"
}

export -f export_config_yaml import_config_yaml moonfrp_export moonfrp_import
```

**CLI Usage:**
```bash
# Export current config
moonfrp export config.yaml

# Preview import (dry-run)
moonfrp import config.yaml --dry-run

# Apply import
moonfrp import config.yaml

# Idempotent - run multiple times safely
moonfrp import config.yaml  # No changes if already applied
```

### Testing Requirements

```bash
test_export_all_configs_to_yaml()
test_import_yaml_creates_configs()
test_import_idempotent()
test_import_validation()
test_export_import_roundtrip()
test_partial_import()
test_yaml_git_friendly_format()
```

### Rollback Strategy

Import uses standard backup system from Epic 1. Failed import triggers automatic rollback to previous configs.

---

## Story 5.2: Non-Interactive CLI Mode

**Story ID:** MOONFRP-E05-S02  
**Priority:** P2  
**Effort:** 1 day

### Problem Statement

Automation scripts and CI/CD pipelines cannot handle interactive prompts. All operations must support non-interactive execution with proper exit codes.

### Acceptance Criteria

1. `--yes` / `-y` flag bypasses all confirmations
2. `--quiet` / `-q` flag suppresses non-essential output
3. Exit code 0 for success, non-zero for failure
4. Specific exit codes for different failures (1=general, 2=validation, 3=permission, etc.)
5. Operations timeout after reasonable duration (no hanging)
6. All menu-driven functions accessible via CLI arguments
7. Help text for all commands: `moonfrp <command> --help`

### Technical Specification

**Location:** `moonfrp.sh` - CLI argument parsing

**Implementation:**
```bash
#!/bin/bash
# moonfrp.sh - Main entry point with CLI support

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_VALIDATION_ERROR=2
readonly EXIT_PERMISSION_ERROR=3
readonly EXIT_NOT_FOUND=4
readonly EXIT_TIMEOUT=5

# Global flags
MOONFRP_YES=false
MOONFRP_QUIET=false
MOONFRP_TIMEOUT=300  # 5 minutes default

# Parse global flags
parse_global_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                MOONFRP_YES=true
                shift
                ;;
            -q|--quiet)
                MOONFRP_QUIET=true
                shift
                ;;
            --timeout)
                MOONFRP_TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    export MOONFRP_YES MOONFRP_QUIET MOONFRP_TIMEOUT
}

# Override safe_read for non-interactive mode
safe_read() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    
    if [[ "$MOONFRP_YES" == "true" ]]; then
        # Non-interactive: use default or 'y' for confirmations
        if [[ "$prompt" == *"(y/N)"* ]] || [[ "$prompt" == *"(Y/n)"* ]]; then
            eval "$var_name='y'"
        else
            eval "$var_name='$default'"
        fi
        return 0
    fi
    
    # Interactive: normal read
    read -p "$prompt: " "$var_name"
    
    if [[ -z "${!var_name}" ]]; then
        eval "$var_name='$default'"
    fi
}

# Override log for quiet mode
log() {
    local level="$1"
    shift
    local message="$@"
    
    if [[ "$MOONFRP_QUIET" == "true" ]]; then
        # Quiet mode: only errors
        [[ "$level" == "ERROR" ]] && echo "ERROR: $message" >&2
        return
    fi
    
    # Normal logging
    case "$level" in
        INFO) echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
    esac
}

# CLI command dispatcher
main() {
    parse_global_flags "$@"
    
    local command="$1"
    shift
    
    # Set timeout
    if [[ -n "$MOONFRP_TIMEOUT" ]]; then
        trap 'log "ERROR" "Operation timed out"; exit $EXIT_TIMEOUT' ALRM
        (sleep "$MOONFRP_TIMEOUT" && kill -ALRM $$) 2>/dev/null &
        local timeout_pid=$!
    fi
    
    case "$command" in
        # Service management
        start)
            bulk_start_services
            ;;
        stop)
            bulk_stop_services
            ;;
        restart)
            bulk_restart_services
            ;;
        status)
            show_status_non_interactive
            ;;
        
        # Configuration
        export)
            moonfrp_export "$@"
            ;;
        import)
            moonfrp_import "$@"
            ;;
        validate)
            validate_all_configs
            ;;
        
        # Bulk operations
        bulk)
            run_bulk_operation "$@"
            ;;
        
        # Search
        search)
            search_non_interactive "$@"
            ;;
        
        # Tags
        tag)
            tag_operation_non_interactive "$@"
            ;;
        
        # Optimization
        optimize)
            optimize_system "$1" "${MOONFRP_YES}"
            ;;
        
        # Interactive menu (default)
        menu|"")
            if [[ "$MOONFRP_YES" == "true" ]]; then
                log "ERROR" "Interactive menu not available in non-interactive mode"
                exit $EXIT_GENERAL_ERROR
            fi
            main_menu
            ;;
        
        # Help
        help|--help|-h)
            show_help "$@"
            ;;
        
        *)
            log "ERROR" "Unknown command: $command"
            show_help
            exit $EXIT_GENERAL_ERROR
            ;;
    esac
    
    local exit_code=$?
    
    # Kill timeout
    [[ -n "$timeout_pid" ]] && kill "$timeout_pid" 2>/dev/null
    
    exit $exit_code
}

# Help text
show_help() {
    local command="$1"
    
    if [[ -z "$command" ]]; then
        cat <<EOF
MoonFRP - Enterprise Tunnel Management
Version: $MOONFRP_VERSION

Usage: moonfrp [OPTIONS] COMMAND [ARGS...]

Global Options:
  -y, --yes          Non-interactive mode (auto-confirm)
  -q, --quiet        Quiet mode (errors only)
  --timeout SECONDS  Operation timeout (default: 300)
  -h, --help         Show help

Commands:
  Service Management:
    start              Start all services
    stop               Stop all services
    restart            Restart all services
    status             Show service status

  Configuration:
    export [FILE]      Export config to YAML (default: moonfrp-config.yaml)
    import FILE        Import config from YAML
    validate           Validate all configs

  Bulk Operations:
    bulk OPERATION     Bulk operations (start|stop|restart|update)

  Search & Filter:
    search QUERY       Search configs

  Tags:
    tag OPERATION      Tag operations (add|remove|list)

  Optimization:
    optimize PRESET    System optimization (conservative|balanced|aggressive)

  Interactive:
    menu               Interactive menu (default)

Examples:
  moonfrp --yes restart
  moonfrp export config.yaml
  moonfrp import config.yaml --yes
  moonfrp bulk restart --filter=tag:prod --yes
  moonfrp search "192.168.1.100"

For command-specific help: moonfrp COMMAND --help
EOF
    else
        # Command-specific help
        case "$command" in
            start|stop|restart)
                echo "Usage: moonfrp $command [--yes]"
                echo "  ${command^} all MoonFRP services"
                ;;
            export)
                echo "Usage: moonfrp export [FILE]"
                echo "  Export current configuration to YAML"
                echo "  Default file: moonfrp-config.yaml"
                ;;
            import)
                echo "Usage: moonfrp import FILE [--dry-run] [--yes]"
                echo "  Import configuration from YAML"
                echo "  Options:"
                echo "    --dry-run  Preview changes without applying"
                ;;
            bulk)
                echo "Usage: moonfrp bulk OPERATION [--filter=FILTER] [--yes]"
                echo "  Operations: start, stop, restart, update"
                echo "  Filters: tag:VALUE, type:client, name:PATTERN"
                ;;
            *)
                echo "No detailed help available for: $command"
                ;;
        esac
    fi
}

# Non-interactive status display
show_status_non_interactive() {
    if [[ "$MOONFRP_QUIET" == "true" ]]; then
        # Quiet: just exit code (0=all active, 1=some failed)
        systemctl is-active --quiet moonfrp-* && exit 0 || exit 1
    else
        # Normal: JSON output
        echo "{"
        echo "  \"services\": {"
        
        local first=true
        systemctl list-units --type=service --all --no-pager --no-legend \
            | grep "moonfrp-" | while read -r unit state rest; do
            
            [[ "$first" == "false" ]] && echo ","
            first=false
            
            echo -n "    \"${unit%.service}\": \"$state\""
        done
        
        echo
        echo "  }"
        echo "}"
    fi
}

# Run with timeout protection
main "$@"
```

**CLI Examples:**
```bash
# Non-interactive automation
moonfrp --yes restart
moonfrp --yes --quiet import production.yaml

# CI/CD pipeline
moonfrp export config.yaml
git add config.yaml
git commit -m "Update tunnel config"

# Scripting with exit codes
if moonfrp validate; then
    moonfrp --yes restart
else
    echo "Validation failed"
    exit 1
fi
```

### Testing Requirements

```bash
test_noninteractive_yes_flag()
test_noninteractive_quiet_flag()
test_exit_codes()
test_timeout_handling()
test_help_text()
test_all_commands_cli_accessible()
```

### Rollback Strategy

Non-interactive mode uses same rollback mechanisms as interactive. No special handling needed.

---

## Story 5.3: Structured Logging

**Story ID:** MOONFRP-E05-S03  
**Priority:** P2  
**Effort:** 0.5 days

### Problem Statement

DevOps teams integrate logs with centralized logging systems (ELK, Splunk, Loki). Need machine-readable JSON logging format.

### Acceptance Criteria

1. `--log-format=json` outputs structured JSON logs
2. Each log entry includes: timestamp, level, message, context
3. Compatible with common log parsers
4. Performance: <1ms overhead per log entry
5. Optional fields: service, operation, duration
6. Errors include stack traces when available

### Technical Specification

**Location:** `moonfrp-core.sh` - Enhanced logging

**Implementation:**
```bash
# Logging configuration
MOONFRP_LOG_FORMAT="${MOONFRP_LOG_FORMAT:-text}"  # text|json

# Enhanced log function
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date -Iseconds)
    
    case "$MOONFRP_LOG_FORMAT" in
        json)
            log_json "$level" "$message" "$timestamp"
            ;;
        *)
            log_text "$level" "$message"
            ;;
    esac
}

# JSON logging
log_json() {
    local level="$1"
    local message="$2"
    local timestamp="$3"
    
    # Build JSON
    local json=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "level": "$level",
  "message": "$message",
  "application": "moonfrp",
  "version": "$MOONFRP_VERSION"
}
EOF
)
    
    echo "$json"
}

# Text logging (existing)
log_text() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        INFO) echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
    esac
}
```

### Testing Requirements

```bash
test_json_logging_format()
test_json_logging_valid()
test_json_logging_performance()
test_text_logging_default()
```

### Rollback Strategy

Logging format is a display option - no rollback needed.

---

## Epic-Level Acceptance

**This epic is COMPLETE when:**

1. ✅ All 3 stories implemented and tested
2. ✅ Export/import working with 50 configs
3. ✅ All operations accessible non-interactively
4. ✅ Proper exit codes for scripting
5. ✅ JSON logging functional
6. ✅ CI/CD pipeline tested
7. ✅ Documentation updated

---

**Status:** Ready for Implementation  
**Created:** 2025-11-02  
**Approved By:** BMad Master, Team Consensus

