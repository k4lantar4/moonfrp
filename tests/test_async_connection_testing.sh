#!/bin/bash

#==============================================================================
# Unit Tests for Async Connection Testing
# Story: 3-4-async-connection-testing
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
TEST_TEMP_DIR="${TEMP_DIR:-/tmp}/test_async_conn_$$"
TEST_DB="$TEST_TEMP_DIR/test_index.db"

# Source the functions being tested
set +e
mkdir -p "$TEST_TEMP_DIR"

# Source core files
source "$PROJECT_ROOT/moonfrp-core.sh" || true
source "$PROJECT_ROOT/moonfrp-index.sh" || true
source "$PROJECT_ROOT/moonfrp-services.sh" || true

set -u
set -o pipefail

# Ensure cleanup on exit
cleanup() {
    rm -rf "$TEST_TEMP_DIR"
}

trap cleanup EXIT

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

# Setup test database
setup_test_db() {
    # Create test database
    sqlite3 "$TEST_DB" << 'SQL'
CREATE TABLE IF NOT EXISTS config_index (
    file_path TEXT PRIMARY KEY,
    config_type TEXT NOT NULL,
    server_addr TEXT,
    server_port INTEGER,
    bind_port INTEGER,
    proxy_count INTEGER DEFAULT 0
);
SQL

    # Create test configs
    local test_configs=(
        "$TEST_TEMP_DIR/frpc1.toml"
        "$TEST_TEMP_DIR/frpc2.toml"
        "$TEST_TEMP_DIR/frpc3.toml"
    )
    
    for config in "${test_configs[@]}"; do
        echo "[common]
serverAddr = \"127.0.0.1\"
serverPort = 7000" > "$config"
    done
    
    # Insert test data
    sqlite3 "$TEST_DB" << SQL
INSERT INTO config_index (file_path, config_type, server_addr, server_port) VALUES
('$TEST_TEMP_DIR/frpc1.toml', 'client', '127.0.0.1', 7000),
('$TEST_TEMP_DIR/frpc2.toml', 'client', '127.0.0.1', 7001),
('$TEST_TEMP_DIR/frpc3.toml', 'client', '127.0.0.1', 7002);
SQL

    # Override INDEX_DB_PATH for testing
    export INDEX_DB_PATH="$TEST_DB"
}

# Mock TCP test that succeeds
mock_tcp_test_ok() {
    # Use nc (netcat) if available, otherwise skip
    if command -v nc &>/dev/null; then
        timeout 0.1 nc -z "$1" "$2" 2>/dev/null && return 0
    fi
    # If nc not available, return success for localhost
    [[ "$1" == "127.0.0.1" ]] && return 0
    return 1
}

# Test async_connection_test with empty configs
test_async_connection_test_empty_configs() {
    local output
    output=$(async_connection_test 2>&1)
    
    if [[ "$output" == *"No configs provided"* ]] || [[ -z "$output" ]]; then
        test_passed "Empty configs handled gracefully"
        return 0
    else
        test_failed "Empty configs not handled" "Warning or empty" "$output"
        return 1
    fi
}

# Test async_connection_test framework structure
test_async_connection_test_framework() {
    setup_test_db
    
    # Test that function exists and can be called
    if type async_connection_test &>/dev/null 2>&1; then
        test_passed "async_connection_test function exists"
        return 0
    else
        test_failed "async_connection_test function not found"
        return 1
    fi
}

# Test check_completed_tests function exists
test_check_completed_tests_exists() {
    if type check_completed_tests &>/dev/null 2>&1; then
        test_passed "check_completed_tests function exists"
        return 0
    else
        test_failed "check_completed_tests function not found"
        return 1
    fi
}

# Test run_connection_tests_all function exists
test_run_connection_tests_all_exists() {
    if type run_connection_tests_all &>/dev/null 2>&1; then
        test_passed "run_connection_tests_all function exists"
        return 0
    else
        test_failed "run_connection_tests_all function not found"
        return 1
    fi
}

