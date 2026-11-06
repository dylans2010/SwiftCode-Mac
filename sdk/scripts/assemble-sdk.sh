#!/bin/bash
set -euo pipefail

# Wave 14 adaptation (Legacy SDK/Scripts/assemble-sdk.sh):
# - SDK_ROOT is now this repo's sdk/ (TypeScript SDK root); the TypeScript
#   trees live at sdk/package, sdk/cli, sdk/runtime-adapter, sdk/templates.
# - The Swift build outputs now come from ycode/.build/release (SWIFT_PACKAGE_DIR);
#   the Swift SDK package migration (ledger: ycode/Package.swift
#   NOT STARTED, other wave) must land before the binaries exist to copy.
# - Step 6 (populate-distribution.py) was REMOVED: that script is a synthetic-
#   filler generator, dropped by design in Wave 14 along with the other 10
#   Scripts/*.py. The 200 MB size gate in step 8 is report-only for the same
#   reason: it was only passable via filler.
# - The Contracts/Manifest copies in section 4 now resolve: the schema
#   landed at sdk/Contracts/Manifest/ in Wave 14 (copied verbatim from
#   Legacy SDK/Contracts/Manifest/, with ExampleManifests).
SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SDK_ROOT/.." && pwd)"
SWIFT_PACKAGE_DIR="$REPO_ROOT/ycode"
DIST_DIR="$SDK_ROOT/Distribution"
DEST="$DIST_DIR/SwiftCodeSDK"

echo "Assembling SwiftCode SDK distribution at $DEST..."
rm -rf "$DEST"

mkdir -p "$DEST/bin"
mkdir -p "$DEST/lib"
mkdir -p "$DEST/tools"
mkdir -p "$DEST/templates/macos-app"
mkdir -p "$DEST/templates/swift-package"
mkdir -p "$DEST/templates/typescript-extension"
mkdir -p "$DEST/templates/automation-extension"
mkdir -p "$DEST/templates/source-control-extension"
mkdir -p "$DEST/extensions/manifests"
mkdir -p "$DEST/extensions/examples"
mkdir -p "$DEST/extensions/schemas"
mkdir -p "$DEST/languages/swift"
mkdir -p "$DEST/languages/typescript"
mkdir -p "$DEST/languages/python"
mkdir -p "$DEST/documentation/api"
mkdir -p "$DEST/documentation/guides"
mkdir -p "$DEST/documentation/tutorials"
mkdir -p "$DEST/documentation/offline-index"
mkdir -p "$DEST/resources/schemas"
mkdir -p "$DEST/resources/configuration"
mkdir -p "$DEST/resources/diagnostics-rules"
mkdir -p "$DEST/examples/project-automation"
mkdir -p "$DEST/examples/build-integration"
mkdir -p "$DEST/examples/source-control"
mkdir -p "$DEST/tests/fixtures"
mkdir -p "$DEST/tests/integration"
mkdir -p "$DEST/tests/compatibility"
mkdir -p "$DEST/manifests"

# 1. Root Metadata
echo "1.0.0" > "$DEST/VERSION"

cat << 'EOF' > "$DEST/LICENSE"
MIT License

Copyright (c) 2026 SwiftCode Authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

cat << 'EOF' > "$DEST/README.md"
# SwiftCode SDK

SwiftCode SDK is the professional developer kit for building, automating, testing, and distributing native macOS applications, Swift packages, and SwiftCode extensions.

## Architecture & Modules
- **SwiftCodeSDK**: Root coordination, diagnostics, and environment discovery.
- **ProjectKit**: Native project automation, inspection, and generation.
- **BuildKit**: Compiler discovery, safe process orchestration, and diagnostic parsing.
- **SourceControlKit**: Git repository inspection and safe source control operations.
- **WorkspaceKit**: Safe file access, traversal prevention, and directory inspection.
- **DiagnosticsKit**: Standardized diagnostics engine with structured error codes.
- **ExtensionKit**: Extension lifecycle, capability enforcement, and packaging.

