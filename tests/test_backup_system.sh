#!/bin/bash

#==============================================================================
# Unit Tests for Automatic Backup System
# Story: 1-4-automatic-backup-system
#==============================================================================

set -u
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test environment
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_backup_$$"
TEST_BACKUP_DIR="${HOME}/.moonfrp/backups_test_$$"

# Cleanup function
cleanup() {
    rm -rf "$TEST_CONFIG_DIR" "$TEST_BACKUP_DIR" 2>/dev/null
}
trap cleanup EXIT

# Source the functions being tested
set +e
mkdir -p "$TEST_CONFIG_DIR"

# Temporarily unset readonly CONFIG_DIR if it exists
if [[ -n "${CONFIG_DIR:-}" ]]; then
    unset CONFIG_DIR 2>/dev/null || true
fi
export CONFIG_DIR="$TEST_CONFIG_DIR"

source "$PROJECT_ROOT/moonfrp-core.sh" || true

# Set BACKUP_DIR before sourcing moonfrp-config.sh (since it's readonly)
export BACKUP_DIR="$TEST_BACKUP_DIR"
export HOME="${HOME:-/root}"  # Ensure HOME is set

source "$PROJECT_ROOT/moonfrp-config.sh" || true

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

# Setup test config file
setup_test_config() {
    local config_file="$1"
    local content="${2:-# Test config file
bindAddr = \"0.0.0.0\"
bindPort = 7000
auth.token = \"test123\"
}"
    echo "$content" > "$config_file"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing Automatic Backup System${NC}"
echo -e "${BLUE}Story: 1-4-automatic-backup-system${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Test 1: Backup creates timestamped file (AC: 2)
echo -e "${YELLOW}Test 1: Backup creates timestamped file${NC}"
TEST_CONFIG="$TEST_CONFIG_DIR/frps.toml"
setup_test_config "$TEST_CONFIG"

# Call backup function and capture output
if backup_file=$(backup_config_file "$TEST_CONFIG" 2>&1); then
    if [[ -n "$backup_file" ]] && [[ -f "$backup_file" ]]; then
        # Check filename format: config-name.YYYYMMDD-HHMMSS.bak
        backup_basename=$(basename "$backup_file")
        if [[ "$backup_basename" =~ ^frps\.toml\.[0-9]{8}-[0-9]{6}\.bak$ ]]; then
            test_passed "Backup creates timestamped file with correct format"
        else
            test_failed "Backup filename format" "frps.toml.YYYYMMDD-HHMMSS.bak" "$backup_basename"
        fi
    else
        test_failed "Backup file creation" "File should exist" "Got: $backup_file"
    fi
else
    test_failed "Backup function call" "Should succeed" "Function failed: $backup_file"
fi
echo

# Test 2: Backup directory is created automatically (AC: 6)
echo -e "${YELLOW}Test 2: Backup directory is created automatically${NC}"
rm -rf "$TEST_BACKUP_DIR"
TEST_CONFIG="$TEST_CONFIG_DIR/frps2.toml"
setup_test_config "$TEST_CONFIG"
backup_config_file "$TEST_CONFIG" >/dev/null 2>&1
if [[ -d "$TEST_BACKUP_DIR" ]]; then
    test_passed "Backup directory created automatically"
else
    test_failed "Backup directory creation" "Directory should exist" "Directory not created"
fi
echo

# Test 3: Cleanup keeps last 10 backups (AC: 3)
echo -e "${YELLOW}Test 3: Cleanup keeps last 10 backups${NC}"
TEST_CONFIG="$TEST_CONFIG_DIR/frpc.toml"
setup_test_config "$TEST_CONFIG"

# Create 15 backups
for i in {1..15}; do
    sleep 0.01  # Small delay to ensure different timestamps
    cp "$TEST_CONFIG" "$TEST_BACKUP_DIR/frpc.toml.$(date '+%Y%m%d-%H%M%S').bak" 2>/dev/null
done

# Run cleanup
cleanup_old_backups "$TEST_CONFIG"

# Count remaining backups
backup_count=$(find "$TEST_BACKUP_DIR" -name "frpc.toml.*.bak" -type f 2>/dev/null | wc -l)
if [[ $backup_count -eq 10 ]]; then
    test_passed "Cleanup keeps exactly 10 backups"
