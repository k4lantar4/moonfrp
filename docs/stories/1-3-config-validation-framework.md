# Story 1.3: Config Validation Framework

Status: ready-for-dev

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

- [ ] Implement TOML syntax validation (AC: 1, 4, 5)
  - [ ] Create validate_toml_syntax() function
  - [ ] Try using toml-validator command if available
  - [ ] Fallback to parsing test with get_toml_value() for basic syntax check
  - [ ] Return clear error messages if syntax invalid
- [ ] Implement server config validation (AC: 2, 3, 4)
  - [ ] Create validate_server_config() function
  - [ ] Validate required field: bindPort (must be 1-65535)
  - [ ] Validate required field: auth.token (minimum 8 characters)
  - [ ] Return clear error messages for each validation failure
- [ ] Implement client config validation (AC: 2, 3, 4)
  - [ ] Create validate_client_config() function
  - [ ] Validate required field: serverAddr (must be valid IP/domain)
  - [ ] Validate required field: serverPort (must be 1-65535)
  - [ ] Validate required field: auth.token
  - [ ] Check for at least one proxy definition (warning if none)
  - [ ] Return clear error messages for each validation failure
- [ ] Create main validation function (AC: 1, 2, 3, 4, 5)
  - [ ] Create validate_config_file() function with auto-detection
  - [ ] Detect config type (server/client) from filename
  - [ ] Run TOML syntax validation
  - [ ] Run config-type-specific validation
  - [ ] Aggregate all errors and report clearly
  - [ ] Return appropriate exit code (0=valid, 1=invalid)
- [ ] Integrate validation into save flow (AC: 6)
  - [ ] Update save_config_file() or equivalent save function
  - [ ] Write config to temporary file first
  - [ ] Validate temporary file before moving to final location
  - [ ] Prevent save if validation fails (delete temp file, show errors)
  - [ ] Only move to final location if validation passes
- [ ] Add optional FRP binary validation (AC: 7)
  - [ ] Check if frps --verify-config or similar command available
  - [ ] Use FRP binary validation as additional check if available
  - [ ] Make this optional (don't fail if command unavailable)
- [ ] Performance and error message testing (AC: 4, 5)
  - [ ] Test validation completes in <100ms
  - [ ] Verify error messages are clear and actionable
  - [ ] Test with various invalid configurations
  - [ ] Test with valid configurations
- [ ] Unit tests (AC: 1, 2, 3, 4, 5, 6)
  - [ ] test_validate_valid_server_config()
  - [ ] test_validate_valid_client_config()
  - [ ] test_validate_missing_required_field()
  - [ ] test_validate_invalid_port_range()
  - [ ] test_validate_invalid_toml_syntax()
  - [ ] test_validate_performance_under_100ms()
  - [ ] test_save_rejected_on_validation_failure()

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

### File List

## Change Log

- 2025-11-02: Story created from Epic 1.3 requirements

