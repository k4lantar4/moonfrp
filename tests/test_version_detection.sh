#!/bin/bash

#==============================================================================
# Unit Tests for FRP Version Detection
# Story: 1-1-fix-frp-version-detection
#==============================================================================

set -u
set -o pipefail
# Note: Don't use set -e as we want to continue on test failures

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

# Source the function being tested
# Temporarily disable error exit to prevent sourcing from killing the test script
set +e
source "$PROJECT_ROOT/moonfrp-core.sh" || true
set -u
set -o pipefail

# Backup original binaries if they exist
BACKUP_DIR="${TEMP_DIR:-/tmp}/frp_backup_$$"
TEST_FRP_DIR="${TEMP_DIR:-/tmp}/test_frp_$$"
BACKUP_CREATED=false

# Test framework functions
test_passed() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

test_failed() {
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo "  Expected: $2"
    echo "  Got: $3"
}

run_test() {
    local test_name="$1"
    local expected="$2"
    shift 2
    
    ((TESTS_RUN++))
    local result
    result=$(eval "$@" 2>&1) || result="ERROR"
    result=$(echo "$result" | head -1 | tr -d '\n\r')
    
    if [[ "$result" == "$expected" ]]; then
        test_passed "$test_name"
        return 0
    else
        test_failed "$test_name" "$expected" "$result"
        return 1
    fi
}

# Performance test helper
test_performance() {
    local test_name="$1"
    local max_ms="$2"
    shift 2
    local command="$@"
    
    ((TESTS_RUN++))
    
    local start_time=$(date +%s%N)
    eval "$command" > /dev/null 2>&1
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

# Setup test environment - create test binaries in FRP_DIR
setup_test_env() {
    # Backup existing binaries only once
    if [[ "$BACKUP_CREATED" != "true" ]]; then
        mkdir -p "$BACKUP_DIR"
        mkdir -p "$TEST_FRP_DIR"
        
        # Backup existing binaries if they exist
        if [[ -f "$FRP_DIR/frps" ]]; then
            cp "$FRP_DIR/frps" "$BACKUP_DIR/frps" 2>/dev/null || true
        fi
        if [[ -f "$FRP_DIR/frpc" ]]; then
            cp "$FRP_DIR/frpc" "$BACKUP_DIR/frpc" 2>/dev/null || true
        fi
        if [[ -f "$FRP_DIR/.version" ]]; then
            cp "$FRP_DIR/.version" "$BACKUP_DIR/.version" 2>/dev/null || true
        fi
        BACKUP_CREATED=true
    fi
    
    # Ensure FRP_DIR exists
    mkdir -p "$FRP_DIR"
}

# Cleanup test environment
cleanup_test_env() {
    # Restore backups
    if [[ -f "$BACKUP_DIR/frps" ]]; then
        cp "$BACKUP_DIR/frps" "$FRP_DIR/frps" 2>/dev/null || true
        chmod +x "$FRP_DIR/frps" 2>/dev/null || true
    else
        rm -f "$FRP_DIR/frps" 2>/dev/null || true
    fi
    
    if [[ -f "$BACKUP_DIR/frpc" ]]; then
        cp "$BACKUP_DIR/frpc" "$FRP_DIR/frpc" 2>/dev/null || true
        chmod +x "$FRP_DIR/frpc" 2>/dev/null || true
    else
        rm -f "$FRP_DIR/frpc" 2>/dev/null || true
    fi
    
    if [[ -f "$BACKUP_DIR/.version" ]]; then
        cp "$BACKUP_DIR/.version" "$FRP_DIR/.version" 2>/dev/null || true
    else
        rm -f "$FRP_DIR/.version" 2>/dev/null || true
    fi
    
    # Cleanup
    rm -rf "$BACKUP_DIR" "$TEST_FRP_DIR" 2>/dev/null || true
}

# Ensure cleanup on exit
trap cleanup_test_env EXIT

# Test cases

test_version_with_v_prefix() {
    setup_test_env
    
    # Create mock frps that outputs version with 'v' prefix
    cat > "$FRP_DIR/frps" << 'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "frps version v0.65.0"
    exit 0
fi
EOF
    chmod +x "$FRP_DIR/frps"
    
    # Create mock frpc
    touch "$FRP_DIR/frpc"
    chmod +x "$FRP_DIR/frpc"
    
    run_test "Version detection with 'v' prefix" "v0.65.0" "get_frp_version"
}

test_version_without_v_prefix() {
    setup_test_env
    
    # Create mock frps that outputs version without 'v' prefix
    cat > "$FRP_DIR/frps" << 'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "frps version 0.65.0"
    exit 0
fi
EOF
    chmod +x "$FRP_DIR/frps"
    
    # Create mock frpc
    touch "$FRP_DIR/frpc"
    chmod +x "$FRP_DIR/frpc"
    
    run_test "Version detection without 'v' prefix (should add 'v')" "v0.65.0" "get_frp_version"
}

test_version_old_versions() {
    setup_test_env
    
    # Test with 0.52.0
    cat > "$FRP_DIR/frps" << 'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "frps version v0.52.0"
    exit 0
fi
EOF
    chmod +x "$FRP_DIR/frps"
    touch "$FRP_DIR/frpc"
    chmod +x "$FRP_DIR/frpc"
    
    run_test "Version detection with old version 0.52.0" "v0.52.0" "get_frp_version"
    
    # Test with 0.58.0
    cat > "$FRP_DIR/frps" << 'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "frps version v0.58.0"
    exit 0
fi
EOF
    
    run_test "Version detection with old version 0.58.0" "v0.58.0" "get_frp_version"
}

test_version_missing_binary() {
    setup_test_env
    
    # Don't create binaries - should return "not installed"
    rm -f "$FRP_DIR/frps" "$FRP_DIR/frpc"
    
    run_test "Version detection with missing binary (should return 'not installed')" "not installed" "get_frp_version"
}

test_version_corrupted_binary() {
    setup_test_env
    
    # Create corrupted binary (non-executable or fails)
    cat > "$FRP_DIR/frps" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$FRP_DIR/frps"
    
    cat > "$FRP_DIR/frpc" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$FRP_DIR/frpc"
    
    # Should fallback to unknown since binaries fail
    run_test "Version detection with corrupted binary (should return 'unknown')" "unknown" "get_frp_version"
}

test_version_fallback_to_frpc() {
    setup_test_env
    
    # frps doesn't work, but frpc does
    cat > "$FRP_DIR/frps" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$FRP_DIR/frps"
    
    cat > "$FRP_DIR/frpc" << 'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "frpc version v0.65.0"
    exit 0
fi
EOF
    chmod +x "$FRP_DIR/frpc"
    
    run_test "Version detection fallback to frpc when frps fails" "v0.65.0" "get_frp_version"
}

test_version_file_method() {
    setup_test_env
    
    # Create non-functional binaries
    cat > "$FRP_DIR/frps" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$FRP_DIR/frps"
    
    cat > "$FRP_DIR/frpc" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$FRP_DIR/frpc"
    
    # Create .version file
    echo "v0.65.0" > "$FRP_DIR/.version"
    
    run_test "Version detection from .version file" "v0.65.0" "get_frp_version"
    
    # Test .version file without 'v' prefix
    echo "0.65.0" > "$FRP_DIR/.version"
    
    run_test "Version detection from .version file without 'v' prefix" "v0.65.0" "get_frp_version"
}

test_version_performance() {
    setup_test_env
    
    cat > "$FRP_DIR/frps" << 'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "frps version v0.65.0"
    exit 0
fi
EOF
    chmod +x "$FRP_DIR/frps"
    touch "$FRP_DIR/frpc"
    chmod +x "$FRP_DIR/frpc"
    
    test_performance "Version detection performance (<100ms)" 100 "get_frp_version"
}

# Main test execution
main() {
    echo "Running FRP Version Detection Tests"
    echo "===================================="
    echo ""
    
    test_version_with_v_prefix
    test_version_without_v_prefix
    test_version_old_versions
    test_version_missing_binary
    test_version_corrupted_binary
    test_version_fallback_to_frpc
    test_version_file_method
    test_version_performance
    
    echo ""
    echo "===================================="
    echo "Test Summary"
    echo "===================================="
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
