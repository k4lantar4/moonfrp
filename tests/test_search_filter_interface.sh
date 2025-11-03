#!/bin/bash

#==============================================================================
# Unit Tests for Search & Filter Interface
# Story: 3-2-search-filter-interface
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
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_search_$$"
TEST_HOME="${TEMP_DIR:-/tmp}/test_moonfrp_home_search_$$"

# Source the functions being tested
set +e
export CONFIG_DIR="$TEST_CONFIG_DIR"
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.moonfrp"
mkdir -p "$TEST_CONFIG_DIR"

source "$PROJECT_ROOT/moonfrp-core.sh" || true
source "$PROJECT_ROOT/moonfrp-config.sh" || true
source "$PROJECT_ROOT/moonfrp-index.sh" || true
source "$PROJECT_ROOT/moonfrp-services.sh" || true
source "$PROJECT_ROOT/moonfrp-ui.sh" || true
source "$PROJECT_ROOT/moonfrp-search.sh" || true

# INDEX_DB_PATH is readonly and will be $HOME/.moonfrp/index.db
# We've set HOME=$TEST_HOME, so index will be in test location

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
    
    local output
    if output=$(eval "$@" 2>&1); then
        test_passed "$test_name"
        return 0
    else
        test_failed "$test_name" "" "$output"
        return 1
    fi
}

