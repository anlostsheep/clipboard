#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift test
swift build
Scripts/test-automation.sh
