#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
METRICS_SH="$ROOT_DIR/moonfrp-metrics.sh"

start=$(date +%s)
bash -c "source '$METRICS_SH'; collect_metrics"
end=$(date +%s)
elapsed=$((end-start))

# Sanity: ensure a collection completes quickly (<= 3 seconds)
if (( elapsed > 3 )); then
  echo "Collection took too long: ${elapsed}s" >&2
  exit 1
fi
echo "Low-overhead runtime check passed (${elapsed}s)."


