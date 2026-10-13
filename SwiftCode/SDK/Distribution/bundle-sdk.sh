#!/bin/bash
set -euo pipefail

# Run the TypeScript builds and npm pack before building the macOS app.
# This phase only copies verified release artifacts; it never installs tools,
# accesses the network, or writes outside the build products directory.
ROOT="${SRCROOT:?}/SwiftCode/SDK"
DEST="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/SwiftCodeSDK"
for entry in TypeScript/package/dist/index.js TypeScript/package/dist/assist.js TypeScript/runtime-adapter/dist/adapter.js TypeScript/cli/node_modules/archiver/package.json Distribution/swiftcode-sdk-1.0.0.tgz; do
    if [ ! -f "$ROOT/$entry" ]; then
        echo "error: Missing SDK artifact: $entry. Build the SDK package/runtime adapter and install CLI dependencies before xcodebuild."
        exit 1
    fi
done
mkdir -p "$DEST/TypeScript/package" "$DEST/TypeScript/cli" "$DEST/TypeScript/runtime-adapter/dist" "$DEST/Distribution"
rsync -a --delete --exclude='*.map' "$ROOT/TypeScript/package/dist/" "$DEST/TypeScript/package/dist/"
cp "$ROOT/TypeScript/package/package.json" "$ROOT/TypeScript/package/README.md" "$DEST/TypeScript/package/"
rsync -a --delete --exclude='.git*' --exclude='tests' --exclude='package-lock.json' "$ROOT/TypeScript/cli/" "$DEST/TypeScript/cli/"
rsync -a --delete --exclude='*.map' "$ROOT/TypeScript/runtime-adapter/dist/" "$DEST/TypeScript/runtime-adapter/dist/"
# The adapter imports only @swiftcode/sdk; no TypeScript compiler is shipped.
mkdir -p "$DEST/TypeScript/runtime-adapter/node_modules/@swiftcode/sdk"
rsync -a --delete "$DEST/TypeScript/package/" "$DEST/TypeScript/runtime-adapter/node_modules/@swiftcode/sdk/"
rsync -a --delete "$ROOT/TypeScript/templates/" "$DEST/TypeScript/templates/"
rsync -a --delete --delete-excluded --include='*/' --include='*.json' --exclude='*' "$ROOT/Contracts/" "$DEST/Contracts/"
rsync -a --delete "$ROOT/Documentation/" "$DEST/Documentation/"
cp "$ROOT/Distribution/swiftcode-sdk-1.0.0.tgz" "$DEST/Distribution/"
cp "$ROOT/TypeScript/package/snippets.json" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/snippets.json"
echo "Bundled complete SwiftCode SDK toolkit at $DEST"
