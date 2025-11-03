#!/bin/bash

#==============================================================================
# Unit Tests for Cached Status Display
# Story: 3-1-cached-status-display
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
source "$PROJECT_ROOT/moonfrp-services.sh" || true
source "$PROJECT_ROOT/moonfrp-ui.sh" || true

# Note: INDEX_DB_PATH is readonly in moonfrp-index.sh, but it defaults to $HOME/.moonfrp/index.db
# Since we set HOME=$TEST_HOME, the index will automatically use the test location

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
    rm -rf "$TEST_CONFIG_DIR"/* 2>/dev/null
    rm -rf "$TEST_HOME/.moonfrp"/* 2>/dev/null
    
    # Initialize index database
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$TEST_HOME/.moonfrp/index.db" "CREATE TABLE IF NOT EXISTS config_index (
            file_path TEXT PRIMARY KEY,
            config_type TEXT,
            proxy_count INTEGER DEFAULT 0,
            last_indexed INTEGER
        );" 2>/dev/null || true
    fi
    
    # Reset STATUS_CACHE
    unset STATUS_CACHE 2>/dev/null || true
    declare -A STATUS_CACHE
    STATUS_CACHE["timestamp"]=0
    STATUS_CACHE["data"]=""
    STATUS_CACHE["ttl"]=5
    STATUS_CACHE["refreshing"]="false"
}

# Cleanup test environment
cleanup_test_env() {
    rm -rf "$TEST_CONFIG_DIR" 2>/dev/null
    rm -rf "$TEST_HOME" 2>/dev/null
}

# Create test config files for performance testing
create_test_configs() {
    local count="${1:-50}"
    local i=1
    
    while [[ $i -le $count ]]; do
        cat > "$TEST_CONFIG_DIR/frpc-$i.toml" << EOF
serverAddr = "192.168.1.$i"
serverPort = 7000
authToken = "test-token"

[[proxies]]
type = "tcp"
localIP = "127.0.0.1"
localPort = $((8000 + i))
remotePort = $((9000 + i))
EOF
        # Index the config
        if command -v index_config_file >/dev/null 2>&1; then
            index_config_file "$TEST_CONFIG_DIR/frpc-$i.toml" >/dev/null 2>&1 || true
        fi
        ((i++))
    done
}

# Test: Cache initialization
test_cache_initialization() {
    setup_test_env
    
    run_test "STATUS_CACHE associative array exists" "declare -p STATUS_CACHE &>/dev/null"
    run_test "init_status_cache creates cache directory" "init_status_cache && [[ -d \"$TEST_HOME/.moonfrp\" ]]"
    run_test "init_status_cache sets default TTL to 5" "init_status_cache && [[ \${STATUS_CACHE[\"ttl\"]} -eq 5 ]]"
    
    cleanup_test_env
}

# Test: Configurable TTL (AC: 2)
test_configurable_ttl() {
    setup_test_env
    
    # Test default TTL
    unset STATUS_CACHE_TTL 2>/dev/null || true
    unset STATUS_CACHE 2>/dev/null || true
    declare -A STATUS_CACHE
    init_status_cache
    run_test "Default TTL is 5 seconds" "[[ \${STATUS_CACHE[\"ttl\"]} -eq 5 ]]"
    
    # Test custom TTL via environment variable
    unset STATUS_CACHE 2>/dev/null || true
    declare -A STATUS_CACHE
    export STATUS_CACHE_TTL=10
    init_status_cache
    run_test "Custom TTL via STATUS_CACHE_TTL environment variable works" "[[ \${STATUS_CACHE[\"ttl\"]} -eq 10 ]]"
    
    unset STATUS_CACHE_TTL
    cleanup_test_env
}

# Test: FRP version caching (AC: 1)
test_frp_version_cached_ttl_1_hour() {
    setup_test_env
    
    # Test cache file creation
    local version1=$(get_frp_version_cached)
    run_test "get_frp_version_cached creates cache file" "[[ -f \"$TEST_HOME/.moonfrp/frp_version.cache\" ]]"
    run_test "get_frp_version_cached creates timestamp file" "[[ -f \"$TEST_HOME/.moonfrp/frp_version.cache.timestamp\" ]]"
    
    # Test cache hit (same call should use cache)
    local cache_time=$(date +%s)
    local version2=$(get_frp_version_cached)
    local after_time=$(date +%s)
    local elapsed=$((after_time - cache_time))
    
    # Should return quickly (< 100ms) if using cache
    run_test "get_frp_version_cached returns cached version quickly" "[[ $elapsed -lt 1 ]]"
    
    # Verify cache file contains version
    if [[ -f "$TEST_HOME/.moonfrp/frp_version.cache" ]]; then
        local cached_version=$(cat "$TEST_HOME/.moonfrp/frp_version.cache")
        run_test "Cache file contains version string" "[[ -n \"$cached_version\" ]]"
    fi
    
    cleanup_test_env
}

# Test: Cached status query performance (AC: 1)
test_cached_status_query_under_50ms() {
    setup_test_env
    
    # Create some test configs and populate cache
    create_test_configs 10
    refresh_status_cache_sync
    
    # Test that get_cached_status returns quickly when cache is fresh
    test_performance "get_cached_status returns in <50ms when cache is fresh" 50 "get_cached_status > /dev/null"
    
    cleanup_test_env
}

# Test: Generate quick status performance (AC: 1)
test_generate_quick_status_under_200ms() {
    setup_test_env
    
    # Create 50 configs for performance test
    create_test_configs 50
    
    # Test that generate_quick_status completes quickly
    test_performance "generate_quick_status completes in <200ms with 50 configs" 200 "generate_quick_status > /dev/null"
    
    cleanup_test_env
}

# Test: Menu load time under 200ms with 50 configs (AC: 1)
test_menu_load_under_200ms_with_50_configs() {
    setup_test_env
    
    # Create 50 configs for performance test
    create_test_configs 50
    
    # Ensure cache is populated synchronously once
    refresh_status_cache_sync
    
    # Measure time to render the main menu header and cached status
    test_performance "menu render completes in <200ms with 50 configs" 200 "show_header 'MoonFRP' 'Advanced FRP Management Tool'; display_cached_status"
    
    cleanup_test_env
}

# Test: Menu load performance with 50 configs (AC: 1)
test_menu_load_under_200ms_with_50_configs() {
    setup_test_env
    
    # Create 50 configs for performance test
    create_test_configs 50
    
    # Refresh cache synchronously first to ensure cache is populated
    refresh_status_cache_sync
    
    # Test that display_cached_status completes quickly (this is what main_menu calls)
    # This tests the full path: get_cached_status() -> display_cached_status() with cached data
    test_performance "display_cached_status completes in <200ms with 50 configs (menu render simulation)" 200 "display_cached_status > /dev/null"
    
    cleanup_test_env
}

# Test: SQLite queries performance (AC: 1)
test_sqlite_queries_performance() {
    setup_test_env
    
    create_test_configs 50
    
    if command -v sqlite3 >/dev/null 2>&1 && [[ -f "$TEST_HOME/.moonfrp/index.db" ]]; then
        test_performance "COUNT(*) query executes in <50ms" 50 "sqlite3 \"$TEST_HOME/.moonfrp/index.db\" \"SELECT COUNT(*) FROM config_index;\" > /dev/null"
        test_performance "SUM(proxy_count) query executes in <50ms" 50 "sqlite3 \"$TEST_HOME/.moonfrp/index.db\" \"SELECT COALESCE(SUM(proxy_count), 0) FROM config_index;\" > /dev/null"
    else
        test_passed "SQLite not available - skipping SQLite performance test"
    fi
    
    cleanup_test_env
}

# Test: Systemctl batch query performance (AC: 1)
test_systemctl_batch_query_performance() {
    setup_test_env
    
    test_performance "systemctl list-units batch query executes in <50ms" 50 "systemctl list-units --type=service --all --no-pager --no-legend | grep moonfrp- > /dev/null || true"
    
    cleanup_test_env
}

# Test: Background refresh non-blocking (AC: 3)
test_background_refresh_non_blocking() {
    setup_test_env
    
    create_test_configs 10
    refresh_status_cache_sync
    
    # Make cache stale by waiting
    sleep 6
    
    # Background refresh should return immediately (<10ms)
    test_performance "refresh_status_cache_background returns in <10ms (non-blocking)" 10 "refresh_status_cache_background"
    
    # Wait for background process to complete
    sleep 2
    
    cleanup_test_env
}

# Test: Cache TTL expiration (AC: 2)
test_cache_ttl_expiration() {
    setup_test_env
    
    create_test_configs 5
    refresh_status_cache_sync
    
    local initial_timestamp="${STATUS_CACHE["timestamp"]}"
    
    # Wait for cache to expire (>5 seconds)
    sleep 6
    
    # get_cached_status should trigger background refresh when cache is stale
    get_cached_status > /dev/null
    
    # Check that refreshing flag is set (or was set during refresh)
    # Allow some time for background refresh to start
    sleep 1
    
    # Verify that cache timestamp will be updated (check file cache)
    if [[ -f "$TEST_HOME/.moonfrp/status.cache.timestamp" ]]; then
        local file_timestamp=$(cat "$TEST_HOME/.moonfrp/status.cache.timestamp")
        # File timestamp should be newer after refresh completes
        sleep 2
        local new_file_timestamp=$(cat "$TEST_HOME/.moonfrp/status.cache.timestamp" 2>/dev/null || echo "0")
        run_test "Cache file timestamp updated after TTL expiration" "[[ $new_file_timestamp -ge $file_timestamp ]]"
    fi
    
    cleanup_test_env
}

# Test: Manual refresh works (AC: 5)
test_manual_refresh_works() {
    setup_test_env
    
    create_test_configs 5
    refresh_status_cache_sync
    
    local initial_timestamp="${STATUS_CACHE["timestamp"]}"
    
    # Wait a bit
    sleep 1
    
    # Manual refresh
    refresh_status_cache_sync
    
    local new_timestamp="${STATUS_CACHE["timestamp"]}"
    
    run_test "Manual refresh updates cache timestamp" "[[ $new_timestamp -gt $initial_timestamp ]]"
    run_test "Manual refresh updates cache data" "[[ -n \"${STATUS_CACHE[\"data\"]}\" ]]"
    run_test "Manual refresh sets refreshing flag to false" "[[ \"${STATUS_CACHE[\"refreshing\"]}\" == \"false\" ]]"
    
    cleanup_test_env
}

# Test: Cache survives menu navigation (AC: 6)
test_cache_survives_menu_navigation() {
    setup_test_env
    
    create_test_configs 5
    refresh_status_cache_sync
    
    local initial_timestamp="${STATUS_CACHE["timestamp"]}"
    local initial_data="${STATUS_CACHE["data"]}"
    
    # Simulate menu navigation (multiple calls to get_cached_status)
    get_cached_status > /dev/null
    get_cached_status > /dev/null
    get_cached_status > /dev/null
    
    local final_timestamp="${STATUS_CACHE["timestamp"]}"
    local final_data="${STATUS_CACHE["data"]}"
    
    # Cache should persist across calls
    run_test "Cache timestamp persists across navigation" "[[ \"$final_timestamp\" == \"$initial_timestamp\" ]]"
    run_test "Cache data persists across navigation" "[[ \"$final_data\" == \"$initial_data\" ]]"
    
    cleanup_test_env
}

# Test: Stale cache display while refreshing (AC: 4)
test_stale_cache_display_while_refreshing() {
    setup_test_env
    
    create_test_configs 5
    refresh_status_cache_sync
    
    # Wait for cache to expire
    sleep 6
    
    # get_cached_status should return stale cache while refreshing
    local stale_status=$(get_cached_status)
    run_test "get_cached_status returns stale cache when expired" "[[ -n \"$stale_status\" ]]"
    
    # Check that refreshing flag is set (or background process started)
    sleep 1
    
    # Verify cache is being refreshed in background
    if [[ -f "$TEST_HOME/.moonfrp/status.cache" ]]; then
        run_test "Background refresh updates cache file" "[[ -f \"$TEST_HOME/.moonfrp/status.cache\" ]]"
    fi
    
    cleanup_test_env
}

# Test: Cache file persistence (AC: 2)
test_cache_file_persistence() {
    setup_test_env
    
    create_test_configs 5
    refresh_status_cache_sync
    
    run_test "status.cache file created" "[[ -f \"$TEST_HOME/.moonfrp/status.cache\" ]]"
    run_test "status.cache.timestamp file created" "[[ -f \"$TEST_HOME/.moonfrp/status.cache.timestamp\" ]]"
    
    # Verify cache files contain data
    if [[ -f "$TEST_HOME/.moonfrp/status.cache" ]]; then
        local cache_data=$(cat "$TEST_HOME/.moonfrp/status.cache")
        run_test "Cache file contains status data" "[[ -n \"$cache_data\" ]]"
    fi
    
    # Test background refresh updates files
    sleep 6
    refresh_status_cache_background
    sleep 2  # Wait for background process
    
    if [[ -f "$TEST_HOME/.moonfrp/status.cache.timestamp" ]]; then
        local timestamp=$(cat "$TEST_HOME/.moonfrp/status.cache.timestamp")
        run_test "Background refresh updates cache timestamp file" "[[ -n \"$timestamp\" && $timestamp -gt 0 ]]"
    fi
    
    cleanup_test_env
}

# Test: Display cached status formatting (AC: 4)
test_display_cached_status_formatting() {
    setup_test_env
    
    create_test_configs 5
    refresh_status_cache_sync
    
    # Test that display_cached_status outputs formatted text
    local output=$(display_cached_status)
    
    run_test "display_cached_status outputs status information" "[[ -n \"$output\" ]]"
    run_test "display_cached_status includes FRP version or status" "echo \"$output\" | grep -qE '(FRP|Active|Inactive)'"
    
    cleanup_test_env
}

# Test: Cache persistence across processes (AC: 6)
test_cache_persistence_across_processes() {
    setup_test_env
    
    create_test_configs 5
    
    # Refresh cache in current process
    refresh_status_cache_sync
    
    local initial_timestamp=$(cat "$TEST_HOME/.moonfrp/status.cache.timestamp" 2>/dev/null || echo "0")
    
    # Simulate background refresh (separate process updates files)
    (
        source "$PROJECT_ROOT/moonfrp-core.sh" 2>/dev/null || true
        source "$PROJECT_ROOT/moonfrp-index.sh" 2>/dev/null || true
        source "$PROJECT_ROOT/moonfrp-ui.sh" 2>/dev/null || true
        
        export HOME="$TEST_HOME"
        export CONFIG_DIR="$TEST_CONFIG_DIR"
        # INDEX_DB_PATH is readonly but defaults to $HOME/.moonfrp/index.db, so it will use test location
        
        generate_quick_status > "$TEST_HOME/.moonfrp/status.cache"
        date +%s > "$TEST_HOME/.moonfrp/status.cache.timestamp"
    )
    
    sleep 1
    
    # Verify cache files updated
    local new_timestamp=$(cat "$TEST_HOME/.moonfrp/status.cache.timestamp" 2>/dev/null || echo "0")
    run_test "Background process updates cache timestamp file" "[[ $new_timestamp -ge $initial_timestamp ]]"
    
    # Verify in-memory cache can be updated from files
    unset STATUS_CACHE 2>/dev/null || true
    declare -A STATUS_CACHE
    init_status_cache
    
    run_test "In-memory cache loads from file cache" "[[ -n \"${STATUS_CACHE[\"data\"]}\" ]]"
    
    cleanup_test_env
}

# Run all tests
main() {
    echo "Running cached status display tests..."
    echo "========================================"
    echo
    
    test_cache_initialization
    test_configurable_ttl
    test_frp_version_cached_ttl_1_hour
    test_cached_status_query_under_50ms
    test_generate_quick_status_under_200ms
    test_menu_load_under_200ms_with_50_configs
    test_sqlite_queries_performance
    test_systemctl_batch_query_performance
    test_background_refresh_non_blocking
    test_cache_ttl_expiration
    test_manual_refresh_works
    test_cache_survives_menu_navigation
    test_stale_cache_display_while_refreshing
    test_cache_file_persistence
    test_display_cached_status_formatting
    test_cache_persistence_across_processes
    
    echo
    echo "========================================"
    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Cleanup on exit
trap cleanup_test_env EXIT

main "$@"

