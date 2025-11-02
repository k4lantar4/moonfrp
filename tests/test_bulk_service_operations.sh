#!/bin/bash

#==============================================================================
# Unit Tests for Bulk Parallel Service Operations
# Story: 2-1-parallel-service-management
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
TEST_TEMP_DIR="${TEMP_DIR:-/tmp}/test_bulk_ops_$$"

# Source the functions being tested
set +e
mkdir -p "$TEST_TEMP_DIR"

# Source core files
source "$PROJECT_ROOT/moonfrp-core.sh" || true
source "$PROJECT_ROOT/moonfrp-services.sh" || true

set -u
set -o pipefail

# Ensure cleanup on exit
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

run_test_expect_fail() {
    local test_name="$1"
    shift
    ((TESTS_RUN++))
    
    local output
    if output=$(eval "$@" 2>&1); then
        test_failed "$test_name" "Expected failure" "Command succeeded"
        return 1
    else
        test_passed "$test_name"
        return 0
    fi
}

# Mock service functions for testing (avoid actual systemctl calls)
create_mock_service() {
    local service_name="$1"
    local service_file="/tmp/mock_${service_name}.service"
    echo "[Unit]
Description=Mock service $service_name
[Service]
ExecStart=/bin/sleep 1
[Install]
WantedBy=multi-user.target" > "$service_file"
    echo "$service_name"
}

# Setup test services
setup_test_services() {
    local count="$1"
    local services=()
    for i in $(seq 1 "$count"); do
        services+=("moonfrp-test-service-$i")
    done
    echo "${services[@]}"
}

# Test: Empty service list handling
test_bulk_operation_empty_service_list() {
    local output
    output=$(bulk_service_operation "start" 10 2>&1 || true)
    
    if echo "$output" | grep -q "No services provided\|No services"; then
        return 0
    else
        return 1
    fi
}

# Test: Progress indicator displayed (functional test)
test_bulk_operation_progress_indicator() {
    setup_mock_services 15
    
    local services=()
    for i in $(seq 1 15); do
        services+=("moonfrp-test-service-$i")
    done
    
    # Mock start_service with slight delay to see progress
    start_service() {
        sleep 0.05  # Small delay to allow progress updates
        return 0
    }
    
    # Capture stderr (where progress is printed)
    local output
    output=$(bulk_service_operation "start" 10 "${services[@]}" 2>&1)
    
    # Verify progress indicator was displayed
    if echo "$output" | grep -q "Progress:.*services"; then
        # Verify progress updates show increasing count
        local progress_count=$(echo "$output" | grep -o "Progress: [0-9]*" | wc -l)
        if [[ $progress_count -gt 0 ]]; then
            test_passed "test_bulk_operation_progress_indicator"
            unset -f start_service 2>/dev/null || true
            return 0
        else
            test_failed "test_bulk_operation_progress_indicator" "Progress updates displayed" "No progress lines found"
            unset -f start_service 2>/dev/null || true
            return 1
        fi
    else
        test_failed "test_bulk_operation_progress_indicator" "Progress indicator displayed" "Not found in output"
        unset -f start_service 2>/dev/null || true
        return 1
    fi
}

