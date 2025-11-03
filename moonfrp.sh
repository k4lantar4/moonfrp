#!/bin/bash

#==============================================================================
# MoonFRP - Advanced FRP Management Tool (Refactored)
# Version: 2.0.0
# Author: MoonFRP Team
# Description: Modular FRP configuration and service management tool
# Refactored: 2025-01-26 - Complete rewrite with modular architecture
#==============================================================================

# Use safer bash settings
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core functions
source "$SCRIPT_DIR/moonfrp-core.sh"

# Source other modules
source "$SCRIPT_DIR/moonfrp-config.sh"
source "$SCRIPT_DIR/moonfrp-index.sh"
source "$SCRIPT_DIR/moonfrp-services.sh"
source "$SCRIPT_DIR/moonfrp-ui.sh"
source "$SCRIPT_DIR/moonfrp-templates.sh"
source "$SCRIPT_DIR/moonfrp-search.sh"

#==============================================================================
# MAIN EXECUTION
#==============================================================================

# Initialize MoonFRP
init

# Load configuration
load_config

# Show help for non-interactive usage
show_help() {
    cat << EOF
MoonFRP v$MOONFRP_VERSION - Advanced FRP Management Tool

USAGE:
    moonfrp [COMMAND] [OPTIONS]

COMMANDS:
    setup server              Quick server setup
    setup client              Quick client setup
    setup multi-ip            Quick multi-IP client setup
    
    service start [name]      Start service(s)
    service stop [name]       Stop service(s)
    service restart [name]    Restart service(s)
    service status [name]     Show service status
    service logs [name]       View service logs
    service start --tag=X    Start services by tag
    service stop --tag=X     Stop services by tag
    service restart --tag=X  Restart services by tag
    
    tag add <config> <key> <value>  Add tag to config
    tag remove <config> <key>       Remove tag from config
    tag list <config>               List tags for config
    tag bulk --key=X --value=Y --filter=all  Bulk tag configs
    
    config server             Configure server
    config client             Configure client
    config multi-ip           Configure multi-IP clients
    config visitor            Configure visitor
    config bulk-update        Bulk update config fields (--field=X --value=Y --filter=all [--dry-run])
    
    template list             List available templates
    template create <name> <file>  Create template from file
    template view <name>      View template content
    template instantiate <name> <output> --var=KEY=VALUE  Instantiate template
    template bulk-instantiate <name> <csv-file>  Bulk instantiate from CSV
    template version <name>   Show template version
    template delete <name>    Delete template
    
    health check              Check system health
    status                    Show system status
    logs [service]            View logs
    
    restore <config> --backup=<timestamp>  Restore config from backup
    install                   Install FRP binaries
    uninstall                 Uninstall MoonFRP
    
    help                      Show this help

EXAMPLES:
    # Quick server setup
    moonfrp setup server
    
    # Quick client setup with environment variables
    MOONFRP_CLIENT_SERVER_ADDR="1.1.1.1" \\
    MOONFRP_CLIENT_AUTH_TOKEN="your-token" \\
    moonfrp setup client
    
    # Multi-IP setup
    MOONFRP_SERVER_IPS="1.1.1.1,2.2.2.2" \\
    MOONFRP_SERVER_PORTS="7000,7000" \\
    MOONFRP_CLIENT_PORTS="8080,8081" \\
    moonfrp setup multi-ip
    
    # Service management
    moonfrp service start all
    moonfrp service status
    moonfrp service logs moonfrp-server
    
    # Health check
    moonfrp health check
    
    # Restore from backup
    moonfrp restore /etc/frp/frpc.toml --backup=20250130-143025

ENVIRONMENT VARIABLES:
    # Core Configuration
    FRP_VERSION               FRP version to install (default: $FRP_VERSION)
    FRP_ARCH                  FRP architecture (default: $FRP_ARCH)
    FRP_DIR                   FRP installation directory (default: $FRP_DIR)
    MOONFRP_CONFIG_DIR        Configuration directory (default: $CONFIG_DIR)
    MOONFRP_LOG_DIR           Log directory (default: $LOG_DIR)
    
    # Server Configuration
    MOONFRP_SERVER_BIND_ADDR  Server bind address (default: $DEFAULT_SERVER_BIND_ADDR)
    MOONFRP_SERVER_BIND_PORT  Server bind port (default: $DEFAULT_SERVER_BIND_PORT)
    MOONFRP_SERVER_AUTH_TOKEN Server auth token (auto-generated if empty)
    MOONFRP_SERVER_DASHBOARD_PORT Dashboard port (default: $DEFAULT_SERVER_DASHBOARD_PORT)
    MOONFRP_SERVER_DASHBOARD_USER Dashboard username (default: $DEFAULT_SERVER_DASHBOARD_USER)
    MOONFRP_SERVER_DASHBOARD_PASSWORD Dashboard password (auto-generated if empty)
    
    # Client Configuration
    MOONFRP_CLIENT_SERVER_ADDR Client server address
    MOONFRP_CLIENT_SERVER_PORT Client server port (default: $DEFAULT_CLIENT_SERVER_PORT)
    MOONFRP_CLIENT_AUTH_TOKEN Client auth token
    MOONFRP_CLIENT_USER       Client username (auto-generated if empty)
    
    # Multi-IP Configuration
    MOONFRP_SERVER_IPS        Comma-separated server IPs
    MOONFRP_SERVER_PORTS      Comma-separated server ports
    MOONFRP_CLIENT_PORTS      Comma-separated client ports
    
    # Security Settings
    MOONFRP_TLS_ENABLE        Enable TLS (default: $DEFAULT_TLS_ENABLE)
    MOONFRP_TLS_FORCE         Force TLS (default: $DEFAULT_TLS_FORCE)
    MOONFRP_AUTH_METHOD       Auth method (default: $DEFAULT_AUTH_METHOD)
    
    # Performance Settings
    MOONFRP_MAX_POOL_COUNT    Max pool count (default: $DEFAULT_MAX_POOL_COUNT)
    MOONFRP_POOL_COUNT        Pool count (default: $DEFAULT_POOL_COUNT)
    MOONFRP_TCP_MUX           TCP multiplexing (default: $DEFAULT_TCP_MUX)
    MOONFRP_HEARTBEAT_INTERVAL Heartbeat interval (default: $DEFAULT_HEARTBEAT_INTERVAL)
    MOONFRP_HEARTBEAT_TIMEOUT Heartbeat timeout (default: $DEFAULT_HEARTBEAT_TIMEOUT)
    
    # Logging Settings
    MOONFRP_LOG_LEVEL         Log level (default: $DEFAULT_LOG_LEVEL)
    MOONFRP_LOG_MAX_DAYS      Log retention days (default: $DEFAULT_LOG_MAX_DAYS)
    MOONFRP_LOG_DISABLE_COLOR Disable log colors (default: $DEFAULT_LOG_DISABLE_COLOR)

For more information, visit: https://github.com/k4lantar4/moonfrp
EOF
}