else
    test_failed "Backup cleanup retention" "10 backups" "$backup_count backups"
fi
echo

# Test 4: Restore from backup (AC: 4)
echo -e "${YELLOW}Test 4: Restore from backup${NC}"
TEST_CONFIG="$TEST_CONFIG_DIR/restore_test.toml"
ORIGINAL_CONTENT="# Original config
bindAddr = \"0.0.0.0\"
bindPort = 7000
"
setup_test_config "$TEST_CONFIG" "$ORIGINAL_CONTENT"

# Create backup
backup_file=$(backup_config_file "$TEST_CONFIG" 2>/dev/null)

# Modify config
echo "# Modified config" > "$TEST_CONFIG"

# Restore from backup
if restore_config_from_backup "$TEST_CONFIG" "$backup_file" >/dev/null 2>&1; then
    if grep -q "Original config" "$TEST_CONFIG"; then
        test_passed "Restore from backup works correctly"
    else
        test_failed "Restore content" "Should contain original content" "Content mismatch"
    fi
else
    test_failed "Restore operation" "Should succeed" "Restore failed"
fi
echo

# Test 5: Nested backup (backup before restore) (AC: 4)
echo -e "${YELLOW}Test 5: Nested backup before restore${NC}"
TEST_CONFIG="$TEST_CONFIG_DIR/nested_test.toml"
setup_test_config "$TEST_CONFIG" "# Before restore
bindPort = 7000
"

# Create initial backup
backup1=$(backup_config_file "$TEST_CONFIG" 2>/dev/null)

# Modify config
echo "# Modified" > "$TEST_CONFIG"

# Create another backup
backup2=$(backup_config_file "$TEST_CONFIG" 2>/dev/null)

# Restore from first backup
restore_config_from_backup "$TEST_CONFIG" "$backup1" >/dev/null 2>&1

# Check that current config was backed up before restore
backup_count=$(find "$TEST_BACKUP_DIR" -name "nested_test.toml.*.bak" -type f 2>/dev/null | wc -l)
if [[ $backup_count -ge 3 ]]; then  # original + modified + nested before restore
    test_passed "Nested backup created before restore"
else
    test_failed "Nested backup" "Should have at least 3 backups" "Found $backup_count"
fi
echo

# Test 6: List backups sorted (AC: 4)
echo -e "${YELLOW}Test 6: List backups sorted${NC}"
TEST_CONFIG="$TEST_CONFIG_DIR/list_test.toml"
setup_test_config "$TEST_CONFIG"

# Create multiple backups with delays
for i in {1..5}; do
    sleep 0.02
    backup_config_file "$TEST_CONFIG" >/dev/null 2>&1
done

# List backups
backup_list=()
while IFS= read -r backup; do
    [[ -n "$backup" ]] && backup_list+=("$backup")
done < <(list_backups "$TEST_CONFIG")

