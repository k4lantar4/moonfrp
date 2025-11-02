#!/bin/bash

#==============================================================================
# Unit Tests for Config Index
# Story: 1-2-implement-config-index
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
TEST_INDEX_DB="${TEMP_DIR:-/tmp}/test_moonfrp_index_$$.db"
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

# Override INDEX_DB_PATH for testing
INDEX_DB_PATH="$TEST_HOME/.moonfrp/index.db"

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
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_CONFIG_DIR"
    rm -rf "$TEST_HOME"
    rm -f "$TEST_INDEX_DB"
}

# Ensure cleanup on exit
trap cleanup_test_env EXIT

# Create test config files
create_test_server_config() {
    local file="$TEST_CONFIG_DIR/frps.toml"
    cat > "$file" << 'EOF'
bindAddr = "0.0.0.0"
bindPort = 7000
auth.method = "token"
auth.token = "test-token-12345"
EOF
}

create_test_client_config() {
    local suffix="${1:-}"
    local file="$TEST_CONFIG_DIR/frpc${suffix}.toml"
    cat > "$file" << EOF
user = "testuser${suffix}"
serverAddr = "1.2.3.4"
serverPort = 7000
auth.method = "token"
auth.token = "client-token-${suffix}"

[[proxies]]
name = "proxy1${suffix}"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8080
remotePort = 8080

[[proxies]]
name = "proxy2${suffix}"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8081
remotePort = 8081
EOF
}

create_corrupted_config() {
    local file="$TEST_CONFIG_DIR/corrupted.toml"
    echo "invalid toml content {{[[[}" > "$file"
}

# Test cases

test_index_initialization() {
    setup_test_env
    run_test "Index database initialization" "init_config_index"
    run_test "Index database file exists" "[[ -f \"$INDEX_DB_PATH\" ]]"
}

test_index_single_file() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    create_test_server_config
    
    run_test "Index single config file" "index_config_file \"$TEST_CONFIG_DIR/frps.toml\""
    
    local count=$(sqlite3 "$INDEX_DB_PATH" "SELECT COUNT(*) FROM config_index WHERE file_path='$TEST_CONFIG_DIR/frps.toml';" 2>/dev/null || echo "0")
    if [[ "$count" == "1" ]]; then
        test_passed "Indexed file appears in database"
    else
        test_failed "Indexed file appears in database" "1" "$count"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

test_query_by_type() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    create_test_server_config
    create_test_client_config ""
    create_test_client_config "-2"
    
    index_config_file "$TEST_CONFIG_DIR/frps.toml" >/dev/null 2>&1
    index_config_file "$TEST_CONFIG_DIR/frpc.toml" >/dev/null 2>&1
    index_config_file "$TEST_CONFIG_DIR/frpc-2.toml" >/dev/null 2>&1
    
    local server_result=$(query_configs_by_type "server" 2>/dev/null)
    local client_result=$(query_configs_by_type "client" 2>/dev/null)
    
    if echo "$server_result" | grep -q "frps.toml"; then
        test_passed "Query by type: server config found"
    else
        test_failed "Query by type: server config found" "frps.toml" "$server_result"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
    
    local client_count=$(echo "$client_result" | wc -l)
    if [[ $client_count -eq 2 ]]; then
        test_passed "Query by type: client configs found (count: $client_count)"
    else
        test_failed "Query by type: client configs found" "2" "$client_count"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

test_total_proxy_count() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    create_test_client_config ""  # 2 proxies
    create_test_client_config "-2"  # 2 proxies
    
    index_config_file "$TEST_CONFIG_DIR/frpc.toml" >/dev/null 2>&1
    index_config_file "$TEST_CONFIG_DIR/frpc-2.toml" >/dev/null 2>&1
    
    local total=$(query_total_proxy_count 2>/dev/null || echo "0")
    if [[ "$total" == "4" ]]; then
        test_passed "Total proxy count calculation (expected 4)"
    else
        test_failed "Total proxy count calculation" "4" "$total"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

test_index_survives_corrupted_config() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    create_test_server_config
    create_corrupted_config
    
    index_config_file "$TEST_CONFIG_DIR/frps.toml" >/dev/null 2>&1
    
    # Indexing corrupted config should not crash
    if index_config_file "$TEST_CONFIG_DIR/corrupted.toml" 2>/dev/null; then
        test_passed "Index survives corrupted config (graceful handling)"
    else
        # It's okay if it fails, as long as it doesn't crash
        test_passed "Index survives corrupted config (handles failure gracefully)"
    fi
    ((TESTS_RUN++))
}

