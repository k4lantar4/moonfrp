#!/bin/bash

#==============================================================================
# Unit Tests for Bulk Configuration Operations
# Story: 2-2-bulk-configuration-operations
#==============================================================================

set -u
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test environment
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_bulk_$$"
TEST_BACKUP_DIR="${HOME}/.moonfrp/backups_test_$$"

# Cleanup function
cleanup() {
    rm -rf "$TEST_CONFIG_DIR" "$TEST_BACKUP_DIR" 2>/dev/null
}
trap cleanup EXIT

# Source the functions being tested
set +e
mkdir -p "$TEST_CONFIG_DIR"

# Temporarily unset readonly CONFIG_DIR if it exists
if [[ -n "${CONFIG_DIR:-}" ]]; then
    unset CONFIG_DIR 2>/dev/null || true
fi
export CONFIG_DIR="$TEST_CONFIG_DIR"

source "$PROJECT_ROOT/moonfrp-core.sh" || true

# Set BACKUP_DIR before sourcing moonfrp-config.sh (since it's readonly)
export BACKUP_DIR="$TEST_BACKUP_DIR"
export HOME="${HOME:-/root}"

source "$PROJECT_ROOT/moonfrp-config.sh" || true

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

run_test_expect_fail() {
    local test_name="$1"
    shift
    ((TESTS_RUN++))
    
    if eval "$@" >/dev/null 2>&1; then
        test_failed "$test_name" "Should fail" "Command succeeded"
        return 1
    else
        test_passed "$test_name"
        return 0
    fi
}

# Helper: Create test server config
create_test_server_config() {
    local config_file="$1"
    cat > "$config_file" << 'EOF'
bindAddr = "0.0.0.0"
bindPort = 7000
auth.method = "token"
auth.token = "test_token_123"
EOF
}

# Helper: Create test client config
create_test_client_config() {
    local config_file="$1"
    cat > "$config_file" << 'EOF'
user = "test_user"
serverAddr = "1.1.1.1"
serverPort = 7000
auth.method = "token"
auth.token = "test_token_123"
EOF
}

