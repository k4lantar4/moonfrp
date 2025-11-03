#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
METRICS_SH="$ROOT_DIR/moonfrp-metrics.sh"
export HOME="${HOME:-/root}"

run_collect_once() {
  bash -c "source '$METRICS_SH'; collect_metrics"
}

assert_grep() {
  local pattern="$1" file="$2"
  if ! grep -E "$pattern" "$file" >/dev/null 2>&1; then
    echo "ASSERT FAIL: pattern not found: $pattern in $file" >&2
    exit 1
  fi
}

main() {
  # Run one collection cycle
  run_collect_once

  local prom="$HOME/.moonfrp/metrics/moonfrp_metrics.prom"
  [[ -f "$prom" ]] || { echo "Missing metrics file: $prom" >&2; exit 1; }

  # Basic Prometheus headers
  assert_grep '^# HELP moonfrp_services_total ' "$prom"
  assert_grep '^# TYPE moonfrp_services_total gauge' "$prom"

  # Core metrics exist and are numeric
  assert_grep '^moonfrp_services_total [0-9]+' "$prom"
  # Accept either legacy or normalized metric names
  (grep -E '^moonfrp_cpu_usage_percent [0-9]+(\.[0-9]+)?' "$prom" || grep -E '^moonfrp_system_cpu_percent [0-9]+' "$prom") >/dev/null || { echo "CPU metric missing" >&2; exit 1; }
  (grep -E '^moonfrp_memory_used_megabytes [0-9]+' "$prom" || grep -E '^moonfrp_system_mem_used_mb [0-9]+' "$prom") >/dev/null || { echo "MEM metric missing" >&2; exit 1; }
  (grep -E '^moonfrp_net_rx_bytes_total [0-9]+' "$prom" || grep -E '^moonfrp_system_net_rx_bytes [0-9]+' "$prom") >/dev/null || { echo "RX metric missing" >&2; exit 1; }
  (grep -E '^moonfrp_net_tx_bytes_total [0-9]+' "$prom" || grep -E '^moonfrp_system_net_tx_bytes [0-9]+' "$prom") >/dev/null || { echo "TX metric missing" >&2; exit 1; }

  # Tunnel aggregates aligned with dashboard
  assert_grep '^moonfrp_tunnel_count [0-9]+' "$prom"
  assert_grep '^moonfrp_tunnel_errors [0-9]+' "$prom"
  assert_grep '^moonfrp_alerts_tunnel_failures_total [0-9]+' "$prom"
  assert_grep '^moonfrp_tunnel_bandwidth_bps [0-9]+' "$prom"

  echo "All basic metrics tests passed."
}

main "$@"


