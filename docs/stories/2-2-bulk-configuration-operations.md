# Story 2.2: Bulk Configuration Operations

Status: review

## Story

As a DevOps engineer managing 50+ configs,
I want to update multiple configuration files in bulk with validation and rollback,
so that I can quickly change auth tokens, server IPs, or ports across all configs without manual editing.

## Acceptance Criteria

1. Update single field across multiple configs: `bulk-update --field=auth.token --value=NEW_TOKEN --filter=all`
2. Update multiple fields with JSON/YAML input
3. Dry-run mode shows changes without applying
4. Validates each config before saving
5. Atomic operation: all succeed or all rollback
6. Backup before bulk changes
7. Performance: <5s for 50 configs

## Tasks / Subtasks

- [x] Implement bulk config field update (AC: 1, 3, 4, 5)
  - [x] Create bulk_update_config_field() function in moonfrp-config.sh
  - [x] Implement filter system: all|tag:X|type:client|server|name:pattern
  - [x] Implement dry-run mode to preview changes
  - [x] Use temp files for atomic transaction behavior
  - [x] Validate each temp file before commit (use Story 1.3 validation)
  - [x] Rollback on any validation failure
  - [x] Commit all changes atomically if all validations pass
- [x] Implement TOML field update helper (AC: 1)
  - [x] Create update_toml_field() helper function
  - [x] Support nested fields (e.g., "auth.token")
  - [x] Parse field path: section.key format
  - [x] Use awk/sed to update field value
  - [x] Preserve TOML formatting and comments
- [x] Implement config filtering (AC: 1)
  - [x] Create get_configs_by_filter() function
  - [x] Support filter types: all, type:server, type:client, tag:X, name:pattern
  - [x] Integrate with Story 2.3 tagging (when available)
  - [x] Return array of matching config file paths
- [x] Implement bulk update from file (AC: 2)
  - [x] Create bulk_update_from_file() function
  - [x] Parse JSON/YAML update file
  - [x] Extract field, value, and filter from update file
  - [x] Call bulk_update_config_field() with extracted values
  - [x] Support dry-run mode from file
- [x] Integrate with backup system (AC: 6)
  - [x] Call backup_config_file() before each config update
  - [x] Use Story 1.4 backup system (when available)
  - [x] Backup all configs before bulk update starts
  - [x] Handle backup failures gracefully
- [x] Integrate with validation system (AC: 4, 5)
  - [x] Validate each temp file using Story 1.3 validate_config_file()
  - [x] Abort transaction if any validation fails
  - [x] Only commit if all validations pass
- [x] Integrate with index system (AC: 7)
  - [x] Update index after successful bulk update
  - [x] Use Story 1.2 index_config_file() for each updated config
  - [x] Don't update index until commit phase
- [x] CLI integration (AC: 1, 2, 3)
  - [x] Add `moonfrp config bulk-update --field=X --value=Y --filter=all` command
  - [x] Add `--dry-run` option support
  - [x] Add `--file=updates.json` option for file-based updates
  - [x] Display changes preview in dry-run mode
- [x] Performance optimization (AC: 7)
  - [x] Minimize file I/O operations
  - [x] Batch validation operations
  - [x] Optimize temp file operations
  - [x] Benchmark with 50 configs (target <5s)
- [x] Testing (AC: 1, 2, 3, 4, 5, 6, 7)
  - [x] test_bulk_update_single_field_dry_run()
  - [x] test_bulk_update_single_field_apply()
  - [x] test_bulk_update_validation_failure_rollback()
  - [x] test_bulk_update_atomic_transaction()
  - [x] test_bulk_update_50_configs_under_5s()
  - [x] test_bulk_update_backup_before_change()
  - [x] test_bulk_update_filter_by_type()
  - [x] test_bulk_update_filter_by_tag()

## Dev Notes

### Requirements Context

**Source Documents:**
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.2-Bulk-Configuration-Operations]
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.2-Bulk-Configuration-Operations#Technical-Specification]

**Problem Statement:**
Updating auth tokens, server IPs, or ports across 50 configs manually is error-prone and time-consuming. Currently, each config must be edited individually, which is slow and increases risk of errors. Need bulk update capabilities with validation and dry-run.

