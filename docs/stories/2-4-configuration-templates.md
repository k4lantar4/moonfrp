# Story 2.4: Configuration Templates

Status: review

## Story

As a DevOps engineer deploying 50+ similar tunnels,
I want to create config templates with variables and instantiate them in bulk,
so that I can rapidly deploy consistent tunnel configurations without manual editing.

## Acceptance Criteria

1. Create template with variables: `${SERVER_IP}`, `${REGION}`, `${PORT}`
2. Instantiate template with variable values
3. Bulk instantiation: CSV with variable values
4. Templates stored in `~/.moonfrp/templates/`
5. Validate template before instantiation
6. Auto-tag from template metadata
7. Template versioning

## Tasks / Subtasks

- [x] Create new module file `moonfrp-templates.sh` (AC: 1, 4)
  - [x] Define TEMPLATE_DIR constant: `$HOME/.moonfrp/templates`
  - [x] Create template directory if it doesn't exist
  - [x] Define template file extension: `.toml.tmpl`
- [x] Implement template creation (AC: 1, 7)
  - [x] Create create_template() function
  - [x] Save template content to `TEMPLATE_DIR/{name}.toml.tmpl`
  - [x] Support template metadata comments: `# Template:`, `# Variables:`, `# Tags:`
  - [x] Template versioning support (store version in metadata or filename)
- [x] Implement template listing (AC: 4)
  - [x] Create list_templates() function
  - [x] List all `.toml.tmpl` files in template directory
  - [x] Return template names (without extension)
- [x] Implement template instantiation (AC: 1, 2, 5, 6)
  - [x] Create instantiate_template() function
  - [x] Read template file from TEMPLATE_DIR
  - [x] Extract template metadata (tags, description) from comments
  - [x] Substitute variables: `${VAR_NAME}` → value
  - [x] Check for unsubstituted variables (warn or error)
  - [x] Write instantiated config to output file
  - [x] Validate generated config (use Story 1.3 validation)
  - [x] Index generated config (use Story 1.2 indexing)
  - [x] Apply tags from template metadata (use Story 2.3 tagging)
- [x] Implement variable substitution (AC: 1, 2)
  - [x] Parse variable format: `${VAR_NAME}`
  - [x] Accept variables as key=value pairs
  - [x] Substitute all occurrences of variable in template
  - [x] Handle variable values with special characters
  - [x] Support both string and numeric variables
- [x] Implement bulk instantiation from CSV (AC: 3)
  - [x] Create bulk_instantiate_template() function
  - [x] Parse CSV file: first row is header with variable names
  - [x] First column is output_file name
  - [x] Subsequent columns are variable values
  - [x] Instantiate template for each data row
  - [x] Handle errors per row (continue on error)
- [x] Integrate with validation system (AC: 5)
  - [x] Use Story 1.3 `validate_config_file()` after instantiation
  - [x] Abort if validation fails
  - [x] Clean up invalid generated configs
- [x] Integrate with indexing system (AC: 2)
  - [x] Use Story 1.2 `index_config_file()` after successful instantiation
  - [x] Index only if validation passes
- [x] Integrate with tagging system (AC: 6)
  - [x] Parse `# Tags:` comment from template
  - [x] Extract tags: `env:prod, type:client`
  - [x] Apply tags using Story 2.3 `add_config_tag()`
  - [x] Support tag inheritance from templates
- [x] Create interactive template menu (AC: 1, 2, 3)
  - [x] Create template_management_menu() function
  - [x] List existing templates
  - [x] Create template (interactive)
  - [x] Instantiate template (interactive with variable prompts)
  - [x] Bulk instantiate from CSV (interactive)
  - [x] View template content
  - [x] Delete template
- [x] CLI integration (AC: 1, 2, 3)
  - [x] Add `moonfrp template create <name> <file>` command
  - [x] Add `moonfrp template list` command
  - [x] Add `moonfrp template instantiate <name> <output> --var=X=Y` command
  - [x] Add `moonfrp template bulk-instantiate <name> <csv-file>` command
  - [x] Add `moonfrp template view <name>` command
  - [x] Add `moonfrp template delete <name>` command
- [x] Template versioning support (AC: 7)
  - [x] Store version in template metadata: `# Version: 1.0`
  - [x] Support version query: `moonfrp template version <name>`
  - [x] Optional: Support version in filename: `template-v1.0.toml.tmpl`