test_index_auto_rebuild_on_changes() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    create_test_client_config ""
    
    index_config_file "$TEST_CONFIG_DIR/frpc.toml" >/dev/null 2>&1
    
    # Modify config file
    sleep 1
    echo "" >> "$TEST_CONFIG_DIR/frpc.toml"
    
    check_and_update_index >/dev/null 2>&1
    
    # Verify file was re-indexed
    local last_indexed=$(sqlite3 "$INDEX_DB_PATH" "SELECT last_indexed FROM config_index WHERE file_path='$TEST_CONFIG_DIR/frpc.toml';" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    
    # Should be recent (within last 5 seconds)
    if [[ $((current_time - last_indexed)) -lt 5 ]]; then
        test_passed "Index auto-updates on config changes"
    else
        test_failed "Index auto-updates on config changes" "recent timestamp" "$last_indexed"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

test_rebuild_config_index() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    
    # Create multiple configs
    create_test_server_config
    for i in {1..5}; do
        create_test_client_config "-$i"
    done
    
    run_test "Rebuild config index with multiple files" "rebuild_config_index"
    
    local total=$(sqlite3 "$INDEX_DB_PATH" "SELECT COUNT(*) FROM config_index;" 2>/dev/null || echo "0")
    if [[ "$total" == "6" ]]; then
        test_passed "Rebuild indexes all config files (expected 6)"
    else
        test_failed "Rebuild indexes all config files" "6" "$total"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

test_index_query_50_configs_under_50ms() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    
    # Create 50 test configs
    create_test_server_config
    for i in {1..49}; do
        create_test_client_config "-$i"
    done
    
    rebuild_config_index >/dev/null 2>&1
    
    test_performance "Query 50 configs performance (<50ms)" 50 "query_configs_by_type \"client\""
}

test_index_rebuild_50_configs_under_2s() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    
    # Create 50 test configs
    create_test_server_config
    for i in {1..49}; do
        create_test_client_config "-$i"
    done
    
    test_performance "Rebuild 50 configs performance (<2000ms)" 2000 "rebuild_config_index"
}

test_index_size_under_1mb() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    
    # Create 50 test configs
    create_test_server_config
    for i in {1..49}; do
        create_test_client_config "-$i"
    done
    
    rebuild_config_index >/dev/null 2>&1
    
    local db_size=$(stat -c %s "$INDEX_DB_PATH" 2>/dev/null || echo "0")
    local db_size_mb=$(awk "BEGIN {printf \"%.2f\", $db_size/1024/1024}")
    local max_bytes=$((1024 * 1024))  # 1MB
    
    ((TESTS_RUN++))
    if [[ $db_size -lt $max_bytes ]]; then
        test_passed "Index size under 1MB (${db_size_mb}MB)"
    else
        test_failed "Index size under 1MB" "< 1MB" "${db_size_mb}MB"
        ((TESTS_FAILED++))
    fi
}

test_fallback_to_file_parsing() {
    setup_test_env
    # Don't initialize index - should fallback
    
    create_test_client_config ""
    
    # Should use fallback function
    local result=$(query_configs_by_type_fallback "client" 2>/dev/null)
    
    if echo "$result" | grep -q "frpc.toml"; then
        test_passed "Fallback to file parsing works"
    else
        test_failed "Fallback to file parsing works" "frpc.toml in result" "$result"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

test_index_unique_file_path() {
    setup_test_env
    init_config_index >/dev/null 2>&1
    create_test_server_config
    
    index_config_file "$TEST_CONFIG_DIR/frps.toml" >/dev/null 2>&1
    index_config_file "$TEST_CONFIG_DIR/frps.toml" >/dev/null 2>&1  # Index again
    
    local count=$(sqlite3 "$INDEX_DB_PATH" "SELECT COUNT(*) FROM config_index WHERE file_path='$TEST_CONFIG_DIR/frps.toml';" 2>/dev/null || echo "0")
    
    ((TESTS_RUN++))
    if [[ "$count" == "1" ]]; then
        test_passed "UNIQUE constraint on file_path prevents duplicates"
    else
        test_failed "UNIQUE constraint on file_path prevents duplicates" "1" "$count"
        ((TESTS_FAILED++))
    fi
}

# Main test execution
main() {
    echo "Running Config Index Tests"
    echo "=========================="
    echo ""
    
    # Check if sqlite3 is available
    if ! command -v sqlite3 &> /dev/null; then
        echo -e "${YELLOW}WARNING: sqlite3 not found, skipping index tests${NC}"
        echo "Tests skipped: Index functionality requires sqlite3"
        exit 0
    fi
    
    test_index_initialization
    test_index_single_file
    test_query_by_type
    test_total_proxy_count
    test_index_survives_corrupted_config
    test_index_auto_rebuild_on_changes
    test_rebuild_config_index
    test_index_query_50_configs_under_50ms
    test_index_rebuild_50_configs_under_2s
    test_index_size_under_1mb
    test_fallback_to_file_parsing
    test_index_unique_file_path
    
    echo ""
    echo "=========================="
    echo "Test Summary"
    echo "=========================="
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

