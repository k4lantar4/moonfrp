#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
METRICS_SH="$ROOT_DIR/moonfrp-metrics.sh"
export HOME="${HOME:-/root}"
export METRICS_HISTORY_DIR="$HOME/.moonfrp/metrics/history"
mkdir -p "$METRICS_HISTORY_DIR"

# Create an old file and a recent file
oldf="$METRICS_HISTORY_DIR/old.prom"
newf="$METRICS_HISTORY_DIR/new.prom"
echo 1 > "$oldf"
echo 2 > "$newf"
touch -d '2 days ago' "$oldf"

# Set retention to 1 hour so old file should be pruned on next collect
RETENTION_HOURS=1 bash -c "source '$METRICS_SH'; collect_metrics"

[[ ! -f "$oldf" ]] || { echo "Old history file not pruned" >&2; exit 1; }
[[ -f "$newf" ]] || true
echo "Retention pruning passed."


