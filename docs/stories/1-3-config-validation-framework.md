# Story 1.3: Config Validation Framework

Status: review

## Story

As a DevOps engineer,
I want config files validated before saving,
so that invalid configurations are rejected with clear error messages and don't crash services.

## Acceptance Criteria

1. Validates TOML syntax before saving
2. Validates required fields (serverAddr, bindPort, auth.token, etc.)
3. Validates value ranges (ports 1-65535, valid IPs)
4. Clear error messages with line numbers
5. Validation completes in <100ms
6. Prevents save if validation fails
7. Optional: Use `frps --verify-config` if available

## Tasks / Subtasks

- [x] Implement TOML syntax validation (AC: 1, 4, 5)
  - [x] Create validate_toml_syntax() function
  - [x] Try using toml-validator command if available
  - [x] Fallback to parsing test with get_toml_value() for basic syntax check
  - [x] Return clear error messages if syntax invalid
- [x] Implement server config validation (AC: 2, 3, 4)
  - [x] Create validate_server_config() function
  - [x] Validate required field: bindPort (must be 1-65535)
  - [x] Validate required field: auth.token (minimum 8 characters)
  - [x] Return clear error messages for each validation failure
- [x] Implement client config validation (AC: 2, 3, 4)
  - [x] Create validate_client_config() function
  - [x] Validate required field: serverAddr (must be valid IP/domain)
  - [x] Validate required field: serverPort (must be 1-65535)
  - [x] Validate required field: auth.token
  - [x] Check for at least one proxy definition (warning if none)
  - [x] Return clear error messages for each validation failure
- [x] Create main validation function (AC: 1, 2, 3, 4, 5)
  - [x] Create validate_config_file() function with auto-detection
  - [x] Detect config type (server/client) from filename
  - [x] Run TOML syntax validation
  - [x] Run config-type-specific validation
  - [x] Aggregate all errors and report clearly
  - [x] Return appropriate exit code (0=valid, 1=invalid)
- [x] Integrate validation into save flow (AC: 6)
  - [x] Update save_config_file() or equivalent save function
  - [x] Write config to temporary file first
  - [x] Validate temporary file before moving to final location
  - [x] Prevent save if validation fails (delete temp file, show errors)
  - [x] Only move to final location if validation passes
- [x] Add optional FRP binary validation (AC: 7)
  - [x] Check if frps --verify-config or similar command available
  - [x] Use FRP binary validation as additional check if available
  - [x] Make this optional (don't fail if command unavailable)
- [x] Performance and error message testing (AC: 4, 5)
  - [x] Test validation completes in <100ms
  - [x] Verify error messages are clear and actionable
  - [x] Test with various invalid configurations
  - [x] Test with valid configurations
- [x] Unit tests (AC: 1, 2, 3, 4, 5, 6)
  - [x] test_validate_valid_server_config()
  - [x] test_validate_valid_client_config()
  - [x] test_validate_missing_required_field()
  - [x] test_validate_invalid_port_range()
  - [x] test_validate_invalid_toml_syntax()
  - [x] test_validate_performance_under_100ms()
  - [x] test_save_rejected_on_validation_failure()

## Dev Notes

### Requirements Context

**Source Documents:**
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.3-Config-Validation-Framework]
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.3-Config-Validation-Framework#Technical-Specification]

**Problem Statement:**
Invalid configs crash services and are hard to debug. Currently, there's no pre-save validation, so users can create invalid TOML files or configs with missing required fields, which only fail when the service tries to start. This creates poor user experience and makes troubleshooting difficult.

**Current Implementation:**
Config files are saved directly without validation in `moonfrp-config.sh`. The `get_toml_value()` function exists for reading, but there's no validation framework.

**Required Implementation:**
Create a comprehensive validation framework that:
- Validates TOML syntax before saving
- Validates required fields based on config type (server vs client)
- Validates value ranges (ports, IP addresses)
- Provides clear, actionable error messages
- Prevents saving invalid configurations
- Completes quickly (<100ms) to maintain good UX

### Technical Constraints

**File Location:** `moonfrp-config.sh` - New validation functions

**Dependencies:**
- Existing `get_toml_value()` function from `moonfrp-config.sh` (line 16-31)
- Existing `validate_ip()` and `validate_port()` functions from `moonfrp-core.sh`
- Optional: `toml-validator` command-line tool (if available)
- Optional: `frps --verify-config` command (if available in FRP)

**Integration Points:**
- Update save/config creation functions to call validation before saving
- Integrate with Story 1.4 (Automatic Backup System) - validation should run before backup
- May integrate with Story 1.2 (Config Index) - validation should run before indexing

**Performance Requirements:**
- Validation must complete in <100ms to maintain responsive UI
- Avoid multiple file reads - use temporary file for validation

### Project Structure Notes

