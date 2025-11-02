# Story 2.4: Configuration Templates

Status: drafted

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

- [ ] Create new module file `moonfrp-templates.sh` (AC: 1, 4)
  - [ ] Define TEMPLATE_DIR constant: `$HOME/.moonfrp/templates`
  - [ ] Create template directory if it doesn't exist
  - [ ] Define template file extension: `.toml.tmpl`
- [ ] Implement template creation (AC: 1, 7)
  - [ ] Create create_template() function
  - [ ] Save template content to `TEMPLATE_DIR/{name}.toml.tmpl`
  - [ ] Support template metadata comments: `# Template:`, `# Variables:`, `# Tags:`
  - [ ] Template versioning support (store version in metadata or filename)
- [ ] Implement template listing (AC: 4)
  - [ ] Create list_templates() function
  - [ ] List all `.toml.tmpl` files in template directory
  - [ ] Return template names (without extension)
- [ ] Implement template instantiation (AC: 1, 2, 5, 6)
  - [ ] Create instantiate_template() function
  - [ ] Read template file from TEMPLATE_DIR
  - [ ] Extract template metadata (tags, description) from comments
  - [ ] Substitute variables: `${VAR_NAME}` → value
  - [ ] Check for unsubstituted variables (warn or error)
  - [ ] Write instantiated config to output file
  - [ ] Validate generated config (use Story 1.3 validation)
  - [ ] Index generated config (use Story 1.2 indexing)
  - [ ] Apply tags from template metadata (use Story 2.3 tagging)
- [ ] Implement variable substitution (AC: 1, 2)
  - [ ] Parse variable format: `${VAR_NAME}`
  - [ ] Accept variables as key=value pairs
  - [ ] Substitute all occurrences of variable in template
  - [ ] Handle variable values with special characters
  - [ ] Support both string and numeric variables
- [ ] Implement bulk instantiation from CSV (AC: 3)
  - [ ] Create bulk_instantiate_template() function
  - [ ] Parse CSV file: first row is header with variable names
  - [ ] First column is output_file name
  - [ ] Subsequent columns are variable values
  - [ ] Instantiate template for each data row
  - [ ] Handle errors per row (continue on error)
- [ ] Integrate with validation system (AC: 5)
  - [ ] Use Story 1.3 `validate_config_file()` after instantiation
  - [ ] Abort if validation fails
  - [ ] Clean up invalid generated configs
- [ ] Integrate with indexing system (AC: 2)
  - [ ] Use Story 1.2 `index_config_file()` after successful instantiation
  - [ ] Index only if validation passes
- [ ] Integrate with tagging system (AC: 6)
  - [ ] Parse `# Tags:` comment from template
  - [ ] Extract tags: `env:prod, type:client`
  - [ ] Apply tags using Story 2.3 `add_config_tag()`
  - [ ] Support tag inheritance from templates
- [ ] Create interactive template menu (AC: 1, 2, 3)
  - [ ] Create template_management_menu() function
  - [ ] List existing templates
  - [ ] Create template (interactive)
  - [ ] Instantiate template (interactive with variable prompts)
  - [ ] Bulk instantiate from CSV (interactive)
  - [ ] View template content
  - [ ] Delete template
- [ ] CLI integration (AC: 1, 2, 3)
  - [ ] Add `moonfrp template create <name> <file>` command
  - [ ] Add `moonfrp template list` command
  - [ ] Add `moonfrp template instantiate <name> <output> --var=X=Y` command
  - [ ] Add `moonfrp template bulk-instantiate <name> <csv-file>` command
  - [ ] Add `moonfrp template view <name>` command
  - [ ] Add `moonfrp template delete <name>` command
- [ ] Template versioning support (AC: 7)
  - [ ] Store version in template metadata: `# Version: 1.0`
  - [ ] Support version query: `moonfrp template version <name>`
  - [ ] Optional: Support version in filename: `template-v1.0.toml.tmpl`
- [ ] Testing (AC: 1, 2, 3, 5, 6)
  - [ ] test_create_template()
  - [ ] test_instantiate_template_with_variables()
  - [ ] test_instantiate_template_missing_variable_warning()
  - [ ] test_bulk_instantiate_from_csv()
  - [ ] test_template_validation()
  - [ ] test_template_auto_tagging()
  - [ ] test_template_list()
  - [ ] test_template_versioning()

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

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

