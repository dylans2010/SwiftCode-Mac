#!/bin/bash
set -euo pipefail

# Wave 14 adaptation (Legacy SDK/Scripts/verify-sdk.sh):
# - SDK_ROOT is now this repo's sdk/; the distribution assembles under
#   sdk/Distribution (build output, created by assemble-sdk.sh).
# - `manifests/components.json` was REMOVED from the required-files check:
#   it was written by Scripts/populate-distribution.py, a synthetic-filler
#   generator dropped by design in Wave 14.
# - The 200 MB size gate in step 3 is report-only for the same reason: it
#   was only passable via filler. Real SDK content is far smaller.
# - The binary/tool checks in step 1 still require the Swift SDK migration
#   (ledger: ycode/Package.swift NOT STARTED, other wave).
SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$SDK_ROOT/Distribution"
DEST="$DIST_DIR/SwiftCodeSDK"

# Portable file-size probe (Wave 16): see assemble-sdk.sh — Legacy used
# BSD-only `stat -f %z`, which fails on GNU stat.
if stat -f '%z' "$0" >/dev/null 2>&1; then
    _STAT_SIZE=(stat -f %z)
else
    _STAT_SIZE=(stat -c %s)
fi

echo "=== SwiftCode SDK Verification ==="
echo "Target: $DEST"

if [ ! -d "$DEST" ]; then
    echo "Error: Assembled SDK directory does not exist at $DEST"
    exit 1
fi

# 1. Verify required files & executables
echo "1. Checking required files and executables..."
for req in VERSION README.md LICENSE SDKManifest.json bin/swiftcode-sdk; do
    if [ ! -f "$DEST/$req" ]; then
        echo "Error: Missing required distribution file: $req"
        exit 1
    fi
done

for tool in project-generator project-inspector extension-validator diagnostics documentation-indexer; do
    if [ ! -x "$DEST/tools/$tool/$tool" ]; then
        echo "Error: Missing executable tool: $tool"
        exit 1
    fi
done

# 2. Run CLI doctor from distribution
echo "2. Testing swiftcode-sdk CLI from staging directory..."
"$DEST/bin/swiftcode-sdk" --version
"$DEST/bin/swiftcode-sdk" doctor

# 3. Verify Size Gate
echo "3. Verifying installed file size..."
TOTAL_BYTES=$(find "$DEST" -type f -exec "${_STAT_SIZE[@]}" {} + | awk '{ total += $1 } END { printf "%.0f\n", total }')
DECIMAL_MB=$(awk "BEGIN { printf \"%.2f\", $TOTAL_BYTES / 1000000 }")
MIB=$(awk "BEGIN { printf \"%.2f\", $TOTAL_BYTES / 1048576 }")
FILE_COUNT=$(find "$DEST" -type f | wc -l | tr -d ' ')

echo "Total Regular Files: $FILE_COUNT"
echo "Installed File Size: $TOTAL_BYTES bytes ($DECIMAL_MB MB / $MIB MiB)"

if [ "$TOTAL_BYTES" -lt 200000000 ]; then
    echo "Note: Installed size ($TOTAL_BYTES bytes) is below the legacy 200,000,000 bytes threshold (that threshold was only reachable with synthetic filler, dropped in Wave 14). Size is reported, not gated."
else
    echo "✅ Size Gate PASSED: $TOTAL_BYTES bytes >= 200,000,000 bytes ($DECIMAL_MB MB)."
fi

# 4. Top-level breakdown
echo "4. Distribution Breakdown by Component:"
for dir in bin lib tools templates extensions languages documentation resources examples tests manifests; do
    if [ -d "$DEST/$dir" ]; then
        DIR_BYTES=$(find "$DEST/$dir" -type f -exec "${_STAT_SIZE[@]}" {} + | awk '{ total += $1 } END { printf "%.0f\n", total }')
        DIR_MB=$(awk "BEGIN { printf \"%.2f\", $DIR_BYTES / 1000000 }")
        echo "  - $dir/: $DIR_BYTES bytes ($DIR_MB MB)"
    fi
done

echo "✅ All verification checks PASSED successfully!"
