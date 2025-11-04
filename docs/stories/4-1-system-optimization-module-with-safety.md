# Story 4.1: System Optimization Module with Safety

Status: approved

## Story

As a DevOps engineer operating high-throughput MoonFRP tunnels,
I want safe, preset-based system network tuning with dry-run and automatic rollback,
so that I can maximize performance for 50+ tunnels without risking system stability.

## Acceptance Criteria

1. Three presets: conservative (safe), balanced (recommended), aggressive (max performance)
2. Dry-run shows all sysctl/ulimit changes before applying
3. Automatic backup of original settings
4. Validation of changes after applying
5. One-command rollback to original settings
6. OS detection with warnings for non-Ubuntu systems
7. Optimization completes in <10s

## Tasks / Subtasks

- [ ] Implement optimization entrypoint (AC: 1, 2, 7)
  - [ ] Add `optimize_system(preset, dry_run)` in `moonfrp-optimize.sh`
  - [ ] Clear screen and show header with preset info
  - [ ] Support `dry_run=true` to preview without changes
  - [ ] Confirm before applying when not dry-run
- [ ] Implement OS compatibility checks (AC: 6)
  - [ ] `validate_os_compatibility()` using `lsb_release` if available
  - [ ] Warn for non-Ubuntu or Ubuntu <20.04 and require explicit confirm
- [ ] Define presets with safe defaults (AC: 1)
  - [ ] `PRESET_CONSERVATIVE`, `PRESET_BALANCED`, `PRESET_AGGRESSIVE` assoc arrays
  - [ ] Include fs.file-max, rmem_max/wmem_max, tcp_rmem/tcp_wmem, backlog, syn backlog
  - [ ] Aggressive includes `tcp_fastopen`, `somaxconn`, `default_qdisc`
- [ ] Implement dry-run preview (AC: 2)
  - [ ] `preview_optimizations(preset)` shows current → new values for each sysctl key
  - [ ] Show planned ulimit changes (open files, processes)
- [ ] Implement backup/rollback (AC: 3, 5)
  - [ ] `backup_system_settings()` saves `/etc/sysctl.conf`, `/etc/profile`, and `sysctl -a` snapshot under `$HOME/.moonfrp/backups/system`
  - [ ] Track latest backup timestamp in `.latest`
  - [ ] `rollback_system_settings()` restores files and reapplies `sysctl -p`
- [ ] Apply sysctl changes (AC: 2, 4)
  - [ ] `apply_sysctl_optimizations(preset)` writes a titled block to `/etc/sysctl.conf`
  - [ ] Remove previous MoonFRP block before appending
  - [ ] Apply immediately via `sysctl -p` with error handling
- [ ] Apply ulimit changes (AC: 2, 4)
  - [ ] `apply_ulimit_optimizations(preset)` appends limits block to `/etc/profile`
  - [ ] Set `ulimit -n 1048576` and `ulimit -u 65536` defaults
- [ ] Validate applied settings (AC: 4)
  - [ ] `validate_optimizations(preset)` compares actual sysctl values to expected
  - [ ] On mismatch: log WARN and fail validation
  - [ ] On failure: trigger automatic rollback and report
- [ ] Interactive menu (optional helper) (AC: 1, 2, 5)
  - [ ] `optimization_menu()` allowing preset selection, dry-run preview, and rollback
- [ ] Performance target (AC: 7)
  - [ ] Ensure end-to-end optimization path completes in <10s on Ubuntu 20.04+

### Testing Subtasks

- [ ] Add test_optimize_conservative_preset() (AC: 1)
- [ ] Add test_optimize_balanced_preset() (AC: 1)
- [ ] Add test_optimize_aggressive_preset() (AC: 1)
- [ ] Add test_optimize_dry_run() (AC: 2)
- [ ] Add test_optimize_backup_created() (AC: 3)
- [ ] Add test_optimize_rollback() (AC: 5)
- [ ] Add test_optimize_validation_failure() (AC: 4)
- [ ] Add test_os_compatibility_check() (AC: 6)
- [ ] Add test_optimization_path_under_10s() (AC: 7)

## Dev Notes

### Architecture patterns and constraints

- Apply sysctl and ulimit changes via idempotent titled blocks; remove prior MoonFRP block before append to avoid duplication.
- Always validate applied values against expected; on any mismatch, trigger rollback to last backup.
- Maintain safe defaults for `conservative` and `balanced`; isolate riskier toggles (e.g., `tcp_fastopen`, `default_qdisc`) to `aggressive` only.

### References

- [Source: docs/epics/epic-04-system-optimization.md#Story-4.1-System-Optimization-Module-with-Safety]
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.1-System-Optimization-Module-with-Safety#Technical-Specification]
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.1-System-Optimization-Module-with-Safety#Testing-Requirements]

### Learnings from Previous Story

First story in Epic 4 → no prior story continuity required.

## Technical Notes

Location: new file `moonfrp-optimize.sh` (sources `moonfrp-core.sh`).

Key constants:
- `SYSCTL_PATH=/etc/sysctl.conf`
- `PROFILE_PATH=/etc/profile`
- `BACKUP_DIR=$HOME/.moonfrp/backups/system`

Functions to implement/export:
- `optimize_system`
- `validate_os_compatibility`
- `display_preset_info`
- `preview_optimizations`
- `apply_sysctl_optimizations`
- `apply_ulimit_optimizations`
- `backup_system_settings`
- `rollback_system_settings`
- `validate_optimizations`
- `optimization_menu` (optional)

## Testing Requirements

```bash
test_optimize_conservative_preset()
test_optimize_balanced_preset()
test_optimize_aggressive_preset()
test_optimize_dry_run()
test_optimize_rollback()
test_optimize_validation_failure()
test_optimize_backup_created()
test_os_compatibility_check()
```

## Requirements Context

Source Documents:
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.1-System-Optimization-Module-with-Safety]
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.1-System-Optimization-Module-with-Safety#Technical-Specification]
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.1-System-Optimization-Module-with-Safety#Testing-Requirements]

Problem Statement:
50 concurrent tunnels can saturate default Linux network settings. DevOps engineers need system tuning but current aggressive approach risks stability. Need preset-based optimization with safety checks.

Implementation Overview:
- Implement `moonfrp-optimize.sh` with preset-based sysctl/ulimit tuning, dry-run, backup, validation, and rollback. Integrate OS validation and optional interactive menu.

### Project Structure Notes

- Module: `moonfrp-optimize.sh` – System optimization module
- Integration: Source from UI main flows when optimization is triggered (future story), standalone safe CLI entrypoint for now
- Backup location: `$HOME/.moonfrp/backups/system`

## Change Log

- 2025-11-03: Draft created from Epic 4 technical specification.



## Dev Agent Record

### Context Reference

- docs/stories/4-1-system-optimization-module-with-safety.context.xml

### Code Review Notes (2025-11-03)

- Implementation meets ACs: presets, dry-run, backup, validation, rollback, OS check, and CLI.
- Suggestion: also write limits to `/etc/security/limits.d/moonfrp.conf` for non-interactive sessions; `/etc/profile` only affects login shells.
- Suggestion: guard `net.core.default_qdisc=fq` on kernels lacking `fq`; warn instead of failing.
- Suggestion: add `--force` flag to skip interactive confirm for automation.
- Validation compares exact strings; acceptable, but consider normalizing whitespace for robustness.
