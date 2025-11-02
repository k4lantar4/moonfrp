# Story 2.3: Service Grouping & Tagging

Status: drafted

## Story

As a DevOps engineer managing 50+ tunnels,
I want to tag services with key-value pairs for logical organization,
so that I can perform filtered operations by environment, region, customer, or service type.

## Acceptance Criteria

1. Tag services with key-value pairs: `env:prod`, `region:eu`, `customer:acme`
2. Multiple tags per service
3. Tags stored in config index (fast queries)
4. Operations by tag: `restart --tag=env:prod`
5. List/filter services by tags
6. Tag inheritance from config templates
7. Tag management: add, remove, list

## Tasks / Subtasks

- [ ] Verify service_tags table exists in index database (AC: 3)
  - [ ] Check if service_tags table exists (created in Epic 1)
  - [ ] If missing, create table with schema from Epic 1
  - [ ] Create indexes: idx_tag_key, idx_tag_value, idx_tag_key_value
  - [ ] Verify foreign key constraint to config_index table
- [ ] Implement tag management functions (AC: 1, 7)
  - [ ] Create add_config_tag() function in moonfrp-index.sh
  - [ ] Create remove_config_tag() function
  - [ ] Create list_config_tags() function
  - [ ] Verify config exists in index before tagging
  - [ ] Handle SQL injection with proper escaping
  - [ ] Return appropriate error codes
- [ ] Implement tag query functions (AC: 3, 5)
  - [ ] Create query_configs_by_tag() function in moonfrp-index.sh
  - [ ] Support exact match: "key:value"
  - [ ] Support key-only match: "key" (any value)
  - [ ] Use JOIN with config_index for fast queries
  - [ ] Return array of config file paths
- [ ] Implement service-to-tag mapping (AC: 4)
  - [ ] Create get_services_by_tag() function in moonfrp-services.sh
  - [ ] Convert config paths to service names (moonfrp-{basename})
  - [ ] Use query_configs_by_tag() for config lookup
  - [ ] Return array of service names
- [ ] Implement bulk tagging (AC: 1, 7)
  - [ ] Create bulk_tag_configs() function
  - [ ] Use get_configs_by_filter() from Story 2.2
  - [ ] Apply tag to all matching configs
  - [ ] Support filter types: all, type, tag, name
- [ ] Create interactive tag management menu (AC: 7)
  - [ ] Create tag_management_menu() function
  - [ ] Add tag to config (interactive)
  - [ ] Remove tag from config (interactive)
  - [ ] List tags for config (interactive)
  - [ ] Bulk tag configs (interactive)
  - [ ] List all tags (show all key-value pairs in use)
  - [ ] Operations by tag menu (integration with Story 2.1)
- [ ] CLI integration (AC: 1, 4, 5, 7)
  - [ ] Add `moonfrp tag add <config> <key> <value>` command
  - [ ] Add `moonfrp tag remove <config> <key>` command
  - [ ] Add `moonfrp tag list <config>` command
  - [ ] Add `moonfrp tag bulk --key=X --value=Y --filter=all` command
  - [ ] Update service commands to support `--tag=key:value` option
- [ ] Integrate with Story 2.1 filtered operations (AC: 4)
  - [ ] Update bulk_operation_filtered() to use get_services_by_tag()
  - [ ] Support `--tag=env:prod` filter in service bulk operations
  - [ ] Support `--tag=region:us` filter in service bulk operations
- [ ] Integrate with Story 2.2 config filtering (AC: 5)
  - [ ] Update get_configs_by_filter() to support `tag:X` filter
  - [ ] Use query_configs_by_tag() for tag-based filtering
- [ ] Integrate with Story 2.4 templates (AC: 6)
  - [ ] Support tag inheritance from template metadata
  - [ ] Apply tags from template "# Tags:" comment during instantiation
  - [ ] Parse template tags and apply via add_config_tag()
- [ ] Testing (AC: 1, 2, 3, 4, 5, 7)
  - [ ] test_add_tag_to_config()
  - [ ] test_remove_tag_from_config()
  - [ ] test_query_configs_by_tag()
  - [ ] test_bulk_tag_assignment()
  - [ ] test_filtered_operations_by_tag()
  - [ ] test_multiple_tags_per_config()
  - [ ] test_tag_persistence_in_index()
  - [ ] test_service_name_conversion()

## Dev Notes

### Requirements Context

**Source Documents:**
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.3-Service-Grouping-&-Tagging]
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.3-Service-Grouping-&-Tagging#Technical-Specification]

**Problem Statement:**
50 tunnels need logical organization: by environment (prod/staging), region (eu/us), customer, or service type. Currently, there's no way to group or filter services, making bulk operations difficult. Tagging enables filtered operations across logical groups.

**Current Implementation:**
Config index exists (Story 1.2) with config_index table. The service_tags table schema is defined in Epic 1 but may not be created yet. Services are managed individually without grouping.

**Required Implementation:**
Create a tagging system that:
- Stores key-value tags in config index database (service_tags table)
- Provides fast tag queries via indexed database
- Enables filtered operations by tag
- Supports multiple tags per config
- Provides tag management functions (add, remove, list)
- Integrates with bulk operations from Stories 2.1 and 2.2

### Technical Constraints

**File Location:** `moonfrp-index.sh` and `moonfrp-services.sh`

**Database Schema:**
```sql
CREATE TABLE IF NOT EXISTS service_tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    config_id INTEGER NOT NULL,
    tag_key TEXT NOT NULL,
    tag_value TEXT NOT NULL,
    FOREIGN KEY (config_id) REFERENCES config_index(id) ON DELETE CASCADE,
    UNIQUE(config_id, tag_key)
);

CREATE INDEX IF NOT EXISTS idx_tag_key ON service_tags(tag_key);
CREATE INDEX IF NOT EXISTS idx_tag_value ON service_tags(tag_value);
CREATE INDEX IF NOT EXISTS idx_tag_key_value ON service_tags(tag_key, tag_value);
```

