# Story 5.3: Structured Logging

Status: ready-for-dev

## Story

As a DevOps observability engineer,
I want JSON-structured logs with context fields,
so that logs integrate cleanly with ELK/Splunk/Loki and are machine-parsable.

## Acceptance Criteria

1. `--log-format=json` outputs structured JSON logs
2. Each log entry includes: timestamp, level, message, context
3. Compatible with common log parsers
4. Performance: <1ms overhead per log entry
5. Optional fields: service, operation, duration
6. Errors include stack traces when available

## Tasks / Subtasks

- [ ] Add `MOONFRP_LOG_FORMAT` config with default `text` (AC: 1)
- [ ] Implement `log_json` and route via `log` (AC: 1,2)
  - [ ] Include fields: timestamp, level, message, application, version (AC: 2,3)
  - [ ] Support optional fields via parameters/env (AC: 5)
- [ ] Ensure performance threshold (<1ms/entry) (AC: 4)
  - [ ] Micro-bench and optimize string building
- [ ] Ensure error logs include stack/trace context when available (AC: 6)
- [ ] Tests (AC: 1–6)
  - [ ] `test_json_logging_format`
  - [ ] `test_json_logging_valid`
  - [ ] `test_json_logging_performance`
  - [ ] `test_text_logging_default`

## Dev Notes

- Keep default `text` logging unchanged; JSON is opt-in
- Avoid external deps; pure shell-compatible implementation

### Project Structure Notes

- Modify `moonfrp-core.sh` logging functions only; avoid breaking callers

### References

- [Source: docs/epics/epic-05-devops-integration.md#Story-5.3]

## Dev Agent Record

### Context Reference

- docs/stories/5-3-structured-logging.context.xml

### Agent Model Used


### Debug Log References


### Completion Notes List


### File List