**Current Implementation:**
Config files are managed in `moonfrp-config.sh` with individual update functions. There's no bulk update mechanism. Changes require manual editing of each TOML file.

**Required Implementation:**
Create bulk configuration update system that:
- Updates single field across multiple configs via filter system
- Supports JSON/YAML file-based updates for multiple fields
- Provides dry-run mode to preview changes
- Validates all configs before committing
- Provides atomic transaction behavior (all succeed or all rollback)
- Creates backups before changes
- Completes quickly (<5s for 50 configs)

### Technical Constraints

**File Location:** `moonfrp-config.sh` - Bulk configuration functions

**Implementation Pattern:**
```bash
bulk_update_config_field() {
    local field="$1"
    local value="$2"
    local filter="${3:-all}"
    local dry_run="${4:-false}"
    
    # Phase 1: Update all to temp files & validate
    # Phase 2: If all succeeded, commit; else rollback
}
```

**Dependencies:**
- Story 1.3: `validate_config_file()` - Validation before commit
- Story 1.4: `backup_config_file()` - Backup before changes
- Story 1.2: `index_config_file()` - Index update after commit
- Story 2.3: `query_configs_by_tag()` - Tag-based filtering (optional)
- Existing `get_toml_value()` from `moonfrp-config.sh` for parsing
- Optional: `jq` command for JSON parsing

**Integration Points:**
- Use Story 1.3 validation in transaction phase
- Use Story 1.4 backup before each config update
- Update Story 1.2 index after successful commit
- Use Story 2.3 tagging for filtered operations

**Performance Requirements:**
- 50 config updates: <5 seconds
- Atomic transaction: all-or-nothing behavior
- Dry-run should be fast (preview only, no file writes)

### Project Structure Notes

- **Module:** `moonfrp-config.sh` - Configuration management functions
- **New Functions:**
  - `bulk_update_config_field()` - Main bulk update function
  - `update_toml_field()` - TOML field update helper
  - `get_configs_by_filter()` - Config filtering by criteria
  - `bulk_update_from_file()` - File-based bulk updates
- **CLI Integration:** Update `moonfrp.sh` to add `config bulk-update` command
- **Transaction Pattern:** Temp files → validate → commit or rollback

### Atomic Transaction Design

**Two-Phase Commit Pattern:**
1. **Phase 1: Prepare**
   - Update all configs to temp files
   - Validate each temp file
   - Collect validation results
   
2. **Phase 2: Commit or Rollback**
   - If all validations pass: backup originals, move temp files to final location, update index
   - If any validation fails: delete all temp files, abort transaction

**Rollback Strategy:**
- Temp files deleted on validation failure
- No changes committed until all validations pass
- After commit: use Story 1.4 restore functionality if needed

### Filter System

**Supported Filters:**
- `all` - All config files
- `type:server` - Server configs only
- `type:client` - Client configs only
- `tag:key:value` - Configs with specific tag (Story 2.3)
- `name:pattern` - Configs matching filename pattern

**Filter Implementation:**
- `get_configs_by_filter()` returns array of matching config paths
- Integrates with Story 1.2 index for fast queries
- Falls back to file system search if index unavailable

### Testing Strategy

**Functional Tests:**
- Test single field update across multiple configs
- Test dry-run preview
- Test validation failure triggers rollback
- Test atomic transaction (partial failure scenarios)
- Test filter system with various criteria
- Test file-based updates

**Performance Tests:**
- Benchmark 50 config updates (target <5s)
- Test with various field types
- Test with validation overhead

**Edge Cases:**
- Empty filter results (no configs match)
- Invalid field paths
- Corrupted config files
- Validation failure mid-transaction

### Learnings from Previous Stories

**From Story 1-4-automatic-backup-system (Status: done)**
- Backup pattern: call `backup_config_file()` before any modification
- Backup should happen before validation
- Graceful error handling: log warnings but continue if backup fails (non-critical)
- Backup directory: `~/.moonfrp/backups/`

**From Story 1-3-config-validation-framework (Status: done)**
- Validation pattern: validate before save
- Use `validate_config_file()` for main validation
- Validation should happen on temp files before commit
- Error aggregation: collect all errors before reporting