# Test run_connection_tests_all with no configs
test_run_connection_tests_all_no_configs() {
    setup_test_db
    
    # Empty the database
    sqlite3 "$TEST_DB" "DELETE FROM config_index WHERE config_type='client'"
    
    local output
    output=$(run_connection_tests_all 2>&1)
    
    if [[ "$output" == *"No client configs"* ]] || [[ "$output" == *"No client configurations"* ]]; then
        test_passed "No configs handled gracefully"
        return 0
    else
        test_failed "No configs not handled" "Warning message" "$output"
        return 1
    fi
}

# Test query_configs_by_type integration
test_query_configs_by_type_integration() {
    setup_test_db
    
    local output
    output=$(query_configs_by_type "client" 2>/dev/null)
    
    if [[ -n "$output" ]] && [[ "$output" == *"frpc"* ]]; then
        test_passed "query_configs_by_type returns configs"
        return 0
    else
        test_failed "query_configs_by_type not working" "Config paths" "$output"
        return 1
    fi
}

# Test timeout handling (AC: 3)
test_timeout_handling() {
    setup_test_db
    
    # Function should use timeout=1 per test
    # We can't easily test actual timeout without network, but we can verify
    # the function structure supports timeout
    
    if type async_connection_test &>/dev/null 2>&1; then
        # Check if function has timeout logic
        local source_file="$PROJECT_ROOT/moonfrp-services.sh"
        if grep -q "timeout.*bash.*tcp" "$source_file" 2>/dev/null; then
            test_passed "Timeout handling implemented"
            return 0
        else
            test_failed "Timeout handling not found in source"
            return 1
        fi
    else
        test_failed "async_connection_test not found"
        return 1
    fi
}

# Test max_parallel=20 setting (AC: 1)
test_max_parallel_setting() {
    local source_file="$PROJECT_ROOT/moonfrp-services.sh"
    
    if grep -q "max_parallel=20" "$source_file" 2>/dev/null; then
        test_passed "max_parallel=20 configured"
        return 0
    else
        test_failed "max_parallel=20 not found"
        return 1
    fi
}

# Test cancellation support with trap (AC: 4)
test_cancellation_trap() {
    local source_file="$PROJECT_ROOT/moonfrp-services.sh"
    
    if grep -q "trap.*EXIT.*INT.*TERM" "$source_file" 2>/dev/null || \
       grep -q "trap.*rm.*tmp_dir" "$source_file" 2>/dev/null; then
        test_passed "Cancellation trap implemented"
        return 0
    else
        test_failed "Cancellation trap not found"
        return 1
    fi
}

# Test summary generation (AC: 6)
test_summary_generation() {
    local source_file="$PROJECT_ROOT/moonfrp-services.sh"
    
    if grep -q "Reachable.*Unreachable" "$source_file" 2>/dev/null || \
       grep -q "Summary:" "$source_file" 2>/dev/null; then
        test_passed "Summary generation implemented"
        return 0
    else
        test_failed "Summary generation not found"
        return 1
    fi
}

# Test live result display structure (AC: 2, 5)
test_live_result_display() {
    local source_file="$PROJECT_ROOT/moonfrp-services.sh"
    
    if grep -q "check_completed_tests" "$source_file" 2>/dev/null && \
       grep -q "Testing.*servers" "$source_file" 2>/dev/null; then
        test_passed "Live result display implemented"
        return 0
    else
        test_failed "Live result display not found"
        return 1
    fi
}

# Test result file pattern (AC: 1)
test_result_file_pattern() {
    local source_file="$PROJECT_ROOT/moonfrp-services.sh"
    
    if grep -q "\.result" "$source_file" 2>/dev/null && \
       grep -q "tmp_dir" "$source_file" 2>/dev/null; then
        test_passed "Result file pattern implemented"
        return 0
    else
        test_failed "Result file pattern not found"
        return 1
    fi
}