## Quick Start
Add the SDK `bin` directory to your PATH:
```bash
export PATH="/path/to/SwiftCodeSDK/bin:$PATH"
swiftcode-sdk doctor
```
Initialize a new extension:
```bash
swiftcode-sdk init typescript-extension MyExtension
swiftcode-sdk validate ./MyExtension
swiftcode-sdk package ./MyExtension --out ./dist
```
EOF

# 2. Binaries & Libraries
RELEASE_BUILD="$SWIFT_PACKAGE_DIR/.build/release"
if [ ! -f "$RELEASE_BUILD/swiftcode-sdk" ]; then
    echo "Building release targets..."
    swift build --package-path "$SWIFT_PACKAGE_DIR" -c release --disable-sandbox
fi

cp "$RELEASE_BUILD/swiftcode-sdk" "$DEST/bin/"
chmod +x "$DEST/bin/swiftcode-sdk"

for tool in project-generator project-inspector extension-validator diagnostics documentation-indexer; do
    mkdir -p "$DEST/tools/$tool"
    cp "$RELEASE_BUILD/$tool" "$DEST/tools/$tool/"
    chmod +x "$DEST/tools/$tool/$tool"
done

# Copy static libraries and swiftmodules
for mod in SwiftCodeSDK ProjectKit BuildKit SourceControlKit WorkspaceKit DiagnosticsKit ExtensionKit; do
    mkdir -p "$DEST/lib/$mod"
    if [ -f "$RELEASE_BUILD/lib$mod.a" ]; then
        cp "$RELEASE_BUILD/lib$mod.a" "$DEST/lib/$mod/"
    fi
    if [ -d "$RELEASE_BUILD/$mod.swiftmodule" ]; then
        cp -R "$RELEASE_BUILD/$mod.swiftmodule" "$DEST/lib/$mod/"
    fi
done

# 3. Templates
# macOS App template
cat << 'EOF' > "$DEST/templates/macos-app/Package.swift"
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOSAppTemplate",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacOSAppTemplate", targets: ["MacOSAppTemplate"])],
    targets: [.executableTarget(name: "MacOSAppTemplate")]
)
EOF
mkdir -p "$DEST/templates/macos-app/Sources/MacOSAppTemplate"
cat << 'EOF' > "$DEST/templates/macos-app/Sources/MacOSAppTemplate/main.swift"
import SwiftUI

@main
struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello, SwiftCode App!")
                .padding(40)
        }
    }
}
EOF

# Swift Package template
cat << 'EOF' > "$DEST/templates/swift-package/Package.swift"
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftPackageTemplate",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SwiftPackageTemplate", targets: ["SwiftPackageTemplate"])],
    targets: [
        .target(name: "SwiftPackageTemplate"),
        .testTarget(name: "SwiftPackageTemplateTests", dependencies: ["SwiftPackageTemplate"])
    ]
)
EOF
mkdir -p "$DEST/templates/swift-package/Sources/SwiftPackageTemplate"
cat << 'EOF' > "$DEST/templates/swift-package/Sources/SwiftPackageTemplate/Library.swift"
public struct SwiftPackageTemplate {
    public static let greeting = "Hello from SwiftPackageTemplate"
}
EOF

# Copy existing TypeScript templates if present
if [ -d "$SDK_ROOT/templates" ]; then
    cp -R "$SDK_ROOT/templates/"* "$DEST/templates/typescript-extension/" 2>/dev/null || true
fi

# 4. Extensions & Schemas
if [ -f "$SDK_ROOT/Contracts/Manifest/swiftcode-extension-v1.schema.json" ]; then
    cp "$SDK_ROOT/Contracts/Manifest/swiftcode-extension-v1.schema.json" "$DEST/extensions/schemas/"
    cp "$SDK_ROOT/Contracts/Manifest/swiftcode-extension-v1.schema.json" "$DEST/resources/schemas/"
fi
if [ -d "$SDK_ROOT/Contracts/Manifest/ExampleManifests" ]; then
    cp -R "$SDK_ROOT/Contracts/Manifest/ExampleManifests/"* "$DEST/extensions/manifests/" 2>/dev/null || true
