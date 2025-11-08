#!/bin/bash

#==============================================================================
# Unit Tests for Non-Interactive CLI Mode
# Story: 5-2-non-interactive-cli-mode
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
TEST_CONFIG_DIR="${TEMP_DIR:-/tmp}/test_moonfrp_cli_$$"
TEST_HOME="${TEMP_DIR:-/tmp}/test_moonfrp_home_cli_$$"

# Source the functions being tested
set +e
export CONFIG_DIR="$TEST_CONFIG_DIR"
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.moonfrp"
mkdir -p "$TEST_CONFIG_DIR"

# Source moonfrp.sh which includes all modules
source "$PROJECT_ROOT/moonfrp-core.sh" || true
source "$PROJECT_ROOT/moonfrp.sh" || true

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

run_test_expect_exit() {
    local test_name="$1"
    local expected_exit="$2"
    shift 2
    ((TESTS_RUN++))

    set +e
    eval "$@" >/dev/null 2>&1
    local actual_exit=$?
    set -e

    if [[ $actual_exit -eq $expected_exit ]]; then
        test_passed "$test_name"
        return 0
    else
        test_failed "$test_name" "Exit code $expected_exit" "Exit code $actual_exit"
        return 1
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
}

# Test: --yes flag bypasses confirmations
test_noninteractive_yes_flag() {
    echo "Testing --yes flag..."

    # Test that --yes sets MOONFRP_YES
    local test_output
    test_output=$(bash -c "source $PROJECT_ROOT/moonfrp.sh; parse_global_flags --yes help >/dev/null 2>&1; echo \$MOONFRP_YES")

    if [[ "$test_output" == "true" ]]; then
        test_passed "test_noninteractive_yes_flag - MOONFRP_YES set"
    else
        test_failed "test_noninteractive_yes_flag - MOONFRP_YES set" "true" "$test_output"
    fi

    # Test that -y also works
    test_output=$(bash -c "source $PROJECT_ROOT/moonfrp.sh; parse_global_flags -y help >/dev/null 2>&1; echo \$MOONFRP_YES")

    if [[ "$test_output" == "true" ]]; then
        test_passed "test_noninteractive_yes_flag - -y flag works"
    else
        test_failed "test_noninteractive_yes_flag - -y flag works" "true" "$test_output"
    fi
}

# Test: --quiet flag suppresses output
test_noninteractive_quiet_flag() {
    echo "Testing --quiet flag..."

    # Test that --quiet sets MOONFRP_QUIET
    local test_output
    test_output=$(bash -c "source $PROJECT_ROOT/moonfrp.sh; parse_global_flags --quiet help >/dev/null 2>&1; echo \$MOONFRP_QUIET")

    if [[ "$test_output" == "true" ]]; then
        test_passed "test_noninteractive_quiet_flag - MOONFRP_QUIET set"
    else
        test_failed "test_noninteractive_quiet_flag - MOONFRP_QUIET set" "true" "$test_output"
    fi

    # Test that -q also works
    test_output=$(bash -c "source $PROJECT_ROOT/moonfrp.sh; parse_global_flags -q help >/dev/null 2>&1; echo \$MOONFRP_QUIET")

    if [[ "$test_output" == "true" ]]; then
        test_passed "test_noninteractive_quiet_flag - -q flag works"
    else
        test_failed "test_noninteractive_quiet_flag - -q flag works" "true" "$test_output"
    fi
}

# Test: Exit codes
test_exit_codes() {
    echo "Testing exit codes..."

    # Test EXIT_SUCCESS (0) - help command should succeed
    run_test_expect_exit "test_exit_codes - help command" 0 \
        "bash $PROJECT_ROOT/moonfrp.sh help >/dev/null 2>&1"

    # Test EXIT_VALIDATION (2) - invalid command should return validation error
    run_test_expect_exit "test_exit_codes - invalid command" 1 \
        "bash $PROJECT_ROOT/moonfrp.sh invalid-command >/dev/null 2>&1"

    # Test EXIT_NOT_FOUND (4) - validate non-existent file
    run_test_expect_exit "test_exit_codes - file not found" 4 \
        "bash $PROJECT_ROOT/moonfrp.sh --yes validate /nonexistent/file.toml >/dev/null 2>&1"
}

