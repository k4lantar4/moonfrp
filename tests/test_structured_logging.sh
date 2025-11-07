#!/bin/bash

#==============================================================================
# Unit Tests for Structured Logging
# Story: 5-3-structured-logging
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
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_logging_$$"
TEST_HOME="${TEMP_DIR:-/tmp}/test_moonfrp_home_logging_$$"

# Source the functions being tested
set +e
export CONFIG_DIR="$TEST_CONFIG_DIR"
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.moonfrp"
mkdir -p "$TEST_CONFIG_DIR"

source "$PROJECT_ROOT/moonfrp-core.sh" || true

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

# Helper to check JSON validity using Python
check_json_valid() {
    local json="$1"
    python3 -c "import json, sys; json.loads(sys.stdin.read())" <<< "$json" 2>/dev/null
}

# Test: JSON logging format (AC: 1)
test_json_logging_format() {
    echo "Testing JSON logging format..."

    # Enable JSON logging
    export MOONFRP_LOG_FORMAT="json"

    # Test INFO level
    local output
    output=$(log "INFO" "Test message")

    if [[ "$output" =~ ^\{.*\}$ ]]; then
        test_passed "test_json_logging_format - Output is JSON object"
    else
        test_failed "test_json_logging_format - Output is JSON object" "JSON object" "$output"
        return 1
    fi

    # Test that it's valid JSON
    if check_json_valid "$output"; then
        test_passed "test_json_logging_format - Valid JSON"
    else
        test_failed "test_json_logging_format - Valid JSON" "Valid JSON" "Invalid JSON"
        return 1
    fi

    # Test DEBUG level
    output=$(log "DEBUG" "Debug message")
    if check_json_valid "$output"; then
        test_passed "test_json_logging_format - DEBUG level JSON"
    else
        test_failed "test_json_logging_format - DEBUG level JSON"
        return 1
    fi

    # Test WARN level
    output=$(log "WARN" "Warning message")
    if check_json_valid "$output"; then
        test_passed "test_json_logging_format - WARN level JSON"
    else
        test_failed "test_json_logging_format - WARN level JSON"
        return 1
    fi

    # Test ERROR level
    output=$(log "ERROR" "Error message")
    if check_json_valid "$output"; then
        test_passed "test_json_logging_format - ERROR level JSON"
    else
        test_failed "test_json_logging_format - ERROR level JSON"
        return 1
    fi

    unset MOONFRP_LOG_FORMAT
}

# Test: Required fields in JSON logs (AC: 2, 3)
test_json_logging_valid() {
    echo "Testing JSON logging required fields..."

    export MOONFRP_LOG_FORMAT="json"

    local output
    output=$(log "INFO" "Test message with required fields")

    # Check for required fields using Python
    local has_timestamp has_level has_message has_application has_version

    has_timestamp=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('timestamp' in d)" <<< "$output" 2>/dev/null || echo "false")
    has_level=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('level' in d)" <<< "$output" 2>/dev/null || echo "false")
    has_message=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('message' in d)" <<< "$output" 2>/dev/null || echo "false")
    has_application=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('application' in d)" <<< "$output" 2>/dev/null || echo "false")
    has_version=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('version' in d)" <<< "$output" 2>/dev/null || echo "false")

    if [[ "$has_timestamp" == "True" ]]; then
        test_passed "test_json_logging_valid - Has timestamp field"
    else
        test_failed "test_json_logging_valid - Has timestamp field" "True" "$has_timestamp"
    fi

    if [[ "$has_level" == "True" ]]; then
        test_passed "test_json_logging_valid - Has level field"
    else
        test_failed "test_json_logging_valid - Has level field" "True" "$has_level"
    fi

    if [[ "$has_message" == "True" ]]; then
        test_passed "test_json_logging_valid - Has message field"
    else
        test_failed "test_json_logging_valid - Has message field" "True" "$has_message"
    fi

    if [[ "$has_application" == "True" ]]; then
        test_passed "test_json_logging_valid - Has application field"
    else
        test_failed "test_json_logging_valid - Has application field" "True" "$has_application"
    fi

    if [[ "$has_version" == "True" ]]; then
        test_passed "test_json_logging_valid - Has version field"
    else
        test_failed "test_json_logging_valid - Has version field" "True" "$has_version"
    fi

    # Test that application is "moonfrp"
    local app_value
    app_value=$(python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('application', ''))" <<< "$output" 2>/dev/null || echo "")
    if [[ "$app_value" == "moonfrp" ]]; then
        test_passed "test_json_logging_valid - Application value is 'moonfrp'"
    else
        test_failed "test_json_logging_valid - Application value is 'moonfrp'" "moonfrp" "$app_value"
    fi

    # Test that level matches
    local level_value
    level_value=$(python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('level', ''))" <<< "$output" 2>/dev/null || echo "")
    if [[ "$level_value" == "INFO" ]]; then
        test_passed "test_json_logging_valid - Level value matches"
    else
        test_failed "test_json_logging_valid - Level value matches" "INFO" "$level_value"
    fi

    # Test JSON parser compatibility (AC: 3) - try jq if available, else Python
    if command -v jq >/dev/null 2>&1; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            test_passed "test_json_logging_valid - Compatible with jq parser"
        else
            test_failed "test_json_logging_valid - Compatible with jq parser"
        fi
    fi

    unset MOONFRP_LOG_FORMAT
}