**From Story 1-2-implement-config-index (Status: done)**
- Index update pattern: call `index_config_file()` after successful save
- Index update should happen in commit phase, not prepare phase
- Fast queries via index for filter operations

**From Story 2-1-parallel-service-management (Status: drafted)**
- Parallel execution patterns (if applicable for bulk operations)
- Error collection and reporting patterns
- Continue-on-error vs atomic transaction (this story uses atomic, Story 2.1 uses continue-on-error)

**Relevant Patterns:**
- Atomic transaction pattern: temp files → validate → commit/rollback
- Backup before modification (Story 1.4 pattern)
- Validate before save (Story 1.3 pattern)
- Index after save (Story 1.2 pattern)

[Source: docs/stories/1-4-automatic-backup-system.md#Dev-Agent-Record]
[Source: docs/stories/1-3-config-validation-framework.md#Dev-Agent-Record]
[Source: docs/stories/1-2-implement-config-index.md#Dev-Agent-Record]

### Integration Notes

**Save Flow with Multiple Stories:**
When Stories 1.2, 1.3, 1.4, and 2.2 are all implemented:
1. Backup existing configs (Story 1.4)
2. Update to temp files (Story 2.2)
3. Validate temp files (Story 1.3)
4. If valid: move temp to final, update index (Story 1.2)
5. If invalid: delete temp files, abort transaction

**With Story 2.3 (Tagging):**
- `get_configs_by_filter()` will use `query_configs_by_tag()` from Story 2.3
- Tag-based filtering: `--filter=tag:env:prod`
- Story 2.2 should work without Story 2.3 but will be enhanced by it

### References

- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.2-Bulk-Configuration-Operations]
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.2-Bulk-Configuration-Operations#Technical-Specification]
- [Source: moonfrp-config.sh] - Existing config management functions
- [Source: docs/stories/1-3-config-validation-framework.md] - Validation framework
- [Source: docs/stories/1-4-automatic-backup-system.md] - Backup system

## Dev Agent Record

### Context Reference

- docs/stories/2-2-bulk-configuration-operations.context.xml

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

**Implementation Complete (2025-11-02):**
- ✅ Implemented all core bulk configuration functions in `moonfrp-config.sh`:
  - `get_configs_by_filter()` - Filter configs by type, tag, or name pattern
  - `update_toml_field()` - Update TOML fields while preserving formatting
  - `bulk_update_config_field()` - Atomic bulk update with two-phase commit
  - `bulk_update_from_file()` - JSON/YAML file-based bulk updates
- ✅ Integrated with existing systems:
  - Story 1.2 (Index): Updates index after successful commits
  - Story 1.3 (Validation): Validates temp files before commit
  - Story 1.4 (Backup): Creates backups before each update
  - Story 2.3 (Tagging): Supports tag-based filtering (when available)
- ✅ CLI integration in `moonfrp.sh`:
  - Added `config bulk-update` command with `--field`, `--value`, `--filter`, `--dry-run`, `--file` options
  - Supports both direct field updates and file-based updates
- ✅ Comprehensive test suite created:
  - Tests cover all acceptance criteria: dry-run, apply, validation failure, atomic transaction, backup, filtering, performance
  - Test file: `tests/test_bulk_config_operations.sh`
- ✅ Performance optimized:
  - Uses index system for fast config queries when available
  - Two-phase commit pattern minimizes I/O operations
  - Temp files used for atomic transactions

**Technical Approach:**
- Two-phase commit pattern: Phase 1 (Prepare) validates all temp files, Phase 2 (Commit) applies all or rolls back
- Filter system integrates with Story 1.2 index for fast queries, falls back to file system search
- TOML field update preserves formatting and comments using sed-based parsing
- Atomic transaction ensures all-or-nothing behavior as per AC 5

### File List

**Modified:**
- `moonfrp-config.sh` - Added bulk configuration operations functions (lines 1251-1762)
- `moonfrp.sh` - Added CLI integration for `config bulk-update` command (lines 222-292)

**Created:**
- `tests/test_bulk_config_operations.sh` - Comprehensive test suite for bulk operations

