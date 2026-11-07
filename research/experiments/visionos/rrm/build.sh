#!/bin/sh
set -e
OUT=${1:?output directory}; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$OUT"
cc() { xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -O1 -g "$@"; }
cc -fobjc-arc -framework Foundation -framework Metal -o "$OUT/rrmcli" "$HERE/rrmcli.m"
cc -dynamiclib -fobjc-arc -framework Foundation -framework Metal -Wl,-undefined,dynamic_lookup -o "$OUT/rrmpeek.dylib" "$HERE/rrmpeek.m"
cc -dynamiclib -framework IOSurface -o "$OUT/mslog.dylib" "$HERE/../../simulator/metal-sim/mslog.c"
for f in rrmcli rrmpeek.dylib mslog.dylib; do codesign -s - -f "$OUT/$f" >/dev/null; done
echo "built in $OUT"