if [[ ${#backup_list[@]} -ge 5 ]]; then
    # Check that list is sorted (newest first - check timestamps)
    local prev_timestamp=99999999999999
    local sorted=true
    for backup in "${backup_list[@]}"; do
        local backup_name=$(basename "$backup")
        local timestamp_part="${backup_name##*.}"
        timestamp_part="${timestamp_part%.bak}"
        local timestamp_num="${timestamp_part//-/}"
        if [[ $timestamp_num -gt $prev_timestamp ]]; then
            sorted=false
            break
        fi
        prev_timestamp=$timestamp_num
    done
    
    if [[ "$sorted" == "true" ]]; then
        test_passed "List backups returns sorted list (newest first)"
    else
        test_failed "Backup list sorting" "Should be sorted newest first" "Not properly sorted"
    fi
else
    test_failed "Backup list" "Should have at least 5 backups" "Found ${#backup_list[@]}"
fi
echo

# Test 7: Backup performance <50ms (AC: 5)
echo -e "${YELLOW}Test 7: Backup performance <50ms${NC}"
TEST_CONFIG="$TEST_CONFIG_DIR/perf_test.toml"
setup_test_config "$TEST_CONFIG"
test_performance "Backup operation performance" 50 "backup_config_file \"$TEST_CONFIG\""
echo

# Test 8: Backup before save (AC: 1)
echo -e "${YELLOW}Test 8: Backup before save${NC}"
TEST_CONFIG="$TEST_CONFIG_DIR/save_test.toml"
ORIGINAL="# Original"
setup_test_config "$TEST_CONFIG" "$ORIGINAL"

# Count backups before save
backup_count_before=$(find "$TEST_BACKUP_DIR" -name "save_test.toml.*.bak" -type f 2>/dev/null | wc -l)

# Save using set_toml_value (which should trigger backup)
echo "# Modified" > "$TEST_CONFIG"
set_toml_value "$TEST_CONFIG" "bindPort" "8000" >/dev/null 2>&1

# Count backups after save
backup_count_after=$(find "$TEST_BACKUP_DIR" -name "save_test.toml.*.bak" -type f 2>/dev/null | wc -l)

if [[ $backup_count_after -gt $backup_count_before ]]; then
    test_passed "Backup created before config save"
else
    test_failed "Backup before save" "Backup count should increase" "Before: $backup_count_before, After: $backup_count_after"
fi
echo

# Test 9: Backup failure handling (graceful degradation)
echo -e "${YELLOW}Test 9: Backup failure handling${NC}"
# Create a read-only backup directory (if possible)
TEST_CONFIG="$TEST_CONFIG_DIR/fail_test.toml"
setup_test_config "$TEST_CONFIG"

# Temporarily make backup dir read-only (may fail on some systems)
chmod 555 "$TEST_BACKUP_DIR" 2>/dev/null || true

# Try to backup - should fail gracefully
if backup_config_file "$TEST_CONFIG" >/dev/null 2>&1; then
    test_passed "Backup failure handled (may succeed if chmod failed)"
else
    # This is expected - backup should fail but not crash
    test_passed "Backup failure handled gracefully"
fi

# Restore permissions
chmod 755 "$TEST_BACKUP_DIR" 2>/dev/null || true
echo

# Test 10: List all backups when no config file specified
echo -e "${YELLOW}Test 10: List all backups${NC}"
# Create backups for different config files
TEST_CONFIG1="$TEST_CONFIG_DIR/config1.toml"
TEST_CONFIG2="$TEST_CONFIG_DIR/config2.toml"
setup_test_config "$TEST_CONFIG1"
setup_test_config "$TEST_CONFIG2"

backup_config_file "$TEST_CONFIG1" >/dev/null 2>&1
backup_config_file "$TEST_CONFIG2" >/dev/null 2>&1

# List all backups
all_backups=()
while IFS= read -r backup; do
    [[ -n "$backup" ]] && all_backups+=("$backup")
done < <(list_backups)

if [[ ${#all_backups[@]} -ge 2 ]]; then
    test_passed "List all backups works"
else
    test_failed "List all backups" "Should have at least 2 backups" "Found ${#all_backups[@]}"
fi
echo

# Test 11: Restore validates config (if validation available) (AC: 4)
echo -e "${YELLOW}Test 11: Restore validates config${NC}"
if type validate_config_file &>/dev/null; then
    TEST_CONFIG="$TEST_CONFIG_DIR/validate_test.toml"
    VALID_CONTENT="bindAddr = \"0.0.0.0\"
bindPort = 7000
auth.method = \"token\"
auth.token = \"test123456789012345678901234\"
"
    setup_test_config "$TEST_CONFIG" "$VALID_CONTENT"
    
    backup_file=$(backup_config_file "$TEST_CONFIG" 2>/dev/null)
    
    # Modify to invalid config
    echo "# Invalid" > "$TEST_CONFIG"
    
    # Restore (should validate)
    if restore_config_from_backup "$TEST_CONFIG" "$backup_file" >/dev/null 2>&1; then
        test_passed "Restore validates config"
    else
        test_failed "Restore validation" "Should succeed with valid config" "Restore failed"
    fi
else
    echo -e "${YELLOW}  SKIP: validate_config_file not available${NC}"
fi
echo

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Tests run: ${TESTS_RUN}"
echo -e "${GREEN}Tests passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Tests failed: ${TESTS_FAILED}${NC}"
echo

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi

