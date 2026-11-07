#!/bin/sh
set -e
OUT=${1:?output directory}; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$OUT"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -dynamiclib -fobjc-arc -O1 \
  -framework Foundation -framework IOSurface -framework IOKit -Wl,-undefined,dynamic_lookup \
  -o "$OUT/camrec.dylib" "$HERE/camrec.m"
codesign -s - -f "$OUT/camrec.dylib" >/dev/null
echo "built $OUT/camrec.dylib"
