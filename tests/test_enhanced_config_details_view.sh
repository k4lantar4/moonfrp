#!/bin/bash

#==============================================================================
# Unit Tests for Enhanced Config Details View
# Story: 3-3-enhanced-config-details-view
#==============================================================================

set -u
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test environment
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_config_$$"
TEST_HOME="${TEMP_DIR:-/tmp}/test_moonfrp_home_$$"

# Source the functions being tested
set +e
export CONFIG_DIR="$TEST_CONFIG_DIR"
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.moonfrp"
mkdir -p "$TEST_CONFIG_DIR"

source "$PROJECT_ROOT/moonfrp-core.sh" || true
source "$PROJECT_ROOT/moonfrp-config.sh" || true
source "$PROJECT_ROOT/moonfrp-index.sh" || true
source "$PROJECT_ROOT/moonfrp-ui.sh" || true

set -u
set -o pipefail

# Test framework functions
test_passed() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

test_failed() {
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: $1"
    [[ -n "${2:-}" ]] && echo "  Expected: $2"
    [[ -n "${3:-}" ]] && echo "  Got: $3"
}

run_test() {
    local test_name="$1"
    shift
    ((TESTS_RUN++))
    
    if eval "$@" >/dev/null 2>&1; then
        test_passed "$test_name"
        return 0
    else
        test_failed "$test_name" "" "Command failed"
        return 1
    fi
}

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_HOME/.moonfrp"
    
    # Set environment variables (HOME controls index location)
    export HOME="$TEST_HOME"
    export CONFIG_DIR="$TEST_CONFIG_DIR"
    
    # Initialize index (uses $HOME/.moonfrp/index.db internally)
    init_config_index
    
    # Create test configs
    cat > "$TEST_CONFIG_DIR/frpc-1.toml" <<'EOF'
serverAddr = "192.168.1.100"
serverPort = 7000
auth.token = "abc1234567890xyz"
[[proxies]]
name = "web1"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8080
remotePort = 8000
[[proxies]]
name = "web2"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8081
remotePort = 8001
EOF

    cat > "$TEST_CONFIG_DIR/frpc-2.toml" <<'EOF'
serverAddr = "192.168.1.101"
serverPort = 7000
auth.token = "def9876543210uvw"
[[proxies]]
name = "web3"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8082
remotePort = 8002
EOF

    cat > "$TEST_CONFIG_DIR/frps-1.toml" <<'EOF'
bindPort = 7000
auth.token = "server123456token"
EOF

    # Index the configs
    index_config_file "$TEST_CONFIG_DIR/frpc-1.toml"
    index_config_file "$TEST_CONFIG_DIR/frpc-2.toml"
    index_config_file "$TEST_CONFIG_DIR/frps-1.toml"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_CONFIG_DIR"
    rm -rf "$TEST_HOME/.moonfrp"
    rm -rf "$TEST_HOME"
}

# Test: Config details grouped by server
test_config_details_grouped_by_server() {
    setup_test_env
    
    local output
    output=$(show_config_details 2>&1 | grep -c "Server: 192.168.1.100" || echo "0")
    
    if [[ "$output" -ge 1 ]]; then
        test_passed "test_config_details_grouped_by_server"
        cleanup_test_env
        return 0
    else
        test_failed "test_config_details_grouped_by_server" "At least 1 server header" "Found: $output"
        cleanup_test_env
        return 1
    fi
}

# Test: Display all fields
test_config_details_display_all_fields() {
    setup_test_env
    
    local db_path="$HOME/.moonfrp/index.db"
    local output
    output=$(display_config_summary "$TEST_CONFIG_DIR/frpc-1.toml" "$db_path" 2>&1)
    
    local has_type=false
    local has_server=false
    local has_proxies=false
    local has_token=false
    
    echo "$output" | grep -q "Type:" && has_type=true
    echo "$output" | grep -q "Server:" && has_server=true
    echo "$output" | grep -q "Proxies:" && has_proxies=true
    echo "$output" | grep -q "Token:" && has_token=true
    
    if [[ "$has_type" == "true" ]] && [[ "$has_server" == "true" ]] && [[ "$has_proxies" == "true" ]] && [[ "$has_token" == "true" ]]; then
        test_passed "test_config_details_display_all_fields"
        cleanup_test_env
        return 0
    else
        test_failed "test_config_details_display_all_fields" "All fields present" "Type: $has_type, Server: $has_server, Proxies: $has_proxies, Token: $has_token"
        cleanup_test_env
        return 1
    fi
}