- [x] Testing (AC: 1, 2, 3, 5, 6)
  - [x] test_create_template()
  - [x] test_instantiate_template_with_variables()
  - [x] test_instantiate_template_missing_variable_warning()
  - [x] test_bulk_instantiate_from_csv()
  - [x] test_template_validation()
  - [x] test_template_auto_tagging()
  - [x] test_template_list()
  - [x] test_template_versioning()

## Dev Notes

### Requirements Context

**Source Documents:**
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.4-Configuration-Templates]
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.4-Configuration-Templates#Technical-Specification]

**Problem Statement:**
Creating 50 similar configs manually is tedious and error-prone. Currently, each config must be created individually, leading to inconsistencies and errors. Templates with variables enable rapid, consistent deployment of tunnel configs.

**Current Implementation:**
Configs are created manually or via `generate_client_config()` and `generate_server_config()` functions. There's no template system for rapid deployment of similar configs.

**Required Implementation:**
Create a template system that:
- Stores templates in `~/.moonfrp/templates/` directory
- Supports variable substitution: `${VAR_NAME}` → value
- Enables bulk instantiation from CSV files
- Validates generated configs
- Auto-applies tags from template metadata
- Supports template versioning

### Technical Constraints

**File Location:** New file `moonfrp-templates.sh`

**Template Format:**
```toml
# Template: client-base.toml.tmpl
# Variables: SERVER_IP, SERVER_PORT, REGION, PROXY_NAME, LOCAL_PORT
# Tags: env:prod, type:client

serverAddr = "${SERVER_IP}"
serverPort = ${SERVER_PORT}
auth.token = "${AUTH_TOKEN}"

user = "moonfrp-${REGION}"

[[proxies]]
name = "${PROXY_NAME}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${LOCAL_PORT}
remotePort = ${REMOTE_PORT}
```

**Dependencies:**
- Story 1.3: `validate_config_file()` - Validate generated configs
- Story 1.2: `index_config_file()` - Index generated configs
- Story 2.3: `add_config_tag()` - Apply tags from template metadata
- Existing config file functions from `moonfrp-config.sh`

**Integration Points:**
- Source `moonfrp-templates.sh` in `moonfrp.sh`
- Use validation before finalizing generated config
- Use indexing after successful instantiation
- Use tagging for tag inheritance

**Performance Requirements:**
- Template instantiation should be fast (<100ms per config)
- Bulk instantiation should handle 50+ configs efficiently
- Variable substitution should be efficient

### Project Structure Notes

- **New Module:** `moonfrp-templates.sh` - Template management functions
- **Template Directory:** `~/.moonfrp/templates/` - Created automatically
- **Template Extension:** `.toml.tmpl` - Template files
- **New Functions:**
  - `create_template()` - Create template from content
  - `list_templates()` - List available templates
  - `instantiate_template()` - Instantiate template with variables
  - `bulk_instantiate_template()` - Bulk instantiate from CSV
  - `template_management_menu()` - Interactive template menu
- **CLI Integration:** Update `moonfrp.sh` to add `template` commands
- **Menu Integration:** Add template management to main menu

### Template Format Design

**Template File Structure:**
- Metadata comments at top: `# Template:`, `# Variables:`, `# Tags:`, `# Version:`
- TOML content with variable placeholders: `${VAR_NAME}`
- Variable substitution: replace all occurrences of `${VAR_NAME}` with value
- Support both string (`"${VAR}"`) and numeric (${VAR}) formats

**Variable Format:**
- Pattern: `${VAR_NAME}`
- Case-sensitive
- Can appear multiple times in template
- Values provided as `key=value` pairs during instantiation

### CSV Format for Bulk Instantiation

**Format:**
```csv
output_file,SERVER_IP,SERVER_PORT,REGION,PROXY_NAME,LOCAL_PORT,REMOTE_PORT
frpc-eu-1.toml,192.168.1.100,7000,eu,web-eu-1,8080,30001
frpc-eu-2.toml,192.168.1.100,7000,eu,web-eu-2,8080,30002
frpc-us-1.toml,10.0.1.50,7000,us,web-us-1,8080,30003
```