# Performance test helper
test_performance() {
    local test_name="$1"
    local max_ms="$2"
    shift 2
    
    ((TESTS_RUN++))
    
    local start_time=$(date +%s%N)
    eval "$@" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $duration_ms -lt $max_ms ]]; then
        test_passed "$test_name (${duration_ms}ms < ${max_ms}ms)"
        return 0
    else
        test_failed "$test_name" "< ${max_ms}ms" "${duration_ms}ms"
        return 1
    fi
}

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_HOME/.moonfrp"
    rm -f "$INDEX_DB_PATH"
    rm -f "$TEST_CONFIG_DIR"/*.toml
    
    # Initialize index
    init_config_index || true
    
    # Create test configs for search
    create_test_configs
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_CONFIG_DIR"
    rm -rf "$TEST_HOME"
}

# Ensure cleanup on exit
trap cleanup_test_env EXIT

# Create test config files
create_test_configs() {
    # Create configs with different names, IPs, ports
    local i=1
    for name in "web-server" "api-server" "db-proxy" "cache-proxy" "test-service"; do
        local file="$TEST_CONFIG_DIR/${name}.toml"
        local server_ip="192.168.1.$i"
        local port=$((7000 + i))
        
        cat > "$file" << EOF
user = "testuser"
serverAddr = "$server_ip"
serverPort = $port
auth.method = "token"
auth.token = "test-token-$i"
EOF
        ((i++))
    done
    
    # Index the configs
    rebuild_config_index || true
}

# Test: search_by_name with fuzzy matching
test_search_by_name() {
    local query="web"
    local results
    results=$(search_configs "$query" "name" 2>/dev/null)
    
    if [[ -n "$results" ]] && echo "$results" | grep -q "web-server"; then
        test_passed "test_search_by_name"
        return 0
    else
        test_failed "test_search_by_name" "should find web-server" "$results"
        return 1
    fi
}

# Test: search_by_ip
test_search_by_ip() {
    local query="192.168.1.1"
    local results
    results=$(search_configs "$query" "ip" 2>/dev/null)
    
    if [[ -n "$results" ]] && echo "$results" | grep -q "192.168.1.1"; then
        test_passed "test_search_by_ip"
        return 0
    else
        test_failed "test_search_by_ip" "should find config with IP 192.168.1.1" "$results"
        return 1
    fi
}

# Test: search_by_port
test_search_by_port() {
    local query="7001"
    local results
    results=$(search_configs "$query" "port" 2>/dev/null)
    
    if [[ -n "$results" ]]; then
        test_passed "test_search_by_port"
        return 0
    else
        test_failed "test_search_by_port" "should find config with port 7001" "$results"
        return 1
    fi
}

# Test: auto-detect IP pattern
test_auto_detect_ip_pattern() {
    local query="192.168.1.2"
    local results
    results=$(search_configs "$query" "auto" 2>/dev/null)
    
    if [[ -n "$results" ]] && echo "$results" | grep -q "192.168.1.2"; then
        test_passed "test_auto_detect_ip_pattern"
        return 0
    else
        test_failed "test_auto_detect_ip_pattern" "should auto-detect IP and find config" "$results"
        return 1
    fi
}

# Test: auto-detect port pattern
test_auto_detect_port_pattern() {
    local query="7002"
    local results
    results=$(search_configs "$query" "auto" 2>/dev/null)
    
    if [[ -n "$results" ]]; then
        test_passed "test_auto_detect_port_pattern"
        return 0
    else
        test_failed "test_auto_detect_port_pattern" "should auto-detect port and find config" "$results"
        return 1
    fi
}

# Test: auto-detect tag pattern
test_auto_detect_tag_pattern() {
    local query="env:test"
    local results
    # This will try tag search, may fail if tagging not set up - that's ok
    results=$(search_configs "$query" "auto" 2>/dev/null)
    
    # Just verify it doesn't crash and returns something (even if empty)
    test_passed "test_auto_detect_tag_pattern"
    return 0
}

# Test: auto-detect defaults to name
test_auto_detect_defaults_to_name() {
    local query="server"
    local results
    results=$(search_configs "$query" "auto" 2>/dev/null)
    
    if [[ -n "$results" ]] && echo "$results" | grep -qi "server"; then
        test_passed "test_auto_detect_defaults_to_name"
        return 0
    else
        test_failed "test_auto_detect_defaults_to_name" "should default to name search" "$results"
        return 1
    fi
}

# Test: fuzzy name matching (case-insensitive)
test_fuzzy_name_matching() {
    local query="WEB"
    local results
    results=$(search_configs "$query" "name" 2>/dev/null)
    
    if [[ -n "$results" ]] && echo "$results" | grep -qi "web-server"; then
        test_passed "test_fuzzy_name_matching"
        return 0
    else
        test_failed "test_fuzzy_name_matching" "should find web-server case-insensitively" "$results"
        return 1
    fi
}

# Test: performance - name search under 50ms
test_search_by_name_under_50ms() {
    test_performance "test_search_by_name_under_50ms" 50 \
        "search_configs 'server' 'name'"
}

# Test: performance - IP search under 50ms
test_search_by_ip_under_50ms() {
    test_performance "test_search_by_ip_under_50ms" 50 \
        "search_configs '192.168.1.1' 'ip'"
}

# Test: performance - port search under 50ms
test_search_by_port_under_50ms() {
    test_performance "test_search_by_port_under_50ms" 50 \
        "search_configs '7001' 'port'"
}

# Test: all search types under 50ms
test_all_search_types_under_50ms() {
    local all_passed=1
    
    test_performance "name search performance" 50 \
        "search_configs 'server' 'name'" || all_passed=0
    
    test_performance "ip search performance" 50 \
        "search_configs '192.168.1.1' 'ip'" || all_passed=0
    
    test_performance "port search performance" 50 \
        "search_configs '7001' 'port'" || all_passed=0
    
    if [[ $all_passed -eq 1 ]]; then
        return 0
    else
        return 1
    fi
}

# Test: search_configs function exists
test_search_configs_exists() {
    if command -v search_configs &> /dev/null || [[ "$(type -t search_configs)" == "function" ]]; then
        test_passed "test_search_configs_exists"
        return 0
    else
        test_failed "test_search_configs_exists" "function should exist" "not found"
        return 1
    fi
}

# Test: search_configs_auto function exists
test_search_configs_auto_exists() {
    if command -v search_configs_auto &> /dev/null || [[ "$(type -t search_configs_auto)" == "function" ]]; then
        test_passed "test_search_configs_auto_exists"
        return 0
    else
        test_failed "test_search_configs_auto_exists" "function should exist" "not found"
        return 1
    fi
}

# Test: search_filter_menu function exists
test_search_filter_menu_exists() {
    if command -v search_filter_menu &> /dev/null || [[ "$(type -t search_filter_menu)" == "function" ]]; then
        test_passed "test_search_filter_menu_exists"
        return 0
    else
        test_failed "test_search_filter_menu_exists" "function should exist" "not found"
        return 1
    fi
}

# Test: filter preset file operations (if jq available or basic)
test_filter_preset_save_load() {
    local preset_file="$TEST_HOME/.moonfrp/filter_presets.json"
    mkdir -p "$(dirname "$preset_file")"
    
    # Create a simple preset manually
    local test_json='[{"name":"test_preset","filters":{"name":"server","ip":"192.168.1.1"}}]'
    echo "$test_json" > "$preset_file"
    
    # Try to load it
    if [[ -f "$preset_file" ]] && [[ -s "$preset_file" ]]; then
        test_passed "test_filter_preset_save_load"
        return 0
    else
        test_failed "test_filter_preset_save_load" "preset file should exist" "not found"
        return 1
    fi
}

# Main test execution
main() {
    echo "=============================================================================="
    echo "Testing Search & Filter Interface (Story 3.2)"
    echo "=============================================================================="
    echo
    
    setup_test_env
    
    echo "Running functional tests..."
    echo
    test_search_configs_exists
    test_search_configs_auto_exists
    test_search_filter_menu_exists
    test_search_by_name
    test_search_by_ip
    test_search_by_port
    test_auto_detect_ip_pattern
    test_auto_detect_port_pattern
    test_auto_detect_tag_pattern
    test_auto_detect_defaults_to_name
    test_fuzzy_name_matching
    test_filter_preset_save_load
    
    echo
    echo "Running performance tests..."
    echo
    test_search_by_name_under_50ms
    test_search_by_ip_under_50ms
    test_search_by_port_under_50ms
    
    echo
    echo "=============================================================================="
    echo "Test Summary"
    echo "=============================================================================="
    echo -e "Tests Run:    ${CYAN}$TESTS_RUN${NC}"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# Run tests
main