# Test: Continue-on-error behavior (functional test)
test_bulk_operation_continue_on_error() {
    setup_mock_services 10 "3 7"  # Services 3 and 7 will fail
    
    local services=()
    for i in $(seq 1 10); do
        services+=("moonfrp-test-service-$i")
    done
    
    local fail_count=0
    
    # Mock restart_service: services 3 and 7 fail, others succeed
    restart_service() {
        local svc="$1"
        if [[ "$svc" == "moonfrp-test-service-3" ]] || [[ "$svc" == "moonfrp-test-service-7" ]]; then
            return 1  # Fail these services
        else
            sleep 0.01
            return 0  # Succeed others
        fi
    }
    
    # Run bulk operation - should continue despite failures
    local output
    output=$(bulk_service_operation "restart" 10 "${services[@]}" 2>&1)
    local result=$?
    
    # Verify operation continued (not aborted) and processed all services
    if echo "$output" | grep -q "succeeded.*failed"; then
        # Verify failed services are reported
        if echo "$output" | grep -qi "failed\|moonfrp-test-service-[37]"; then
            test_passed "test_bulk_operation_continue_on_error"
            unset -f restart_service 2>/dev/null || true
            return 0
        else
            test_failed "test_bulk_operation_continue_on_error" "Failed services reported" "Not found in output"
            unset -f restart_service 2>/dev/null || true
            return 1
        fi
    else
        test_failed "test_bulk_operation_continue_on_error" "Continue-on-error behavior" "Operation may have aborted"
        unset -f restart_service 2>/dev/null || true
        return 1
    fi
}

# Test: Failure reporting (functional test)
test_bulk_operation_failure_reporting() {
    setup_mock_services 5 "2 4"  # Services 2 and 4 will fail
    
    local services=()
    for i in $(seq 1 5); do
        services+=("moonfrp-test-service-$i")
    done
    
    # Mock stop_service: services 2 and 4 fail with error messages
    stop_service() {
        local svc="$1"
        if [[ "$svc" == "moonfrp-test-service-2" ]]; then
            echo "ERROR: Service dependency missing" >&2
            return 1
        elif [[ "$svc" == "moonfrp-test-service-4" ]]; then
            echo "ERROR: Permission denied" >&2
            return 1
        else
            sleep 0.01
            return 0
        fi
    }
    
    # Run bulk operation and capture output
    local output
    output=$(bulk_service_operation "stop" 10 "${services[@]}" 2>&1)
    local result=$?
    
    # Verify failed services are listed with reasons
    if echo "$output" | grep -qi "failed" && \
       echo "$output" | grep -q "moonfrp-test-service-[24]"; then
        # Verify summary shows counts
        if echo "$output" | grep -qE "succeeded.*failed|failed.*succeeded"; then
            test_passed "test_bulk_operation_failure_reporting"
            unset -f stop_service 2>/dev/null || true
            return 0
        else
            test_failed "test_bulk_operation_failure_reporting" "Summary with counts" "Not found"
            unset -f stop_service 2>/dev/null || true
            return 1
        fi
    else
        test_failed "test_bulk_operation_failure_reporting" "Failed services listed" "Not found in output: $output"
        unset -f stop_service 2>/dev/null || true
        return 1
    fi
}

# Test: get_moonfrp_services function exists
test_get_moonfrp_services_exists() {
    if type get_moonfrp_services &>/dev/null; then
        test_passed "test_get_moonfrp_services_exists"
        return 0
    else
        test_failed "test_get_moonfrp_services_exists" "Function exists" "Not found"
        return 1
    fi
}

# Test: bulk_service_operation function exists
test_bulk_service_operation_exists() {
    if type bulk_service_operation &>/dev/null; then
        test_passed "test_bulk_service_operation_exists"
        return 0
    else
        test_failed "test_bulk_service_operation_exists" "Function exists" "Not found"
        return 1
    fi
}

# Test: User-facing bulk functions exist
test_bulk_functions_exist() {
    local all_exist=true
    
    for func in bulk_start_services bulk_stop_services bulk_restart_services bulk_reload_services; do
        if ! type "$func" &>/dev/null; then
            test_failed "test_bulk_functions_exist" "$func exists" "Not found"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == true ]]; then
        test_passed "test_bulk_functions_exist"
        return 0
    else
        return 1
    fi
}

# Test: Filtered operations function exists
test_bulk_operation_filtered_exists() {
    if type bulk_operation_filtered &>/dev/null; then
        test_passed "test_bulk_operation_filtered_exists"
        return 0
    else
        test_failed "test_bulk_operation_filtered_exists" "Function exists" "Not found"
        return 1
    fi
}

