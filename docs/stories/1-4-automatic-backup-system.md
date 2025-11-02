# Story 1.4: Automatic Backup System

Status: ready-for-dev

## Story

As a DevOps engineer,
I want automatic backups created before any config modification,
so that I can easily rollback to previous configurations if something goes wrong.

## Acceptance Criteria

1. Automatic backup before ANY config modification
2. Timestamped backups: `config-name.YYYYMMDD-HHMMSS.bak`
3. Keeps last 10 backups per file
4. Easy restore: `moonfrp restore <config> --backup=<timestamp>`
5. Backup operation <50ms
6. Backup directory: `~/.moonfrp/backups/`

## Tasks / Subtasks

- [ ] Implement backup core functions (AC: 1, 2, 5, 6)
  - [ ] Define BACKUP_DIR constant: `$HOME/.moonfrp/backups`
  - [ ] Define MAX_BACKUPS_PER_FILE constant: 10
  - [ ] Create backup_config_file() function
  - [ ] Generate timestamp in format YYYYMMDD-HHMMSS
  - [ ] Create backup filename: `config-name.YYYYMMDD-HHMMSS.bak`
  - [ ] Copy config file to backup location
  - [ ] Ensure backup directory exists
  - [ ] Log backup creation
- [ ] Implement backup cleanup (AC: 3)
  - [ ] Create cleanup_old_backups() function
  - [ ] Find all backups for a specific config file
  - [ ] Sort backups by modification time (newest first)
  - [ ] Keep only last 10 backups per file
  - [ ] Remove older backups beyond limit
  - [ ] Log removed backups
- [ ] Implement backup listing (AC: 4)
  - [ ] Create list_backups() function
  - [ ] Support listing backups for specific config or all backups
  - [ ] Sort by modification time (newest first)
  - [ ] Return backup file paths
- [ ] Implement restore functionality (AC: 4)
  - [ ] Create restore_config_from_backup() function
  - [ ] Validate backup file exists
  - [ ] Backup current config before restore (nested backup)
  - [ ] Copy backup file to config location
  - [ ] Revalidate restored config (using Story 1.3 validation)
  - [ ] Update index if available (from Story 1.2)
  - [ ] Log restore operation
- [ ] Implement interactive restore menu (AC: 4)
  - [ ] Create restore_config_interactive() function
  - [ ] List available backups with formatted dates
  - [ ] Allow user to select backup by number
  - [ ] Confirm restore operation
  - [ ] Call restore_config_from_backup() on confirmation
- [ ] Integrate backup into save flow (AC: 1)
  - [ ] Update save_config_file() or equivalent save function
  - [ ] Call backup_config_file() before any config modification
  - [ ] Ensure backup happens before file write
  - [ ] Handle backup failures gracefully (log warning, continue if backup fails)
- [ ] Performance and testing (AC: 5)
  - [ ] Benchmark backup operation (target <50ms)
  - [ ] Test backup cleanup keeps exactly 10 backups
  - [ ] Test restore from backup
  - [ ] Test restore validates config
  - [ ] Test nested backup (backup before restore)
  - [ ] Test backup listing and sorting
- [ ] Unit tests (AC: 1, 2, 3, 4, 5, 6)
  - [ ] test_backup_creates_timestamped_file()
  - [ ] test_backup_cleanup_keeps_last_10()
  - [ ] test_restore_from_backup()
  - [ ] test_restore_validates_config()
  - [ ] test_backup_performance_under_50ms()
  - [ ] test_list_backups_sorted()

## Dev Notes

### Requirements Context

**Source Documents:**
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.4-Automatic-Backup-System]
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.4-Automatic-Backup-System#Technical-Specification]

**Problem Statement:**
Config changes risk data loss and service disruption. Currently, there's no backup mechanism, so if a config modification causes issues, users must manually restore from their own backups or risk losing configuration data. This creates risk and poor user experience.

**Current Implementation:**
Config files are modified directly without backup in `moonfrp-config.sh`. There's no built-in rollback capability.

**Required Implementation:**
Create an automatic backup system that:
- Creates timestamped backups before any config modification
- Manages backup retention (keep last 10 per file)
- Provides easy restore functionality
- Completes quickly (<50ms) to maintain good UX
- Integrates seamlessly with save operations

### Technical Constraints

**File Location:** `moonfrp-core.sh` or `moonfrp-config.sh` - Backup functions

**Backup Directory:** `$HOME/.moonfrp/backups/`