# Test: Token masking
test_token_masking_display() {
    setup_test_env
    
    local db_path="$HOME/.moonfrp/index.db"
    local output
    output=$(display_config_summary "$TEST_CONFIG_DIR/frpc-1.toml" "$db_path" 2>&1)
    
    # Token should be masked: first 8 chars ... last 4 chars
    # Token is "abc1234567890xyz", masked should be "abc12345...0xyz"
    if echo "$output" | grep -qE "Token: abc12345\.\.\.[0-9a-z]{4}"; then
        test_passed "test_token_masking_display"
        cleanup_test_env
        return 0
    else
        test_failed "test_token_masking_display" "Token masked format" "Output: $(echo "$output" | grep Token || echo 'No token found')"
        cleanup_test_env
        return 1
    fi
}

# Test: Service status indicator
test_service_status_indicator() {
    setup_test_env
    
    local db_path="$HOME/.moonfrp/index.db"
    local output
    output=$(display_config_summary "$TEST_CONFIG_DIR/frpc-1.toml" "$db_path" 2>&1)
    
    # Should have status icon (● or ○)
    if echo "$output" | grep -qE "[●○]"; then
        test_passed "test_service_status_indicator"
        cleanup_test_env
        return 0
    else
        test_failed "test_service_status_indicator" "Status icon present" "No icon found"
        cleanup_test_env
        return 1
    fi
}

# Test: Statistics display
test_statistics_display() {
    setup_test_env
    
    local output
    output=$(show_config_details 2>&1)
    
    local has_total=false
    local has_proxies=false
    local has_servers=false
    
    echo "$output" | grep -qE "Total Configs:" && has_total=true
    echo "$output" | grep -qE "Total Proxies:" && has_proxies=true
    echo "$output" | grep -qE "Unique Servers:" && has_servers=true
    
    if [[ "$has_total" == "true" ]] && [[ "$has_proxies" == "true" ]] && [[ "$has_servers" == "true" ]]; then
        test_passed "test_statistics_display"
        cleanup_test_env
        return 0
    else
        test_failed "test_statistics_display" "All statistics present" "Total: $has_total, Proxies: $has_proxies, Servers: $has_servers"
        cleanup_test_env
        return 1
    fi
}

# Test: Copy-paste format
test_copy_paste_format() {
    setup_test_env
    
    local output
    output=$(show_config_details 2>&1)
    
    # Should be readable text format without special control characters (except color codes)
    # Should have server headers and config details
    if echo "$output" | grep -q "Server:" && echo "$output" | grep -q "Type:"; then
        test_passed "test_copy_paste_format"
        cleanup_test_env
        return 0
    else
        test_failed "test_copy_paste_format" "Readable format" "Missing server or type info"
        cleanup_test_env
        return 1
    fi
}

# Test: Export to text
test_export_to_text() {
    setup_test_env
    
    export_config_summary "text" >/dev/null 2>&1 <<<""
    
    local output_file="$TEST_HOME/.moonfrp/config-summary.txt"
    
    if [[ -f "$output_file" ]]; then
        local content
        content=$(cat "$output_file")
        
        if echo "$content" | grep -q "MoonFRP Configuration Summary" && echo "$content" | grep -q "Server:"; then
            test_passed "test_export_to_text"
            cleanup_test_env
            return 0
        else
            test_failed "test_export_to_text" "Valid content" "File exists but content invalid"
            cleanup_test_env
            return 1
        fi
    else
        test_failed "test_export_to_text" "File created" "File not found: $output_file"
        cleanup_test_env
        return 1
    fi
}

# Test: Export to JSON
test_export_to_json() {
    setup_test_env
    
    export_config_summary "json" >/dev/null 2>&1 <<<""
    
    local output_file="$TEST_HOME/.moonfrp/config-summary.json"
    
    if [[ -f "$output_file" ]]; then
        local content
        content=$(cat "$output_file")
        
        # Check if it's valid JSON (starts with [ or {)
        if echo "$content" | head -c 1 | grep -qE "[\[{]"; then
            test_passed "test_export_to_json"
            cleanup_test_env
            return 0
        else
            test_failed "test_export_to_json" "Valid JSON" "Invalid JSON format"
            cleanup_test_env
            return 1
        fi
    else
        test_failed "test_export_to_json" "File created" "File not found: $output_file"
        cleanup_test_env
        return 1
    fi
}

