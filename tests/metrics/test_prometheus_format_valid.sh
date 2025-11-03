#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
METRICS_SH="$ROOT_DIR/moonfrp-metrics.sh"
export HOME="${HOME:-/root}"

bash -c "source '$METRICS_SH'; collect_metrics"
PROM="$HOME/.moonfrp/metrics/moonfrp_metrics.prom"
[[ -f "$PROM" ]]

# Ensure each HELP has a TYPE following it for core groups
grep -E '^# HELP moonfrp_services_total ' "$PROM" >/dev/null
grep -E '^# TYPE moonfrp_services_total gauge' "$PROM" >/dev/null

grep -E '^# HELP moonfrp_system_cpu_percent|^# HELP moonfrp_cpu_usage_percent' "$PROM" >/dev/null
grep -E '^# TYPE moonfrp_system_cpu_percent gauge|^# TYPE moonfrp_cpu_usage_percent gauge' "$PROM" >/dev/null

grep -E '^# HELP moonfrp_system_net_rx_bytes|^# HELP moonfrp_net_rx_bytes_total' "$PROM" >/dev/null
grep -E '^# TYPE moonfrp_system_net_rx_bytes counter|^# TYPE moonfrp_net_rx_bytes_total counter' "$PROM" >/dev/null

grep -E '^# HELP moonfrp_tunnel_count ' "$PROM" >/dev/null
grep -E '^# TYPE moonfrp_tunnel_count gauge' "$PROM" >/dev/null

echo "Format validation passed."


