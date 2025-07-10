#!/bin/bash

# Set testing flag to prevent auto-execution
export MOONFRP_TESTING=1

# Source the main script (will not execute main due to testing flag)
source ./moonfrp.sh

# Test the functions directly
echo "=== Testing show_about_info ==="
if declare -f show_about_info >/dev/null; then
    echo "✅ show_about_info function exists"
    # Test with timeout and non-interactive
    timeout 5 bash -c 'export MOONFRP_TESTING=1; source ./moonfrp.sh; echo "Function test" | show_about_info' 2>/dev/null || echo "❌ Function failed"
else
    echo "❌ show_about_info function not found"
fi

echo -e "\n=== Testing show_current_config_summary ==="
if declare -f show_current_config_summary >/dev/null; then
    echo "✅ show_current_config_summary function exists"
    # Test with timeout and non-interactive
    timeout 5 bash -c 'export MOONFRP_TESTING=1; source ./moonfrp.sh; echo "Function test" | show_current_config_summary' 2>/dev/null || echo "❌ Function failed"
else
    echo "❌ show_current_config_summary function not found"
fi

echo -e "\n=== Function Definition Check ==="
echo "Available functions with 'show' in name:"
declare -F | grep show || echo "No show functions found"

echo -e "\n=== Script Structure Check ==="
echo "Total lines in script: $(wc -l < moonfrp.sh)"
echo "Lines with function definitions: $(grep -c "^[a-z_]*() {" moonfrp.sh)"
echo "Lines with show_about_info: $(grep -c "show_about_info" moonfrp.sh)"
echo "Lines with show_current_config_summary: $(grep -c "show_current_config_summary" moonfrp.sh)"

echo -e "\n=== Test Complete ===" 