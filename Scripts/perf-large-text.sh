#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

tmp_dir="$(mktemp -d)"
cleanup() {
  printf "clipboard-manager-perf-complete" | pbcopy
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

json_10mb="$tmp_dir/large-10mb.json"
log_100mb="$tmp_dir/large-100mb.log"

python3 - <<'PY' "$json_10mb" "$log_100mb"
import sys
json_path, log_path = sys.argv[1], sys.argv[2]
with open(json_path, "w", encoding="utf-8") as f:
    f.write("{")
    for i in range(560000):
        f.write(f'"message{i}":"hello",')
    f.write('"end":true}')
with open(log_path, "w", encoding="utf-8") as f:
    line = "2026-04-30T00:00:00Z INFO clipboard-manager performance sample line\n"
    while f.tell() < 100 * 1024 * 1024:
        f.write(line)
PY

echo "10MB json bytes: $(wc -c < "$json_10mb")"
echo "100MB log bytes: $(wc -c < "$log_100mb")"

echo "Running PerformanceGuardTests"
swift test --filter PerformanceGuardTests

echo "Copying 10MB JSON to system pasteboard"
/usr/bin/time -p sh -c 'pbcopy < "$1"' sh "$json_10mb"
swift run ClipboardManualProbe read-once | sed -n '1,12p'

echo "Copying 100MB log to system pasteboard"
/usr/bin/time -p sh -c 'pbcopy < "$1"' sh "$log_100mb"
swift run ClipboardManualProbe read-once | sed -n '1,12p'
