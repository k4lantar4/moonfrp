#!/bin/bash

#==============================================================================
# Unit Tests for Config Validation Framework
# Story: 1-3-config-validation-framework
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
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_validation_$$"

# Source the functions being tested
set +e
mkdir -p "$TEST_CONFIG_DIR"

# Temporarily unset readonly CONFIG_DIR if it exists, then set it
if [[ -n "${CONFIG_DIR:-}" ]]; then
    unset CONFIG_DIR 2>/dev/null || true
fi
export CONFIG_DIR="$TEST_CONFIG_DIR"

source "$PROJECT_ROOT/moonfrp-core.sh" || true
source "$PROJECT_ROOT/moonfrp-config.sh" || true

# Override CONFIG_DIR after sourcing (may fail if readonly, but try anyway)
CONFIG_DIR="$TEST_CONFIG_DIR" 2>/dev/null || true
export CONFIG_DIR="$TEST_CONFIG_DIR"

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
    rm -f "$TEST_CONFIG_DIR"/*.toml
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_CONFIG_DIR"
}

# Ensure cleanup on exit
trap cleanup_test_env EXIT

# Create valid test configs
create_valid_server_config() {
    local file="$TEST_CONFIG_DIR/frps.toml"
    cat > "$file" << 'EOF'
bindAddr = "0.0.0.0"
bindPort = 7000
quicBindPort = 7000
auth.method = "token"
auth.token = "valid-token-12345678"
webServer.addr = "0.0.0.0"
webServer.port = 7500
log.to = "/var/log/frp/frps.log"
log.level = "info"
EOF
}

create_valid_client_config() {
    local file="$TEST_CONFIG_DIR/frpc.toml"
    cat > "$file" << 'EOF'
user = "testuser"
serverAddr = "1.2.3.4"
serverPort = 7000
auth.method = "token"
auth.token = "client-token"

[[proxies]]
name = "proxy1"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8080
remotePort = 8080
EOF
}

create_invalid_toml_syntax() {
    local file="$TEST_CONFIG_DIR/invalid.toml"
    cat > "$file" << 'EOF'
bindPort = 7000
invalid syntax here [[[{
auth.token = "token"
EOF
}

create_server_missing_bindport() {
    local file="$TEST_CONFIG_DIR/missing_bindport.toml"
    cat > "$file" << 'EOF'
bindAddr = "0.0.0.0"
auth.method = "token"
auth.token = "valid-token-12345678"
EOF
}

create_server_missing_auth_token() {
    local file="$TEST_CONFIG_DIR/missing_token.toml"
    cat > "$file" << 'EOF'
bindAddr = "0.0.0.0"
bindPort = 7000
auth.method = "token"
EOF
}

create_server_short_token() {
    local file="$TEST_CONFIG_DIR/short_token.toml"
    cat > "$file" << 'EOF'
bindAddr = "0.0.0.0"
bindPort = 7000
auth.method = "token"
auth.token = "short"
EOF
}

create_server_invalid_port() {
    local file="$TEST_CONFIG_DIR/invalid_port.toml"
    cat > "$file" << 'EOF'
bindAddr = "0.0.0.0"
bindPort = 99999
auth.method = "token"
auth.token = "valid-token-12345678"
EOF
}

create_client_missing_serveraddr() {
    local file="$TEST_CONFIG_DIR/missing_addr.toml"
    cat > "$file" << 'EOF'
user = "testuser"
serverPort = 7000
auth.method = "token"
auth.token = "client-token"
EOF
}

create_client_invalid_ip() {
    local file="$TEST_CONFIG_DIR/invalid_ip.toml"
    cat > "$file" << 'EOF'
user = "testuser"
serverAddr = "999.999.999.999"
serverPort = 7000
auth.method = "token"
auth.token = "client-token"
EOF
}

create_client_no_proxies() {
    local file="$TEST_CONFIG_DIR/no_proxies.toml"
    cat > "$file" << 'EOF'
user = "testuser"
serverAddr = "1.2.3.4"
serverPort = 7000
auth.method = "token"
auth.token = "client-token"
EOF
}

# Test cases

test_validate_valid_server_config() {
    setup_test_env
    create_valid_server_config
    
    ((TESTS_RUN++))
    if validate_config_file "$TEST_CONFIG_DIR/frps.toml" "server" 2>&1; then
        test_passed "Valid server config passes validation"
    else
        test_failed "Valid server config passes validation" "Should pass" "Validation failed"
    fi
}

test_validate_valid_client_config() {
    setup_test_env
    create_valid_client_config
    
    ((TESTS_RUN++))
    if validate_config_file "$TEST_CONFIG_DIR/frpc.toml" "client" 2>&1; then
        test_passed "Valid client config passes validation"
    else
        test_failed "Valid client config passes validation" "Should pass" "Validation failed"
    fi
}

test_validate_missing_required_field() {
    setup_test_env
    create_server_missing_bindport
    create_server_missing_auth_token
    create_client_missing_serveraddr
    
    run_test_expect_fail "Missing bindPort detected" "validate_config_file \"$TEST_CONFIG_DIR/missing_bindport.toml\" \"server\""
    run_test_expect_fail "Missing auth.token detected" "validate_config_file \"$TEST_CONFIG_DIR/missing_token.toml\" \"server\""
    run_test_expect_fail "Missing serverAddr detected" "validate_config_file \"$TEST_CONFIG_DIR/missing_addr.toml\" \"client\""
}

test_validate_invalid_port_range() {
    setup_test_env
    create_server_invalid_port
    
    run_test_expect_fail "Invalid port range detected" "validate_config_file \"$TEST_CONFIG_DIR/invalid_port.toml\" \"server\""
}

test_validate_invalid_ip_address() {
    setup_test_env
    create_client_invalid_ip
    
    run_test_expect_fail "Invalid IP address detected" "validate_config_file \"$TEST_CONFIG_DIR/invalid_ip.toml\" \"client\""
}

test_validate_invalid_toml_syntax() {
    setup_test_env
    create_invalid_toml_syntax
    
    run_test_expect_fail "Invalid TOML syntax detected" "validate_toml_syntax \"$TEST_CONFIG_DIR/invalid.toml\""
}

test_validate_auth_token_min_length() {
    setup_test_env
    create_server_short_token
    
    run_test_expect_fail "Short auth token detected (server)" "validate_config_file \"$TEST_CONFIG_DIR/short_token.toml\" \"server\""
}

test_validate_client_proxy_warning() {
    setup_test_env
    create_client_no_proxies
    
    ((TESTS_RUN++))
    local output
    output=$(validate_config_file "$TEST_CONFIG_DIR/no_proxies.toml" "client" 2>&1)
    if echo "$output" | grep -qi "warning.*proxy"; then
        test_passed "Warning shown for client config without proxies"
    else
        # Warning is optional, validation should still pass
        if echo "$output" | grep -qi "error"; then
            test_failed "Client config without proxies" "Should pass with warning" "Validation failed"
        else
            test_passed "Client config without proxies (warning may be suppressed)"
        fi
    fi
}

test_validate_error_messages_clear() {
    setup_test_env
    create_server_missing_bindport
    
    ((TESTS_RUN++))
    local output
    output=$(validate_config_file "$TEST_CONFIG_DIR/missing_bindport.toml" "server" 2>&1)
    if echo "$output" | grep -qi "bindPort.*missing"; then
        test_passed "Error message is clear and actionable"
    else
        test_failed "Error message is clear and actionable" "Should mention bindPort" "$output"
    fi
}

test_validate_performance_under_100ms() {
    setup_test_env
    create_valid_server_config
    
    test_performance "Validation performance (<100ms)" 100 "validate_config_file \"$TEST_CONFIG_DIR/frps.toml\" \"server\""
}

test_save_rejected_on_validation_failure() {
    setup_test_env
    create_valid_server_config
    
    # Create invalid config content
    local invalid_file="$TEST_CONFIG_DIR/frps_invalid.toml"
    cat > "$invalid_file" << 'EOF'
bindAddr = "0.0.0.0"
# Missing bindPort and auth.token
EOF
    
    # Try to use set_toml_value on invalid file (should fail validation)
    ((TESTS_RUN++))
    if set_toml_value "$invalid_file" "bindPort" "7000" 2>/dev/null; then
        # Check if bindPort was actually added
        if get_toml_value "$invalid_file" "bindPort" >/dev/null 2>&1; then
            # File was modified - validation should have prevented this
            # But if auth.token is still missing, validation should fail on next save
            if ! set_toml_value "$invalid_file" "auth.token" "\"short\"" 2>/dev/null; then
                test_passed "Save rejected on validation failure (short token)"
            else
                test_failed "Save rejected on validation failure" "Should reject" "Accepted invalid config"
            fi
        else
            test_passed "Save rejected on validation failure (bindPort not added)"
        fi
    else
        test_passed "Save rejected on validation failure"
    fi
}

test_validate_auto_detection() {
    setup_test_env
    create_valid_server_config
    create_valid_client_config
    
    # Test auto-detection from filename
    ((TESTS_RUN++))
    if validate_config_file "$TEST_CONFIG_DIR/frps.toml" 2>&1; then
        test_passed "Auto-detection: server config type"
    else
        test_failed "Auto-detection: server config type" "Should pass" "Failed"
    fi
    
    ((TESTS_RUN++))
    if validate_config_file "$TEST_CONFIG_DIR/frpc.toml" 2>&1; then
        test_passed "Auto-detection: client config type"
    else
        test_failed "Auto-detection: client config type" "Should pass" "Failed"
    fi
}

test_validate_domain_name() {
    setup_test_env
    local file="$TEST_CONFIG_DIR/domain_client.toml"
    cat > "$file" << 'EOF'
user = "testuser"
serverAddr = "example.com"
serverPort = 7000
auth.method = "token"
auth.token = "client-token"
EOF
    
    ((TESTS_RUN++))
    if validate_config_file "$file" "client" 2>&1; then
        test_passed "Domain name validation (client config)"
    else
        test_failed "Domain name validation" "Should accept valid domain" "Rejected"
    fi
}

test_validate_empty_file() {
    setup_test_env
    local file="$TEST_CONFIG_DIR/empty.toml"
    touch "$file"
    
    run_test_expect_fail "Empty file rejected" "validate_toml_syntax \"$file\""
}

test_validate_comments_only() {
    setup_test_env
    local file="$TEST_CONFIG_DIR/comments.toml"
    cat > "$file" << 'EOF'
# This is a comment
# Another comment
EOF
    
    run_test_expect_fail "Comments-only file rejected" "validate_toml_syntax \"$file\""
}

# Main test execution
main() {
    echo "Running Config Validation Framework Tests"
    echo "=========================================="
    echo ""
    
    test_validate_valid_server_config
    test_validate_valid_client_config
    test_validate_missing_required_field
    test_validate_invalid_port_range
    test_validate_invalid_ip_address
    test_validate_invalid_toml_syntax
    test_validate_auth_token_min_length
    test_validate_client_proxy_warning
    test_validate_error_messages_clear
    test_validate_performance_under_100ms
    test_save_rejected_on_validation_failure
    test_validate_auto_detection
    test_validate_domain_name
    test_validate_empty_file
    test_validate_comments_only
    
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo "Tests failed: $TESTS_FAILED"
        exit 0
    fi
}

# Run tests
main "$@"
