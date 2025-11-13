# MoonFRP – Environment Variables & Commands

This document enumerates every environment variable and CLI command that `moonfrp` (the entrypoint script `moonfrp.sh` and its sourced modules) recognises. Use it as a reference when wiring MoonFRP into automation tools such as Ansible.

> **Note:** Defaults shown below reflect the hard-coded values inside the scripts _after_ configuration files are loaded. environment overrides always win, followed by `/etc/moonfrp/config`, then the built-in defaults.

## Environment Variables

### Runtime & Logging Controls
- `MOONFRP_YES` (default `false`): Forces non-interactive answers; required when stdin is non-TTY.
- `MOONFRP_QUIET` (default `false`): Suppresses non-error log lines (`log()` wrapper in `moonfrp.sh`).
- `MOONFRP_TIMEOUT` (default `300` seconds): Upper bound for any command before the alarm handler aborts.
- `MOONFRP_LOG_FORMAT` (default `text`): Accepts `text` or `json`; affects both `log()` implementations.
- `MOONFRP_LOG_SERVICE`, `MOONFRP_LOG_OPERATION`, `MOONFRP_LOG_DURATION`: Optional context fields appended to structured logs.
- `MOONFRP_USE_NATIVE_SQLITE` (default `0`): When `1`, bypasses the Python shim and invokes the system `sqlite3` for query operations (see wrapper in `moonfrp-core.sh`).

### Installation & Paths
- `FRP_VERSION` (default `0.65.0`): Target frp release; persisted into `/etc/moonfrp/config` if absent.
- `FRP_ARCH` / `MOONFRP_FRP_ARCH`: Explicit architecture identifier (e.g. `linux_amd64`); otherwise guessed from `uname`.
- `FRP_DIR` / `MOONFRP_INSTALL_DIR` (default `/opt/frp`): Installation root used by service units and binary downloads.
- `CONFIG_DIR` / `MOONFRP_CONFIG_DIR` (default `/etc/frp`): Base directory for generated `frps.toml`, `frpc*.toml`, and visitor configs.
- `LOG_DIR` / `MOONFRP_LOG_DIR` (default `/var/log/frp`): Log output destination referenced by generated configs.
- `TEMP_DIR` (default `/tmp/moonfrp`): Working directory for downloads, temp files, and bulk-update staging.
- `MOONFRP_DATA_DIR` (default `/opt/moonfrp/data`): Root for index/cache data (see `moonfrp-index.sh`).
- `MOONFRP_INDEX_DB_PATH` (default `$HOME/.moonfrp/index.db`): Location of the legacy SQLite index (fallback path for some checks).

### Server Configuration Inputs
- `MOONFRP_SERVER_BIND_ADDR` (default `0.0.0.0`): Value written to `bindAddr` in `frps.toml`.
- `MOONFRP_SERVER_BIND_PORT` (default `7000`): Applied to `bindPort`/`quicBindPort`.
- `MOONFRP_SERVER_AUTH_TOKEN` (default empty): If blank, MoonFRP auto-generates a secure token.
- `MOONFRP_SERVER_DASHBOARD_PORT` (default `7500`): Exposed dashboard port (`webServer.port`).
- `MOONFRP_SERVER_DASHBOARD_USER` (default `admin`): Dashboard username (`webServer.user`).
- `MOONFRP_SERVER_DASHBOARD_PASSWORD` (default empty): Dashboard password; generated when unset.

### Client Configuration Inputs
- `MOONFRP_CLIENT_SERVER_ADDR` (default empty): Target server address recorded as `serverAddr`.
- `MOONFRP_CLIENT_SERVER_PORT` (default `7000`): Remote frp port `serverPort`.
- `MOONFRP_CLIENT_AUTH_TOKEN` (default empty): Shared token; required for non-interactive client setup.
- `MOONFRP_CLIENT_USER` (default empty): Overrides generated client username (`user` field).
- `MOONFRP_CLIENT_LOCAL_PORTS` (default empty): Explicit list of local ports for automatic proxy sections.
- `MOONFRP_LOCAL_PORTS` / `MOONFRP_REMOTE_PORTS` (default empty): Legacy aliases still honoured by `quick_client_setup`.

### Multi-IP / Bulk Client Inputs
- `MOONFRP_SERVER_IPS` (default empty): Comma-separated server addresses triggers multi-IP mode.
- `MOONFRP_SERVER_PORTS` (default empty): Per-IP remote ports; falls back to `MOONFRP_CLIENT_SERVER_PORT`.
- `MOONFRP_CLIENT_PORTS` (default empty): Local client ports used during bulk generation.