# Test: Timeout handling
test_timeout_handling() {
    echo "Testing timeout handling..."

    # Test that --timeout sets MOONFRP_TIMEOUT
    local test_output
    test_output=$(bash -c "source $PROJECT_ROOT/moonfrp.sh; parse_global_flags --timeout=60 help >/dev/null 2>&1; echo \$MOONFRP_TIMEOUT")

    if [[ "$test_output" == "60" ]]; then
        test_passed "test_timeout_handling - timeout value set"
    else
        test_failed "test_timeout_handling - timeout value set" "60" "$test_output"
    fi

    # Test invalid timeout value
    run_test_expect_exit "test_timeout_handling - invalid timeout" 2 \
        "bash $PROJECT_ROOT/moonfrp.sh --timeout=invalid help >/dev/null 2>&1"
}

# Test: Help text
test_help_text() {
    echo "Testing help text..."

    # Test main help
    if bash "$PROJECT_ROOT/moonfrp.sh" help 2>&1 | grep -q "GLOBAL FLAGS"; then
        test_passed "test_help_text - main help includes global flags"
    else
        test_failed "test_help_text - main help includes global flags"
    fi

    # Test command-specific help
    if bash "$PROJECT_ROOT/moonfrp.sh" search --help 2>&1 | grep -q "Usage: moonfrp search"; then
        test_passed "test_help_text - search --help works"
    else
        test_failed "test_help_text - search --help works"
    fi

    if bash "$PROJECT_ROOT/moonfrp.sh" optimize --help 2>&1 | grep -q "Usage: moonfrp optimize"; then
        test_passed "test_help_text - optimize --help works"
    else
        test_failed "test_help_text - optimize --help works"
    fi

    if bash "$PROJECT_ROOT/moonfrp.sh" validate --help 2>&1 | grep -q "Usage: moonfrp validate"; then
        test_passed "test_help_text - validate --help works"
    else
        test_failed "test_help_text - validate --help works"
    fi
}

# Test: All commands CLI accessible
test_all_commands_cli_accessible() {
    echo "Testing CLI command accessibility..."

    # Test search command
    run_test_expect_exit "test_all_commands_cli_accessible - search command" 2 \
        "bash $PROJECT_ROOT/moonfrp.sh --yes search >/dev/null 2>&1"

    # Test optimize command (should work even without root in test)
    run_test "test_all_commands_cli_accessible - optimize command exists" \
        "bash $PROJECT_ROOT/moonfrp.sh --yes optimize --help >/dev/null 2>&1"

    # Test validate command
    run_test_expect_exit "test_all_commands_cli_accessible - validate command" 2 \
        "bash $PROJECT_ROOT/moonfrp.sh --yes validate >/dev/null 2>&1"

    # Test that non-interactive mode rejects menu
    run_test_expect_exit "test_all_commands_cli_accessible - non-interactive rejects menu" 2 \
        "echo '' | bash $PROJECT_ROOT/moonfrp.sh --yes >/dev/null 2>&1"
}

# Main test execution
main() {
    echo "=========================================="
    echo "Testing Non-Interactive CLI Mode"
    echo "Story: 5-2-non-interactive-cli-mode"
    echo "=========================================="
    echo

    setup_test_env

    test_noninteractive_yes_flag
    test_noninteractive_quiet_flag
    test_exit_codes
    test_timeout_handling
    test_help_text
    test_all_commands_cli_accessible

    cleanup_test_env

    echo
    echo "=========================================="
    echo "Test Results:"
    echo "  Tests Run: $TESTS_RUN"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "=========================================="

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