# Handle command line arguments first
if [[ $# -gt 0 ]]; then
    case "$1" in
        "setup")
            case "${2:-}" in
                "server")
                    quick_server_setup
                    ;;
                "client")
                    quick_client_setup
                    ;;
                "multi-ip")
                    quick_multi_ip_setup
                    ;;
                *)
                    log "ERROR" "Invalid setup type. Use: server, client, or multi-ip"
                    exit 1
                    ;;
            esac
            ;;
        "service")
            case "${2:-}" in
                "start")
                    local tag_filter=""
                    local service_name="${3:-}"
                    shift 3 2>/dev/null || shift 2
                    while [[ $# -gt 0 ]]; do
                        if [[ "$1" == --tag=* ]]; then
                            tag_filter="${1#*=}"
                            break
                        fi
                        shift
                    done
                    if [[ -n "$tag_filter" ]]; then
                        bulk_operation_filtered "start" "tag" "$tag_filter"
                    elif [[ "$service_name" == "all" ]] || [[ -z "$service_name" ]]; then
                        start_all_services
                    else
                        start_service "$service_name"
                    fi
                    ;;
                "stop")
                    local tag_filter=""
                    local service_name="${3:-}"
                    shift 3 2>/dev/null || shift 2
                    while [[ $# -gt 0 ]]; do
                        if [[ "$1" == --tag=* ]]; then
                            tag_filter="${1#*=}"
                            break
                        fi
                        shift
                    done
                    if [[ -n "$tag_filter" ]]; then
                        bulk_operation_filtered "stop" "tag" "$tag_filter"
                    elif [[ "$service_name" == "all" ]] || [[ -z "$service_name" ]]; then
                        stop_all_services
                    else
                        stop_service "$service_name"
                    fi
                    ;;
                "restart")
                    local tag_filter=""
                    local service_name="${3:-}"
                    shift 3 2>/dev/null || shift 2
                    while [[ $# -gt 0 ]]; do
                        if [[ "$1" == --tag=* ]]; then
                            tag_filter="${1#*=}"
                            break
                        fi
                        shift
                    done
                    if [[ -n "$tag_filter" ]]; then
                        bulk_operation_filtered "restart" "tag" "$tag_filter"
                    elif [[ "$service_name" == "all" ]] || [[ -z "$service_name" ]]; then
                        restart_all_services
                    else
                        restart_service "$service_name"
                    fi
                    ;;
                "status")
                    if [[ -n "${3:-}" ]]; then
                        show_service_status "${3}"
                    else
                        list_frp_services
                    fi
                    ;;
                "logs")
                    if [[ -n "${3:-}" ]]; then
                        view_service_logs "${3}"
                    else
                        log "ERROR" "Service name required for logs command"
                        exit 1
                    fi
                    ;;
                "bulk")
                    local operation=""
                    local filter=""
                    local filter_type=""
                    local filter_value=""
                    local max_parallel=10
                    local dry_run=false
                    
                    shift 2
                    while [[ $# -gt 0 ]]; do
                        case "$1" in
                            --operation=*)
                                operation="${1#*=}"
                                ;;
                            --filter=*)
                                filter="${1#*=}"
                                if [[ "$filter" == tag:* ]]; then
                                    filter_type="tag"
                                    filter_value="${filter#tag:}"
                                elif [[ "$filter" == status:* ]]; then
                                    filter_type="status"
                                    filter_value="${filter#status:}"
                                elif [[ "$filter" == name:* ]]; then
                                    filter_type="name"
                                    filter_value="${filter#name:}"
                                else
                                    log "ERROR" "Invalid filter format. Use: --filter=tag:value, --filter=status:value, or --filter=name:value"
                                    exit 1
                                fi
                                ;;
                            --max-parallel=*)
                                max_parallel="${1#*=}"
                                if ! [[ "$max_parallel" =~ ^[0-9]+$ ]] || [[ $max_parallel -lt 1 ]]; then
                                    log "ERROR" "max-parallel must be a positive integer"
                                    exit 1
                                fi
                                ;;
                            --dry-run)
                                dry_run=true
                                ;;
                            *)
                                log "ERROR" "Unknown option: $1"
                                exit 1
                                ;;
                        esac
                        shift
                    done
                    
                    if [[ -z "$operation" ]]; then
                        log "ERROR" "Operation required. Use: --operation=start|stop|restart|reload"
                        exit 1
                    fi
                    
                    if [[ "$dry_run" == true ]]; then
                        log "INFO" "DRY RUN: Would execute bulk $operation operation"
                        if [[ -n "$filter_type" ]]; then
                            log "INFO" "  Filter: $filter_type=$filter_value"
                        fi
                        log "INFO" "  Max parallel: $max_parallel"
                        local services=($(get_moonfrp_services))
                        log "INFO" "  Services that would be affected: ${#services[@]}"
                        if [[ -n "$filter_type" ]]; then
                            log "INFO" "  Filtered services would be determined at runtime"
                        else
                            for svc in "${services[@]}"; do
                                echo "    - $svc"
                            done
                        fi
                        exit 0
                    fi
                    
                    if [[ -n "$filter_type" ]]; then
                        bulk_operation_filtered "$operation" "$filter_type" "$filter_value" "$max_parallel"
                    else
                        local services=($(get_moonfrp_services))
                        bulk_service_operation "$operation" "$max_parallel" "${services[@]}"
                    fi
                    ;;
                *)
                    log "ERROR" "Invalid service command. Use: start, stop, restart, status, logs, or bulk"
                    exit 1
                    ;;
            esac
            ;;
        "config")
            case "${2:-}" in
                "server")
                    config_server_wizard
                    ;;
                "client")
                    config_client_wizard
                    ;;
                "multi-ip")
                    config_multi_ip_wizard
                    ;;
                "visitor")
                    config_visitor_wizard
                    ;;
                "bulk-update")
                    # Parse bulk-update command
                    # Usage: moonfrp config bulk-update --field=X --value=Y --filter=all [--dry-run] [--file=updates.json]
                    shift 2
                    local field=""
                    local value=""
                    local filter="all"
                    local dry_run="false"
                    local update_file=""
                    
                    while [[ $# -gt 0 ]]; do
                        case "$1" in
                            --field=*)
                                field="${1#--field=}"
                                ;;
                            --field)
                                field="${2:-}"
                                shift
                                ;;
                            --value=*)
                                value="${1#--value=}"
                                ;;
                            --value)
                                value="${2:-}"
                                shift
                                ;;
                            --filter=*)
                                filter="${1#--filter=}"
                                ;;
                            --filter)
                                filter="${2:-}"
                                shift
                                ;;
                            --dry-run)
                                dry_run="true"
                                ;;
                            --file=*)
                                update_file="${1#--file=}"
                                ;;
                            --file)
                                update_file="${2:-}"
                                shift
                                ;;
                            *)
                                log "ERROR" "Unknown option: $1"
                                log "INFO" "Usage: moonfrp config bulk-update --field=X --value=Y --filter=all [--dry-run] [--file=updates.json]"
                                exit 1
                                ;;
                        esac
                        shift
                    done
                    
                    # If update file is provided, use file-based bulk update
                    if [[ -n "$update_file" ]]; then
                        if ! bulk_update_from_file "$update_file" "$dry_run"; then
                            log "ERROR" "Bulk update from file failed"
                            exit 1
                        fi
                    # Otherwise, use field-based bulk update
                    elif [[ -n "$field" ]] && [[ -n "$value" ]]; then
                        if ! bulk_update_config_field "$field" "$value" "$filter" "$dry_run"; then
                            log "ERROR" "Bulk update failed"
                            exit 1
                        fi
                    else
                        log "ERROR" "Either --field and --value, or --file is required"
                        log "INFO" "Usage: moonfrp config bulk-update --field=X --value=Y --filter=all [--dry-run]"
                        log "INFO" "   or: moonfrp config bulk-update --file=updates.json [--dry-run]"
                        exit 1
                    fi
                    ;;
                *)
                    config_wizard
                    ;;
            esac
            ;;
        "health")
            case "${2:-}" in
                "check")
                    health_check
                    ;;
                *)
                    log "ERROR" "Invalid health command. Use: check"
                    exit 1
                    ;;
            esac
            ;;
        "status")
            show_system_status
            ;;
        "logs")
            if [[ -n "${2:-}" ]]; then
                view_service_logs "${2}"
            else
                view_logs_menu
            fi
            ;;
        "restore")
            # Parse restore command: moonfrp restore <config> --backup=<timestamp>
            local config_file="${2:-}"
            local backup_timestamp=""
            
            # Parse arguments
            shift 2 2>/dev/null || true
            while [[ $# -gt 0 ]]; do
                if [[ "$1" =~ ^--backup=(.+)$ ]]; then
                    backup_timestamp="${BASH_REMATCH[1]}"
                elif [[ "$1" =~ ^--backup$ ]] && [[ -n "${2:-}" ]]; then
                    backup_timestamp="$2"
                    shift
                else
                    log "ERROR" "Unknown option: $1"
                    log "INFO" "Usage: moonfrp restore <config> --backup=<timestamp>"
                    exit 1
                fi
                shift
            done
            
            if [[ -z "$config_file" ]]; then
                log "ERROR" "Config file required"
                log "INFO" "Usage: moonfrp restore <config> --backup=<timestamp>"
                log "INFO" "Example: moonfrp restore /etc/frp/frpc.toml --backup=20250130-143025"
                exit 1
            fi
            
            if [[ -z "$backup_timestamp" ]]; then
                # No timestamp provided - use interactive mode
                if ! restore_config_interactive "$config_file"; then
                    exit 1
                fi
                exit 0
            fi
            
            # Find backup file matching timestamp
            local filename=$(basename "$config_file")
            local backup_dir="${BACKUP_DIR:-${HOME}/.moonfrp/backups}"
            local backup_file="${backup_dir}/${filename}.${backup_timestamp}.bak"
            
            if [[ ! -f "$backup_file" ]]; then
                log "ERROR" "Backup file not found: $backup_file"
                log "INFO" "Available backups for $(basename "$config_file"):"
                local backups=()
                while IFS= read -r backup; do
                    [[ -n "$backup" ]] && backups+=("$backup")
                done < <(list_backups "$config_file" 2>/dev/null)
                
                if [[ ${#backups[@]} -eq 0 ]]; then
                    log "WARN" "No backups found for this config file"
                else
                    log "INFO" "Use one of these timestamps:"
                    for backup in "${backups[@]}"; do
                        local backup_name=$(basename "$backup")
                        local ts="${backup_name##*.}"
                        ts="${ts%.bak}"
                        log "INFO" "  - $ts"
                    done
                fi
                exit 1
            fi
            
            # Restore from backup
            if restore_config_from_backup "$config_file" "$backup_file"; then
                log "INFO" "Successfully restored $(basename "$config_file") from backup"
            else
                log "ERROR" "Failed to restore configuration"
                exit 1
            fi
            ;;
        "tag")
            case "${2:-}" in
                "add")
                    local config_file="${3:-}"
                    local tag_key="${4:-}"
                    local tag_value="${5:-}"
                    if [[ -z "$config_file" ]] || [[ -z "$tag_key" ]] || [[ -z "$tag_value" ]]; then
                        log "ERROR" "Usage: moonfrp tag add <config> <key> <value>"
                        log "INFO" "Example: moonfrp tag add /etc/frp/frpc.toml env prod"
                        exit 1
                    fi
                    if ! add_config_tag "$config_file" "$tag_key" "$tag_value"; then
                        exit 1
                    fi
                    ;;
                "remove")
                    local config_file="${3:-}"
                    local tag_key="${4:-}"
                    if [[ -z "$config_file" ]] || [[ -z "$tag_key" ]]; then
                        log "ERROR" "Usage: moonfrp tag remove <config> <key>"
                        log "INFO" "Example: moonfrp tag remove /etc/frp/frpc.toml env"
                        exit 1
                    fi
                    if ! remove_config_tag "$config_file" "$tag_key"; then
                        exit 1
                    fi
                    ;;
                "list")
                    local config_file="${3:-}"
                    if [[ -z "$config_file" ]]; then
                        log "ERROR" "Usage: moonfrp tag list <config>"
                        log "INFO" "Example: moonfrp tag list /etc/frp/frpc.toml"
                        exit 1
                    fi
                    local tags_output
                    if tags_output=$(list_config_tags "$config_file"); then
                        while IFS=':' read -r key value; do
                            [[ -n "$key" ]] && echo "$key: $value"
                        done <<< "$tags_output"
                    else
                        log "INFO" "No tags found for $config_file"
                    fi
                    ;;
                "bulk")
                    local tag_key=""
                    local tag_value=""
                    local filter="all"
                    shift 2
                    while [[ $# -gt 0 ]]; do
                        case "$1" in
                            --key=*)
                                tag_key="${1#*=}"
                                ;;
                            --value=*)
                                tag_value="${1#*=}"
                                ;;
                            --filter=*)
                                filter="${1#*=}"
                                ;;
                            *)
                                log "ERROR" "Unknown option: $1"
                                log "INFO" "Usage: moonfrp tag bulk --key=X --value=Y --filter=all"
                                exit 1
                                ;;
                        esac
                        shift
                    done
                    if [[ -z "$tag_key" ]] || [[ -z "$tag_value" ]]; then
                        log "ERROR" "Usage: moonfrp tag bulk --key=X --value=Y [--filter=all]"
                        log "INFO" "Example: moonfrp tag bulk --key=env --value=prod --filter=type:client"
                        exit 1
                    fi
                    if ! bulk_tag_configs "$tag_key" "$tag_value" "$filter"; then
                        exit 1
                    fi
                    ;;
                *)
                    log "ERROR" "Invalid tag command. Use: add, remove, list, or bulk"
                    log "INFO" "Examples:"
                    log "INFO" "  moonfrp tag add <config> <key> <value>"
                    log "INFO" "  moonfrp tag remove <config> <key>"
                    log "INFO" "  moonfrp tag list <config>"
                    log "INFO" "  moonfrp tag bulk --key=X --value=Y --filter=all"
                    exit 1
                    ;;
            esac
            ;;
        "template")
            case "${2:-}" in
                "list")
                    echo "Available templates:"
                    list_templates | while read -r template; do
                        echo "  - $template"
                    done
                    ;;
                "create")
                    local template_name="${3:-}"
                    local template_file="${4:-}"
                    if [[ -z "$template_name" ]] || [[ -z "$template_file" ]]; then
                        log "ERROR" "Usage: moonfrp template create <name> <file>"
                        log "INFO" "Example: moonfrp template create my-template /path/to/template.toml"
                        exit 1
                    fi
                    if ! create_template_from_file "$template_name" "$template_file"; then
                        exit 1
                    fi
                    ;;
                "view")
                    local template_name="${3:-}"
                    if [[ -z "$template_name" ]]; then
                        log "ERROR" "Usage: moonfrp template view <name>"
                        log "INFO" "Example: moonfrp template view my-template"
                        exit 1
                    fi
                    if ! view_template "$template_name"; then
                        exit 1
                    fi
                    ;;
                "instantiate")
                    local template_name="${3:-}"
                    local output_file="${4:-}"
                    shift 4 2>/dev/null || shift 3
                    local variables=()
                    while [[ $# -gt 0 ]]; do
                        if [[ "$1" == --var=* ]]; then
                            variables+=("${1#*=}")
                        elif [[ "$1" == --var ]] && [[ -n "${2:-}" ]]; then
                            variables+=("$2")
                            shift
                        else
                            log "ERROR" "Unknown option: $1"
                            log "INFO" "Usage: moonfrp template instantiate <name> <output> --var=KEY=VALUE [--var=KEY2=VALUE2 ...]"
                            exit 1
                        fi
                        shift
                    done
                    if [[ -z "$template_name" ]] || [[ -z "$output_file" ]]; then
                        log "ERROR" "Usage: moonfrp template instantiate <name> <output> --var=KEY=VALUE"
                        log "INFO" "Example: moonfrp template instantiate my-template /etc/frp/frpc.toml --var=SERVER_ADDR=1.1.1.1 --var=PORT=8080"
                        exit 1
                    fi
                    if ! instantiate_template "$template_name" "$output_file" "${variables[@]}"; then
                        exit 1
                    fi
                    ;;
                "bulk-instantiate")
                    local template_name="${3:-}"
                    local csv_file="${4:-}"
                    if [[ -z "$template_name" ]] || [[ -z "$csv_file" ]]; then
                        log "ERROR" "Usage: moonfrp template bulk-instantiate <name> <csv-file>"
                        log "INFO" "Example: moonfrp template bulk-instantiate my-template instances.csv"
                        exit 1
                    fi
                    if ! bulk_instantiate_template "$template_name" "$csv_file"; then
                        exit 1
                    fi
                    ;;
                "version")
                    local template_name="${3:-}"
                    if [[ -z "$template_name" ]]; then
                        log "ERROR" "Usage: moonfrp template version <name>"
                        log "INFO" "Example: moonfrp template version my-template"
                        exit 1
                    fi
                    local version=$(get_template_version "$template_name")
                    if [[ $? -eq 0 ]]; then
                        echo "Template version: $version"
                    else
                        exit 1
                    fi
                    ;;
                "delete")
                    local template_name="${3:-}"
                    if [[ -z "$template_name" ]]; then
                        log "ERROR" "Usage: moonfrp template delete <name>"
                        log "INFO" "Example: moonfrp template delete my-template"
                        exit 1
                    fi
                    if ! delete_template "$template_name"; then
                        exit 1
                    fi
                    ;;
                *)
                    log "ERROR" "Invalid template command. Use: list, create, view, instantiate, bulk-instantiate, version, or delete"
                    log "INFO" "Examples:"
                    log "INFO" "  moonfrp template list"
                    log "INFO" "  moonfrp template create <name> <file>"
                    log "INFO" "  moonfrp template view <name>"
                    log "INFO" "  moonfrp template instantiate <name> <output> --var=KEY=VALUE"
                    exit 1
                    ;;
            esac
            ;;
        "install")
            install_frp
            ;;
        "uninstall")
            uninstall_moonfrp
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log "ERROR" "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
else
    # No arguments - check if running interactively
    if [[ -t 0 ]]; then
        # Interactive mode - show main menu
        main_menu
    else
        # Non-interactive mode - show help
        show_help
    fi
fi