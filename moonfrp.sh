#!/bin/bash

################################################################################
# MoonFRP - Advanced FRP Management Script (Refactored v2.0.0)
# Simplified production-ready version
################################################################################

set -uo pipefail

# Script metadata
readonly SCRIPT_VERSION="2.0.0"
readonly FRP_VERSION="0.65.0"
readonly FRP_DIR="/opt/frp"
readonly CONFIG_DIR="/etc/frp"
readonly SERVICE_DIR="/etc/systemd/system"
readonly LOG_DIR="/var/log/frp"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Error codes
readonly ERR_SUCCESS=0
readonly ERR_GENERAL=1
readonly ERR_USER_CANCELLED=130

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# Print helpers
print_success() { echo -e "${GREEN}✅ $*${NC}"; }
print_error() { echo -e "${RED}❌ $*${NC}"; }
print_info() { echo -e "${CYAN}ℹ️  $*${NC}"; }

# Check root
check_root() {
    [[ $EUID -eq 0 ]] || { log_error "Must run as root"; exit 1; }
}

# Install FRP
install_frp() {
    clear
    echo "=== FRP Installation ==="
    
    local url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
    local tmp="/tmp/frp.tar.gz"
    
    print_info "Downloading FRP v${FRP_VERSION}..."
    curl -fsSL "$url" -o "$tmp" || { print_error "Download failed"; return 1; }
    
    print_info "Extracting..."
    mkdir -p "$FRP_DIR"
    tar -xzf "$tmp" -C /tmp/
    cp /tmp/frp_${FRP_VERSION}_linux_amd64/frp{s,c} "$FRP_DIR/"
    chmod +x "$FRP_DIR"/frp{s,c}
    rm -rf "$tmp" /tmp/frp_${FRP_VERSION}_linux_amd64
    
    print_success "FRP installed successfully!"
}

# Setup server
setup_server() {
    clear
    echo "=== Server Setup ==="
    
    read -p "Bind port [7000]: " port
    port=${port:-7000}
    
    read -p "Auth token: " token
    [[ -z "$token" ]] && token=$(openssl rand -hex 16)
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/frps.toml" <<EOF
bindPort = $port
auth.method = "token"
auth.token = "$token"
transport.maxPoolCount = 5
transport.tcpMux = true
log.level = "info"
EOF

    cat > "$SERVICE_DIR/moonfrps.service" <<EOF
[Unit]
Description=MoonFRP Server
After=network.target

[Service]
Type=simple
ExecStart=$FRP_DIR/frps -c $CONFIG_DIR/frps.toml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now moonfrps
    
    print_success "Server configured!"
    print_info "Token: $token"
}

# Setup client
setup_client() {
    clear
    echo "=== Client Setup ==="
    
    read -p "Server IP: " server_ip
    read -p "Server port [7000]: " server_port
    server_port=${server_port:-7000}
    read -p "Auth token: " token
    read -p "Local ports (comma-separated): " ports
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/frpc.toml" <<EOF
serverAddr = "$server_ip"
serverPort = $server_port
auth.method = "token"
auth.token = "$token"
transport.poolCount = 5
transport.tcpMux = true
log.level = "info"
EOF

    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        cat >> "$CONFIG_DIR/frpc.toml" <<EOF

[[proxies]]
name = "tcp_${port}"
type = "tcp"
localIP = "127.0.0.1"
localPort = $port
remotePort = $port
EOF
    done
    
    cat > "$SERVICE_DIR/moonfrpc.service" <<EOF
[Unit]
Description=MoonFRP Client
After=network.target

[Service]
Type=simple
ExecStart=$FRP_DIR/frpc -c $CONFIG_DIR/frpc.toml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now moonfrpc
    
    print_success "Client configured!"
}

# List services
list_services() {
    clear
    echo "=== FRP Services ==="
    systemctl list-units --type=service | grep -E "(moonfrp|frp)" || echo "No services found"
    echo ""
    read -p "Press Enter to continue..."
}

# Main menu
main_menu() {
    while true; do
        clear
        echo "╔════════════════════════════════════╗"
        echo "║      MoonFRP v${SCRIPT_VERSION}            ║"
        echo "╚════════════════════════════════════╝"
        echo ""
        echo "1. Install FRP"
        echo "2. Setup Server (Iran)"
        echo "3. Setup Client (Foreign)"
        echo "4. List Services"
        echo "0. Exit"
        echo ""
        read -p "Choice: " choice
        
        case "$choice" in
            1) install_frp; read -p "Press Enter..." ;;
            2) setup_server; read -p "Press Enter..." ;;
            3) setup_client; read -p "Press Enter..." ;;
            4) list_services ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid choice"; sleep 1 ;;
        esac
    done
}

# Main
check_root
mkdir -p "$FRP_DIR" "$CONFIG_DIR" "$LOG_DIR"
main_menu
