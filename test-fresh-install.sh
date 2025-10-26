#!/bin/bash

#==============================================================================
# MoonFRP Fresh Server Test Suite
# Version: 2.0.0
# Description: Comprehensive testing for fresh server deployment
#==============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Test configuration
readonly TEST_DIR="/tmp/moonfrp-test"
readonly TEST_LOG="$TEST_DIR/test.log"
readonly TEST_RESULTS="$TEST_DIR/results.txt"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[$timestamp] [INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
        "TEST")  echo -e "${BLUE}[$timestamp] [TEST]${NC} $message" ;;
    esac
    
    # Also log to file
    echo "[$timestamp] [$level] $message" >> "$TEST_LOG"
}

# Test function
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    log "TEST" "Running: $test_name"
    
    if $test_function; then
        ((TESTS_PASSED++))
        log "INFO" "✓ PASSED: $test_name"
        echo "PASS: $test_name" >> "$TEST_RESULTS"
        return 0
    else
        ((TESTS_FAILED++))
        log "ERROR" "✗ FAILED: $test_name"
        echo "FAIL: $test_name" >> "$TEST_RESULTS"
        return 1
    fi
}

# Setup test environment
setup_test_environment() {
    log "INFO" "Setting up test environment..."
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    
    # Clean up any existing MoonFRP installation
    systemctl stop moonfrp-server moonfrp-client* moonfrp-visitor* 2>/dev/null || true
    rm -rf /opt/frp /etc/frp /var/log/frp /etc/moonfrp
    rm -f /usr/local/bin/moonfrp /usr/bin/moonfrp
    
    log "INFO" "Test environment ready"
}

# Test 1: Clean installation
test_clean_installation() {
    log "INFO" "Testing clean installation..."
    
    # Run installation
    if ! bash "$(dirname "${BASH_SOURCE[0]}")/install-new.sh"; then
        log "ERROR" "Installation failed"
        return 1
    fi
    
    # Verify installation
    if [[ ! -x "/usr/local/bin/moonfrp" ]]; then
        log "ERROR" "MoonFRP binary not found"
        return 1
    fi
    
    if [[ ! -f "/etc/moonfrp/config" ]]; then
        log "ERROR" "Configuration file not found"
        return 1
    fi
    
    log "INFO" "Clean installation successful"
    return 0
}

# Test 2: Environment variable configuration
test_environment_variables() {
    log "INFO" "Testing environment variable configuration..."
    
    # Set environment variables
    export MOONFRP_SERVER_BIND_PORT="7001"
    export MOONFRP_SERVER_AUTH_TOKEN="test-token-123"
    export MOONFRP_SERVER_DASHBOARD_PASSWORD="test-password-123"
    export MOONFRP_CLIENT_SERVER_ADDR="127.0.0.1"
    export MOONFRP_CLIENT_AUTH_TOKEN="test-token-123"
    
    # Test server setup
    if ! moonfrp setup server; then
        log "ERROR" "Server setup with environment variables failed"
        return 1
    fi
    
    # Verify configuration
    if ! grep -q "bindPort = 7001" /etc/frp/frps.toml; then
        log "ERROR" "Environment variable not applied to server config"
        return 1
    fi
    
    if ! grep -q "test-token-123" /etc/frp/frps.toml; then
        log "ERROR" "Auth token not applied to server config"
        return 1
    fi
    
    log "INFO" "Environment variable configuration successful"
    return 0
}

# Test 3: Server setup
test_server_setup() {
    log "INFO" "Testing server setup..."
    
    # Setup server
    if ! moonfrp setup server; then
        log "ERROR" "Server setup failed"
        return 1
    fi
    
    # Verify service exists
    if [[ ! -f "/etc/systemd/system/moonfrp-server.service" ]]; then
        log "ERROR" "Server service file not created"
        return 1
    fi
    
    # Start service
    if ! moonfrp service start moonfrp-server; then
        log "ERROR" "Failed to start server service"
        return 1
    fi
    
    # Check service status
    if ! systemctl is-active --quiet moonfrp-server; then
        log "ERROR" "Server service not running"
        return 1
    fi
    
    log "INFO" "Server setup successful"
    return 0
}

# Test 4: Client setup
test_client_setup() {
    log "INFO" "Testing client setup..."
    
    # Setup client
    if ! moonfrp setup client; then
        log "ERROR" "Client setup failed"
        return 1
    fi
    
    # Verify service exists
    if [[ ! -f "/etc/systemd/system/moonfrp-client.service" ]]; then
        log "ERROR" "Client service file not created"
        return 1
    fi
    
    # Start service
    if ! moonfrp service start moonfrp-client; then
        log "ERROR" "Failed to start client service"
        return 1
    fi
    
    # Check service status
    if ! systemctl is-active --quiet moonfrp-client; then
        log "ERROR" "Client service not running"
        return 1
    fi
    
    log "INFO" "Client setup successful"
    return 0
}

