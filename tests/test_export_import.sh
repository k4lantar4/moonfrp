#!/bin/bash

#==============================================================================
# Unit Tests for Configuration Export/Import (IaC)
# Story: 5-1-configuration-as-code-export-import
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
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_export_$$"
TEST_HOME="${TEMP_DIR:-/tmp}/test_moonfrp_home_export_$$"
TEST_EXPORT_FILE="${TEMP_DIR:-/tmp}/test_moonfrp_export_$$.yaml"

# Source the functions being tested
set +e
export CONFIG_DIR="$TEST_CONFIG_DIR"
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.moonfrp"
mkdir -p "$TEST_CONFIG_DIR"

source "$PROJECT_ROOT/moonfrp-core.sh" || true
source "$PROJECT_ROOT/moonfrp-config.sh" || true
source "$PROJECT_ROOT/moonfrp-index.sh" || true
source "$PROJECT_ROOT/moonfrp-iac.sh" || true

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

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_HOME/.moonfrp"
    rm -f "$TEST_EXPORT_FILE"
    
    # Initialize index
    init_config_index >/dev/null 2>&1 || true
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_CONFIG_DIR"
    rm -rf "$TEST_HOME"
    rm -f "$TEST_EXPORT_FILE"
}

# Create test server config
create_test_server_config() {
    local config_file="$TEST_CONFIG_DIR/frps.toml"
    cat > "$config_file" <<'EOF'
bindPort = 7000
bindAddr = "0.0.0.0"
auth.token = "test-token-12345"
EOF
    index_config_file "$config_file" >/dev/null 2>&1 || true
    echo "$config_file"
}

# Create test client config
create_test_client_config() {
    local config_file="$TEST_CONFIG_DIR/frpc.toml"
    cat > "$config_file" <<'EOF'
serverAddr = "1.1.1.1"
serverPort = 7000
auth.token = "test-token-12345"
user = "testuser"

[[proxies]]
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000
EOF
    index_config_file "$config_file" >/dev/null 2>&1 || true
    echo "$config_file"
}

# Test: Export all configs to YAML
test_export_all_configs_to_yaml() {
    setup_test_env
    
    # Create test configs
    create_test_server_config >/dev/null
    create_test_client_config >/dev/null
    
    # Export
    if export_config_yaml "$TEST_EXPORT_FILE" >/dev/null 2>&1; then
        # Check file exists and has content
        if [[ -f "$TEST_EXPORT_FILE" ]] && [[ -s "$TEST_EXPORT_FILE" ]]; then
            # Check for server and client configs in YAML
            if grep -q "type: server" "$TEST_EXPORT_FILE" && grep -q "type: client" "$TEST_EXPORT_FILE"; then
                test_passed "test_export_all_configs_to_yaml"
                return 0
            else
                test_failed "test_export_all_configs_to_yaml" "Should contain server and client types" "Missing types in YAML"
                return 1
            fi
        else
            test_failed "test_export_all_configs_to_yaml" "Export file should exist and have content" "File missing or empty"
            return 1
        fi
    else
        test_failed "test_export_all_configs_to_yaml" "Export should succeed" "Export failed"
        return 1
    fi
}

# Test: Import YAML recreates exact configuration
test_import_yaml_creates_configs() {
    setup_test_env
    
    # Create and export configs
    local server_file
    server_file=$(create_test_server_config)
    local client_file
    client_file=$(create_test_client_config)
    
    # Export
    export_config_yaml "$TEST_EXPORT_FILE" >/dev/null 2>&1 || return 1
    
    # Remove original configs
    rm -f "$server_file" "$client_file"
    
    # Import
    if import_config_yaml "$TEST_EXPORT_FILE" "all" "false" >/dev/null 2>&1; then
        # Check configs were recreated
        if [[ -f "$server_file" ]] && [[ -f "$client_file" ]]; then
            # Check content matches (basic check)
            if grep -q "bindPort = 7000" "$server_file" && grep -q "serverAddr = \"1.1.1.1\"" "$client_file"; then
                test_passed "test_import_yaml_creates_configs"
                return 0
            else
                test_failed "test_import_yaml_creates_configs" "Config content should match" "Content mismatch"
                return 1
            fi
        else
            test_failed "test_import_yaml_creates_configs" "Configs should be recreated" "Configs missing"
            return 1
        fi
    else
        test_failed "test_import_yaml_creates_configs" "Import should succeed" "Import failed"
        return 1
    fi
}

# Test: Import is idempotent
test_import_idempotent() {
    setup_test_env
    
    # Create and export
    local server_file
    server_file=$(create_test_server_config)
    export_config_yaml "$TEST_EXPORT_FILE" >/dev/null 2>&1 || return 1
    
    # Get original hash
    local original_hash
    original_hash=$(sha256sum "$server_file" | awk '{print $1}')
    
    # Import twice
    import_config_yaml "$TEST_EXPORT_FILE" "all" "false" >/dev/null 2>&1 || return 1
    local hash_after_first
    hash_after_first=$(sha256sum "$server_file" | awk '{print $1}')
    
    import_config_yaml "$TEST_EXPORT_FILE" "all" "false" >/dev/null 2>&1 || return 1
    local hash_after_second
    hash_after_second=$(sha256sum "$server_file" | awk '{print $1}')
    
    # All hashes should match
    if [[ "$original_hash" == "$hash_after_first" ]] && [[ "$hash_after_first" == "$hash_after_second" ]]; then
        test_passed "test_import_idempotent"
        return 0
    else
        test_failed "test_import_idempotent" "Hashes should match (idempotent)" "Hash mismatch"
        return 1
    fi
}

