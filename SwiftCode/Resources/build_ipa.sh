#!/bin/bash

# SwiftCode Production-grade IPA Packaging Script

set -e

# Exit Codes
ERR_INVALID_APP=10
ERR_MISSING_PLIST=11
ERR_TEMP_FAILED=12
ERR_PACKAGING_FAILED=13

# Input parameters
APP_PATH="$1"
OUTPUT_DIR="$2"
IPA_NAME="$3"

echo "[SHELL] Initiating SwiftCode IPA Build Pipeline..."
echo "[SHELL] Target App Bundle: $APP_PATH"
echo "[SHELL] Output Directory: $OUTPUT_DIR"

# 1. Validate application package path
if [ ! -d "$APP_PATH" ]; then
    echo "[ERROR] The specified .app bundle is missing or invalid: $APP_PATH"
    exit $ERR_INVALID_APP
fi

if [[ "$APP_PATH" != *.app ]]; then
    echo "[ERROR] Invalid package extension. Must be a compiled '.app' bundle."
    exit $ERR_INVALID_APP
fi

# 2. Validate Info.plist
PLIST_PATH="$APP_PATH/Info.plist"
if [ ! -f "$PLIST_PATH" ]; then
    echo "[ERROR] Info.plist not found inside the app bundle."
    exit $ERR_MISSING_PLIST
fi

# 3. Read metadata using defaults
echo "[SHELL] Parsing application Info.plist specifications..."
BUNDLE_ID=$(defaults read "$PLIST_PATH" CFBundleIdentifier 2>/dev/null || echo "Unknown")
DISPLAY_NAME=$(defaults read "$PLIST_PATH" CFBundleDisplayName 2>/dev/null || defaults read "$PLIST_PATH" CFBundleName 2>/dev/null || echo "App")
VERSION=$(defaults read "$PLIST_PATH" CFBundleShortVersionString 2>/dev/null || echo "1.0")
BUILD=$(defaults read "$PLIST_PATH" CFBundleVersion 2>/dev/null || echo "1")

echo "[SHELL] Display Name: $DISPLAY_NAME"
echo "[SHELL] Bundle Identifier: $BUNDLE_ID"
echo "[SHELL] Short Version: $VERSION"
echo "[SHELL] Build Number: $BUILD"

# 4. Create temporary workspace
TEMP_DIR=$(mktemp -d -t swiftcode-ipa-build)
echo "[SHELL] Created clean temporary packaging workspace: $TEMP_DIR"

cleanup() {
    echo "[SHELL] Performing workspace cleanup..."
    rm -rf "$TEMP_DIR"
    echo "[SHELL] Cleanup completed cleanly."
}
trap cleanup EXIT

# 5. Create Payload folder and copy .app
PAYLOAD_DIR="$TEMP_DIR/Payload"
mkdir -p "$PAYLOAD_DIR"
echo "[SHELL] Aligning Payload structures..."
cp -RP "$APP_PATH" "$PAYLOAD_DIR/"

# 6. Compress Payload into IPA
if [ -z "$IPA_NAME" ]; then
    IPA_NAME="${DISPLAY_NAME// /_}.ipa"
fi

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"
FINAL_IPA_PATH="$OUTPUT_DIR/$IPA_NAME"

echo "[SHELL] Compressing Payload container..."
cd "$TEMP_DIR"
zip -r -y "$FINAL_IPA_PATH" "Payload" > /dev/null

echo "[SUCCESS] IPA container packaging completed successfully!"
echo "[SUCCESS] Output File: $FINAL_IPA_PATH"
ls -lh "$FINAL_IPA_PATH"

exit 0