### Security & Performance Tunables
- `MOONFRP_TLS_ENABLE` (default `true`): Proposed TLS toggle for transport blocks.
- `MOONFRP_TLS_FORCE` (default `false`): Forces TLS when true.
- `MOONFRP_AUTH_METHOD` (default `token`): Sets `auth.method` for both server and client configs.
- `MOONFRP_MAX_POOL_COUNT` (default `20`): Global pool upper bound.
- `MOONFRP_POOL_COUNT` (default `20`): Default connection pool per client.
- `MOONFRP_TCP_MUX` (default `false`): Controls `transport.tcpMux`.
- `MOONFRP_TCP_MUX_KEEPALIVE_INTERVAL` (default `10`): Applied to `transport.tcpMuxKeepaliveInterval`.
- `MOONFRP_DIAL_SERVER_TIMEOUT` (default `10`): Propagated to `transport.dialServerTimeout`.
- `MOONFRP_DIAL_SERVER_KEEPALIVE` (default `120`): Sets `transport.dialServerKeepalive`.
- `MOONFRP_HEARTBEAT_INTERVAL` (default `30`): Heartbeat cadence.
- `MOONFRP_HEARTBEAT_TIMEOUT` (default `90`): Heartbeat timeout.

### Logging Behaviour in Generated Configs
- `MOONFRP_LOG_LEVEL` (default `info`): `log.level` for frp configs.
- `MOONFRP_LOG_MAX_DAYS` (default `7`): Rotation window (`log.maxDays`).
- `MOONFRP_LOG_DISABLE_COLOR` (default `false`): Controls `log.disablePrintColor`.

### Indexing, Status & Caching
- `STATUS_CACHE_TTL` (default `5` seconds): Status cache time-to-live used by `moonfrp-ui.sh`.
- `MOONFRP_STATUS_TTL` (fallback): Secondary TTL source when `STATUS_CACHE_TTL` is absent.

### Backups & Housekeeping
- `BACKUP_DIR` (default `$HOME/.moonfrp/backups`): Storage for automatic backups prior to mutations.
- `MAX_BACKUPS_PER_FILE` (default `10`): Retention limit enforced after each backup rotation.

## CLI Commands

Global flags accepted ahead of any command:
- `-y`, `--yes`: Enable non-interactive confirmations.
- `-q`, `--quiet`: Reduce log noise.
- `--timeout=<seconds>`: Adjust command timeout window.
- `--log-format=text|json`: Switch logging mode.
- `--help`, `-h`: Show full usage.
- `--version`, `-v`, or `version`: Print the MoonFRP version and exit.

### Setup & Configuration
- `setup server`: Run the streamlined server bootstrap (respects server-related env vars above).
- `setup client`: Run the quick client bootstrap; auto-detects multi-IP when relevant env vars are set.
- `config server|client|multi-ip|visitor`: Launch interactive wizards for each configuration type.
- `config bulk-update [options]`: Batch update fields using `--field`, `--value`, `--filter`, `--dry-run`, or `--file=<json>` directives.

### Service Management
- `service start|stop|restart [name]`: Control individual services or use `all`.
- `service <action> --tag=<KEY>`: Apply operations to services tagged with the specified value.
- `service status [name]`: Show status for one service or list all when omitted.
- `service logs <name>`: Stream logs for a given unit.
- `service bulk --operation=<start|stop|restart|reload> [--filter=tag:val|status:state|name:regex] [--max-parallel=N] [--dry-run]`: Parallelised service orchestration.

### Configuration Lifecycle
- `backup` functionality is implicit via any modifying command (backups land in `BACKUP_DIR`).
- `restore <config> --backup=<timestamp>`: Restore a specific configuration backup; without `--backup` launches interactive picker.
- `export [file]`: Dump all indexed configs to YAML (default filename `moonfrp-configs.yaml`).
- `import <file> [server|client|all] [--dry-run]`: Load configs from YAML with optional type filter.
- `validate <config> [server|client|auto]`: Syntax and semantic validation for TOML files.
- `tag add|remove|list`: Manage metadata tags for individual configs.
- `tag bulk --key=<k> --value=<v> [--filter=...]`: Apply tags en masse.

### Templates
- `template list`: Enumerate stored templates.
- `template create <name> <path>`: Ingest a TOML template from disk.
- `template view <name>`: Display template contents.
- `template instantiate <name> <output> --var=KEY=VALUE [...]`: Render a template with variable substitutions.
- `template bulk-instantiate <name> <csv>`: Create multiple outputs from CSV input.
- `template version <name>`: Show stored template revision.
- `template delete <name>`: Remove a template.

### Operations & Insights
- `status`: High-level MoonFRP and frp status summary.
- `logs [service]`: View stored log menu or jump straight to a service.
- `health check`: Run the health-check routine.
- `search <query> [--type=auto|name|ip|port|tag]`: Query the configuration index.
- `optimize [preset] [--dry-run]`: Apply kernel and frp tuning presets (`conservative`, `balanced`, `aggressive`).

### Installation Utilities
- `install`: Download and install frp binaries plus supporting files.
- `uninstall`: Remove MoonFRP assets and services.

These commands make up the complete public interface exposed by `moonfrp.sh`. When automating with Ansible, combine the relevant environment variables with the corresponding command invocations to reproduce the desired server/client state.