- **Module:** `moonfrp-config.sh` - Configuration management functions
- **New Functions:** 
  - `validate_config_file()` - Main validation entry point
  - `validate_toml_syntax()` - TOML syntax validation
  - `validate_server_config()` - Server-specific validation
  - `validate_client_config()` - Client-specific validation
- **Integration:** Update existing save functions to use validation
- **Dependencies on Previous Stories:** None required, but will integrate with Stories 1.2 and 1.4 when they're implemented

### Validation Rules

**Server Config Required Fields:**
- `bindPort`: Must be integer 1-65535
- `auth.token`: Must be string, minimum 8 characters

**Client Config Required Fields:**
- `serverAddr`: Must be valid IP address or domain name
- `serverPort`: Must be integer 1-65535
- `auth.token`: Must be present (no minimum length requirement for client)
- At least one `[[proxies]]` section (warning, not error)

**Value Range Validations:**
- Ports: 1-65535 (inclusive)
- IP addresses: Use existing `validate_ip()` function
- Auth token length: Minimum 8 characters for server

### Testing Strategy

**Unit Test Location:** Create tests in test suite (to be defined)

**Functional Testing:**
- Test valid server config passes validation
- Test valid client config passes validation
- Test missing required fields are detected
- Test invalid port ranges are detected
- Test invalid TOML syntax is detected
- Test save is prevented when validation fails

**Performance Testing:**
- Benchmark validation time (target <100ms)
- Test with various config sizes
- Test with complex configs (many proxies)

**Edge Cases:**
- Empty config files
- Configs with comments only
- Configs with malformed TOML
- Configs with correct TOML but missing required fields
- Configs with out-of-range port numbers

### Learnings from Previous Stories

**From Story 1-1-fix-frp-version-detection (Status: drafted)**
- Simple function replacement pattern established
- No architectural changes needed

**From Story 1-2-implement-config-index (Status: drafted)**
- New module pattern established for `moonfrp-index.sh`
- Story 1.3 should integrate with index: validate before indexing
- Use `get_toml_value()` function for parsing (already available)

[Source: docs/stories/1-1-fix-frp-version-detection.md#Dev-Agent-Record]
[Source: docs/stories/1-2-implement-config-index.md#Dev-Agent-Record]

### References

- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.3-Config-Validation-Framework]
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.3-Config-Validation-Framework#Technical-Specification]
- [Source: moonfrp-config.sh#16-31] - get_toml_value() function
- [Source: moonfrp-core.sh#233-240] - validate_port() function
- [Source: moonfrp-core.sh] - validate_ip() function

## Dev Agent Record

### Context Reference

- docs/stories/1-3-config-validation-framework.context.xml

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

- ✅ Implemented comprehensive validation framework with four main functions:
  - `validate_toml_syntax()`: Validates TOML file syntax using toml-validator if available, with fallback to parsing-based checks. Provides clear error messages with line numbers.
  - `validate_server_config()`: Validates server config required fields (bindPort: 1-65535, auth.token: min 8 chars) with clear error messages.
  - `validate_client_config()`: Validates client config required fields (serverAddr: valid IP/domain, serverPort: 1-65535, auth.token) with proxy count warning.
  - `validate_config_file()`: Main entry point with auto-detection of config type, aggregates all validation errors, includes optional FRP binary validation, and tracks performance (<100ms target).

- ✅ Integrated validation into save flow:
  - Updated `generate_server_config()` and `generate_client_config()` to write to temp file, validate, then move to final location.
  - Updated `set_toml_value()` to validate after modifications before saving.
  - All save operations now prevent invalid configs from being written.

- ✅ Created comprehensive test suite (`tests/test_config_validation.sh`) covering:
  - Valid server/client configs
  - Missing required fields
  - Invalid port ranges and IP addresses
  - Invalid TOML syntax
  - Auth token minimum length enforcement
  - Performance requirements
  - Save rejection on validation failure
  - Auto-detection of config type
  - Edge cases (empty files, comments-only files, domain names)

- ✅ All acceptance criteria satisfied:
  1. Validates TOML syntax before saving ✓
  2. Validates required fields ✓
  3. Validates value ranges (ports 1-65535, valid IPs) ✓
  4. Clear error messages with line numbers ✓
  5. Validation completes in <100ms ✓
  6. Prevents save if validation fails ✓
  7. Optional FRP binary validation if available ✓

### File List

- moonfrp-config.sh (modified) - Added validation functions: validate_toml_syntax(), validate_server_config(), validate_client_config(), validate_config_file(); Updated generate_server_config(), generate_client_config(), set_toml_value() to use validation
- tests/test_config_validation.sh (new) - Comprehensive unit tests for validation framework

## Change Log

- 2025-11-02: Story created from Epic 1.3 requirements
- 2025-11-02: Implementation complete - Added config validation framework with TOML syntax validation, server/client field validation, integration into save flow, and comprehensive unit tests

