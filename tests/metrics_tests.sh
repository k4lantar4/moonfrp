#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
METRICS_SH="$ROOT_DIR/moonfrp-metrics.sh"

run_test() {
  local name="$1"; shift
  echo "[TEST] $name"
  "$@"
  echo "[PASS] $name"
}

test_metrics_collection() {
  # shellcheck disable=SC1090
  source "$METRICS_SH"
  collect_metrics
  [[ -f "$METRICS_FILE" ]]
  grep -q '^moonfrp_services_total ' "$METRICS_FILE"
  grep -q '^moonfrp_system_cpu_percent ' "$METRICS_FILE"
  grep -q '^moonfrp_tunnel_count ' "$METRICS_FILE" || true
}

test_prometheus_format_headers() {
  # shellcheck disable=SC1090
  source "$METRICS_SH"
  collect_metrics
  grep -q '^# HELP moonfrp_services_total' "$METRICS_FILE"
  grep -q '^# TYPE moonfrp_services_total' "$METRICS_FILE"
}

test_dashboard_runs() {
  # shellcheck disable=SC1090
  source "$METRICS_SH"
  show_metrics_dashboard >/dev/null 2>&1 || true
  collect_metrics
  show_metrics_dashboard >/dev/null 2>&1
}

main() {
  run_test "metrics_collection" test_metrics_collection
  run_test "prometheus_headers" test_prometheus_format_headers
  run_test "dashboard_runs" test_dashboard_runs
}

main "$@"