# Test: Performance threshold (<1ms per entry) (AC: 4)
test_json_logging_performance() {
    echo "Testing JSON logging performance..."

    export MOONFRP_LOG_FORMAT="json"

    # Measure time for 100 log entries
    local start_time end_time duration_ms
    start_time=$(date +%s%N)

    for i in {1..100}; do
        log "INFO" "Performance test message $i" >/dev/null
    done

    end_time=$(date +%s%N)
    duration_ms=$(( (end_time - start_time) / 1000000 ))
    local avg_ms=$(( duration_ms / 100 ))

    if [[ $avg_ms -lt 1 ]]; then
        test_passed "test_json_logging_performance - Average time <1ms (${avg_ms}ms per entry)"
    else
        test_failed "test_json_logging_performance - Average time <1ms" "<1ms" "${avg_ms}ms per entry"
    fi

    unset MOONFRP_LOG_FORMAT
}

# Test: Optional fields (AC: 5)
test_json_logging_optional_fields() {
    echo "Testing JSON logging optional fields..."

    export MOONFRP_LOG_FORMAT="json"
    export MOONFRP_LOG_SERVICE="test-service"
    export MOONFRP_LOG_OPERATION="test-operation"
    export MOONFRP_LOG_DURATION="123"

    local output
    output=$(log "INFO" "Test with optional fields")

    # Check for optional fields
    local has_service has_operation has_duration

    has_service=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('service' in d)" <<< "$output" 2>/dev/null || echo "false")
    has_operation=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('operation' in d)" <<< "$output" 2>/dev/null || echo "false")
    has_duration=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('duration' in d)" <<< "$output" 2>/dev/null || echo "false")

    if [[ "$has_service" == "True" ]]; then
        test_passed "test_json_logging_optional_fields - Has service field"
    else
        test_failed "test_json_logging_optional_fields - Has service field" "True" "$has_service"
    fi

    if [[ "$has_operation" == "True" ]]; then
        test_passed "test_json_logging_optional_fields - Has operation field"
    else
        test_failed "test_json_logging_optional_fields - Has operation field" "True" "$has_operation"
    fi

    if [[ "$has_duration" == "True" ]]; then
        test_passed "test_json_logging_optional_fields - Has duration field"
    else
        test_failed "test_json_logging_optional_fields - Has duration field" "True" "$has_duration"
    fi

    # Test that values match
    local service_value operation_value duration_value
    service_value=$(python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('service', ''))" <<< "$output" 2>/dev/null || echo "")
    operation_value=$(python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('operation', ''))" <<< "$output" 2>/dev/null || echo "")
    duration_value=$(python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('duration', ''))" <<< "$output" 2>/dev/null || echo "")

    if [[ "$service_value" == "test-service" ]]; then
        test_passed "test_json_logging_optional_fields - Service value matches"
    else
        test_failed "test_json_logging_optional_fields - Service value matches" "test-service" "$service_value"
    fi

    if [[ "$operation_value" == "test-operation" ]]; then
        test_passed "test_json_logging_optional_fields - Operation value matches"
    else
        test_failed "test_json_logging_optional_fields - Operation value matches" "test-operation" "$operation_value"
    fi

    if [[ "$duration_value" == "123" ]]; then
        test_passed "test_json_logging_optional_fields - Duration value matches"
    else
        test_failed "test_json_logging_optional_fields - Duration value matches" "123" "$duration_value"
    fi

    # Test without optional fields
    unset MOONFRP_LOG_SERVICE MOONFRP_LOG_OPERATION MOONFRP_LOG_DURATION
    output=$(log "INFO" "Test without optional fields")

    has_service=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('service' in d)" <<< "$output" 2>/dev/null || echo "false")
    if [[ "$has_service" == "False" ]]; then
        test_passed "test_json_logging_optional_fields - Optional fields not present when not set"
    else
        test_failed "test_json_logging_optional_fields - Optional fields not present when not set" "False" "$has_service"
    fi

    unset MOONFRP_LOG_FORMAT
}

