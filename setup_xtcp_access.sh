#!/bin/bash

# MoonFRP XTCP Access Setup Script
# This script sets up XTCP access to X-UI panel on remote servers

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Target IPs
IPS=(
    "45.94.214.223"
    "89.47.198.149"
    "62.60.193.202"
    "89.47.198.185"
)

# Function to display header
show_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}🚀 MoonFRP XTCP Access Setup for X-UI${NC}         ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
}

# Function to setup XTCP access on a target IP
setup_xtcp_access() {
    local target_ip="$1"
    
    echo -e "\n${BLUE}🔧 Setting up XTCP access for ${YELLOW}$target_ip${NC}..."
    
    # Check if target is reachable
    if ping -c 1 "$target_ip" &> /dev/null; then
        echo -e "${GREEN}✅ Target $target_ip is reachable${NC}"
    else
        echo -e "${RED}❌ Target $target_ip is not reachable${NC}"
        return 1
    fi
    
    # Copy visitor configuration
    echo -e "${YELLOW}📋 Copying visitor configuration...${NC}"
    if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        /etc/frp/frpc_visitor_149.toml root@"$target_ip":/tmp/; then
        echo -e "${GREEN}✅ Configuration copied successfully${NC}"
    else
        echo -e "${RED}❌ Failed to copy configuration${NC}"
        return 1
    fi
    
    # Setup directories and start visitor client
    echo -e "${YELLOW}🚀 Setting up FRP client...${NC}"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$target_ip" << 'EOF'
        # Create directories
        mkdir -p /etc/frp /var/log/frp
        
        # Move configuration
        mv /tmp/frpc_visitor_149.toml /etc/frp/
        
        # Download FRP if not exists
        if [ ! -f /usr/local/bin/frpc ]; then
            echo "Downloading FRP client..."
            wget -O /tmp/frp.tar.gz https://github.com/fatedier/frp/releases/download/v0.63.0/frp_0.63.0_linux_amd64.tar.gz
            tar -xzf /tmp/frp.tar.gz -C /tmp/
            cp /tmp/frp_0.63.0_linux_amd64/frpc /usr/local/bin/
            chmod +x /usr/local/bin/frpc
            rm -rf /tmp/frp*
        fi
        
        # Kill existing frpc processes
        pkill -f "frpc.*visitor" || true
        
        # Start visitor client in background
        nohup /usr/local/bin/frpc -c /etc/frp/frpc_visitor_149.toml > /var/log/frp/visitor.log 2>&1 &
        
        # Wait a moment for startup
        sleep 3
        
        # Check if running
        if pgrep -f "frpc.*visitor" > /dev/null; then
            echo "✅ FRP visitor client started successfully"
            echo "🌐 X-UI Panel accessible at: http://localhost:8096"
            echo "📋 Xray service access: http://localhost:8005 (port 9005)"
        else
            echo "❌ Failed to start FRP visitor client"
            echo "📋 Check logs: tail -f /var/log/frp/visitor.log"
        fi
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ XTCP access setup completed for $target_ip${NC}"
        echo -e "${CYAN}🌐 X-UI Panel: ${YELLOW}http://$target_ip:9001${NC} (via localhost tunnel)"
    else
        echo -e "${RED}❌ Setup failed for $target_ip${NC}"
    fi
}

# Function to display access information
show_access_info() {
    echo -e "\n${CYAN}📋 Access Information:${NC}"
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${YELLOW}After setup, access X-UI on each server via:${NC}         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                      ${CYAN}║${NC}"
    for ip in "${IPS[@]}"; do
        echo -e "${CYAN}║${NC} ${GREEN}$ip${NC}: http://localhost:8096          ${CYAN}║${NC}"
    done
    echo -e "${CYAN}║${NC}                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} ${YELLOW}Note: Access via SSH tunnel or local browser${NC}        ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
}

# Function to check status
check_status() {
    echo -e "\n${BLUE}🔍 Checking XTCP status on all servers...${NC}"
    
    for ip in "${IPS[@]}"; do
        echo -e "\n${YELLOW}Checking $ip...${NC}"
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" << 'EOF'
            echo "🔍 FRP Process Status:"
            pgrep -f "frpc.*visitor" > /dev/null && echo "✅ FRP visitor client is running" || echo "❌ FRP visitor client is not running"
            
            echo "🔍 Port Status:"
            netstat -tuln | grep :8096 > /dev/null && echo "✅ Port 8096 is listening (X-UI)" || echo "❌ Port 8096 is not listening"
            netstat -tuln | grep :8005 > /dev/null && echo "✅ Port 8005 is listening (Xray)" || echo "❌ Port 8005 is not listening"
            
            echo "🔍 Recent logs:"
            tail -3 /var/log/frp/visitor.log 2>/dev/null || echo "No logs available"
EOF
    done
}

# Main menu
main_menu() {
    while true; do
        show_header
        echo -e "\n${YELLOW}Choose an option:${NC}"
        echo "1. Setup XTCP access on all servers"
        echo "2. Setup XTCP access on specific server"
        echo "3. Check status on all servers"
        echo "4. Show access information"
        echo "5. Exit"
        
        read -p "Enter your choice [1-5]: " choice
        
        case $choice in
            1)
                for ip in "${IPS[@]}"; do
                    setup_xtcp_access "$ip"
                done
                show_access_info
                ;;
            2)
                echo -e "\n${YELLOW}Available servers:${NC}"
                for i in "${!IPS[@]}"; do
                    echo "$((i+1)). ${IPS[$i]}"
                done
                read -p "Select server number: " server_num
                if [[ "$server_num" -ge 1 && "$server_num" -le "${#IPS[@]}" ]]; then
                    setup_xtcp_access "${IPS[$((server_num-1))]}"
                else
                    echo -e "${RED}Invalid selection${NC}"
                fi
                ;;
            3)
                check_status
                ;;
            4)
                show_access_info
                ;;
            5)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}Press any key to continue...${NC}"
        read -n 1
    done
}

# Run main menu
main_menu 