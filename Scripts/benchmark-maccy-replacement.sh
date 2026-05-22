#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

report_dir=".build/benchmark-reports"
mkdir -p "$report_dir"

bundle_id="${BUNDLE_IDENTIFIER:-com.local.clipboard-manager}"
timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
report_path="$report_dir/clipboard-benchmark-$timestamp.json"

args=(--bundle-id "$bundle_id" --output "$report_path")
if [[ -n "${MACCY_BASELINE_JSON:-}" ]]; then
  args+=(--maccy-baseline "$MACCY_BASELINE_JSON")
fi

swift run ClipboardBenchmarkProbe "${args[@]}"

echo "JSON report: $report_path"
if [[ -n "${MACCY_BASELINE_JSON:-}" ]]; then
  echo "Maccy baseline: $MACCY_BASELINE_JSON"
else
  echo "Maccy baseline: missing; report comparisons will be not_comparable per metric."
fi
