#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift test --filter ClipboardCoreTests
swift test --filter ClipboardPlatformTests
swift build --product ClipboardApp
swift build --product ClipboardManualProbe
