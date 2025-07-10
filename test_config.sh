#!/bin/bash
source ./moonfrp.sh

# Set required variables
CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
mkdir -p "$LOG_DIR"

# Test generate_frps_config function
echo "Testing generate_frps_config function..."
if generate_frps_config "test-token" "7000" "7500" "admin" "test123"; then
    echo "SUCCESS: Configuration generated"
    echo "Config file exists: $(test -f /etc/frp/frps.toml && echo 'YES' || echo 'NO')"
    echo "Config file size: $(stat -c%s /etc/frp/frps.toml 2>/dev/null || echo '0') bytes"
    if [[ -f "/etc/frp/frps.toml" ]]; then
        echo "First 5 lines of config:"
        head -5 /etc/frp/frps.toml
    fi
else
    echo "FAILED: Configuration generation failed"
fi
