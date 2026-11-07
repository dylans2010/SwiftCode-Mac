#!/bin/bash
set -euo pipefail
SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SDK_ROOT/.." && pwd)"
SWIFT_PACKAGE_DIR="$REPO_ROOT/swiftcode"
echo "Building SwiftCode SDK release binaries at $SDK_ROOT..."
echo "Swift package root: $SWIFT_PACKAGE_DIR"
cd "$SDK_ROOT"
swift build --package-path "$SWIFT_PACKAGE_DIR" -c release --disable-sandbox
echo "Running automated SDK test suite..."
swift run --package-path "$SWIFT_PACKAGE_DIR" --disable-sandbox sdk-test-runner
echo "Build and test completed successfully."
