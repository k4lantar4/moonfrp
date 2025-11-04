# Story 5.1: Configuration as Code (Export/Import)

Status: ready-for-dev

## Story

As a DevOps engineer,
I want to export and import MoonFRP configuration as YAML,
so that configurations are version-controlled and consistently deployed across environments.

## Acceptance Criteria

1. Export all configs to a single YAML file
2. Import YAML recreates exact configuration
3. Idempotent: running import twice produces same result
4. Supports partial imports (specific configs only)
5. Validates YAML before import
6. Git-friendly format (readable diffs)
7. Export/import completes in <2s for 50 configs

## Tasks / Subtasks

- [ ] Implement `moonfrp-iac.sh` module with export/import functions (AC: 1,2,3,4,5,7)
  - [ ] Implement `export_config_yaml` (AC: 1,6,7)
  - [ ] Implement `export_server_yaml` and `export_client_yaml` (AC: 1,6)
  - [ ] Implement `import_config_yaml` with backup and index rebuild (AC: 2,3,5)
  - [ ] Implement `validate_yaml_file` using `yq` with fallback (AC: 5)
  - [ ] Implement partial import path (server/clients selection) (AC: 4)
- [ ] Integrate CLI commands: `moonfrp export`, `moonfrp import` (AC: 1,2,3,4,5,7)
  - [ ] Wire `moonfrp_export` and `moonfrp_import` in main CLI (AC: 1,2)
  - [ ] Add `--dry-run` preview for import (AC: 3)
- [ ] Tests (AC: 1–7)
  - [ ] `test_export_all_configs_to_yaml`
  - [ ] `test_import_yaml_creates_configs`
  - [ ] `test_import_idempotent`
  - [ ] `test_import_validation`
  - [ ] `test_export_import_roundtrip`
  - [ ] `test_partial_import`
  - [ ] `test_yaml_git_friendly_format`

## Dev Notes

- Use `moonfrp-core.sh` helpers for logging and config paths
- Preserve tags and metadata; ensure readable diffs (sorted keys, stable ordering)
- Back up configs prior to import; on failure, auto-rollback

### Project Structure Notes

- Place new module at project root: `moonfrp-iac.sh`
- Expose functions for CLI integration in `moonfrp.sh`

### References

- [Source: docs/epics/epic-05-devops-integration.md#Story-5.1]

## Dev Agent Record

### Context Reference

- docs/stories/5-1-configuration-as-code-export-import.context.xml

### Agent Model Used


### Debug Log References


### Completion Notes List


### File List


