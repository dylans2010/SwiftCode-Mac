#!/bin/bash
set -euo pipefail

# Wave 14 adaptation (Legacy SDK/Scripts/build-sdk.sh):
# - SDK_ROOT is now this repo's sdk/ (the TypeScript SDK root).
# - The Swift SDK package (Legacy swiftcode/Package.swift) has not been
#   migrated yet (ledger: NOT STARTED, other wave), so the Swift build runs
#   against swiftcode/ — the repo's Swift package, which hosts the migrated Swift
#   SDK code. Until that wave lands the `sdk-test-runner` target, the test
#   step below fails; the build step builds the whole swiftcode package.
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