**Parsing:**
- First row: headers (variable names)
- First column: output_file name
- Subsequent columns: variable values
- Process each data row independently

### Tag Inheritance Design

**Template Metadata:**
```
# Tags: env:prod, type:client, region:eu
```

**Processing:**
- Extract tags from `# Tags:` comment
- Parse comma-separated tags
- Validate tag format (key:value)
- Apply tags via `add_config_tag()` after instantiation
- Tags applied only if Story 2.3 tagging is available

### Testing Strategy

**Functional Tests:**
- Create template with variables
- Instantiate template with variable values
- Verify variable substitution works correctly
- Test missing variable warning
- Bulk instantiate from CSV
- Validate generated configs
- Auto-tagging from template metadata
- Template versioning

**Edge Cases:**
- Missing variables in template
- Invalid template syntax
- CSV parsing errors
- Validation failure after instantiation
- Template not found
- Invalid tag format in metadata

### Learnings from Previous Stories

**From Story 1-3-config-validation-framework (Status: done)**
- Validation pattern: validate before finalizing
- Use `validate_config_file()` after generation
- Clean up invalid generated files
- Validation should happen before indexing

**From Story 1-2-implement-config-index (Status: done)**
- Index pattern: index after successful validation
- Use `index_config_file()` after instantiation
- Index only valid configs

**From Story 2-3-service-grouping-tagging (Status: drafted)**
- Tagging pattern: apply tags after instantiation
- Use `add_config_tag()` for each tag from template
- Tag format: `key:value`
- Parse tags from template metadata comments

**From Story 1-4-automatic-backup-system (Status: done)**
- File creation pattern: create output file directly (no backup needed for new files)
- Backup only applies to existing files being modified

**Relevant Patterns:**
- New module pattern: create `moonfrp-templates.sh` following index module pattern
- Integration: use validation, indexing, and tagging functions from other stories
- Error handling: validate before committing, clean up on failure

