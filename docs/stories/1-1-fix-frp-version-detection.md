# Story 1.1: Fix FRP Version Detection

Status: review

## Story

As a DevOps engineer,
I want the system to accurately detect and display the FRP version,
so that I can verify compatibility and troubleshoot issues effectively.

## Acceptance Criteria

1. Version detection works for FRP versions 0.52.0 through 0.65.0+
2. Displays format: "v0.65.0" (with leading 'v')
3. Falls back gracefully: "unknown" if detection fails, "not installed" if missing
4. Uses multiple detection methods (frps, frpc, version file)
5. Detection completes in <100ms

## Tasks / Subtasks

- [x] Replace get_frp_version() function implementation (AC: 1, 2, 3, 4)
  - [x] Update function to check FRP installation first
  - [x] Implement Method 1: frps --version with regex pattern `v?[0-9]+\.[0-9]+\.[0-9]+`
  - [x] Implement Method 2: frpc --version as fallback with same pattern
  - [x] Implement Method 3: Read from $FRP_DIR/.version file if exists
  - [x] Ensure 'v' prefix is added if missing from detected version
  - [x] Return "unknown" if all methods fail
  - [x] Return "not installed" if FRP installation check fails
- [x] Add unit tests for version detection (AC: 1, 2, 3, 4, 5)
  - [x] Test version detection with 'v' prefix
  - [x] Test version detection without 'v' prefix
  - [x] Test with old FRP versions (0.52.0, 0.58.0)
  - [x] Test with missing binary (should return "not installed")
  - [x] Test with corrupted binary (should return "unknown")
  - [x] Test performance <100ms
- [ ] Manual testing verification (AC: 1, 2, 3, 4)
  - [ ] Install FRP 0.58.0 and verify correct version display
  - [ ] Install FRP 0.61.0 and verify correct version display
  - [ ] Install FRP 0.65.0 and verify correct version display
  - [ ] Remove FRP and verify "not installed" message
  - [ ] Corrupt binary and verify "unknown" message

## Dev Notes

### Requirements Context

**Source Documents:**
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.1-Fix-FRP-Version-Detection]
- [Source: docs/implementation-plan-dev.md#1.1-Fix-FRP-Version-Detection]

**Problem Statement:**
Current implementation in `moonfrp-core.sh` (lines 284-290) uses a simple regex pattern `grep -o 'v[0-9.]*'` which is too permissive and fails to correctly parse version output from FRP binaries. This results in "vunknown" being displayed, breaking compatibility checks and confusing users.

**Current Implementation:**
```bash
get_frp_version() {
    if check_frp_installation; then
        "$FRP_DIR/frps" --version 2>/dev/null | head -1 | grep -o 'v[0-9.]*' || echo "unknown"
    else
        echo "not installed"
    fi
}
```

**Required Implementation:**
The new implementation must:
- Use a stricter regex pattern: `v?[0-9]+\.[0-9]+\.[0-9]+` to match semantic version format
- Try multiple detection methods (frps, frpc, version file) for reliability
- Ensure consistent "v" prefix format regardless of source output
- Handle edge cases gracefully with appropriate fallbacks

### Technical Constraints

**File Location:** `moonfrp-core.sh` - `get_frp_version()` function (lines 284-290)

**Dependencies:**
- Existing `check_frp_installation()` function (line 275)
- `$FRP_DIR` environment variable must be set
- `frps` and `frpc` binaries expected at `$FRP_DIR/frps` and `$FRP_DIR/frpc`

**Performance Requirements:**
- Version detection must complete in <100ms
- Avoid multiple unnecessary binary executions
- Cache-friendly design (no state changes required)

### Project Structure Notes

- **Module:** `moonfrp-core.sh` - Core utility functions
- **Function:** `get_frp_version()` - Line 284-290 (to be replaced)
- **No new files required** - Pure function replacement
- **No dependencies on other stories** - Can be implemented independently

### Testing Strategy

**Unit Test Location:** Create tests in test suite (to be defined)
- Test with various FRP version outputs
- Test with missing/corrupted binaries
- Performance benchmarking to ensure <100ms

**Manual Testing:**
- Install multiple FRP versions and verify detection
- Test edge cases (missing binary, corrupted file)

### Learnings from Previous Story

**First story in epic - no predecessor context**

### References

- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.1-Fix-FRP-Version-Detection]
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.1-Fix-FRP-Version-Detection#Technical-Specification]
- [Source: docs/implementation-plan-dev.md#1.1-Fix-FRP-Version-Detection]
- [Source: moonfrp-core.sh#283-290]

## Dev Agent Record

### Context Reference

- docs/stories/1-1-fix-frp-version-detection.context.xml

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

**Implementation Summary:**
- Replaced `get_frp_version()` function in `moonfrp-core.sh` (lines 284-336) with improved implementation
- Implemented three detection methods with proper fallback chain: frps --version → frpc --version → .version file
- Used stricter regex pattern `v?[0-9]+\.[0-9]+\.[0-9]+` to ensure correct semantic version matching
- Added automatic 'v' prefix normalization to ensure consistent output format
- All detection methods properly handle edge cases (missing prefix, corrupted binaries, missing files)
- Performance verified: function completes in <5ms, well under 100ms requirement

**Testing:**
- Created comprehensive unit test suite at `tests/test_version_detection.sh`
- Tests cover all acceptance criteria: version formats, old versions, error cases, performance
- All automated tests passing (9/9 tests pass)
- Manual testing tasks remain for final validation in target environment

**Files Modified:**
- `moonfrp-core.sh`: Updated `get_frp_version()` function implementation
- `tests/test_version_detection.sh`: New comprehensive test suite
- `moonfrp-ui.sh`: Fixed double "v" prefix issue in version display (lines 41, 286)

### File List

- moonfrp-core.sh (modified)
- tests/test_version_detection.sh (new)
- moonfrp-ui.sh (modified - fixed version display)

## Change Log

- 2025-11-02: Story created from Epic 1.1 requirements
- 2025-11-02: Implementation complete - replaced get_frp_version() with improved version detection using three methods with proper fallback chain. Added comprehensive unit tests. All automated tests passing. Ready for review.

