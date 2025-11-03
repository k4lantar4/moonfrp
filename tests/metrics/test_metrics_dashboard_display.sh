#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
METRICS_SH="$ROOT_DIR/moonfrp-metrics.sh"
export HOME="${HOME:-/root}"

# Case 1: no file yet
rm -f "$HOME/.moonfrp/metrics/moonfrp_metrics.prom" 2>/dev/null || true
out1=$(bash -lc "source '$METRICS_SH'; show_metrics_dashboard" || true)
echo "$out1" | grep -E 'Metrics Dashboard|No metrics available yet|Starting collector' >/dev/null

# Case 2: with file
bash -c "source '$METRICS_SH'; collect_metrics"
out2=$(bash -lc "source '$METRICS_SH'; show_metrics_dashboard")
echo "$out2" | grep -E 'Services:|System:|Tunnels:' >/dev/null
echo "Dashboard display tests passed."


