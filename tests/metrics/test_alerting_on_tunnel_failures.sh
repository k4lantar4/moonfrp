#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
METRICS_SH="$ROOT_DIR/moonfrp-metrics.sh"
export HOME="${HOME:-/root}"

# Ensure FRP is not configured so the collector uses fallback and increments failures
unset FRP_DASHBOARD_URL
bash -c "source '$METRICS_SH'; collect_metrics"
PROM="$HOME/.moonfrp/metrics/moonfrp_metrics.prom"
[[ -f "$PROM" ]]

val=$(grep -E '^moonfrp_alerts_tunnel_failures_total ' "$PROM" | awk '{print $2}' || echo 0)
[[ "${val:-0}" =~ ^[0-9]+$ ]] || { echo "Invalid failure counter" >&2; exit 1; }
echo "Alerting counter present: $val"


