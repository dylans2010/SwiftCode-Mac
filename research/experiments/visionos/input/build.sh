#!/bin/sh
set -e
OUT=${1:?output directory}; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$OUT"
for t in vhid vhm bprobe mkdev; do
  xcrun --sdk macosx clang -arch arm64 -fobjc-arc -O0 -framework Foundation -o "$OUT/$t" "$HERE/$t.m"
  codesign -s - -f "$OUT/$t" >/dev/null
done
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -O1 -o "$OUT/gvhm" "$HERE/gvhm.c"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -dynamiclib -O1 \
  -framework CoreFoundation -framework IOKit -o "$OUT/hidrec.dylib" "$HERE/hidrec.c"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -dynamiclib -O1 \
  -framework CoreFoundation -framework IOKit -o "$OUT/hidrec2.dylib" "$HERE/hidrec2.c"
xcrun --sdk xrsimulator clang -target arm64-apple-xros27.0-simulator -O1 -include string.h \
  -framework CoreFoundation -o "$OUT/oprobe" "$HERE/oprobe.c"
codesign -s - -f "$OUT/gvhm" "$OUT/hidrec.dylib" "$OUT/hidrec2.dylib" "$OUT/oprobe" >/dev/null
echo "built in $OUT"