#==============================================================================
# TEST SUITE
#==============================================================================

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Testing Bulk Configuration Operations${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Test: get_configs_by_filter - all
test_get_configs_by_filter_all() {
    setup_test_env
    create_test_server_config "$TEST_CONFIG_DIR/frps.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc-2.toml"
    
    local result
    result=$(get_configs_by_filter "all" 2>/dev/null)
    
    local count=$(echo "$result" | grep -c ".toml" || echo "0")
    
    if [[ $count -ge 3 ]]; then
        test_passed "get_configs_by_filter all - found configs"
    else
        test_failed "get_configs_by_filter all - found configs" ">= 3" "$count"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: get_configs_by_filter - type:server
test_get_configs_by_filter_type_server() {
    setup_test_env
    create_test_server_config "$TEST_CONFIG_DIR/frps.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    
    local result
    result=$(get_configs_by_filter "type:server" 2>/dev/null)
    
    if echo "$result" | grep -q "frps.toml"; then
        test_passed "get_configs_by_filter type:server - found server config"
    else
        test_failed "get_configs_by_filter type:server - found server config" "frps.toml" "$result"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: get_configs_by_filter - type:client
test_get_configs_by_filter_type_client() {
    setup_test_env
    create_test_server_config "$TEST_CONFIG_DIR/frps.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc-2.toml"
    
    local result
    result=$(get_configs_by_filter "type:client" 2>/dev/null)
    
    local client_count=$(echo "$result" | grep -c "frpc" || echo "0")
    
    if [[ $client_count -ge 2 ]]; then
        test_passed "get_configs_by_filter type:client - found client configs"
    else
        test_failed "get_configs_by_filter type:client - found client configs" ">= 2" "$client_count"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: update_toml_field - simple field
test_update_toml_field_simple() {
    setup_test_env
    create_test_client_config "$TEST_CONFIG_DIR/test.toml"
    
    update_toml_field "$TEST_CONFIG_DIR/test.toml" "serverPort" "8000" 2>/dev/null
    
    local value
    value=$(get_toml_value "$TEST_CONFIG_DIR/test.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
    
    if [[ "$value" == "8000" ]]; then
        test_passed "update_toml_field - simple field update"
    else
        test_failed "update_toml_field - simple field update" "8000" "$value"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: update_toml_field - nested field
test_update_toml_field_nested() {
    setup_test_env
    create_test_client_config "$TEST_CONFIG_DIR/test.toml"
    
    update_toml_field "$TEST_CONFIG_DIR/test.toml" "auth.token" "\"new_token\"" 2>/dev/null
    
    local value
    value=$(get_toml_value "$TEST_CONFIG_DIR/test.toml" "auth.token" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    
    if [[ "$value" == "new_token" ]]; then
        test_passed "update_toml_field - nested field update"
    else
        test_failed "update_toml_field - nested field update" "new_token" "$value"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: bulk_update_config_field - dry-run
test_bulk_update_single_field_dry_run() {
    setup_test_env
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc-2.toml"
    
    local output
    output=$(bulk_update_config_field "serverPort" "8000" "type:client" "true" 2>&1)
    
    if echo "$output" | grep -q "DRY-RUN"; then
        # Verify no changes were made
        local value1 value2
        value1=$(get_toml_value "$TEST_CONFIG_DIR/frpc.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
        value2=$(get_toml_value "$TEST_CONFIG_DIR/frpc-2.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
        
        if [[ "$value1" == "7000" ]] && [[ "$value2" == "7000" ]]; then
            test_passed "bulk_update_config_field - dry-run mode shows preview without applying"
        else
            test_failed "bulk_update_config_field - dry-run should not apply changes" "7000" "$value1/$value2"
            ((TESTS_FAILED++))
        fi
    else
        test_failed "bulk_update_config_field - dry-run should show preview" "DRY-RUN" "$output"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: bulk_update_config_field - apply changes
test_bulk_update_single_field_apply() {
    setup_test_env
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc-2.toml"
    
    bulk_update_config_field "serverPort" "8000" "type:client" "false" >/dev/null 2>&1
    
    local value1 value2
    value1=$(get_toml_value "$TEST_CONFIG_DIR/frpc.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
    value2=$(get_toml_value "$TEST_CONFIG_DIR/frpc-2.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
    
    if [[ "$value1" == "8000" ]] && [[ "$value2" == "8000" ]]; then
        test_passed "bulk_update_config_field - apply changes to multiple configs"
    else
        test_failed "bulk_update_config_field - apply changes" "8000" "$value1/$value2"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: bulk_update_config_field - validation failure rollback
test_bulk_update_validation_failure_rollback() {
    setup_test_env
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc-2.toml"
    
    # Get original values
    local original1 original2
    original1=$(get_toml_value "$TEST_CONFIG_DIR/frpc.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
    original2=$(get_toml_value "$TEST_CONFIG_DIR/frpc-2.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
    
    # Try to set invalid value (empty auth.token should fail validation)
    bulk_update_config_field "auth.token" "\"\"" "type:client" "false" >/dev/null 2>&1
    
    # Verify no changes were made (rollback occurred)
    local value1 value2
    value1=$(get_toml_value "$TEST_CONFIG_DIR/frpc.toml" "auth.token" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    value2=$(get_toml_value "$TEST_CONFIG_DIR/frpc-2.toml" "auth.token" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    
    # Should still have original token
    if [[ "$value1" == "test_token_123" ]] && [[ "$value2" == "test_token_123" ]]; then
        test_passed "bulk_update_config_field - validation failure triggers rollback"
    else
        test_failed "bulk_update_config_field - validation failure rollback" "test_token_123" "$value1/$value2"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: bulk_update_config_field - atomic transaction
test_bulk_update_atomic_transaction() {
    setup_test_env
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc-2.toml"
    
    # Get original values
    local original1 original2
    original1=$(get_toml_value "$TEST_CONFIG_DIR/frpc.toml" "serverAddr" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    original2=$(get_toml_value "$TEST_CONFIG_DIR/frpc-2.toml" "serverAddr" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    
    # Update to valid value - both should succeed
    bulk_update_config_field "serverAddr" "\"2.2.2.2\"" "type:client" "false" >/dev/null 2>&1
    
    local value1 value2
    value1=$(get_toml_value "$TEST_CONFIG_DIR/frpc.toml" "serverAddr" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    value2=$(get_toml_value "$TEST_CONFIG_DIR/frpc-2.toml" "serverAddr" 2>/dev/null | sed 's/["'\'']//g' || echo "")
    
    # Both should be updated (atomic success)
    if [[ "$value1" == "2.2.2.2" ]] && [[ "$value2" == "2.2.2.2" ]]; then
        test_passed "bulk_update_config_field - atomic transaction (all succeed)"
    else
        test_failed "bulk_update_config_field - atomic transaction" "2.2.2.2" "$value1/$value2"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: bulk_update_config_field - backup before change
test_bulk_update_backup_before_change() {
    setup_test_env
    mkdir -p "$TEST_BACKUP_DIR"
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    
    # Perform bulk update
    bulk_update_config_field "serverPort" "8000" "type:client" "false" >/dev/null 2>&1
    
    # Check if backup was created
    local backup_count
    backup_count=$(find "$TEST_BACKUP_DIR" -name "frpc.toml.*.bak" 2>/dev/null | wc -l)
    
    if [[ $backup_count -ge 1 ]]; then
        test_passed "bulk_update_config_field - backup created before change"
    else
        test_failed "bulk_update_config_field - backup created" ">= 1" "$backup_count"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: bulk_update_config_field - filter by type
test_bulk_update_filter_by_type() {
    setup_test_env
    create_test_server_config "$TEST_CONFIG_DIR/frps.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    
    # Update only client configs
    bulk_update_config_field "serverPort" "8000" "type:client" "false" >/dev/null 2>&1
    
    # Verify client updated, server not affected
    local client_port server_port
    client_port=$(get_toml_value "$TEST_CONFIG_DIR/frpc.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
    server_port=$(get_toml_value "$TEST_CONFIG_DIR/frps.toml" "bindPort" 2>/dev/null | tr -d '"' || echo "")
    
    if [[ "$client_port" == "8000" ]] && [[ "$server_port" == "7000" ]]; then
        test_passed "bulk_update_config_field - filter by type works correctly"
    else
        test_failed "bulk_update_config_field - filter by type" "client=8000,server=7000" "client=$client_port,server=$server_port"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: Performance - 50 configs under 5s
test_bulk_update_50_configs_under_5s() {
    setup_test_env
    
    # Create 50 test configs
    local i
    for i in {1..50}; do
        create_test_client_config "$TEST_CONFIG_DIR/frpc-${i}.toml"
    done
    
    # Measure execution time
    local start_time end_time elapsed
    start_time=$(date +%s%N)
    bulk_update_config_field "serverPort" "8000" "type:client" "false" >/dev/null 2>&1
    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000000 ))
    
    if [[ $elapsed -lt 5 ]]; then
        test_passed "bulk_update_config_field - 50 configs under 5s (${elapsed}s)"
    else
        test_failed "bulk_update_config_field - 50 configs performance" "< 5s" "${elapsed}s"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test: bulk_update_from_file - JSON file
test_bulk_update_from_file() {
    setup_test_env
    create_test_client_config "$TEST_CONFIG_DIR/frpc.toml"
    create_test_client_config "$TEST_CONFIG_DIR/frpc-2.toml"
    
    # Create update JSON file
    local update_file="$TEST_CONFIG_DIR/updates.json"
    cat > "$update_file" << 'EOF'
{
  "updates": [
    {
      "field": "serverPort",
      "value": "8000",
      "filter": "type:client"
    }
  ]
}
EOF
    
    if command -v jq &>/dev/null; then
        bulk_update_from_file "$update_file" "false" >/dev/null 2>&1
        
        local value1 value2
        value1=$(get_toml_value "$TEST_CONFIG_DIR/frpc.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
        value2=$(get_toml_value "$TEST_CONFIG_DIR/frpc-2.toml" "serverPort" 2>/dev/null | tr -d '"' || echo "")
        
        if [[ "$value1" == "8000" ]] && [[ "$value2" == "8000" ]]; then
            test_passed "bulk_update_from_file - JSON file updates work"
        else
            test_failed "bulk_update_from_file - JSON file updates" "8000" "$value1/$value2"
            ((TESTS_FAILED++))
        fi
    else
        # Skip test if jq not available
        echo -e "${YELLOW}⊘ SKIP${NC}: bulk_update_from_file - JSON (jq not available)"
        ((TESTS_RUN++))
    fi
}

# Test: Empty filter results
test_bulk_update_empty_filter_results() {
    setup_test_env
    # No config files created
    
    # Try to update with filter that matches nothing
    local output
    output=$(bulk_update_config_field "serverPort" "8000" "type:client" "false" 2>&1)
    
    if echo "$output" | grep -qi "no config\|not found\|empty"; then
        test_passed "bulk_update_config_field - empty filter results handled gracefully"
    else
        # Should return non-zero exit code
        if [[ $? -ne 0 ]]; then
            test_passed "bulk_update_config_field - empty filter results handled gracefully"
        else
            test_failed "bulk_update_config_field - empty filter results" "error message" "$output"
            ((TESTS_FAILED++))
        fi
    fi
    ((TESTS_RUN++))
}

# Setup test environment
setup_test_env() {
    rm -rf "$TEST_CONFIG_DIR" "$TEST_BACKUP_DIR" 2>/dev/null
    mkdir -p "$TEST_CONFIG_DIR" "$TEST_BACKUP_DIR"
}

# Run all tests
setup_test_env

test_get_configs_by_filter_all
test_get_configs_by_filter_type_server
test_get_configs_by_filter_type_client
test_update_toml_field_simple
test_update_toml_field_nested
test_bulk_update_single_field_dry_run
test_bulk_update_single_field_apply
test_bulk_update_validation_failure_rollback
test_bulk_update_atomic_transaction
test_bulk_update_backup_before_change
test_bulk_update_filter_by_type
test_bulk_update_50_configs_under_5s
test_bulk_update_from_file
test_bulk_update_empty_filter_results

# Summary
echo
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Tests run:    ${TESTS_RUN}"
echo -e "${GREEN}Tests passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Tests failed: ${TESTS_FAILED}${NC}"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi
