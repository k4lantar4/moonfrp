# Story 1.2: Implement Config Index

Status: ready-for-dev

## Story

As a DevOps engineer managing 50+ tunnels,
I want config file metadata indexed in a fast queryable database,
so that menu loading and config queries complete in <50ms instead of 2-3 seconds.

## Acceptance Criteria

1. SQLite database indexes all config files
2. Query time for 50 configs: <50ms (vs 2000ms current)
3. Automatic rebuild on config file changes
4. Index includes: file path, server IP, port, proxy count, status, tags
5. Graceful fallback to file parsing if index corrupted
6. Index size: <1MB for 50 configs

## Tasks / Subtasks

- [ ] Create new module file `moonfrp-index.sh` (AC: 1, 2, 3, 4, 5)
  - [ ] Define SQLite database schema with config_index and index_meta tables
  - [ ] Create init_config_index() function to initialize database
  - [ ] Create index_config_file() function to index single config
  - [ ] Create rebuild_config_index() function to rebuild entire index
  - [ ] Create check_and_update_index() function for automatic updates
  - [ ] Implement query functions: query_configs_by_type(), query_total_proxy_count()
  - [ ] Add error handling and fallback to file parsing on corruption
- [ ] Integrate index into existing codebase (AC: 3)
  - [ ] Source moonfrp-index.sh in moonfrp.sh
  - [ ] Call check_and_update_index() before config queries
  - [ ] Update menu loading to use indexed queries instead of file parsing
  - [ ] Ensure backward compatibility if index unavailable
- [ ] Database schema implementation (AC: 1, 4)
  - [ ] Create config_index table with required fields (file_path, file_hash, config_type, server_addr, server_port, bind_port, auth_token_hash, proxy_count, tags, last_modified, last_indexed)
  - [ ] Create index_meta table for metadata storage
  - [ ] Add indexes on config_type, server_addr, and tags
  - [ ] Implement UNIQUE constraint on file_path
- [ ] Performance optimization and testing (AC: 2, 6)
  - [ ] Benchmark query performance with 50 configs (target <50ms)
  - [ ] Benchmark rebuild performance (target <2s for 50 configs)
  - [ ] Verify index size stays under 1MB for 50 configs
  - [ ] Test incremental update performance (target <100ms)
- [ ] Testing and validation (AC: 1, 2, 3, 4, 5, 6)
  - [ ] Unit tests: test_index_survives_corrupted_config()
  - [ ] Unit tests: test_index_auto_rebuild_on_changes()
  - [ ] Unit tests: test_index_fallback_to_file_parsing()
  - [ ] Unit tests: test_query_by_type()
  - [ ] Unit tests: test_query_by_server_addr()
  - [ ] Unit tests: test_total_proxy_count()
  - [ ] Performance tests: test_index_query_50_configs_under_50ms()
  - [ ] Performance tests: test_index_rebuild_50_configs_under_2s()
  - [ ] Performance tests: test_index_incremental_update_under_100ms()
  - [ ] Load tests: Generate 100 configs and measure performance

## Dev Notes

### Requirements Context

**Source Documents:**
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.2-Implement-Config-Index]
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.2-Implement-Config-Index#Technical-Specification]

**Problem Statement:**
With 50+ config files, parsing TOML on every operation creates unacceptable performance (2-3s menu load). The current implementation uses `get_toml_value()` from `moonfrp-config.sh` to parse files directly, which requires reading and parsing each TOML file sequentially. This becomes a bottleneck at scale.

**Current Implementation:**
Config files are stored in `$CONFIG_DIR` (default: `/etc/frp`) and parsed using `get_toml_value()` function in `moonfrp-config.sh` (line 16-31). Each config query requires file I/O and TOML parsing.

**Required Implementation:**
Create a SQLite-based index system that:
- Pre-extracts metadata from all config files into a database
- Provides fast query functions for common operations
- Automatically updates when config files change
- Falls back gracefully if index is corrupted or unavailable

### Technical Constraints

**New File Location:** `moonfrp-index.sh` - New module file

**Database Location:** `$HOME/.moonfrp/index.db`

**Dependencies:**
- SQLite3 must be available on system (`sqlite3` command)
- Existing `get_toml_value()` function from `moonfrp-config.sh` for parsing during indexing
- `CONFIG_DIR` variable from `moonfrp-core.sh` (default: `/etc/frp`)
- `$HOME/.moonfrp/` directory must be writable

**Integration Points:**
- Source `moonfrp-index.sh` in `moonfrp.sh` (main entry point)
- Call `check_and_update_index()` before any config listing operations
- Replace file-based config queries with indexed queries in menu loading
- Maintain backward compatibility: if index unavailable, fall back to file parsing

**Performance Requirements:**
- Query 50 configs: <50ms (vs 2000ms current - 40x improvement)
- Rebuild index for 50 configs: <2s
- Incremental update: <100ms per changed file
- Database size: <1MB for 50 configs

### Project Structure Notes

- **New Module:** `moonfrp-index.sh` - Index management functions
- **Database Location:** `~/.moonfrp/index.db` - SQLite database file
- **Schema File:** Optionally `schema.sql` (if separate file preferred)
- **Integration:** Update `moonfrp.sh` to source new module
- **Dependencies on Story 1.1:** None - can be implemented independently

### Database Schema

**config_index table:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `file_path` (TEXT UNIQUE NOT NULL) - Full path to config file
- `file_hash` (TEXT NOT NULL) - SHA256 hash for change detection
- `config_type` (TEXT NOT NULL) - 'server' or 'client'
- `server_addr` (TEXT) - Server address from config
- `server_port` (INTEGER) - Server port from config
- `bind_port` (INTEGER) - Bind port (for server configs)
- `auth_token_hash` (TEXT) - Hashed auth token (for security)
- `proxy_count` (INTEGER DEFAULT 0) - Number of proxy entries
- `tags` (TEXT) - JSON array of tags
- `last_modified` (INTEGER) - Unix timestamp
- `last_indexed` (INTEGER) - Unix timestamp

**index_meta table:**
- `key` (TEXT PRIMARY KEY)
- `value` (TEXT)

**Indexes:**
- `idx_config_type` on `config_type`
- `idx_server_addr` on `server_addr`
- `idx_tags` on `tags`

### Testing Strategy

**Unit Test Location:** Create tests in test suite (to be defined)

**Performance Benchmarking:**
- Generate 50 realistic config files
- Measure query time (target <50ms)
- Measure rebuild time (target <2s)
- Measure incremental update time (target <100ms per file)
- Verify database size (<1MB)

**Functional Testing:**
- Test index survives corrupted config file
- Test automatic rebuild on config file changes
- Test fallback to file parsing when index corrupted
- Test query functions (by type, by server_addr, total proxy count)

**Load Testing:**
- Generate 100 config files
- Measure performance at scale
- Verify database size scales appropriately

### Learnings from Previous Story

**From Story 1-1-fix-frp-version-detection (Status: drafted)**

- **Pattern Established:** Story 1.1 is a simple function replacement with no new files
- **Note:** Story 1.2 is more complex, introducing a new module and database dependency
- **No technical debt or warnings from Story 1.1** - it's a clean, isolated change

[Source: docs/stories/1-1-fix-frp-version-detection.md#Dev-Agent-Record]

### References

- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.2-Implement-Config-Index]
- [Source: docs/epics/epic-01-scale-foundation.md#Story-1.2-Implement-Config-Index#Technical-Specification]
- [Source: moonfrp-config.sh#16-31] - get_toml_value() function for parsing
- [Source: moonfrp-core.sh#74] - CONFIG_DIR variable definition

## Dev Agent Record

### Context Reference

- docs/stories/1-2-implement-config-index.context.xml

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

## Change Log

- 2025-11-02: Story created from Epic 1.2 requirements