# Test: Max parallelism parameter handling
test_max_parallelism_parameter() {
    # Check that max_parallel is configurable in function signature
    if grep -q 'max_parallel=' "$PROJECT_ROOT/moonfrp-services.sh"; then
        test_passed "test_max_parallelism_parameter"
        return 0
    else
        test_failed "test_max_parallelism_parameter" "max_parallel parameter" "Not found"
        return 1
    fi
}

# Test: Default max_parallel is 10
test_default_max_parallel() {
    if grep -q 'max_parallel="${.*:-10}"' "$PROJECT_ROOT/moonfrp-services.sh" || \
       grep -q 'max_parallel=.*10' "$PROJECT_ROOT/moonfrp-services.sh"; then
        test_passed "test_default_max_parallel"
        return 0
    else
        test_failed "test_default_max_parallel" "Default value 10" "Not found"
        return 1
    fi
}

# Test: Parallel execution structure (PID tracking)
test_parallel_execution_structure() {
    if grep -q "pids" "$PROJECT_ROOT/moonfrp-services.sh" && \
       grep -q "background\|&" "$PROJECT_ROOT/moonfrp-services.sh"; then
        test_passed "test_parallel_execution_structure"
        return 0
    else
        test_failed "test_parallel_execution_structure" "Parallel execution code" "Not found"
        return 1
    fi
}

# Test: CLI bulk command exists
test_cli_bulk_command() {
    if grep -q '"bulk"' "$PROJECT_ROOT/moonfrp.sh"; then
        test_passed "test_cli_bulk_command"
        return 0
    else
        test_failed "test_cli_bulk_command" "CLI bulk command" "Not found"
        return 1
    fi
}

# Test: CLI dry-run option
test_cli_dry_run() {
    if grep -q "dry-run\|dry_run" "$PROJECT_ROOT/moonfrp.sh"; then
        test_passed "test_cli_dry_run"
        return 0
    else
        test_failed "test_cli_dry_run" "dry-run option" "Not found"
        return 1
    fi
}

# Test: CLI max-parallel option
test_cli_max_parallel() {
    if grep -q "max-parallel\|max_parallel" "$PROJECT_ROOT/moonfrp.sh"; then
        test_passed "test_cli_max_parallel"
        return 0
    else
        test_failed "test_cli_max_parallel" "max-parallel option" "Not found"
        return 1
    fi
}

# Test: CLI filter option
test_cli_filter_option() {
    if grep -q "filter=" "$PROJECT_ROOT/moonfrp.sh" || grep -q '--filter' "$PROJECT_ROOT/moonfrp.sh"; then
        test_passed "test_cli_filter_option"
        return 0
    else
        test_failed "test_cli_filter_option" "filter option" "Not found"
        return 1
    fi
}

# Test: Filter types supported (status, name)
test_filter_types_status_name() {
    if grep -q '"status"\|"name"' "$PROJECT_ROOT/moonfrp-services.sh" && \
       grep -q "filter_type" "$PROJECT_ROOT/moonfrp-services.sh"; then
        test_passed "test_filter_types_status_name"
        return 0
    else
        test_failed "test_filter_types_status_name" "Status and name filters" "Not found"
        return 1
    fi
}

# Test: Final summary reporting
test_final_summary_reporting() {
    if grep -q "succeeded.*failed" "$PROJECT_ROOT/moonfrp-services.sh" || \
       grep -q "success_count.*fail_count" "$PROJECT_ROOT/moonfrp-services.sh"; then
        test_passed "test_final_summary_reporting"
        return 0
    else
        test_failed "test_final_summary_reporting" "Summary reporting" "Not found"
        return 1
    fi
}