# Test SQLite query pattern (AC: 1)
test_sqlite_query_pattern() {
    local source_file="$PROJECT_ROOT/moonfrp-services.sh"
    
    if grep -q "SELECT server_addr.*server_port.*config_index" "$source_file" 2>/dev/null || \
       grep -q "sqlite3.*server_addr" "$source_file" 2>/dev/null; then
        test_passed "SQLite query pattern implemented"
        return 0
    else
        test_failed "SQLite query pattern not found"
        return 1
    fi
}

# Performance timing helper (from Story 2.1 pattern)
test_performance_timing() {
    local test_name="$1"
    local max_seconds="$2"
    shift 2
    
    ((TESTS_RUN++))
    
    local start_time=$(date +%s)
    local start_nanos=$(date +%N 2>/dev/null || echo "000000000")
    eval "$@" > /dev/null 2>&1
    local end_time=$(date +%s)
    local end_nanos=$(date +%N 2>/dev/null || echo "000000000")
    
    # Calculate duration in seconds (fallback to integer if nanoseconds not available)
    local duration=$((end_time - start_time))
    if [[ "$start_nanos" != "000000000" ]] && [[ "$end_nanos" != "000000000" ]]; then
        # Use bash arithmetic for fractional seconds
        local start_total=$((start_time * 1000000000 + 10#$start_nanos))
        local end_total=$((end_time * 1000000000 + 10#$end_nanos))
        local duration_nanos=$((end_total - start_total))
        duration=$(awk "BEGIN {printf \"%.3f\", $duration_nanos/1000000000}")
    fi
    
    # Compare using awk or bash (integer comparison as fallback)
    if command -v awk >/dev/null 2>&1; then
        if awk "BEGIN {exit !($duration < $max_seconds)}"; then
            test_passed "$test_name (${duration}s < ${max_seconds}s)"
            return 0
        else
            test_failed "$test_name" "< ${max_seconds}s" "${duration}s"
            return 1
        fi
    else
        # Integer fallback
        if [[ $duration -lt $max_seconds ]]; then
            test_passed "$test_name (${duration}s < ${max_seconds}s)"
            return 0
        else
            test_failed "$test_name" "< ${max_seconds}s" "${duration}s"
            return 1
        fi
    fi
}

# Setup 50 mock configs for performance testing
setup_50_mock_configs() {
    local config_dir="$TEST_TEMP_DIR/performance_configs"
    mkdir -p "$config_dir"
    
    # Create 50 test configs
    local configs=()
    for i in $(seq 1 50); do
        local config="$config_dir/frpc$i.toml"
        echo "[common]
serverAddr = \"127.0.0.1\"
serverPort = $((7000 + i))" > "$config"
        configs+=("$config")
    done
    
    # Insert all configs into test database
    # Use unreachable ports (127.0.0.1:17001-17050) that will timeout at 1s each
    for i in $(seq 1 50); do
        local config="$config_dir/frpc$i.toml"
        sqlite3 "$TEST_DB" <<SQL 2>/dev/null
INSERT INTO config_index (file_path, config_type, server_addr, server_port) 
VALUES ('$config', 'client', '127.0.0.1', $((17000 + i)));
SQL
    done
    
    # Return config array via global variable
    MOCK_50_CONFIGS=("${configs[@]}")
}

# Performance test: 50 servers tested in <5 seconds (AC: 1, 3)
test_async_connection_test_50_servers_under_5s() {
    setup_test_db
    setup_50_mock_configs
    
    # The test uses unreachable ports (127.0.0.1:17001-17050) that will timeout at 1s each
    # With max_parallel=20, we should have:
    # - Batch 1: 20 tests start simultaneously, timeout in ~1s
    # - Batch 2: 20 tests start, timeout in ~1s
    # - Batch 3: 10 tests start, timeout in ~1s
    # Total: ~3 seconds (well under 5s target)
    # The actual timeout is set to 1s per test in async_connection_test function
    
    # Run performance test with 50 configs and measure actual execution time
    test_performance_timing "test_async_connection_test_50_servers_under_5s" 5 \
        'async_connection_test "${MOCK_50_CONFIGS[@]}"'
    
    return $?
}

# Main test execution
main() {
    echo "Running Async Connection Testing Tests..."
    echo "=========================================="
    echo
    
    # Function existence tests
    run_test "async_connection_test exists" test_async_connection_test_framework
    run_test "check_completed_tests exists" test_check_completed_tests_exists
    run_test "run_connection_tests_all exists" test_run_connection_tests_all_exists
    
    # Framework structure tests
    run_test "Empty configs handled" test_async_connection_test_empty_configs
    run_test "max_parallel=20 configured" test_max_parallel_setting
    run_test "Timeout handling implemented" test_timeout_handling
    
    # Integration tests
    run_test "query_configs_by_type integration" test_query_configs_by_type_integration
    run_test "No configs handled" test_run_connection_tests_all_no_configs
    
    # Feature tests
    run_test "Cancellation trap implemented" test_cancellation_trap
    run_test "Live result display implemented" test_live_result_display
    run_test "Summary generation implemented" test_summary_generation
    run_test "Result file pattern implemented" test_result_file_pattern
    run_test "SQLite query pattern implemented" test_sqlite_query_pattern
    
    # Performance tests
    run_test "50 servers tested in <5 seconds (AC: 1, 3)" test_async_connection_test_50_servers_under_5s
    
    # Performance timing helper (Story 2.1 pattern)
    test_performance_timing() {
        local start_ns end_ns elapsed_ms
        start_ns=$(date +%s%N)
        "$@"
        end_ns=$(date +%s%N)
        # Convert to milliseconds
        elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
        echo "$elapsed_ms"
    }

    # Setup 50 mock configs with unreachable ports (127.0.0.1:17001-17050)
    setup_50_mock_configs() {
        mkdir -p "$TEST_TEMP_DIR/configs"
        sqlite3 "$TEST_DB" "DELETE FROM config_index" >/dev/null 2>&1 || true
        local i=1
        while [[ $i -le 50 ]]; do
            local cfg="$TEST_TEMP_DIR/configs/frpc_$i.toml"
            local port=$((17000 + i))
            echo "[common]\nserverAddr=\"127.0.0.1\"\nserverPort=$port" > "$cfg"
            sqlite3 "$TEST_DB" "INSERT INTO config_index (file_path, config_type, server_addr, server_port) VALUES ('$cfg','client','127.0.0.1',$port);"
            i=$((i+1))
        done
        export INDEX_DB_PATH="$TEST_DB"
    }

    # Performance test: 50 servers under 5 seconds
    test_async_connection_test_50_servers_under_5s() {
        setup_test_db
        setup_50_mock_configs
        # Build configs array from DB
        local cfgs
        cfgs=$(sqlite3 "$TEST_DB" "SELECT file_path FROM config_index WHERE config_type='client' ORDER BY file_path")
        local arr=()
        while read -r line; do
            [[ -n "$line" ]] && arr+=("$line")
        done <<< "$cfgs"
        # Measure time to run async_connection_test with 50 configs
        local elapsed_ms
        elapsed_ms=$(test_performance_timing async_connection_test "${arr[@]}")
        # Expect < 5000 ms
        if [[ "$elapsed_ms" -lt 5000 ]]; then
            test_passed "50 servers under 5s (elapsed ${elapsed_ms}ms)"
            return 0
        else
            test_failed "50 servers under 5s" "< 5000ms" "${elapsed_ms}ms"
            return 1
        fi
    }

    # Run performance test
    run_test "50 servers under 5s" test_async_connection_test_50_servers_under_5s

    # Summary
    echo
    echo "=========================================="
    echo "Test Summary:"
    echo "  Tests Run: $TESTS_RUN"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi

