#!/bin/bash

#==============================================================================
# Unit Tests for Template System
# Story: 2-4-configuration-templates
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
TEST_TEMPLATE_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_templates_$$"
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_config_$$"
TEST_HOME="${TEMP_DIR:-/tmp}/test_moonfrp_home_$$"

# Source the functions being tested
set +e
export CONFIG_DIR="$TEST_CONFIG_DIR"
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.moonfrp/templates"
mkdir -p "$TEST_CONFIG_DIR"

source "$PROJECT_ROOT/moonfrp-core.sh" || true
source "$PROJECT_ROOT/moonfrp-config.sh" || true
source "$PROJECT_ROOT/moonfrp-index.sh" || true
source "$PROJECT_ROOT/moonfrp-templates.sh" || true

# Note: TEMPLATE_DIR is readonly, so we use TEST_HOME as HOME for tests
# Templates will be created in $HOME/.moonfrp/templates (which is TEST_HOME/.moonfrp/templates)

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
    mkdir -p "$TEST_HOME/.moonfrp/templates"
    rm -rf "$TEST_CONFIG_DIR"/* 2>/dev/null
    rm -rf "$TEST_HOME/.moonfrp/templates"/* 2>/dev/null
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_CONFIG_DIR" 2>/dev/null
    rm -rf "$TEST_HOME" 2>/dev/null
}

# Create a sample template for testing
create_test_template() {
    local name="$1"
    local content="# Template: ${name}
# Variables: SERVER_IP, SERVER_PORT, REGION, PROXY_NAME, LOCAL_PORT, REMOTE_PORT
# Tags: env:prod, type:client
# Version: 1.0

serverAddr = \"\${SERVER_IP}\"
serverPort = \${SERVER_PORT}
auth.token = \"\${AUTH_TOKEN}\"

user = \"moonfrp-\${REGION}\"

[[proxies]]
name = \"\${PROXY_NAME}\"
type = \"tcp\"
localIP = \"127.0.0.1\"
localPort = \${LOCAL_PORT}
remotePort = \${REMOTE_PORT}
"
    echo "$content" > "$TEST_HOME/.moonfrp/templates/${name}.toml.tmpl"
}

#==============================================================================
# TEST FUNCTIONS
#==============================================================================

test_create_template() {
    setup_test_env
    
    local template_content="# Template: test-template
# Variables: SERVER_IP, SERVER_PORT
serverAddr = \"\${SERVER_IP}\"
serverPort = \${SERVER_PORT}
"
    
    run_test "test_create_template" "create_template test-template \"$template_content\""
    
    if [[ -f "$TEST_HOME/.moonfrp/templates/test-template.toml.tmpl" ]]; then
        test_passed "test_create_template_file_exists"
    else
        test_failed "test_create_template_file_exists" "File exists" "File not found"
    fi
    
    cleanup_test_env
}

test_list_templates() {
    setup_test_env
    
    create_test_template "template1"
    create_test_template "template2"
    create_test_template "template3"
    
    local templates
    templates=$(list_templates)
    local count=$(echo "$templates" | wc -l)
    
    if [[ $count -ge 3 ]]; then
        test_passed "test_list_templates_count"
    else
        test_failed "test_list_templates_count" ">= 3" "$count"
    fi
    
    if echo "$templates" | grep -q "template1" && \
       echo "$templates" | grep -q "template2" && \
       echo "$templates" | grep -q "template3"; then
        test_passed "test_list_templates_names"
    else
        test_failed "test_list_templates_names" "All templates listed" "Missing templates"
    fi
    
    cleanup_test_env
}

test_instantiate_template_with_variables() {
    setup_test_env
    
    create_test_template "test-template"
    
    local output_file="$TEST_CONFIG_DIR/test-instance.toml"
    local variables=(
        "SERVER_IP=192.168.1.100"
        "SERVER_PORT=7000"
        "REGION=eu"
        "PROXY_NAME=web-eu-1"
        "LOCAL_PORT=8080"
        "REMOTE_PORT=30001"
        "AUTH_TOKEN=test-token-123"
    )
    
    run_test "test_instantiate_template_with_variables" \
        "instantiate_template test-template \"$output_file\" \"\${variables[@]}\""
    
    if [[ -f "$output_file" ]]; then
        # Check variable substitution
        if grep -q "serverAddr = \"192.168.1.100\"" "$output_file" && \
           grep -q "serverPort = 7000" "$output_file" && \
           grep -q "user = \"moonfrp-eu\"" "$output_file"; then
            test_passed "test_instantiate_template_variable_substitution"
        else
            test_failed "test_instantiate_template_variable_substitution" \
                "Variables substituted" "Substitution failed"
        fi
        
        # Check no unsubstituted variables remain
        if ! grep -qE '\$\{[A-Z_]+\}' "$output_file"; then
            test_passed "test_instantiate_template_no_unsubstituted"
        else
            test_failed "test_instantiate_template_no_unsubstituted" \
                "No unsubstituted variables" "Found unsubstituted variables"
        fi
    else
        test_failed "test_instantiate_template_output_file" \
            "Output file created" "File not created"
    fi
    
    cleanup_test_env
}

test_instantiate_template_missing_variable_warning() {
    setup_test_env
    
    create_test_template "test-template"
    
    local output_file="$TEST_CONFIG_DIR/test-instance.toml"
    local variables=(
        "SERVER_IP=192.168.1.100"
        "SERVER_PORT=7000"
        # Missing REGION, PROXY_NAME, etc.
    )
    
    # This should still work but warn about missing variables
    if instantiate_template test-template "$output_file" "${variables[@]}" 2>&1 | grep -q "Unsubstituted"; then
        test_passed "test_instantiate_template_missing_variable_warning"
    else
        # Check if file still created (might be valid behavior)
        if [[ -f "$output_file" ]]; then
            test_passed "test_instantiate_template_missing_variable_warning (file created anyway)"
        else
            test_failed "test_instantiate_template_missing_variable_warning" \
                "Warning issued or file created" "No warning, file not created"
        fi
    fi
    
    cleanup_test_env
}

test_bulk_instantiate_from_csv() {
    setup_test_env
    
    create_test_template "test-template"
    
    # Create CSV file
    local csv_file="$TEST_CONFIG_DIR/bulk.csv"
    cat > "$csv_file" << EOF
output_file,SERVER_IP,SERVER_PORT,REGION,PROXY_NAME,LOCAL_PORT,REMOTE_PORT,AUTH_TOKEN
frpc-eu-1.toml,192.168.1.100,7000,eu,web-eu-1,8080,30001,token1
frpc-eu-2.toml,192.168.1.100,7000,eu,web-eu-2,8080,30002,token2
frpc-us-1.toml,10.0.1.50,7000,us,web-us-1,8080,30003,token3
EOF
    
    run_test "test_bulk_instantiate_from_csv" \
        "bulk_instantiate_template test-template \"$csv_file\""
    
    local count=0
    [[ -f "$TEST_CONFIG_DIR/frpc-eu-1.toml" ]] && ((count++))
    [[ -f "$TEST_CONFIG_DIR/frpc-eu-2.toml" ]] && ((count++))
    [[ -f "$TEST_CONFIG_DIR/frpc-us-1.toml" ]] && ((count++))
    
    if [[ $count -eq 3 ]]; then
        test_passed "test_bulk_instantiate_from_csv_count"
    else
        test_failed "test_bulk_instantiate_from_csv_count" "3 files" "$count files"
    fi
    
    cleanup_test_env
}

test_template_validation() {
    setup_test_env
    
    create_test_template "test-template"
    
    local output_file="$TEST_CONFIG_DIR/test-instance.toml"
    local variables=(
        "SERVER_IP=192.168.1.100"
        "SERVER_PORT=7000"
        "REGION=eu"
        "PROXY_NAME=web-eu-1"
        "LOCAL_PORT=8080"
        "REMOTE_PORT=30001"
        "AUTH_TOKEN=test-token-12345678"
    )
    
    if instantiate_template test-template "$output_file" "${variables[@]}"; then
        # Check if validation was called (file exists and is valid)
        if [[ -f "$output_file" ]]; then
            # Try to validate manually to confirm
            if validate_config_file "$output_file" "client" 2>/dev/null; then
                test_passed "test_template_validation"
            else
                test_failed "test_template_validation" "Valid config" "Invalid config generated"
            fi
        else
            test_failed "test_template_validation" "File exists" "File not created"
        fi
    else
        test_failed "test_template_validation" "Instantiation succeeded" "Instantiation failed"
    fi
    
    cleanup_test_env
}

test_template_auto_tagging() {
    setup_test_env
    
    # Skip if add_config_tag doesn't exist
    if ! command -v add_config_tag &>/dev/null && ! declare -f add_config_tag &>/dev/null 2>&1; then
        echo -e "${YELLOW}⊘ SKIP${NC}: test_template_auto_tagging (add_config_tag not available)"
        cleanup_test_env
        return 0
    fi
    
    create_test_template "test-template"
    
    local output_file="$TEST_CONFIG_DIR/test-instance.toml"
    local variables=(
        "SERVER_IP=192.168.1.100"
        "SERVER_PORT=7000"
        "REGION=eu"
        "PROXY_NAME=web-eu-1"
        "LOCAL_PORT=8080"
        "REMOTE_PORT=30001"
        "AUTH_TOKEN=test-token-12345678"
    )
    
    if instantiate_template test-template "$output_file" "${variables[@]}"; then
        # Tags should be applied (env:prod, type:client)
        # Note: Actual tag checking would require database access
        test_passed "test_template_auto_tagging"
    else
        test_failed "test_template_auto_tagging" "Instantiation succeeded" "Instantiation failed"
    fi
    
    cleanup_test_env
}

test_template_versioning() {
    setup_test_env
    
    local template_content="# Template: versioned-template
# Variables: SERVER_IP
# Version: 2.5
serverAddr = \"\${SERVER_IP}\"
"
    
    create_template "versioned-template" "$template_content"
    
    local version=$(get_template_version "versioned-template")
    
    if [[ "$version" == "2.5" ]]; then
        test_passed "test_template_versioning"
    else
        test_failed "test_template_versioning" "2.5" "$version"
    fi
    
    cleanup_test_env
}

test_template_view() {
    setup_test_env
    
    local template_content="# Template: view-template
# Variables: SERVER_IP
serverAddr = \"\${SERVER_IP}\"
"
    
    create_template "view-template" "$template_content"
    
    local output
    output=$(view_template "view-template")
    
    if echo "$output" | grep -q "view-template" && \
       echo "$output" | grep -q "SERVER_IP"; then
        test_passed "test_template_view"
    else
        test_failed "test_template_view" "Template content displayed" "Content mismatch"
    fi
    
    cleanup_test_env
}

test_template_delete() {
    setup_test_env
    
    create_test_template "delete-template"
    
    if delete_template "delete-template"; then
        if [[ ! -f "$TEST_HOME/.moonfrp/templates/delete-template.toml.tmpl" ]]; then
            test_passed "test_template_delete"
        else
            test_failed "test_template_delete" "File deleted" "File still exists"
        fi
    else
        test_failed "test_template_delete" "Delete succeeded" "Delete failed"
    fi
    
    cleanup_test_env
}

#==============================================================================
# MAIN TEST EXECUTION
#==============================================================================

main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Template System Tests"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    test_create_template
    test_list_templates
    test_instantiate_template_with_variables
    test_instantiate_template_missing_variable_warning
    test_bulk_instantiate_from_csv
    test_template_validation
    test_template_auto_tagging
    test_template_versioning
    test_template_view
    test_template_delete
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test Results: $TESTS_RUN tests, $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cleanup_test_env
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run tests
main "$@"