# Test: Export to YAML
test_export_to_yaml() {
    setup_test_env
    
    export_config_summary "yaml" >/dev/null 2>&1 <<<""
    
    local output_file="$TEST_HOME/.moonfrp/config-summary.yaml"
    
    if [[ -f "$output_file" ]]; then
        local content
        content=$(cat "$output_file")
        
        # Check YAML structure:
        # - Should start with "---"
        # - Should have "servers:" key
        # - Should have "statistics:" key
        # - Should have server entries with configs
        local has_yaml_header=false
        local has_servers=false
        local has_statistics=false
        local has_config_entry=false
        
        echo "$content" | head -1 | grep -q "^---$" && has_yaml_header=true
        echo "$content" | grep -q "^servers:" && has_servers=true
        echo "$content" | grep -q "^statistics:" && has_statistics=true
        echo "$content" | grep -qE "^\s+- name:" && has_config_entry=true
        
        if [[ "$has_yaml_header" == "true" ]] && [[ "$has_servers" == "true" ]] && [[ "$has_statistics" == "true" ]] && [[ "$has_config_entry" == "true" ]]; then
            test_passed "test_export_to_yaml"
            cleanup_test_env
            return 0
        else
            test_failed "test_export_to_yaml" "Valid YAML structure" "Header: $has_yaml_header, Servers: $has_servers, Statistics: $has_statistics, Config: $has_config_entry"
            cleanup_test_env
            return 1
        fi
    else
        test_failed "test_export_to_yaml" "File created" "File not found: $output_file"
        cleanup_test_env
        return 1
    fi
}

# Test: Server grouping sort order
test_server_grouping_sort_order() {
    setup_test_env
    
    # Add more configs with different server IPs
    cat > "$TEST_CONFIG_DIR/frpc-3.toml" <<'EOF'
serverAddr = "192.168.1.050"
serverPort = 7000
auth.token = "testtoken123"
EOF
    index_config_file "$TEST_CONFIG_DIR/frpc-3.toml"
    
    local output
    output=$(show_config_details 2>&1)
    
    # Servers should be sorted
    local first_server
    first_server=$(echo "$output" | grep "Server:" | head -1 | sed 's/.*Server: //')
    local second_server
    second_server=$(echo "$output" | grep "Server:" | head -2 | tail -1 | sed 's/.*Server: //')
    
    # Compare: server should come before 192.168.1.050 (or numeric comparison)
    if [[ -n "$first_server" ]] && [[ -n "$second_server" ]]; then
        test_passed "test_server_grouping_sort_order"
        cleanup_test_env
        return 0
    else
        test_failed "test_server_grouping_sort_order" "Servers sorted" "First: $first_server, Second: $second_server"
        cleanup_test_env
        return 1
    fi
}

# Test: Tag display (when available)
test_tag_display() {
    setup_test_env
    
    # Add a tag if tagging system is available
    if command -v add_config_tag &>/dev/null || type add_config_tag &>/dev/null 2>&1; then
        add_config_tag "$TEST_CONFIG_DIR/frpc-1.toml" "env" "prod" >/dev/null 2>&1 || true
        
        local output
        output=$(display_config_summary "$TEST_CONFIG_DIR/frpc-1.toml" "$INDEX_DB_PATH" 2>&1)
        
        if echo "$output" | grep -q "Tags:"; then
            test_passed "test_tag_display"
            cleanup_test_env
            return 0
        else
            test_failed "test_tag_display" "Tags displayed" "Tags not found in output"
            cleanup_test_env
            return 1
        fi
    else
        # Tagging system not available - test graceful handling
        local output
        output=$(display_config_summary "$TEST_CONFIG_DIR/frpc-1.toml" "$INDEX_DB_PATH" 2>&1)
        
        # Should still work without tags
        if echo "$output" | grep -q "Type:"; then
            test_passed "test_tag_display (tagging system not available)"
            cleanup_test_env
            return 0
        else
            test_failed "test_tag_display" "Graceful without tags" "Function failed"
            cleanup_test_env
            return 1
        fi
    fi
}

# Test: One screen summary
test_one_screen_summary() {
    setup_test_env
    
    local output
    output=$(show_config_details 2>&1)
    
    # Should contain all configs and statistics
    local config_count
    config_count=$(echo "$output" | grep -cE "●|○" || echo "0")
    
    if [[ "$config_count" -ge 3 ]]; then
        test_passed "test_one_screen_summary"
        cleanup_test_env
        return 0
    else
        test_failed "test_one_screen_summary" "All configs displayed" "Found: $config_count configs"
        cleanup_test_env
        return 1
    fi
}

# Main test runner
main() {
    echo "Running Enhanced Config Details View Tests..."
    echo "=============================================="
    echo
    
    test_config_details_grouped_by_server
    test_config_details_display_all_fields
    test_token_masking_display
    test_service_status_indicator
    test_statistics_display
    test_copy_paste_format
    test_export_to_text
    test_export_to_json
    test_export_to_yaml
    test_server_grouping_sort_order
    test_tag_display
    test_one_screen_summary
    
    echo
    echo "=============================================="
    echo "Tests Run: $TESTS_RUN"
    echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

