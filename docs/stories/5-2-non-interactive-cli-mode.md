# Story 5.2: Non-Interactive CLI Mode

Status: ready-for-dev

## Story

As a CI/CD pipeline engineer,
I want MoonFRP operations to run non-interactively with clear exit codes,
so that automation scripts can execute reliably without prompts.

## Acceptance Criteria

1. `--yes` / `-y` flag bypasses all confirmations
2. `--quiet` / `-q` flag suppresses non-essential output
3. Exit code 0 for success, non-zero for failure
4. Specific exit codes for failures (1=general, 2=validation, 3=permission, 4=not-found, 5=timeout)
5. Operations timeout after reasonable duration
6. All menu-driven functions accessible via CLI arguments
7. Help text for all commands: `moonfrp <command> --help`

## Tasks / Subtasks

- [ ] Implement global flags in `moonfrp.sh` (AC: 1,2,5)
  - [ ] Parse `-y/--yes`, `-q/--quiet`, `--timeout` (AC: 1,2,5)
  - [ ] Override `safe_read` for non-interactive mode (AC: 1)
  - [ ] Override `log` for quiet mode (AC: 2)
- [ ] Implement exit code constants and usage (AC: 3,4)
  - [ ] Map errors to specific exit codes (AC: 4)
- [ ] Expose commands via CLI dispatcher (AC: 6)
  - [ ] `start|stop|restart|status` (AC: 6)
  - [ ] `export|import|validate` (AC: 6)
  - [ ] `bulk`, `search`, `tag`, `optimize` (AC: 6)
- [ ] Implement timeout handling with trap (AC: 5)
- [ ] Update help text (AC: 7)
- [ ] Tests (AC: 1–7)
  - [ ] `test_noninteractive_yes_flag`
  - [ ] `test_noninteractive_quiet_flag`
  - [ ] `test_exit_codes`
  - [ ] `test_timeout_handling`
  - [ ] `test_help_text`
  - [ ] `test_all_commands_cli_accessible`

## Dev Notes

- Ensure non-interactive mode rejects interactive menu usage with an error
- Keep logging performance acceptable in both modes

### Project Structure Notes

- All changes confined to `moonfrp.sh` (CLI) and `moonfrp-core.sh` helpers

### References

- [Source: docs/epics/epic-05-devops-integration.md#Story-5.2]

## Dev Agent Record

### Context Reference

- docs/stories/5-2-non-interactive-cli-mode.context.xml

### Agent Model Used


### Debug Log References


### Completion Notes List


### File List


