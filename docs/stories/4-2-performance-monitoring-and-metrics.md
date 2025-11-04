# Story 4.2: Performance Monitoring & Metrics

Status: approved

## Story

As a DevOps engineer optimizing MoonFRP performance,
I want actionable service/system/tunnel metrics exported in Prometheus format and a simple dashboard,
so that I can validate optimization impact, detect regressions, and operate confidently with low overhead.

## Acceptance Criteria

1. Track per-tunnel metrics: bandwidth, connections, errors
2. System metrics: CPU, memory, network I/O
3. Export metrics in Prometheus format
4. Simple text dashboard for quick viewing
5. Metrics history: last 24h, configurable retention
6. Alerting on tunnel failures
7. Performance: metrics collection <1% CPU overhead

## Tasks / Subtasks

- [x] Implement metrics module bootstrap (AC: 2, 3, 7)
  - [x] Create `moonfrp-metrics.sh` and source `moonfrp-core.sh`
  - [x] Initialize metrics dir and file paths under `$HOME/.moonfrp/metrics`
  - [x] Provide `init_metrics()` to start background collector
- [x] Implement periodic collection (AC: 1, 2, 7)
  - [x] `collect_metrics()` orchestrates service/system/tunnel metrics and writes timestamped values
  - [x] Ensure collection completes fast; sleep 60s cadence by default
- [x] Service metrics (AC: 6)
  - [x] `collect_service_metrics(ts)` counts total/active/failed `moonfrp-` systemd services
  - [x] Emit Prometheus metrics: `moonfrp_services_total`, `moonfrp_services_active`, `moonfrp_services_failed`
- [x] System metrics (AC: 2, 7)
  - [x] `collect_system_metrics(ts)` records CPU usage, memory used (MB), RX/TX bytes
  - [x] Optimize shell pipelines to keep CPU overhead <1%
- [x] Tunnel metrics (AC: 1, 6)
  - [x] `collect_tunnel_metrics(ts)` uses FRP API if available; otherwise placeholder counts with safe defaults
  - [x] Add error handling when API not available; keep module resilient
  - [x] Emit aggregates: `moonfrp_tunnel_count`, `moonfrp_tunnel_errors`, `moonfrp_alerts_tunnel_failures_total`
- [x] Prometheus export (AC: 3)
  - [x] Write metrics to `$HOME/.moonfrp/metrics/moonfrp_metrics.prom` in text exposition format
  - [x] Provide helper `export_metrics_prometheus()` with integration snippet
- [x] Dashboard (AC: 4)
  - [x] `show_metrics_dashboard()` prints current values grouped by category
  - [x] Gracefully handle case when metrics not yet present
- [x] Retention and housekeeping (AC: 5)
  - [x] Keep last 24h by default; parameterize via constant `RETENTION_HOURS`
  - [x] Add cleanup routine if additional history files introduced later
- [x] Background worker (AC: 7)
  - [x] `collect_metrics_background()` runs forever, sleeps between cycles
  - [x] Validate measured CPU overhead under 1% on reference host (runtime sanity check)

- [x] Alerting on tunnel failures (AC: 6)
  - [x] Detect failure conditions from tunnel metrics and emit alert counters
  - [x] Provide simple alert hook function `on_tunnel_failure()` (no-op default)
  - [x] Increment `moonfrp_alerts_tunnel_failures_total` when API unreachable or no tunnels

### Testing Subtasks

- [x] Add test_metrics_collection() (AC: 1, 2)
- [x] Add test_prometheus_format_valid() (AC: 3)
- [x] Add test_metrics_dashboard_display() (AC: 4)
- [x] Add test_metrics_retention() (AC: 5)
- [x] Add test_metrics_low_overhead() (AC: 7)
- [x] Add test_alerting_on_tunnel_failures() (AC: 6)

## Dev Notes

### Architecture patterns and constraints

- Metrics collection must be modular: service, system, tunnel collectors callable independently by the orchestrator.
- Prometheus exposition file writes should be atomic (write to temp then mv) to avoid readers observing partial writes.
- Background collector should adapt sleep interval but never exceed 1% CPU on reference host.

### References

- [Source: docs/epics/epic-04-system-optimization.md#Story-4.2-Performance-Monitoring-&-Metrics]
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.2-Performance-Monitoring-&-Metrics#Technical-Specification]
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.2-Performance-Monitoring-&-Metrics#Testing-Requirements]

## Technical Notes

Location: new file `moonfrp-metrics.sh` (sources `moonfrp-core.sh`).

Key constants:
- `METRICS_DIR=$HOME/.moonfrp/metrics`
- `METRICS_FILE=$METRICS_DIR/moonfrp_metrics.prom`
- `RETENTION_HOURS=24`

Functions to implement/export:
- `init_metrics`
- `collect_metrics`
- `collect_service_metrics`
- `collect_system_metrics`
- `collect_tunnel_metrics`
- `collect_metrics_background`
- `show_metrics_dashboard`
- `export_metrics_prometheus`

### Alerting Integration

- Textfile collector setup for Prometheus/node_exporter is supported via `show_prometheus_integration_snippet()`.
- Failure detection uses FRP Dashboard API fields: `healthy=false`, non-OK `status` (not `online|running|opened`), and non-empty `lastErr`.
- Aggregated counters exposed:
  - `moonfrp_alerts_tunnel_failures_total`
  - `moonfrp_tunnel_errors`
  - `moonfrp_tunnel_count`

### Performance Validation

- Optional helper `measure_collector_overhead()` samples CPU using `pidstat` when available.
- Target: average CPU overhead <1% over a typical 30–60s window on reference host.

## Testing Requirements

```bash
test_metrics_collection()
test_prometheus_format_valid()
test_metrics_dashboard_display()
test_metrics_retention()
test_metrics_low_overhead()
```

## Requirements Context

Source Documents:
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.2-Performance-Monitoring-&-Metrics]
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.2-Performance-Monitoring-&-Metrics#Technical-Specification]
- [Source: docs/epics/epic-04-system-optimization.md#Story-4.2-Performance-Monitoring-&-Metrics#Testing-Requirements]

Problem Statement:
After optimization, DevOps teams need to monitor actual performance impact. Need metrics collection and export for integration with monitoring stacks (Prometheus, Grafana).

Implementation Overview:
- Implement `moonfrp-metrics.sh` for service/system/tunnel metrics, Prometheus export, and a simple dashboard. Ensure low overhead and resilience when FRP API is absent.

### Project Structure Notes

- Module: `moonfrp-metrics.sh` – Metrics and monitoring
- Integration: Can be started from UI or CLI bootstrap; background process collects every 60s
- Metrics endpoint: local file exposition with copyable Prometheus config snippet

## Change Log

- 2025-11-03: Draft created from Epic 4 technical specification.
- 2025-11-03: Implemented metrics module, aggregates, alert counter; added tests.



## Dev Agent Record

### Context Reference

- docs/stories/4-2-performance-monitoring-and-metrics.context.xml