# Test 5: Multi-IP setup
test_multi_ip_setup() {
    log "INFO" "Testing multi-IP setup..."
    
    # Set multi-IP environment variables
    export MOONFRP_SERVER_IPS="127.0.0.1,127.0.0.1"
    export MOONFRP_SERVER_PORTS="7000,7000"
    export MOONFRP_CLIENT_PORTS="8080,8081"
    export MOONFRP_CLIENT_AUTH_TOKEN="test-token-123"
    
    # Setup multi-IP clients
    if ! moonfrp setup multi-ip; then
        log "ERROR" "Multi-IP setup failed"
        return 1
    fi
    
    # Verify configurations exist
    if [[ ! -f "/etc/frp/frpc_1.toml" ]]; then
        log "ERROR" "First client configuration not created"
        return 1
    fi
    
    if [[ ! -f "/etc/frp/frpc_2.toml" ]]; then
        log "ERROR" "Second client configuration not created"
        return 1
    fi
    
    # Verify services exist
    if [[ ! -f "/etc/systemd/system/moonfrp-client-1.service" ]]; then
        log "ERROR" "First client service not created"
        return 1
    fi
    
    if [[ ! -f "/etc/systemd/system/moonfrp-client-2.service" ]]; then
        log "ERROR" "Second client service not created"
        return 1
    fi
    
    log "INFO" "Multi-IP setup successful"
    return 0
}

# Test 6: Service management
test_service_management() {
    log "INFO" "Testing service management..."
    
    # Test service status
    if ! moonfrp service status; then
        log "ERROR" "Service status command failed"
        return 1
    fi
    
    # Test service stop
    if ! moonfrp service stop all; then
        log "ERROR" "Service stop command failed"
        return 1
    fi
    
    # Test service start
    if ! moonfrp service start all; then
        log "ERROR" "Service start command failed"
        return 1
    fi
    
    # Test service restart
    if ! moonfrp service restart all; then
        log "ERROR" "Service restart command failed"
        return 1
    fi
    
    log "INFO" "Service management successful"
    return 0
}

# Test 7: Health check
test_health_check() {
    log "INFO" "Testing health check..."
    
    # Run health check
    if ! moonfrp health check; then
        log "ERROR" "Health check failed"
        return 1
    fi
    
    log "INFO" "Health check successful"
    return 0
}

# Test 8: Configuration management
test_configuration_management() {
    log "INFO" "Testing configuration management..."
    
    # Test configuration listing
    if ! moonfrp config; then
        log "ERROR" "Configuration wizard failed"
        return 1
    fi
    
    # Test backup
    if ! moonfrp backup; then
        log "ERROR" "Configuration backup failed"
        return 1
    fi
    
    log "INFO" "Configuration management successful"
    return 0
}

# Test 9: Log viewing
test_log_viewing() {
    log "INFO" "Testing log viewing..."
    
    # Test log viewing
    if ! moonfrp logs moonfrp-server; then
        log "ERROR" "Log viewing failed"
        return 1
    fi
    
    log "INFO" "Log viewing successful"
    return 0
}

# Test 10: Uninstall
test_uninstall() {
    log "INFO" "Testing uninstall..."
    
    # Test uninstall
    if ! moonfrp uninstall; then
        log "ERROR" "Uninstall failed"
        return 1
    fi
    
    # Verify uninstall
    if [[ -f "/usr/local/bin/moonfrp" ]]; then
        log "ERROR" "MoonFRP binary still exists after uninstall"
        return 1
    fi
    
    if [[ -d "/opt/frp" ]]; then
        log "ERROR" "FRP directory still exists after uninstall"
        return 1
    fi
    
    log "INFO" "Uninstall successful"
    return 0
}

# Cleanup test environment
cleanup_test_environment() {
    log "INFO" "Cleaning up test environment..."
    
    # Stop all services
    systemctl stop moonfrp-server moonfrp-client* moonfrp-visitor* 2>/dev/null || true
    
    # Remove services
    rm -f /etc/systemd/system/moonfrp-*.service
    systemctl daemon-reload
    
    # Remove directories
    rm -rf /opt/frp /etc/frp /var/log/frp /etc/moonfrp
    
    # Remove binaries
    rm -f /usr/local/bin/moonfrp /usr/bin/moonfrp
    
    log "INFO" "Test environment cleaned up"
}

# Display test results
display_results() {
    echo
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         Test Results                 ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}Tests Run:${NC} $TESTS_RUN"
    echo -e "${GREEN}Tests Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}Tests Failed:${NC} $TESTS_FAILED"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"
        echo -e "${GREEN}MoonFRP is ready for production use.${NC}"
    else
        echo -e "${RED}❌ Some tests failed.${NC}"
        echo -e "${RED}Please check the test log: $TEST_LOG${NC}"
    fi
    
    echo
    echo -e "${CYAN}Test Log:${NC} $TEST_LOG"
    echo -e "${CYAN}Results:${NC} $TEST_RESULTS"
}

# Main test function
main() {
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        MoonFRP Test Suite            ║${NC}"
    echo -e "${PURPLE}║      Fresh Server Deployment         ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo
    
    log "INFO" "Starting MoonFRP test suite..."
    
    # Setup
    setup_test_environment
    
    # Run tests
    run_test "Clean Installation" test_clean_installation
    run_test "Environment Variables" test_environment_variables
    run_test "Server Setup" test_server_setup
    run_test "Client Setup" test_client_setup
    run_test "Multi-IP Setup" test_multi_ip_setup
    run_test "Service Management" test_service_management
    run_test "Health Check" test_health_check
    run_test "Configuration Management" test_configuration_management
    run_test "Log Viewing" test_log_viewing
    run_test "Uninstall" test_uninstall
    
    # Cleanup
    cleanup_test_environment
    
    # Display results
    display_results
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"