**Backup Naming:** `{config-name}.YYYYMMDD-HHMMSS.bak`
- Example: `frpc.toml.20251102-143025.bak`

**Dependencies:**
- `log()` function from `moonfrp-core.sh` for logging
- `safe_read()` function from `moonfrp-core.sh` for interactive prompts
- Story 1.3 validation: `validate_config_file()` (when available)
- Story 1.2 index: `index_config_file()` (when available)

**Integration Points:**
- Update save/config modification functions to call `backup_config_file()` first
- Integrate with Story 1.3 (Config Validation) - backup happens before validation
- Integrate with Story 1.2 (Config Index) - update index after restore

**Performance Requirements:**
- Backup operation must complete in <50ms
- Cleanup operation should be efficient (avoid scanning all backups unnecessarily)

### Project Structure Notes

- **Module:** `moonfrp-core.sh` or `moonfrp-config.sh` - Backup functions
- **New Functions:**
  - `backup_config_file()` - Create timestamped backup
  - `cleanup_old_backups()` - Remove old backups beyond limit
  - `list_backups()` - List available backups
  - `restore_config_from_backup()` - Restore from backup file
  - `restore_config_interactive()` - Interactive restore menu
- **Backup Directory:** `~/.moonfrp/backups/` - Created automatically
- **Dependencies on Previous Stories:**
  - Story 1.3: Use `validate_config_file()` after restore (optional, will work without it)
  - Story 1.2: Use `index_config_file()` after restore (optional, will work without it)

### Backup Workflow

**Before Config Save:**
1. Check if config file exists
2. Call `backup_config_file()` to create backup
3. Perform cleanup of old backups (keep last 10)
4. Proceed with config save (validation, write, etc.)

**Restore Workflow:**
1. List available backups for config file
2. User selects backup (interactive or command-line)
3. Backup current config (if exists) before restore
4. Copy backup file to config location
5. Validate restored config (if Story 1.3 available)
6. Update index (if Story 1.2 available)
7. Log restore operation

### Testing Strategy

**Unit Test Location:** Create tests in test suite (to be defined)

**Functional Testing:**
- Test backup creates timestamped file with correct format
- Test cleanup keeps exactly 10 most recent backups
- Test restore from backup works correctly
- Test restore validates config (if validation available)
- Test nested backup (backup before restore)
- Test backup listing and sorting

**Performance Testing:**
- Benchmark backup operation (target <50ms)
- Test with various config file sizes
- Test cleanup performance with many backups

**Edge Cases:**
- Backup when config file doesn't exist (should fail gracefully)
- Restore when backup doesn't exist
- Cleanup when fewer than 10 backups exist
- Backup directory doesn't exist (should create it)
- Backup directory not writable (should handle gracefully)

### Learnings from Previous Stories

**From Story 1-1-fix-frp-version-detection (Status: drafted)**
- Simple function replacement pattern
- No new files needed

**From Story 1-2-implement-config-index (Status: drafted)**
- New module pattern for complex functionality
- Integration with other stories (validate before indexing)
- Story 1.4 should update index after restore if Story 1.2 is implemented

**From Story 1-3-config-validation-framework (Status: drafted)**
- Validation before save pattern established
- Story 1.4 should backup before validation
- Story 1.4 should revalidate after restore if Story 1.3 is implemented

[Source: docs/stories/1-1-fix-frp-version-detection.md#Dev-Agent-Record]
[Source: docs/stories/1-2-implement-config-index.md#Dev-Agent-Record]
[Source: docs/stories/1-3-config-validation-framework.md#Dev-Agent-Record]

### Integration Notes

**Save Flow Integration:**
When Story 1.3 and Story 1.4 are both implemented, the save flow should be:
1. Write config to temporary file
2. Validate temporary file (Story 1.3)
3. Backup existing config (Story 1.4)
4. Move temporary file to final location
5. Update index (Story 1.2, if available)

**Restore Flow Integration:**
When Stories 1.2, 1.3, and 1.4 are all implemented:
1. Backup current config (Story 1.4)
2. Restore from backup (Story 1.4)
3. Validate restored config (Story 1.3)
4. Update index (Story 1.2)

### References

- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.4-Automatic-Backup-System]
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.4-Automatic-Backup-System#Technical-Specification]
- [Source: moonfrp-core.sh] - log(), safe_read() functions
- [Source: moonfrp-config.sh] - save functions to integrate with

## Dev Agent Record

### Context Reference

- docs/stories/1-4-automatic-backup-system.context.xml

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

## Change Log

- 2025-11-02: Story created from Epic 1.4 requirements