**Dependencies:**
- Story 1.2: Config index database (service_tags table may need creation)
- Story 2.1: `bulk_operation_filtered()` for tag-based service operations
- Story 2.2: `get_configs_by_filter()` for tag-based config filtering
- Story 2.4: Template system for tag inheritance

**Integration Points:**
- Verify/create service_tags table in index initialization
- Provide `get_services_by_tag()` for Story 2.1 filtered operations
- Provide `query_configs_by_tag()` for Story 2.2 config filtering
- Support tag inheritance from Story 2.4 templates

**Performance Requirements:**
- Tag queries should be fast (<50ms) via indexed database
- Bulk tagging operations should be efficient
- Tag queries use JOIN with config_index for fast lookups

### Project Structure Notes

- **Module:** `moonfrp-index.sh` - Tag management and query functions
- **Module:** `moonfrp-services.sh` - Service-to-tag mapping functions
- **Database Table:** `service_tags` in `~/.moonfrp/index.db`
- **New Functions:**
  - `add_config_tag()` - Add tag to config
  - `remove_config_tag()` - Remove tag from config
  - `list_config_tags()` - List tags for config
  - `query_configs_by_tag()` - Query configs by tag
  - `get_services_by_tag()` - Get services by tag
  - `bulk_tag_configs()` - Bulk tag assignment
  - `tag_management_menu()` - Interactive tag menu
- **CLI Integration:** Update `moonfrp.sh` to add `tag` commands
- **Menu Integration:** Add tag management to main menu

### Tag Query Design

**Query Patterns:**
- Exact match: `"env:prod"` → `tag_key='env' AND tag_value='prod'`
- Key-only match: `"env"` → `tag_key='env'` (any value)
- Multiple tags: Can query for configs with multiple tags (future enhancement)

**SQL Query Example:**
```sql
SELECT ci.file_path FROM config_index ci
JOIN service_tags st ON ci.id = st.config_id
WHERE st.tag_key='env' AND st.tag_value='prod';
```

### Service Name Mapping

**Pattern:**
- Config file: `/etc/frp/frpc-eu-1.toml`
- Service name: `moonfrp-frpc-eu-1`
- Conversion: `basename(config, .toml)` → `moonfrp-{basename}`

### Testing Strategy

**Functional Tests:**
- Add tag to config
- Remove tag from config
- Query configs by tag (exact and key-only)
- Bulk tag assignment
- Multiple tags per config
- Tag persistence (verify tags survive index rebuild)
- Service name conversion

**Integration Tests:**
- Tag-based service operations (Story 2.1)
- Tag-based config filtering (Story 2.2)
- Tag inheritance from templates (Story 2.4)

**Edge Cases:**
- Config not in index (should error gracefully)
- Duplicate tag key (should update, not create duplicate)
- Invalid tag format
- SQL injection prevention

### Learnings from Previous Stories

**From Story 1-2-implement-config-index (Status: done)**
- Index module pattern: `moonfrp-index.sh`
- Database initialization: `init_config_index()` function
- SQL injection prevention: proper string escaping
- Error handling: graceful fallback patterns
- Index file location: `~/.moonfrp/index.db`

**From Story 2-1-parallel-service-management (Status: drafted)**
- Service discovery pattern: `get_moonfrp_services()` function
- Service naming convention: `moonfrp-{basename}`
- Filtered operations pattern: `bulk_operation_filtered()` function

**From Story 2-2-bulk-configuration-operations (Status: drafted)**
- Config filtering pattern: `get_configs_by_filter()` function
- Filter support: `tag:X` filter type
- Integration pattern: use query functions from index module

**From Story 2-4-configuration-templates (Status: pending)**
- Tag inheritance: extract tags from template metadata
- Template metadata format: `# Tags: env:prod, type:client`
- Apply tags during template instantiation

**Relevant Patterns:**
- Use SQLite for fast indexed queries
- Follow index module patterns from Story 1.2
- Integrate with existing filter systems
- Support SQL injection prevention

[Source: docs/stories/1-2-implement-config-index.md#Dev-Agent-Record]
[Source: docs/stories/2-1-parallel-service-management.md] - Service operations
[Source: docs/stories/2-2-bulk-configuration-operations.md] - Config filtering

### Integration Notes

**With Story 2.1 (Parallel Service Management):**
- `bulk_operation_filtered()` will use `get_services_by_tag()` for tag-based filtering
- Service operations support `--tag=env:prod` option
- Example: `moonfrp service restart --tag=env:prod`

**With Story 2.2 (Bulk Configuration Operations):**
- `get_configs_by_filter()` will use `query_configs_by_tag()` for tag-based filtering
- Config operations support `--filter=tag:env:prod`
- Example: `moonfrp config bulk-update --field=auth.token --value=X --filter=tag:env:prod`

**With Story 2.4 (Configuration Templates):**
- Template metadata can specify tags: `# Tags: env:prod, type:client`
- Tags are applied automatically during template instantiation
- Tag inheritance enables consistent tagging across generated configs

**Database Schema Verification:**
- Check if service_tags table exists in index database
- If missing, create it during index initialization
- Table should be created in Epic 1 but may need verification

### References

- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.3-Service-Grouping-&-Tagging]
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.3-Service-Grouping-&-Tagging#Technical-Specification]
- [Source: moonfrp-index.sh] - Index module functions
- [Source: docs/stories/1-2-implement-config-index.md] - Config index implementation
- [Source: docs/stories/2-1-parallel-service-management.md] - Service operations

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

