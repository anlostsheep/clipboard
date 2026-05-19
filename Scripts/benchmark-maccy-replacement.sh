#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

report_dir=".build/benchmark-reports"
mkdir -p "$report_dir"

bundle_id="${BUNDLE_IDENTIFIER:-com.local.clipboard-manager}"
timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
report_path="$report_dir/clipboard-benchmark-$timestamp.json"

swift run ClipboardBenchmarkProbe \
  --bundle-id "$bundle_id" \
  --output "$report_path"

echo "JSON report: $report_path"
echo "Maccy comparison: not_comparable (provide Maccy baseline metrics to compare)."
