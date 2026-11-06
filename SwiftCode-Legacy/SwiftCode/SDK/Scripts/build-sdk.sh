#!/bin/bash
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Building SwiftCode SDK release binaries at $SDK_ROOT..."

cd "$SDK_ROOT"
swift build --package-path "$SDK_ROOT" -c release --disable-sandbox

echo "Running automated SDK test suite..."
swift run --package-path "$SDK_ROOT" --disable-sandbox sdk-test-runner

echo "Build and test completed successfully."
