#!/bin/sh
set -e
OUT=${1:?output directory}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
cc() { xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -O1 -g -Wall "$@"; }
cc -framework CoreFoundation -o "$OUT/ismitm" "$HERE/ismitm.c"
cc -dynamiclib -o "$OUT/isinterpose.dylib" "$HERE/isinterpose.c"
cc -framework IOSurface -framework CoreFoundation -o "$OUT/isprobe" "$HERE/isprobe.c"
cc -framework CoreFoundation -o "$OUT/isserve" "$HERE/isserve.c"
cc -o "$OUT/xpcmagic" "$HERE/xpcmagic.c"
cc -o "$OUT/isnames" "$HERE/isnames.c"
for f in ismitm isinterpose.dylib isprobe isserve xpcmagic isnames; do codesign -s - -f "$OUT/$f" >/dev/null 2>&1; done
echo "built in $OUT"
