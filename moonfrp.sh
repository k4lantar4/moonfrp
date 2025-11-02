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
    
    config server             Configure server
    config client             Configure client
    config multi-ip           Configure multi-IP clients
    config visitor            Configure visitor
    
    health check              Check system health
    status                    Show system status
    logs [service]            View logs
    
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
                    if [[ "${3:-}" == "all" ]]; then
                        start_all_services
                    else
                        start_service "${3:-}"
                    fi
                    ;;
                "stop")
                    if [[ "${3:-}" == "all" ]]; then
                        stop_all_services
                    else
                        stop_service "${3:-}"
                    fi
                    ;;
                "restart")
                    if [[ "${3:-}" == "all" ]]; then
                        restart_all_services
                    else
                        restart_service "${3:-}"
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
                *)
                    log "ERROR" "Invalid service command. Use: start, stop, restart, status, or logs"
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