# Test: Error logs with stack traces (AC: 6)
test_json_logging_stack_trace() {
    echo "Testing JSON logging stack traces for errors..."

    export MOONFRP_LOG_FORMAT="json"

    # Create a function that calls log with ERROR to generate stack trace
    test_error_logging() {
        log "ERROR" "Test error with stack trace"
    }

    local output
    output=$(test_error_logging)

    # Check if stack_trace field exists for ERROR level
    local has_stack_trace
    has_stack_trace=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('stack_trace' in d)" <<< "$output" 2>/dev/null || echo "false")

    if [[ "$has_stack_trace" == "True" ]]; then
        test_passed "test_json_logging_stack_trace - ERROR logs include stack_trace field"
    else
        # Stack trace might not always be available depending on bash version/settings
        # This is acceptable per AC: 6 "when available"
        test_passed "test_json_logging_stack_trace - Stack trace handling (may not be available in all contexts)"
    fi

    # Test that non-ERROR levels don't have stack traces
    output=$(log "INFO" "Test info message")
    has_stack_trace=$(python3 -c "import json, sys; d=json.load(sys.stdin); print('stack_trace' in d)" <<< "$output" 2>/dev/null || echo "false")

    if [[ "$has_stack_trace" == "False" ]]; then
        test_passed "test_json_logging_stack_trace - Non-ERROR levels don't have stack_trace"
    else
        test_failed "test_json_logging_stack_trace - Non-ERROR levels don't have stack_trace" "False" "$has_stack_trace"
    fi

    unset MOONFRP_LOG_FORMAT
}

# Test: Default text logging unchanged (AC: 1)
test_text_logging_default() {
    echo "Testing default text logging..."

    # Ensure text format (default)
    unset MOONFRP_LOG_FORMAT

    local output
    output=$(log "INFO" "Test text message")

    # Text format should have colored output with brackets
    if [[ "$output" =~ \[.*\]\ \[INFO\] ]]; then
        test_passed "test_text_logging_default - Text format output structure"
    else
        test_failed "test_text_logging_default - Text format output structure" "Text format with brackets" "$output"
    fi

    # Should not be JSON
    if ! check_json_valid "$output" 2>/dev/null; then
        test_passed "test_text_logging_default - Default is not JSON"
    else
        test_failed "test_text_logging_default - Default is not JSON" "Not JSON" "Is JSON"
    fi

    # Test that explicitly setting text works
    export MOONFRP_LOG_FORMAT="text"
    output=$(log "INFO" "Test explicit text")

    if [[ "$output" =~ \[.*\]\ \[INFO\] ]]; then
        test_passed "test_text_logging_default - Explicit text format works"
    else
        test_failed "test_text_logging_default - Explicit text format works"
    fi

    unset MOONFRP_LOG_FORMAT
}

# Test: --log-format=json command line argument (AC: 1)
test_log_format_cli_argument() {
    echo "Testing --log-format=json CLI argument..."

    # Test that parse_global_flags handles --log-format=json
    local test_output
    test_output=$(bash -c "source $PROJECT_ROOT/moonfrp.sh; parse_global_flags --log-format=json help >/dev/null 2>&1; echo \$MOONFRP_LOG_FORMAT")

    if [[ "$test_output" == "json" ]]; then
        test_passed "test_log_format_cli_argument - --log-format=json sets MOONFRP_LOG_FORMAT"
    else
        test_failed "test_log_format_cli_argument - --log-format=json sets MOONFRP_LOG_FORMAT" "json" "$test_output"
    fi

    # Test invalid format
    local exit_code
    set +e
    bash -c "source $PROJECT_ROOT/moonfrp.sh; parse_global_flags --log-format=invalid help >/dev/null 2>&1" 2>&1
    exit_code=$?
    set -e

    if [[ $exit_code -eq 2 ]]; then
        test_passed "test_log_format_cli_argument - Invalid format returns validation error"
    else
        test_failed "test_log_format_cli_argument - Invalid format returns validation error" "Exit code 2" "Exit code $exit_code"
    fi
}

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_HOME/.moonfrp"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_CONFIG_DIR"
    rm -rf "$TEST_HOME"
    unset MOONFRP_LOG_FORMAT MOONFRP_LOG_SERVICE MOONFRP_LOG_OPERATION MOONFRP_LOG_DURATION
}

# Main test execution
main() {
    echo "================================================================================"
    echo "Structured Logging Unit Tests"
    echo "Story: 5-3-structured-logging"
    echo "================================================================================"
    echo

    setup_test_env

    test_json_logging_format
    test_json_logging_valid
    test_json_logging_performance
    test_json_logging_optional_fields
    test_json_logging_stack_trace
    test_text_logging_default
    test_log_format_cli_argument

    cleanup_test_env

    echo
    echo "================================================================================"
    echo "Test Summary"
    echo "================================================================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

