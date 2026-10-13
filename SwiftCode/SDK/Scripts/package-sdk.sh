#!/bin/bash
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$SDK_ROOT/Distribution"
DEST="$DIST_DIR/SwiftCodeSDK"
ARCHIVE_ZIP="$DIST_DIR/SwiftCodeSDK-1.0.0.zip"
ARCHIVE_TGZ="$DIST_DIR/SwiftCodeSDK-1.0.0.tar.gz"
CHECKSUMS="$DIST_DIR/checksums.txt"

echo "=== SwiftCode SDK Packaging Pipeline ==="

# 1. Run verification
"$SDK_ROOT/Scripts/verify-sdk.sh"

# 2. Package Zip Archive
echo "Creating distributable ZIP archive..."
cd "$DIST_DIR"
rm -f "$ARCHIVE_ZIP" "$ARCHIVE_TGZ"
zip -r -q -9 "$ARCHIVE_ZIP" "SwiftCodeSDK"

echo "Creating distributable tar.gz archive..."
tar -czf "$ARCHIVE_TGZ" "SwiftCodeSDK"

# 3. Compute Checksums
echo "Generating SHA-256 checksums..."
cd "$DIST_DIR"
shasum -a 256 "SwiftCodeSDK-1.0.0.zip" > "$CHECKSUMS"
shasum -a 256 "SwiftCodeSDK-1.0.0.tar.gz" >> "$CHECKSUMS"

# 4. Verify Archive Extraction in Clean Sandbox
echo "Testing archive extraction and execution in clean location..."
TEST_DIR=$(mktemp -d /tmp/swiftcode-sdk-clean-XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

unzip -q "$ARCHIVE_ZIP" -d "$TEST_DIR"
TEST_BIN="$TEST_DIR/SwiftCodeSDK/bin/swiftcode-sdk"

if [ ! -x "$TEST_BIN" ]; then
    echo "Error: Extracted CLI binary is missing or not executable at $TEST_BIN"
    exit 1
fi

"$TEST_BIN" --version
"$TEST_BIN" doctor

ZIP_SIZE=$(stat -f '%z' "$ARCHIVE_ZIP")
ZIP_MB=$(awk "BEGIN { printf \"%.2f\", $ZIP_SIZE / 1000000 }")
TGZ_SIZE=$(stat -f '%z' "$ARCHIVE_TGZ")
TGZ_MB=$(awk "BEGIN { printf \"%.2f\", $TGZ_SIZE / 1000000 }")

echo "=========================================================="
echo "SwiftCode SDK Packaged Successfully!"
echo "ZIP Archive:     $ARCHIVE_ZIP ($ZIP_SIZE bytes / $ZIP_MB MB)"
echo "Tarball Archive: $ARCHIVE_TGZ ($TGZ_SIZE bytes / $TGZ_MB MB)"
echo "Checksums File:  $CHECKSUMS"
echo "Clean Test:      PASSED (extracted and verified in $TEST_DIR)"
echo "=========================================================="