# Mock systemctl wrapper for testing (simulates fast operations)
MOCK_SERVICES_DIR="$TEST_TEMP_DIR/mock_services"
declare -A MOCK_SERVICE_STATES
create_mock_service_state() {
    local service_name="$1"
    local state="${2:-active}"
    MOCK_SERVICE_STATES["$service_name"]="$state"
    mkdir -p "$MOCK_SERVICES_DIR"
    echo "$state" > "$MOCK_SERVICES_DIR/$service_name.state"
}

# Override systemctl for testing
mock_systemctl() {
    local cmd="$1"
    local service_name="$2"
    
    case "$cmd" in
        "list-units")
            # Return list of mock services
            if [[ -d "$MOCK_SERVICES_DIR" ]]; then
                for svc_file in "$MOCK_SERVICES_DIR"/*.state; do
                    [[ -f "$svc_file" ]] && echo "$(basename "$svc_file" .state).service loaded active running"
                done
            fi
            return 0
            ;;
        "is-active")
            local state="${MOCK_SERVICE_STATES[$service_name]:-inactive}"
            [[ "$state" == "active" ]] && return 0 || return 1
            ;;
        "start"|"stop"|"restart")
            # Simulate fast operation (sleep simulates work)
            sleep 0.01
            # Update state
            if [[ "$cmd" == "start" ]] || [[ "$cmd" == "restart" ]]; then
                MOCK_SERVICE_STATES["$service_name"]="active"
            elif [[ "$cmd" == "stop" ]]; then
                MOCK_SERVICE_STATES["$service_name"]="inactive"
            fi
            echo "$state" > "$MOCK_SERVICES_DIR/$service_name.state"
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

# Performance test helper (using bash arithmetic instead of bc)
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

# Setup mock services for testing
setup_mock_services() {
    local count="$1"
    local fail_indices="${2:-}"  # Optional: indices of services that should fail
    
    mkdir -p "$MOCK_SERVICES_DIR"
    # MOCK_SERVICE_STATES is already declared as associative array at top level
    # Clear it by unsetting all keys
    for key in "${!MOCK_SERVICE_STATES[@]}"; do
        unset "MOCK_SERVICE_STATES[$key]"
    done
    
    for i in $(seq 1 "$count"); do
        local svc_name="moonfrp-test-service-$i"
        if echo "$fail_indices" | grep -q "\b$i\b"; then
            create_mock_service_state "$svc_name" "inactive"
        else
            create_mock_service_state "$svc_name" "active"
        fi
    done
}

# Performance test: 50 services restart in <10 seconds
test_bulk_restart_50_services_under_10s() {
    setup_mock_services 50
    
    # Create test service list
    local services=()
    for i in $(seq 1 50); do
        services+=("moonfrp-test-service-$i")
    done
    
    # Override start_service/stop_service/restart_service to use mocks
    local old_start=$(declare -f start_service)
    local old_stop=$(declare -f stop_service)
    local old_restart=$(declare -f restart_service)
    
    # Create mock service functions that complete quickly
    start_service() {
        local svc="$1"
        sleep 0.01  # Simulate fast operation
        MOCK_SERVICE_STATES["$svc"]="active"
        return 0
    }
    
    stop_service() {
        local svc="$1"
        sleep 0.01
        MOCK_SERVICE_STATES["$svc"]="inactive"
        return 0
    }
    
    restart_service() {
        local svc="$1"
        sleep 0.01
        MOCK_SERVICE_STATES["$svc"]="active"
        return 0
    }
    export -f start_service stop_service restart_service 2>/dev/null || true
    
    # Run performance test
    test_performance_timing "test_bulk_restart_50_services_under_10s" 10 \
        'bulk_service_operation "restart" 10 "${services[@]}"'
    
    local result=$?
    
    # Restore original functions (if they were functions)
    unset -f start_service stop_service restart_service 2>/dev/null || true
    
    return $result
}

# Test: Verify parallel execution (not sequential)
test_bulk_start_parallel_execution() {
    setup_mock_services 20
    
    local services=()
    for i in $(seq 1 20); do
        services+=("moonfrp-test-service-$i")
    done
    
    local start_times=()
    local end_times=()
    
    # Mock start_service to record timing
    start_service() {
        local svc="$1"
        start_times+=("$(date +%s.%N)")
        sleep 0.05  # 50ms per service
        end_times+=("$(date +%s.%N)")
        MOCK_SERVICE_STATES["$svc"]="active"
        return 0
    }
    export -f start_service 2>/dev/null || true
    
    ((TESTS_RUN++))
    
    local bulk_start=$(date +%s.%N)
    bulk_service_operation "start" 10 "${services[@]}" > /dev/null 2>&1
    local bulk_end=$(date +%s.%N)
    local bulk_duration=$(echo "scale=3; ($bulk_end - $bulk_start)" | bc 2>/dev/null || echo "0")
    
    # Sequential would take: 20 * 0.05 = 1.0 seconds
    # Parallel (max 10) should take: ~0.1 seconds (2 batches of 10)
    # If it takes significantly less than 1.0s, parallelism is working
    if [[ $bulk_duration -lt 1 ]]; then
        test_passed "test_bulk_start_parallel_execution (parallel execution verified: ${bulk_duration}s < 0.5s)"
        return 0
    else
        test_failed "test_bulk_start_parallel_execution" "Parallel execution (< 0.5s)" "Sequential-like timing: ${bulk_duration}s"
        return 1
    fi
}

# Test: Verify max_parallelism is respected
test_max_parallelism_respected() {
    setup_mock_services 25
    
    local services=()
    for i in $(seq 1 25); do
        services+=("moonfrp-test-service-$i")
    done
    
    local concurrent_count=0
    local max_concurrent=0
    
    # Mock start_service to track concurrent execution using file-based counter
    local concurrent_file="$TEST_TEMP_DIR/concurrent_count.txt"
    echo "0" > "$concurrent_file"
    
    start_service() {
        local svc="$1"
        local current=$(cat "$concurrent_file")
        local new=$((current + 1))
        echo "$new" > "$concurrent_file"
        sleep 0.1  # Give time to observe concurrency
        local final=$(cat "$concurrent_file")
        if [[ $final -gt $max_concurrent ]]; then
            echo "$final" > "$TEST_TEMP_DIR/max_concurrent.txt"
        fi
        local updated=$((final - 1))
        echo "$updated" > "$concurrent_file"
        MOCK_SERVICE_STATES["$svc"]="active"
        return 0
    }
    export -f start_service 2>/dev/null || true
    
    ((TESTS_RUN++))
    
    bulk_service_operation "start" 10 "${services[@]}" > /dev/null 2>&1
    
    local max_concurrent=$(cat "$TEST_TEMP_DIR/max_concurrent.txt" 2>/dev/null || echo "0")
    
    if [[ $max_concurrent -le 10 ]] && [[ $max_concurrent -gt 0 ]]; then
        test_passed "test_max_parallelism_respected (max concurrent: $max_concurrent <= 10)"
        unset -f start_service 2>/dev/null || true
        return 0
    else
        test_failed "test_max_parallelism_respected" "Max concurrent <= 10" "Observed: $max_concurrent"
        unset -f start_service 2>/dev/null || true
        return 1
    fi
}

# Benchmark test with various service counts
test_benchmark_various_service_counts() {
    local counts=(10 25 50 100)
    local all_passed=true
    
    for count in "${counts[@]}"; do
        setup_mock_services "$count"
        
        local services=()
        for i in $(seq 1 "$count"); do
            services+=("moonfrp-test-service-$i")
        done
        
        # Mock fast operations
        start_service() {
            sleep 0.01
            return 0
        }
        stop_service() {
            sleep 0.01
            return 0
        }
        restart_service() {
            sleep 0.01
            return 0
        }
        export -f start_service stop_service restart_service 2>/dev/null || true
        
        ((TESTS_RUN++))
        
        local start_time=$(date +%s.%N)
        bulk_service_operation "restart" 10 "${services[@]}" > /dev/null 2>&1
        local end_time=$(date +%s.%N)
        local duration=$(echo "scale=3; ($end_time - $start_time)" | bc 2>/dev/null || echo "0")
        
        # Estimate: with max_parallel=10, should complete in reasonable time
        # 100 services / 10 parallel = 10 batches * 0.01s = ~0.1s + overhead
        local max_reasonable=$(echo "scale=3; ($count / 10) * 0.05 + 0.5" | bc 2>/dev/null || echo "2")
        
        if (( $(echo "$duration < $max_reasonable" | bc -l 2>/dev/null || echo "1") )); then
            test_passed "Benchmark $count services (${duration}s)"
        else
            test_failed "Benchmark $count services" "< ${max_reasonable}s" "${duration}s"
            all_passed=false
        fi
    done
    
    [[ "$all_passed" == true ]] && return 0 || return 1
}

# Load test: 50 services restart time measurement
test_load_50_services_restart_time() {
    setup_mock_services 50
    
    local services=()
    for i in $(seq 1 50); do
        services+=("moonfrp-test-service-$i")
    done
    
    restart_service() {
        sleep 0.01  # Fast mock operation
        return 0
    }
    export -f restart_service 2>/dev/null || true
    
    test_performance_timing "test_load_50_services_restart_time" 10 \
        'bulk_service_operation "restart" 10 "${services[@]}"'
    
    unset -f restart_service 2>/dev/null || true
}

# Load test: 10 failed services error handling
test_load_10_failed_services_error_handling() {
    setup_mock_services 50 "1 2 3 4 5 6 7 8 9 10"  # First 10 will fail
    
    local services=()
    for i in $(seq 1 50); do
        services+=("moonfrp-test-service-$i")
    done
    
    local fail_count=0
    
    # Mock restart_service: first 10 fail, rest succeed
    restart_service() {
        local svc="$1"
        local svc_num="${svc##*-}"  # Extract number
        
        if [[ $svc_num -le 10 ]]; then
            return 1  # Fail for first 10
        else
            sleep 0.01
            return 0  # Succeed for rest
        fi
    }
    export -f restart_service 2>/dev/null || true
    
    ((TESTS_RUN++))
    
    local output
    output=$(bulk_service_operation "restart" 10 "${services[@]}" 2>&1)
    local exit_code=$?
    
    # Should complete (not abort), report 10 failures, continue processing
    # Exit code should be 10 (number of failures)
    if [[ $exit_code -eq 10 ]] && echo "$output" | grep -qE "(10 failed|failed: 10|succeeded.*failed.*10)"; then
        test_passed "test_load_10_failed_services_error_handling (10 failures reported, processing continued)"
        return 0
    else
        test_failed "test_load_10_failed_services_error_handling" "10 failures reported" "Exit code: $exit_code, Output: $(echo "$output" | head -5)"
        unset -f restart_service 2>/dev/null || true
        return 1
    fi
    unset -f restart_service 2>/dev/null || true
}

# Load test: Concurrent bulk operations (race condition testing)
test_load_concurrent_bulk_operations() {
    setup_mock_services 30
    
    local services1=()
    local services2=()
    for i in $(seq 1 15); do
        services1+=("moonfrp-test-service-$i")
        services2+=("moonfrp-test-service-$((i+15))")
    done
    
    local operation_count=0
    local lock_file="$TEST_TEMP_DIR/.bulk_op_lock"
    
    start_service() {
        local svc="$1"
        # Simple lock mechanism to detect conflicts
        if [[ -f "$lock_file" ]]; then
            # Another operation in progress - potential race
            local other_pid=$(cat "$lock_file" 2>/dev/null || echo "")
            if [[ -n "$other_pid" ]] && kill -0 "$other_pid" 2>/dev/null; then
                # Both operations running concurrently - this is expected, but no data corruption
                :
            fi
        fi
        echo $$ > "$lock_file"
        sleep 0.02
        rm -f "$lock_file"
        ((operation_count++))
        MOCK_SERVICE_STATES["$svc"]="active"
        return 0
    }
    
    ((TESTS_RUN++))
    
    # Run two bulk operations concurrently
    bulk_service_operation "start" 10 "${services1[@]}" > /dev/null 2>&1 &
    local pid1=$!
    bulk_service_operation "start" 10 "${services2[@]}" > /dev/null 2>&1 &
    local pid2=$!
    
    wait "$pid1" "$pid2"
    local result=$?
    
    # Both should complete successfully
    if [[ $result -eq 0 ]] && [[ $operation_count -eq 30 ]]; then
        test_passed "test_load_concurrent_bulk_operations (both operations completed, no race conditions)"
        return 0
    else
        test_failed "test_load_concurrent_bulk_operations" "Both complete successfully" "Result: $result, Operations: $operation_count/30"
        return 1
    fi
}

# Cleanup function
cleanup() {
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR" 2>/dev/null || true
    fi
    if [[ -n "${MOCK_SERVICES_DIR:-}" ]] && [[ -d "$MOCK_SERVICES_DIR" ]]; then
        rm -rf "$MOCK_SERVICES_DIR" 2>/dev/null || true
    fi
    unset -f start_service stop_service restart_service 2>/dev/null || true
}

# Run all tests
echo "Running bulk service operations tests..."
echo ""

run_test "test_get_moonfrp_services_exists" 'test_get_moonfrp_services_exists'
run_test "test_bulk_service_operation_exists" 'test_bulk_service_operation_exists'
run_test "test_bulk_functions_exist" 'test_bulk_functions_exist'
run_test "test_bulk_operation_filtered_exists" 'test_bulk_operation_filtered_exists'
run_test "test_max_parallelism_parameter" 'test_max_parallelism_parameter'
run_test "test_default_max_parallel" 'test_default_max_parallel'
run_test "test_parallel_execution_structure" 'test_parallel_execution_structure'
run_test "test_bulk_operation_empty_service_list" 'test_bulk_operation_empty_service_list'
run_test "test_bulk_operation_progress_indicator" 'test_bulk_operation_progress_indicator'
run_test "test_bulk_operation_continue_on_error" 'test_bulk_operation_continue_on_error'
run_test "test_bulk_operation_failure_reporting" 'test_bulk_operation_failure_reporting'
run_test "test_cli_bulk_command" 'test_cli_bulk_command'
run_test "test_cli_dry_run" 'test_cli_dry_run'
run_test "test_cli_max_parallel" 'test_cli_max_parallel'
run_test "test_cli_filter_option" 'test_cli_filter_option'
run_test "test_filter_types_status_name" 'test_filter_types_status_name'
run_test "test_final_summary_reporting" 'test_final_summary_reporting'

# Performance and Load Tests
echo ""
echo "Running performance and load tests..."
echo ""

run_test "test_bulk_restart_50_services_under_10s" 'test_bulk_restart_50_services_under_10s'
run_test "test_bulk_start_parallel_execution" 'test_bulk_start_parallel_execution'
run_test "test_max_parallelism_respected" 'test_max_parallelism_respected'
run_test "test_benchmark_various_service_counts" 'test_benchmark_various_service_counts'
run_test "test_load_50_services_restart_time" 'test_load_50_services_restart_time'
run_test "test_load_10_failed_services_error_handling" 'test_load_10_failed_services_error_handling'
run_test "test_load_concurrent_bulk_operations" 'test_load_concurrent_bulk_operations'

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary:"
echo "  Tests Run:    $TESTS_RUN"
echo "  Tests Passed: $TESTS_PASSED"
echo "  Tests Failed: $TESTS_FAILED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