fi

# 5. Language Tooling & Runtimes
if [ -d "$SDK_ROOT/package" ]; then
    echo "Installing TypeScript runtime and tooling..."
    mkdir -p "$DEST/languages/typescript/package"
    mkdir -p "$DEST/languages/typescript/runtime-adapter"
    mkdir -p "$DEST/languages/typescript/cli"

    rsync -a --exclude='.git*' "$SDK_ROOT/package/" "$DEST/languages/typescript/package/"
    rsync -a --exclude='.git*' "$SDK_ROOT/runtime-adapter/" "$DEST/languages/typescript/runtime-adapter/"
    rsync -a --exclude='.git*' "$SDK_ROOT/cli/" "$DEST/languages/typescript/cli/"
fi

# Python runner script
mkdir -p "$DEST/languages/python/runner"
cat << 'EOF' > "$DEST/languages/python/runner/swiftcode_runner.py"
import sys
import json
import os

def main():
    print(json.dumps({"status": "ready", "python_version": sys.version}))

if __name__ == "__main__":
    main()
EOF

# Swift format config
mkdir -p "$DEST/languages/swift/formatting"
cat << 'EOF' > "$DEST/languages/swift/formatting/swift-format.json"
{
  "version": 1,
  "indentation": { "spaces": 4 },
  "lineLength": 120,
  "respectsExistingLineBreaks": true
}
EOF

# Resources configuration
mkdir -p "$DEST/resources/configuration"
cat << 'EOF' > "$DEST/resources/configuration/sdk-defaults.json"
{
  "sdkVersion": "1.0.0",
  "minMacOSVersion": "14.0",
  "defaultToolchain": "apple-swift-6.0",
  "isolatedExecution": true,
  "sandboxedBuilds": true
}
EOF

# 6. (Removed in Wave 14.) Legacy called Scripts/populate-distribution.py
# here to generate stub content into the distribution. That script is a
# synthetic-filler generator, dropped by design along with the other 10
# Scripts/*.py — no filler is generated anymore.

# 7. SDK Manifest
cat << 'EOF' > "$DEST/SDKManifest.json"
{
  "name": "SwiftCodeSDK",
  "version": "1.0.0",
  "build": "2026.10.13",
  "schemaVersion": 1,
  "targetOS": "macOS 14.0+",
  "architectures": ["arm64", "x86_64"],
  "modules": [
    "SwiftCodeSDK",
    "ProjectKit",
    "BuildKit",
    "SourceControlKit",
    "WorkspaceKit",
    "DiagnosticsKit",
    "ExtensionKit"
  ],
  "tools": [
    "swiftcode-sdk",
    "project-generator",
    "project-inspector",
    "extension-validator",
    "diagnostics",
    "documentation-indexer"
  ]
}
EOF

# 8. Report installed size (informational only — Wave 14: the former 200 MB
# hard gate was only passable via the dropped synthetic-filler generators,
# so it is no longer enforced; real SDK content is far smaller).
echo "Installed size is reported, not gated."
TOTAL_BYTES=$(find "$DEST" -type f -exec stat -f '%z' {} + | awk '{ total += $1 } END { printf "%.0f\n", total }')
DECIMAL_MB=$(awk "BEGIN { printf \"%.2f\", $TOTAL_BYTES / 1000000 }")
MIB=$(awk "BEGIN { printf \"%.2f\", $TOTAL_BYTES / 1048576 }")

echo "=========================================================="
echo "SwiftCode SDK Assembled Successfully!"
echo "Destination:   $DEST"
echo "Total Bytes:   $TOTAL_BYTES"
echo "Decimal MB:    $DECIMAL_MB MB"
echo "Binary MiB:    $MIB MiB"
echo "=========================================================="

if [ "$TOTAL_BYTES" -lt 200000000 ]; then
    echo "Note: Assembled size ($TOTAL_BYTES bytes) is below the legacy 200 MB threshold (that threshold was only reachable with synthetic filler, dropped in Wave 14)."
else
    echo "SUCCESS: Assembled size passes 200 MB target threshold."
fi