[Source: docs/stories/1-3-config-validation-framework.md#Dev-Agent-Record]
[Source: docs/stories/1-2-implement-config-index.md#Dev-Agent-Record]
[Source: docs/stories/2-3-service-grouping-tagging.md] - Tagging integration

### Integration Notes

**Instantiation Workflow:**
1. Read template file
2. Extract metadata (tags, variables)
3. Substitute variables
4. Write to output file
5. Validate generated config (Story 1.3)
6. If valid: index config (Story 1.2)
7. If valid: apply tags (Story 2.3)
8. If invalid: delete output file, report error

**With Story 1.3 (Validation):**
- Validate every generated config before finalizing
- Abort instantiation if validation fails
- Clean up invalid generated files

**With Story 1.2 (Indexing):**
- Index generated configs after successful validation
- Use `index_config_file()` for each generated config
- Index only valid configs

**With Story 2.3 (Tagging):**
- Extract tags from template metadata: `# Tags: env:prod, type:client`
- Apply tags using `add_config_tag()` after successful instantiation
- Support tag inheritance for consistent tagging

**CSV Bulk Instantiation:**
- Process each row independently
- Continue on error (don't abort entire batch)
- Report success/failure per row
- Generate summary at end

### References

- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.4-Configuration-Templates]
- [Source: docs/epics/epic-02-bulk-operations.md#Story-2.4-Configuration-Templates#Technical-Specification]
- [Source: moonfrp-config.sh] - Existing config generation functions
- [Source: docs/stories/1-3-config-validation-framework.md] - Validation framework
- [Source: docs/stories/1-2-implement-config-index.md] - Index system
- [Source: docs/stories/2-3-service-grouping-tagging.md] - Tagging system

## Dev Agent Record

### Context Reference

- docs/stories/2-4-configuration-templates.context.xml

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

✅ **Implementation Complete (2025-11-02)**

**Summary:**
- Created new module `moonfrp-templates.sh` following the pattern established in `moonfrp-index.sh`
- Implemented all core template functions: creation, listing, instantiation, bulk operations
- Variable substitution supports `${VAR_NAME}` pattern with proper escaping
- Integrated with validation (Story 1.3), indexing (Story 1.2), and tagging (Story 2.3 - graceful fallback when not available)
- Added comprehensive CLI commands for template management
- Created interactive template menu for user-friendly operations
- Template versioning support via metadata comments
- Comprehensive test suite created (`test_template_system.sh`)

**Key Features:**
- Templates stored in `~/.moonfrp/templates/` with `.toml.tmpl` extension
- Bulk instantiation from CSV files (first column: output_file, subsequent: variables)
- Automatic validation, indexing, and tagging integration
- Template metadata extraction (Variables, Tags, Version, Description)
- Graceful handling of missing `add_config_tag()` function (Story 2.3 dependency)

**Integration Points:**
- Module sourced in `moonfrp.sh` (line 25)
- CLI commands added: `template list|create|view|instantiate|bulk-instantiate|version|delete`
- Interactive menu available via `template` command without subcommand

### File List

- moonfrp-templates.sh (new)
- moonfrp.sh (modified - added template CLI commands)
- tests/test_template_system.sh (new)


## Senior Developer Review (AI)

### Reviewer
MMad

### Date
2025-11-03

### Outcome
**Approve**

### Summary

Systematic validation confirms all acceptance criteria are implemented and all completed tasks are verified in code with evidence. The template system is complete, integrates with validation, indexing, and tagging, and includes CLI and interactive menu flows. Tests exist for core functionality.

### Key Findings (by severity)

- HIGH: None
- MEDIUM: None
- LOW: Minor robustness notes only (e.g., CSV whitespace trimming already handled)

### Acceptance Criteria Coverage

| AC# | Description | Status | Evidence |
|-----|-------------|--------|----------|
| 1 | Create template with variables | IMPLEMENTED | moonfrp-templates.sh:111-144, 213-243 |
| 2 | Instantiate template with variable values | IMPLEMENTED | moonfrp-templates.sh:267-342 |
| 3 | Bulk instantiation from CSV | IMPLEMENTED | moonfrp-templates.sh:348-435 |
| 4 | Templates stored in ~/.moonfrp/templates/ | IMPLEMENTED | moonfrp-templates.sh:27-40, 166-183 |
| 5 | Validate template before instantiation | IMPLEMENTED | moonfrp-templates.sh:306-311 |
| 6 | Auto-tag from template metadata | IMPLEMENTED | moonfrp-templates.sh:317-338 |
| 7 | Template versioning | IMPLEMENTED | moonfrp-templates.sh:185-207 |

Summary: 7 of 7 acceptance criteria fully implemented.

### Task Completion Validation

| Task | Marked As | Verified As | Evidence |
|------|-----------|-------------|----------|
| Create new module `moonfrp-templates.sh` | [x] | ✅ VERIFIED | File exists; header 3-7 |
| Implement template creation | [x] | ✅ VERIFIED | 111-144; 146-160 |
| Implement template listing | [x] | ✅ VERIFIED | 166-183 |
| Implement template instantiation | [x] | ✅ VERIFIED | 267-342 |
| Variable substitution | [x] | ✅ VERIFIED | 213-243; 245-261 |
| Bulk instantiation from CSV | [x] | ✅ VERIFIED | 348-435 |
| Integrate with validation system | [x] | ✅ VERIFIED | 306-311 |
| Integrate with indexing system | [x] | ✅ VERIFIED | 312-315 |
| Integrate with tagging system | [x] | ✅ VERIFIED | 317-338 |
| Interactive template menu | [x] | ✅ VERIFIED | 478-562 |
| CLI integration | [x] | ✅ VERIFIED | Exports 564-573; referenced in story |
| Template versioning support | [x] | ✅ VERIFIED | 185-207 |
| Testing | [x] | ✅ VERIFIED | tests/test_template_system.sh present |

Summary: All completed tasks verified; none questionable; zero false completions.

### Test Coverage and Gaps

- Tests exist for creation, instantiation, missing variable warning, bulk, validation, auto-tagging, list, versioning. No critical gaps identified.

### Architectural Alignment

- Follows established bash module patterns; integrates with validation (Story 1.3), indexing (Story 1.2), and tagging (Story 2.3). No violations observed.

### Security Notes

- Variable substitution escapes special characters prior to sed replacement. Tag parsing validates key:value format.

### Best-Practices and References

- Consistent logging, input validation, and graceful error handling align with project standards.

### Action Items

**Code Changes Required:**
- None

**Advisory Notes:**
- Note: Consider supporting quoted CSV values with embedded commas in bulk mode if needed in future.
