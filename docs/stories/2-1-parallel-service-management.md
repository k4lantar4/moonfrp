# Story 2.1: Parallel Service Management

Status: ready-for-dev

## Story

As a DevOps engineer managing 50+ tunnels,
I want to perform bulk start/stop/restart operations on services in parallel,
so that I can manage all services in <10 seconds instead of minutes of serial operations.

## Acceptance Criteria

1. Parallel execution of systemctl operations across all services
2. Complete 50 service restarts in <10 seconds
3. Progress indicator during bulk operations
4. Continue-on-error: report failures, don't abort
5. Final summary: X succeeded, Y failed with reasons
6. Configurable parallelism: default max 10 concurrent operations

## Tasks / Subtasks

- [ ] Implement parallel service operation framework (AC: 1, 2, 6)
  - [ ] Create bulk_service_operation() function in moonfrp-services.sh
  - [ ] Implement parallel execution with configurable max_parallel (default 10)
  - [ ] Use background processes with PID tracking
  - [ ] Implement job queue management (wait when max_parallel reached)
  - [ ] Monitor process completion and track success/failure counts
  - [ ] Return appropriate exit code based on failure count
- [ ] Implement progress indicator (AC: 3)
  - [ ] Display real-time progress: "Progress: X/Y services..."
  - [ ] Update progress during operation execution
  - [ ] Clear progress line after completion
- [ ] Implement continue-on-error handling (AC: 4, 5)
  - [ ] Continue processing remaining services on individual failures
  - [ ] Track failed services with reasons
  - [ ] Collect error logs from failed operations
  - [ ] Generate final summary report
  - [ ] Display failed services list with error messages
- [ ] Create user-facing bulk operation functions (AC: 1, 2)
  - [ ] Create bulk_start_services() function
  - [ ] Create bulk_stop_services() function
  - [ ] Create bulk_restart_services() function
  - [ ] Create bulk_reload_services() function
  - [ ] Use get_moonfrp_services() to discover all services
- [ ] Implement filtered bulk operations (AC: 1, 2)
  - [ ] Create bulk_operation_filtered() function
  - [ ] Support filter types: tag, status, name
  - [ ] Integrate with Story 2.3 tagging system (when available)
  - [ ] Provide clear error messages for invalid filters
- [ ] CLI integration (AC: 1, 2)
  - [ ] Add `moonfrp service bulk --operation=restart` command
  - [ ] Add `--filter=tag:prod` option support
  - [ ] Add `--dry-run` option to preview operations
  - [ ] Add `--max-parallel=N` option for custom parallelism
- [ ] Performance testing (AC: 2)
  - [ ] Create test_bulk_restart_50_services_under_10s() test
  - [ ] Create test_bulk_start_parallel_execution() test
  - [ ] Create test_max_parallelism_respected() test
  - [ ] Benchmark with various service counts (10, 25, 50, 100)
- [ ] Functional testing (AC: 3, 4, 5)
  - [ ] Create test_bulk_operation_continue_on_error() test
  - [ ] Create test_bulk_operation_failure_reporting() test
  - [ ] Create test_bulk_operation_progress_indicator() test
  - [ ] Create test_bulk_operation_empty_service_list() test
- [ ] Load testing (AC: 2)
  - [ ] Test with 50 services: measure restart time
  - [ ] Test with 10 failed services: verify error handling
  - [ ] Test concurrent bulk operations: verify no race conditions

## Dev Notes

### Requirements Context

**Source Documents:**
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.1-Parallel-Service-Management]
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.1-Parallel-Service-Management#Technical-Specification]

**Problem Statement:**
Managing 50 services one-at-a-time is unusable. DevOps engineers need parallel start/stop/restart operations that complete in seconds, not minutes. Current implementation in `moonfrp-services.sh` uses serial operations (`start_service()`, `stop_service()`, `restart_service()`) which execute one service at a time.

**Current Implementation:**
Service operations are serial in `moonfrp-services.sh`:
- `start_service()` - starts single service
- `stop_service()` - stops single service  
- `restart_service()` - restarts single service
- `get_service_status()` - checks single service status

Menu options like "Start All Services" iterate through services sequentially, taking several minutes for 50 services.

**Required Implementation:**
Create a parallel execution framework that:
- Executes systemctl operations concurrently across multiple services
- Completes 50 service restarts in <10 seconds
- Shows progress during bulk operations
- Continues on individual failures and reports them
- Provides configurable parallelism limits
- Integrates with existing service discovery functions

### Technical Constraints

**File Location:** `moonfrp-services.sh` - New bulk operation functions

**Implementation Pattern:**
```bash
bulk_service_operation() {
    local operation="$1"  # start|stop|restart|reload
    shift
    local services=("$@")
    
    local max_parallel=10
    local success_count=0
    local fail_count=0
    local total=${#services[@]}
    
    declare -a failed_services
    declare -a pids
    
    # Parallel execution logic with PID tracking
    # Progress indicator
    # Error collection and reporting
}
```

**Dependencies:**
- Existing `log()` function from `moonfrp-core.sh` for logging
- Existing service functions: `start_service()`, `stop_service()`, `restart_service()`
- `get_moonfrp_services()` function for service discovery (to be created or existing)
- Story 2.3 tagging system for filtered operations (optional dependency)

**Integration Points:**
- Use existing `start_service()`, `stop_service()`, `restart_service()` functions as operation handlers
- Integrate with Story 2.3: `get_services_by_tag()` for filtered operations
- Update service management menu to use bulk operations
- CLI integration in `moonfrp.sh` main command handler

**Performance Requirements:**
- 50 service restarts: <10 seconds (vs several minutes serial)
- Configurable parallelism: default 10 concurrent, max configurable
- Progress updates without blocking execution

### Project Structure Notes

- **Module:** `moonfrp-services.sh` - Service management functions
- **New Functions:**
  - `bulk_service_operation()` - Core parallel execution framework
  - `bulk_start_services()` - Bulk start all services
  - `bulk_stop_services()` - Bulk stop all services
  - `bulk_restart_services()` - Bulk restart all services
  - `bulk_reload_services()` - Bulk reload all services
  - `get_moonfrp_services()` - Discover all MoonFRP services
  - `bulk_operation_filtered()` - Filtered bulk operations (for Story 2.3)
- **CLI Integration:** Update `moonfrp.sh` to add `service bulk` command
- **Menu Integration:** Update service management menu to use bulk operations

### Parallel Execution Design

**Core Algorithm:**
1. Initialize arrays: pids[], failed_services[]
2. For each service:
   - If pids count >= max_parallel: wait for completion
   - Start operation in background, store PID
   - Update progress indicator
3. Wait for all remaining jobs
4. Collect results and generate summary

**Error Handling:**
- Individual service failures don't abort batch
- Failed services tracked in failed_services[] array
- Error logs saved to temp directory
- Final summary shows success/failure counts with reasons

**Progress Indicator:**
- Real-time updates: `\rProgress: X/Y services...`
- Non-blocking display updates
- Clean newline after completion

### Testing Strategy

**Performance Tests:**
- Generate 50 test services
- Measure bulk restart time (target <10 seconds)
- Verify parallelism respected (check max concurrent processes)
- Benchmark with various service counts

**Functional Tests:**
- Test continue-on-error: mix of working and failing services
- Test failure reporting: verify error messages captured
- Test progress indicator: verify updates displayed
- Test empty service list: verify graceful handling
- Test filtered operations (when Story 2.3 available)

**Load Tests:**
- 50 services: restart time measurement
- 10 failed services: error handling verification
- Concurrent bulk operations: race condition testing

### Learnings from Previous Stories

**From Story 1-4-automatic-backup-system (Status: done)**
- Backup system uses simple sequential operations
- Pattern: Create helper functions for core operations, then compose them
- Error handling pattern: graceful degradation, log warnings but continue
- Performance consideration: operations should be fast (<50ms target for backups)

**From Story 1-2-implement-config-index (Status: done)**
- New module pattern for complex functionality (`moonfrp-index.sh`)
- Integration pattern: source module in main script, update existing functions to use new capabilities
- Performance optimization: database queries vs file parsing

**From Story 1-3-config-validation-framework (Status: done)**
- Function composition pattern: core validation functions, then main `validate_config_file()` that composes them
- Error aggregation: collect all errors before reporting
- Integration: update save functions to call validation

**Relevant Patterns:**
- Use existing service functions (`start_service()`, etc.) - don't recreate them
- Follow error handling patterns from backup system (graceful degradation)
- Consider performance requirements early (50 services in <10 seconds)

[Source: docs/stories/1-4-automatic-backup-system.md#Dev-Agent-Record]
[Source: docs/stories/1-2-implement-config-index.md#Dev-Agent-Record]
[Source: docs/stories/1-3-config-validation-framework.md#Dev-Agent-Record]

### Integration Notes

**With Story 2.3 (Service Grouping & Tagging):**
- `bulk_operation_filtered()` will use `get_services_by_tag()` from Story 2.3
- Filter support: `--filter=tag:prod` will query tagged services
- Story 2.1 should work independently but will be enhanced by Story 2.3

**Service Discovery:**
- `get_moonfrp_services()` should query systemctl for all moonfrp-(server|client) services
- Pattern: `systemctl list-units --type=service --all | grep moonfrp-`

### References

- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.1-Parallel-Service-Management]
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.1-Parallel-Service-Management#Technical-Specification]
- [Source: moonfrp-services.sh#64-111] - Existing serial service functions
- [Source: moonfrp-services.sh#477-509] - Service management menu

## Dev Agent Record

### Context Reference

- docs/stories/2-1-parallel-service-management.context.xml

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