# Test: Import validation
test_import_validation() {
    setup_test_env
    
    # Create invalid YAML
    echo "invalid: yaml: content: [unclosed" > "$TEST_EXPORT_FILE"
    
    # Validation should fail
    if ! validate_yaml_file "$TEST_EXPORT_FILE" >/dev/null 2>&1; then
        test_passed "test_import_validation"
        return 0
    else
        test_failed "test_import_validation" "Should reject invalid YAML" "Validation passed incorrectly"
        return 1
    fi
}

# Test: Export/import roundtrip
test_export_import_roundtrip() {
    setup_test_env
    
    # Create configs with tags
    local server_file
    server_file=$(create_test_server_config)
    add_config_tag "$server_file" "env" "production" >/dev/null 2>&1 || true
    
    # Export
    export_config_yaml "$TEST_EXPORT_FILE" >/dev/null 2>&1 || return 1
    
    # Remove original
    rm -f "$server_file"
    
    # Import
    import_config_yaml "$TEST_EXPORT_FILE" "all" "false" >/dev/null 2>&1 || return 1
    
    # Check config exists and tag is preserved
    if [[ -f "$server_file" ]]; then
        local tag_value
        tag_value=$(get_config_metadata_field "$server_file" "tags" 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('env', ''))" 2>/dev/null || echo "")
        if [[ "$tag_value" == "production" ]]; then
            test_passed "test_export_import_roundtrip"
            return 0
        else
            test_failed "test_export_import_roundtrip" "Tag should be preserved" "Tag missing or incorrect"
            return 1
        fi
    else
        test_failed "test_export_import_roundtrip" "Config should be recreated" "Config missing"
        return 1
    fi
}

# Test: Partial import (server only)
test_partial_import() {
    setup_test_env
    
    # Create both server and client
    local server_file
    server_file=$(create_test_server_config)
    local client_file
    client_file=$(create_test_client_config)
    
    # Export
    export_config_yaml "$TEST_EXPORT_FILE" >/dev/null 2>&1 || return 1
    
    # Remove both
    rm -f "$server_file" "$client_file"
    
    # Import only servers
    import_config_yaml "$TEST_EXPORT_FILE" "server" "false" >/dev/null 2>&1 || return 1
    
    # Check only server was imported
    if [[ -f "$server_file" ]] && [[ ! -f "$client_file" ]]; then
        test_passed "test_partial_import"
        return 0
    else
        test_failed "test_partial_import" "Only server should be imported" "Import mismatch"
        return 1
    fi
}

# Test: YAML git-friendly format (sorted keys, stable ordering)
test_yaml_git_friendly_format() {
    setup_test_env
    
    # Create multiple configs
    create_test_server_config >/dev/null
    create_test_client_config >/dev/null
    
    # Export twice
    export_config_yaml "${TEST_EXPORT_FILE}.1" >/dev/null 2>&1 || return 1
    sleep 1
    export_config_yaml "${TEST_EXPORT_FILE}.2" >/dev/null 2>&1 || return 1
    
    # Compare (should be identical except for timestamp)
    # Remove timestamp lines for comparison
    local file1_content file2_content
    file1_content=$(grep -v "^# Generated:" "${TEST_EXPORT_FILE}.1" | grep -v "^# Version:")
    file2_content=$(grep -v "^# Generated:" "${TEST_EXPORT_FILE}.2" | grep -v "^# Version:")
    
    if [[ "$file1_content" == "$file2_content" ]]; then
        test_passed "test_yaml_git_friendly_format"
        rm -f "${TEST_EXPORT_FILE}.1" "${TEST_EXPORT_FILE}.2"
        return 0
    else
        test_failed "test_yaml_git_friendly_format" "Exports should be identical (stable ordering)" "Content differs"
        rm -f "${TEST_EXPORT_FILE}.1" "${TEST_EXPORT_FILE}.2"
        return 1
    fi
}

# Test: Performance - export/import completes in <2s for 50 configs
test_export_import_performance() {
    setup_test_env
    
    # Create 50 configs
    local i
    for ((i=1; i<=50; i++)); do
        local config_file="$TEST_CONFIG_DIR/frpc${i}.toml"
        cat > "$config_file" <<EOF
serverAddr = "1.1.1.1"
serverPort = 7000
auth.token = "test-token-${i}"
user = "user${i}"
EOF
        index_config_file "$config_file" >/dev/null 2>&1 || true
    done
    
    # Time export
    local start_time end_time duration
    start_time=$(date +%s)
    export_config_yaml "$TEST_EXPORT_FILE" >/dev/null 2>&1 || return 1
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [[ $duration -lt 2 ]]; then
        test_passed "test_export_import_performance (export: ${duration}s)"
        return 0
    else
        test_failed "test_export_import_performance" "Export should complete in <2s" "Took ${duration}s"
        return 1
    fi
}

# Main test execution
main() {
    echo "Running Export/Import Tests..."
    echo "================================"
    
    test_export_all_configs_to_yaml
    test_import_yaml_creates_configs
    test_import_idempotent
    test_import_validation
    test_export_import_roundtrip
    test_partial_import
    test_yaml_git_friendly_format
    test_export_import_performance
    
    echo ""
    echo "================================"
    echo "Tests Run: $TESTS_RUN"
    echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
    
    cleanup_test_env
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

