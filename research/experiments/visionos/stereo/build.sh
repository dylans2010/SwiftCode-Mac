#!/bin/sh
set -e
OUT=${1:?output directory}; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$OUT"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -dynamiclib -fobjc-arc -O1 \
  -framework Foundation -framework Metal -framework IOSurface -Wl,-undefined,dynamic_lookup \
  -o "$OUT/stereopeek.dylib" "$HERE/stereopeek.m"
codesign -s - -f "$OUT/stereopeek.dylib" >/dev/null
echo "built $OUT/stereopeek.dylib"
